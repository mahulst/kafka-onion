use actix_web::*;
use ::actix::{SyncContext, Message, Actor, Handler};
use read_topic_api::{KafkaClient, fetch_topics, fetch_latest_topic_detail, TopicResponse,
                     TopicDetailResponse, PartitionOffsets, fetch_from_topic_detail,
};

pub struct DbExecutor(pub KafkaClient);

pub struct FetchTopics {}

impl Message for FetchTopics {
    type Result = Result<Vec<TopicResponse>, Error>;
}

impl Actor for DbExecutor {
    type Context = SyncContext<Self>;
}

impl Handler<FetchTopics> for DbExecutor {
    type Result = Result<Vec<TopicResponse>, Error>;

    fn handle(&mut self, _msg: FetchTopics, _: &mut Self::Context) -> Self::Result {
        let client = &mut self.0;
        let topics = fetch_topics(client)
            .expect("Error fetching topics");

        Ok(topics)
    }
}

pub struct FetchTopicDetail {
    pub topic_name: String
}

impl Message for FetchTopicDetail {
    type Result = Result<TopicDetailResponse, Error>;
}

impl Handler<FetchTopicDetail> for DbExecutor {
    type Result = Result<TopicDetailResponse, Error>;

    fn handle(&mut self, msg: FetchTopicDetail, _: &mut Self::Context) -> Self::Result {
        let client = &mut self.0;

        let topics = fetch_latest_topic_detail(client, &msg.topic_name)
            .expect("Error fetching topic detail");

        Ok(topics)
    }
}

pub struct FetchTopicDetailFrom {
    pub topic_name: String,
    pub partition_offsets: PartitionOffsets,
}

impl Message for FetchTopicDetailFrom {
    type Result = Result<TopicDetailResponse, Error>;
}

impl Handler<FetchTopicDetailFrom> for DbExecutor {
    type Result = Result<TopicDetailResponse, Error>;

    fn handle(&mut self, msg: FetchTopicDetailFrom, _: &mut Self::Context) -> Self::Result {
        let client = &mut self.0;

        let topics = fetch_from_topic_detail(client, &msg.topic_name, &msg.partition_offsets)
            .expect("Error fetching topic detail");

        Ok(topics)
    }
}
