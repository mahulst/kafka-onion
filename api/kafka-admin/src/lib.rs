#[macro_use]
extern crate serde_derive;
#[macro_use]
extern crate log;
extern crate rdkafka;

use std::collections::HashMap;
use std::time::Duration;
use std::{env, thread};

use futures::*;
use rdkafka::admin::TopicReplication::Fixed;
use rdkafka::admin::{AdminClient, AdminOptions, NewTopic};
use rdkafka::client::ClientContext;
use rdkafka::client::DefaultClientContext;
use rdkafka::config::{ClientConfig, RDKafkaLogLevel};
use rdkafka::consumer::stream_consumer::StreamConsumer;
use rdkafka::consumer::{
    BaseConsumer, CommitMode, Consumer, ConsumerContext, DefaultConsumerContext, Rebalance,
};
use rdkafka::message::Message;
use rdkafka::topic_partition_list::Offset::Offset;
use rdkafka::TopicPartitionList;

use backoff::{ExponentialBackoff, Operation};

fn create_config() -> ClientConfig {
    let mut config = ClientConfig::new();
    config.set("bootstrap.servers", get_broker_list().as_str());
    config
}

fn create_admin_client() -> AdminClient<DefaultClientContext> {
    create_config()
        .create()
        .expect("admin client creation failed")
}

pub fn get_broker_list() -> String {
    let broker_list = env::var("KAFKA_BROKER_LIST").unwrap_or(String::from("localhost:9092"));

    broker_list
}

pub type PartitionOffsets = HashMap<i32, i64>;

#[derive(Debug, Serialize, Deserialize)]
pub struct TopicDetailResponse {
    pub name: String,
    pub total_messages: i64,
    pub partition_details: Vec<PartitionDetailResponse>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct PartitionDetailResponse {
    pub id: i32,
    pub highwatermark_offset: i64,
    pub lowwatermark_offset: i64,
    pub message_count: i64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct MessagesResponse {
    messages: Vec<MessageResponse>,
    offsets: PartitionOffsets,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct MessageResponse {
    json: String,
    offset: i64,
    partition: i32,
    timestamp: i64,
}

pub fn fetch_topic_detail(topic: Option<&str>) -> Result<Vec<TopicDetailResponse>, &'static str> {
    let timeout = Duration::from_secs(3);

    let consumer: BaseConsumer = ClientConfig::new()
        .set("bootstrap.servers", &get_broker_list())
        .create()
        .map_err(|_| "Consumer creation failed")?;

    let metadata = consumer
        .fetch_metadata(topic, timeout)
        .map_err(|_| "Failed to fetch metadata")?;

    let mut topics = vec![];

    for topic in metadata.topics() {
        let mut total_messages = 0;
        let mut partition_details = vec![];

        for partition in topic.partitions() {
            let (low, high) = consumer
                .fetch_watermarks(topic.name(), partition.id(), timeout)
                .unwrap_or((-1, -1));

            partition_details.push(PartitionDetailResponse {
                highwatermark_offset: high,
                lowwatermark_offset: low,
                message_count: high - low,
                id: partition.id(),
            });
            total_messages += high - low;
        }

        topics.push(TopicDetailResponse {
            name: String::from(topic.name()),
            partition_details,
            total_messages,
        });
    }

    Ok(topics)
}

struct CustomContext;

impl ClientContext for CustomContext {}

impl ConsumerContext for CustomContext {
    fn pre_rebalance(&self, rebalance: &Rebalance) {
        info!("Pre rebalance {:?}", rebalance);
    }

    fn post_rebalance(&self, rebalance: &Rebalance) {
        info!("Post rebalance {:?}", rebalance);
    }
}

type KafkaConsumer = StreamConsumer<CustomContext>;
pub fn consume(
    brokers: &str,
    group_id: &str,
    topic: &str,
    offsets: &PartitionOffsets,
) -> Result<MessagesResponse, &'static str> {
    let topics_detail = fetch_topic_detail(Some(topic))?;
    let topic_detail = topics_detail.first().expect("topic not found");

    let mut limits: PartitionOffsets = HashMap::new();
    let mut messages_received: PartitionOffsets = HashMap::new();

    let context = CustomContext;
    let mut tpl = TopicPartitionList::new();

    offsets.iter().for_each(|(partition, offset)| {
        let partition_detail: &PartitionDetailResponse = topic_detail
            .partition_details
            .get(*partition as usize)
            .expect("partition not found");
        let max = (partition_detail.highwatermark_offset - 1).min(*offset + 20);
        let min = partition_detail.lowwatermark_offset.max(*offset);

        if min >= max {
            messages_received.insert(*partition, partition_detail.highwatermark_offset);
            return;
        }

        limits.insert(*partition, max);
        messages_received.insert(*partition, min);

        tpl.add_partition_offset(topic, *partition, Offset(*offset));
    });

    let consumer: KafkaConsumer = ClientConfig::new()
        .set("group.id", group_id)
        .set("bootstrap.servers", brokers)
        .set("enable.partition.eof", "false")
        .set("session.timeout.ms", "6000")
        .set("enable.auto.commit", "true")
        .set_log_level(RDKafkaLogLevel::Debug)
        .create_with_context(context)
        .expect("Consumer creation failed");

    consumer
        .assign(&tpl)
        .map_err(|_| "Can't subscribe to specified partitions")?;

    let message_stream = consumer.start();
    let mut messages = vec![];
    for message in message_stream.wait() {
        match message {
            Err(_) => eprintln!("Error while reading from stream."),
            Ok(Err(e)) => eprintln!("Kafka error: {}", e),
            Ok(Ok(m)) => {
                let payload = match m.payload_view::<str>() {
                    None => "",
                    Some(Ok(s)) => s,
                    Some(Err(e)) => {
                        eprintln!("Error while deserializing message payload: {:?}", e);
                        "{\"error\": \"Can't deserialize message payload\" }"
                    }
                };
                messages_received.insert(m.partition(), m.offset());
                consumer.commit_message(&m, CommitMode::Async).unwrap();

                let finished = limits.iter().all(|(k, v)| {
                    let current_offset = messages_received.get(k).unwrap();

                    v <= current_offset
                });

                if finished {
                    consumer.stop();
                }

                messages.push(MessageResponse {
                    json: String::from(payload),
                    offset: m.offset(),
                    partition: m.partition(),
                    timestamp: m
                        .timestamp()
                        .to_millis()
                        .ok_or("No timestamp for message")?,
                })
            }
        };
    }
    println!("hello there");
    eprintln!("messages_received = {:#?}", messages_received);

    Ok(MessagesResponse {
        messages,
        offsets: messages_received,
    })
}

fn verify_delete(topic: &str) {
    let consumer: BaseConsumer<DefaultConsumerContext> =
        create_config().create().expect("consumer creation failed");
    let timeout = Some(Duration::from_secs(3));

    let mut backoff = ExponentialBackoff::default();
    backoff.max_elapsed_time = Some(Duration::from_secs(5));
    (|| {
        // Asking about the topic specifically will recreate it (under the
        // default Kafka configuration, at least) so we have to ask for the list
        // of all topics and search through it.
        let metadata = consumer
            .fetch_metadata(None, timeout)
            .map_err(|e| e.to_string())?;
        if let Some(_) = metadata.topics().iter().find(|t| t.name() == topic) {
            Err(format!("topic {} still exists", topic))?
        }
        Ok(())
    })
    .retry(&mut backoff)
    .unwrap()
}

pub fn delete_topic(topic: &str) -> Result<(), &'static str> {
    let admin_client = create_admin_client();
    let opts = AdminOptions::new().operation_timeout(Duration::from_secs(3));

    admin_client
        .delete_topics(&[topic], &opts)
        .wait()
        .map_err(|_| "topic deletion failed")?;

    Ok(())
}

pub fn create_topic(topic: &TopicDetailResponse) -> Result<(), &'static str> {
    let admin_client = create_admin_client();
    let opts = AdminOptions::new().operation_timeout(Duration::from_secs(3));

    let new_topic = NewTopic {
        name: &topic.name,
        num_partitions: topic.partition_details.len() as i32,
        replication: Fixed(1),
        config: vec![],
    };

    admin_client
        .create_topics(&[new_topic], &opts)
        .wait()
        .map_err(|_| "Failed to recreate topic")?;

    Ok(())
}

pub fn reset_topic(topic_name: &str) -> Result<(), &'static str> {
    let topic_detail = fetch_topic_detail(Some(topic_name))?;
    let topic = topic_detail.first().ok_or("Can't find topic")?;

    let admin_client = create_admin_client();
    let opts = AdminOptions::new().operation_timeout(Duration::from_secs(3));

    admin_client
        .delete_topics(&[topic_name], &opts)
        .wait()
        .map_err(|_| "topic deletion failed")?;

    verify_delete(topic_name);

    // Allow kafka to process deletion of topic
    thread::sleep(Duration::from_millis(500));

    create_topic(topic)?;

    Ok(())
}
