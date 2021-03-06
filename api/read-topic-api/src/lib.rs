#[macro_use]
extern crate serde_derive;

use kafka::client::{fetch, FetchOffset, FetchPartition, PartitionOffset, ProduceMessage};
use std::collections::HashMap;

pub use kafka::client::KafkaClient;
use kafka::producer::RequiredAcks;
use std::cmp::max;
use std::env;
use std::time::Duration;

#[derive(Debug, Serialize, Deserialize)]
pub struct PartitionResponse {
    id: u32,
    offset: i64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct TopicResponse {
    name: String,
    partition_count: usize,
}

impl TopicResponse {
    pub fn new(name: String, partition_count: usize) -> Self {
        Self {
            name,
            partition_count,
        }
    }
}

pub type PartitionOffsets = HashMap<i32, i64>;

#[derive(Debug, Serialize, Deserialize)]
pub struct TopicDetailResponse {
    name: String,
    partition_offsets: PartitionOffsets,
    partition_details: Vec<PartitionDetailResponse>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct PartitionDetailResponse {
    id: u32,
    highwatermark_offset: i64,
    message_count: u32,
    messages: Vec<MessageResponse>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct MessageResponse {
    json: String,
    offset: i64,
    partition: i32,
}

pub fn get_client() -> KafkaClient {
    let broker_list = env::var("KAFKA_BROKER_LIST").unwrap_or(String::from("localhost:9092"));

    let brokers: Vec<String> = broker_list.split(',').map(|s| String::from(s)).collect();
    let mut client = KafkaClient::new(brokers);

    client
}

pub fn fetch_topics(client: &mut KafkaClient) -> Result<Vec<TopicResponse>, &'static str> {
    client
        .load_metadata_all()
        .map_err(|_| "Error loading metadata")?;

    let topics: Vec<TopicResponse> = client
        .topics()
        .iter()
        .map(|t| TopicResponse::new(String::from(t.name()), t.partitions().len()))
        .collect();

    Ok(topics)
}

const MAX_BYTES_MESSAGES: i32 = 2_000_000;

pub fn fetch_from_topic_detail(
    client: &mut KafkaClient,
    topic_name: &str,
    from: &PartitionOffsets,
) -> Result<TopicDetailResponse, &'static str> {
    let reqs: Vec<FetchPartition> = from
        .iter()
        .map(|(partition, offset)| {
            FetchPartition::new(topic_name, *partition, max(offset - 10, 0))
                .with_max_bytes(MAX_BYTES_MESSAGES / from.len() as i32)
        })
        .collect();
    client.load_metadata_all();

    let response: Vec<fetch::Response> = client
        .fetch_messages(reqs)
        .map_err(|_| "Error fetching messages")?;
    let partition_details: Vec<PartitionDetailResponse> = vec![];
    let mut partition_offsets = HashMap::new();
    let partition_details: Vec<PartitionDetailResponse> =
        response
            .iter()
            .fold(partition_details, |acc, res: &fetch::Response| {
                res.topics().iter().fold(acc, |acc, topic: &fetch::Topic| {
                    topic
                        .partitions()
                        .iter()
                        .fold(acc, |mut acc, partition: &fetch::Partition| {
                            let mut messages: Vec<MessageResponse> = vec![];
                            let mut message_count = 0;

                            let mut highwatermark_offset = -1;

                            let mut messages = match partition.data() {
                                &Ok(ref data) => {
                                    highwatermark_offset = data.highwatermark_offset();

                                    data.messages().iter().fold(
                                        messages,
                                        |mut acc, message: &fetch::Message| {
                                            if acc.len() == 10 {
                                                return acc;
                                            }

                                            // Store lowest offset
                                            let offset = partition_offsets
                                                .entry(partition.partition())
                                                .or_insert(message.offset);
                                            if message.offset < *offset {
                                                *offset = message.offset;
                                            }

                                            let message_response = MessageResponse {
                                                json: String::from(
                                                    std::str::from_utf8(message.value)
                                                        .expect("Failed to read string"),
                                                ),
                                                offset: message.offset,
                                                partition: partition.partition(),
                                            };
                                            message_count += 1;
                                            acc.push(message_response);
                                            acc
                                        },
                                    )
                                }
                                _ => messages,
                            };

                            acc.push(PartitionDetailResponse {
                                id: partition.partition() as u32,
                                highwatermark_offset,
                                message_count,
                                messages,
                            });

                            acc
                        })
                })
            });

    Ok(TopicDetailResponse {
        name: String::from(topic_name),
        partition_offsets,
        partition_details,
    })
}

pub fn send_message_to_topic(
    client: &mut KafkaClient,
    topic_name: &str,
    partition: i32,
    message: &str,
) -> Result<(), &'static str> {
    client
        .load_metadata_all()
        .map_err(|_| "Error loading metadata")?;

    let messages = vec![ProduceMessage::new(
        topic_name,
        partition,
        None,
        Some(message.as_bytes()),
    )];

    let resp = client.produce_messages(RequiredAcks::One, Duration::from_millis(100), messages);

    resp.map_err(|_| "Error producing messag")?;

    Ok(())
}

pub fn fetch_latest_topic_detail(
    client: &mut KafkaClient,
    topic_name: &str,
) -> Result<TopicDetailResponse, &'static str> {
    client
        .load_metadata_all()
        .map_err(|_| "Error loading metadata")?;

    let offsets: Vec<PartitionOffset> = client
        .fetch_topic_offsets(topic_name, FetchOffset::Latest)
        .map_err(|_| "Error fetching topic offsets")?;

    let from = offsets.iter().fold(HashMap::new(), |mut acc, p| {
        acc.insert(p.partition, p.offset);
        acc
    });

    fetch_from_topic_detail(client, topic_name, &from)
}
