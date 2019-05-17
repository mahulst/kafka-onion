#[macro_use]
extern crate serde_derive;
extern crate actix;

use actix::prelude::*;
use actix_web::{
    http, middleware, server, App, AsyncResponder, FutureResponse, HttpResponse, Path, Error,
    State, Json
};

use futures::{Future};

mod topics_actors;

use topics_actors::{FetchTopics, DbExecutor};
use read_topic_api::{get_client, PartitionOffsets};
use crate::topics_actors::{FetchTopicDetail, FetchTopicDetailFrom};

struct AppState {
    db: Addr<DbExecutor>,
}

fn fetch_topics(
    state: State<AppState>,
) -> FutureResponse<HttpResponse> {
    // send async `CreateUser` message to a `DbExecutor`
    state
        .db
        .send(FetchTopics {})
        .from_err()
        .and_then(|res| match res {
            Ok(topics) => {
                Ok(HttpResponse::Ok().json(topics))
            },
            Err(_) => Ok(HttpResponse::InternalServerError().into()),
        })
        .responder()
}

fn fetch_topic_detail(
    (name, state): (Path<String>, State<AppState>),
) -> FutureResponse<HttpResponse> {
    // send async `CreateUser` message to a `DbExecutor`
    state
        .db
        .send(FetchTopicDetail {topic_name: name.into_inner(),})
        .from_err()
        .and_then(|res| match res {
            Ok(topic_detail) => {

                Ok(HttpResponse::Ok().json(topic_detail))
            },
            Err(_) => Ok(HttpResponse::InternalServerError().into()),
        })
        .responder()
}

#[derive(Debug, Serialize, Deserialize)]
struct PartitionFromRequest {
    topic_name: String,
    partition_offsets: PartitionOffsets
}

fn fetch_from_topic_detail((item, state): (Json<PartitionFromRequest>, State<AppState>)) -> impl Future<Item = HttpResponse, Error = Error> {
    let item = item.into_inner();
    let message = FetchTopicDetailFrom {
        partition_offsets: item.partition_offsets,
        topic_name: item.topic_name,
    };

    state.db
        .send(message)
        .from_err()
        .and_then(|res| match res {
            Ok(topic_detail) => {
                Ok(HttpResponse::Ok().json(topic_detail))
            },
            Err(_) => Ok(HttpResponse::InternalServerError().into()),
        })
}

fn main() {
    ::std::env::set_var("RUST_LOG", "actix_web=info");
    env_logger::init();
    let sys = actix::System::new("Kafka API");

    let addr = SyncArbiter::start(3, move || DbExecutor(get_client()));

    // Start http server
    server::new(move || {
        App::with_state(AppState{db: addr.clone()})
            // enable logger
            .middleware(middleware::Logger::default())
            .resource("/topics", |r| r.method(http::Method::GET).with(fetch_topics))
            .resource("/topic/{name}", |r| r.method(http::Method::GET).with(fetch_topic_detail))
            .resource("/topic/{name}/from", |r| {
                r.method(http::Method::GET)
                    .with_async_config(fetch_from_topic_detail, |(json_cfg, )| {
                        json_cfg.0.limit(4096); // <- limit size of the payload
                    })
            })
    }).bind("127.0.0.1:8080")
        .unwrap()
        .start();

    println!("Started http server: 127.0.0.1:8080");
    let _ = sys.run();
}