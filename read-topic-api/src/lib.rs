#[macro_use]
extern crate serde_derive;

use kafka::client::{FetchPartition, FetchOffset, PartitionOffset, fetch};
use std::collections::HashMap;

pub use kafka::client::KafkaClient;

#[derive(Debug, Serialize, Deserialize)]
pub struct PartitionResponse {
    id: u32,
    offset: i64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct TopicResponse<> {
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
    partition_offsets:PartitionOffsets,
    message_count: u32,
    messages: Vec<MessageResponse>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct PartitionDetailResponse {
    id: u32,
    from_offset: i64,
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
    //TODO: use env var
    let broker = "localhost:9092";

    let mut client = KafkaClient::new(vec![broker.to_owned()]);

    client
}

pub fn fetch_topics(client: &mut KafkaClient) -> Result<Vec<TopicResponse>, &'static str> {
    client.load_metadata_all().map_err(|_| "Error loading metadata")?;

    let topics: Vec<TopicResponse> = client.topics().iter().map(|t| {
        TopicResponse::new(String::from(t.name()), t.partitions().len())
    }).collect();

    Ok(topics)
}

pub fn fetch_from_topic_detail(client: &mut KafkaClient, topic_name: &str, from: &PartitionOffsets) -> Result<TopicDetailResponse, &'static str> {
    let reqs: Vec<FetchPartition> = from.iter().map(|(partition, offset)| {
        FetchPartition::new(topic_name, *partition, offset - 10)
    }).collect();
    client.load_metadata_all();

    let response: Vec<fetch::Response> = client.fetch_messages(reqs).map_err(|_| "Error fetching messages")?;
    let mut messages: Vec<MessageResponse> = vec![];
    let mut partition_offsets = HashMap::new();
    let mut message_count = 0;
    let mut messages: Vec<MessageResponse> = response.iter().fold(messages, |acc, res: &fetch::Response, | {
        res.topics().iter().fold(acc, |acc, topic: &fetch::Topic| {
            topic.partitions().iter().fold(acc, |acc, partition: &fetch::Partition| {
                match partition.data() {
                    &Ok(ref data) => {
                        data.messages().iter().fold(acc, |mut acc, message: &fetch::Message| {
                            // Store lowest offset
                            let offset = partition_offsets.entry(partition.partition()).or_insert(message.offset);
                            if message.offset < *offset {
                                *offset = message.offset;
                            }

                            let message_response = MessageResponse {
                                json: String::from(std::str::from_utf8(message.value).expect("Failed to read string")),
                                offset: message.offset,
                                partition: partition.partition(),
                            };
                            message_count += 1;
                            acc.push(message_response);
                            acc
                        })
                    }
                    _ => { acc }
                }
            })
        })
    });

    Ok(TopicDetailResponse {
        name: String::from(topic_name),
        partition_offsets,
        message_count,
        messages,
    })
}

pub fn fetch_latest_topic_detail(client: &mut KafkaClient, topic_name: &str) -> Result<TopicDetailResponse, &'static str> {
    client.load_metadata_all().map_err(|_| "Error loading metadata")?;

    let offsets: Vec<PartitionOffset> = client.fetch_topic_offsets(topic_name, FetchOffset::Latest).map_err(|_| "Error fetching topic offsets")?;

    let from = offsets.iter().fold(HashMap::new(), |mut acc, p| {
        acc.insert(p.partition, p.offset);
        acc
    });

    fetch_from_topic_detail(client, topic_name, &from)
}