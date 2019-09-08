#[macro_use]
extern crate serde_derive;

#[macro_use]
extern crate actix_web;

use std::collections::HashMap;
use std::{env, io};

use futures::Future;

use actix_cors::Cors;
use actix_files as fs;
use actix_web::http::StatusCode;
use actix_web::web::Query;
use actix_web::{error, guard, middleware, web, App, Error, HttpResponse, HttpServer, Result};

use kafka_admin::{consume, delete_topic, fetch_topic_detail, reset_topic};
use read_topic_api::{
    fetch_from_topic_detail, fetch_latest_topic_detail, fetch_topics, get_client,
    send_message_to_topic,
};

#[get("/favicon")]
fn favicon() -> Result<fs::NamedFile> {
    Ok(fs::NamedFile::open("static/favicon.ico")?)
}

fn redirect_to_index() -> Result<fs::NamedFile> {
    Ok(fs::NamedFile::open("static/index.html")?.set_status_code(StatusCode::OK))
}

fn fetch_topics_handler() -> impl Future<Item = HttpResponse, Error = Error> {
    web::block(move || {
        let mut client = get_client();

        fetch_topics(&mut client)
    })
    .then(|res| match res {
        Ok(topics) => Ok(HttpResponse::Ok().json(topics)),
        Err(_) => Ok(HttpResponse::InternalServerError().into()),
    })
}

fn fetch_messages(
    topic_name: web::Path<String>,
    offsets: Query<Offsets>,
) -> impl Future<Item = HttpResponse, Error = Error> {
    web::block(move || {
        let partitions: Vec<(i32, i64)> = offsets
            .offsets
            .split(',')
            .map(|el| {
                let els: Vec<&str> = el.split(';').collect();
                let partition = els.first().expect("No partition found in offsets");
                let offset = els.last().expect("No offset found in offsets");

                return (
                    partition
                        .parse::<i32>()
                        .expect("Offsets should contain numbers"),
                    offset
                        .parse::<i64>()
                        .expect("Offsets should contain numbers"),
                );
            })
            .collect();

        let partition_offsets: HashMap<i32, i64> =
            partitions
                .iter()
                .fold(HashMap::new(), |mut acc, (partition, offset)| {
                    acc.insert(*partition, *offset);
                    acc
                });

        consume(
            "localhost:9092",
            "hello_123",
            &topic_name,
            &partition_offsets,
        )
    })
    .then(|res| match res {
        Ok(topics) => Ok(HttpResponse::Ok().json(topics)),
        Err(_) => Ok(HttpResponse::InternalServerError().into()),
    })
}

fn delete_topic_handler(
    topic_name: web::Path<String>,
) -> impl Future<Item = HttpResponse, Error = Error> {
    web::block(move || delete_topic(&topic_name)).then(|res| match res {
        Ok(topics) => Ok(HttpResponse::Ok().json(topics)),
        Err(_) => Ok(HttpResponse::InternalServerError().into()),
    })
}

fn reset_topic_handler(
    topic_name: web::Path<String>,
) -> impl Future<Item = HttpResponse, Error = Error> {
    web::block(move || reset_topic(&topic_name)).then(|res| match res {
        Ok(_) => Ok(HttpResponse::NoContent().finish()),
        Err(_) => Ok(HttpResponse::InternalServerError().into()),
    })
}

fn fetch_topics_handler_v2() -> impl Future<Item = HttpResponse, Error = Error> {
    web::block(move || fetch_topic_detail(None)).then(|res| match res {
        Ok(topics) => Ok(HttpResponse::Ok().json(topics)),
        Err(_) => Ok(HttpResponse::InternalServerError().into()),
    })
}

fn fetch_topic_handler_v2(
    topic_name: web::Path<String>,
) -> impl Future<Item = HttpResponse, Error = Error> {
    web::block(move || fetch_topic_detail(Some(&topic_name))).then(|res| match res {
        Ok(topics) => Ok(HttpResponse::Ok().json(topics)),
        Err(_) => Ok(HttpResponse::InternalServerError().into()),
    })
}

#[derive(Debug, Serialize, Deserialize)]
struct SendMessageRequest {
    partition: i32,
    message: String,
}

fn fetch_topic_detail_from_handler(
    topic_name: web::Path<String>,
    offsets: Query<Offsets>,
) -> impl Future<Item = HttpResponse, Error = Error> {
    // TODO: can actix-web parse lists from query?
    let partitions: Vec<(i32, i64)> = offsets
        .offsets
        .split(',')
        .map(|el| {
            let els: Vec<&str> = el.split(';').collect();
            let partition = els.first().expect("No partition found in offsets");
            let offset = els.last().expect("No offset found in offsets");

            return (
                partition
                    .parse::<i32>()
                    .expect("Offsets should contain numbers"),
                offset
                    .parse::<i64>()
                    .expect("Offsets should contain numbers"),
            );
        })
        .collect();

    let partition_offsets: HashMap<i32, i64> =
        partitions
            .iter()
            .fold(HashMap::new(), |mut acc, (partition, offset)| {
                acc.insert(*partition, *offset);
                acc
            });

    web::block(move || {
        let mut client = get_client();

        fetch_from_topic_detail(&mut client, &topic_name, &partition_offsets)
    })
    .then(|res| match res {
        Ok(topics) => Ok(HttpResponse::Ok().json(topics)),
        Err(_) => Ok(HttpResponse::InternalServerError().into()),
    })
}

#[derive(Deserialize, Debug)]
struct Offsets {
    offsets: String,
}

fn fetch_topic_detail_handler(
    name: web::Path<String>,
) -> impl Future<Item = HttpResponse, Error = Error> {
    web::block(move || {
        let mut client = get_client();

        fetch_latest_topic_detail(&mut client, &name)
    })
    .then(|res| match res {
        Ok(topics) => Ok(HttpResponse::Ok().json(topics)),
        Err(_) => Ok(HttpResponse::InternalServerError().into()),
    })
}

fn send_message_to_topic_handler(
    topic_name: web::Path<String>,
    item: web::Json<SendMessageRequest>,
) -> impl Future<Item = HttpResponse, Error = Error> {
    web::block(move || {
        let mut client = get_client();

        send_message_to_topic(&mut client, &topic_name, item.partition, &item.message)
    })
    .then(|res| match res {
        Ok(_) => Ok(HttpResponse::Ok().finish()),
        Err(_) => Ok(HttpResponse::InternalServerError().into()),
    })
}

fn main() -> io::Result<()> {
    let port = env::var("API_PORT").unwrap_or(String::from("8080"));

    env::set_var("RUST_LOG", "actix_web=debug");
    env_logger::init();

    let sys = actix_rt::System::new("kafka-onion-api");
    let listen = format!("0.0.0.0:{}", port);

    HttpServer::new(|| {
        App::new()
            .wrap(middleware::Logger::default())
            .wrap(Cors::new().allowed_methods(vec!["GET", "POST", "DELETE"]))
            .service(favicon)
            .service(web::resource("api/topics").route(web::get().to_async(fetch_topics_handler)))
            .service(
                web::resource("api/v2/topics").route(web::get().to_async(fetch_topics_handler_v2)),
            )
            .service(
                web::resource("api/v2/topic/{topic_name}")
                    .route(web::get().to_async(fetch_topic_handler_v2)),
            )
            .service(
                web::resource("api/topic/{topic_name}")
                    .route(web::get().to_async(fetch_topic_detail_handler)),
            )
            .service(
                web::resource("api/v2/topic/{topic_name}/reset")
                    .route(web::delete().to_async(reset_topic_handler)),
            )
            .service(
                web::resource("api/v2/topic/{topic_name}")
                    .route(web::delete().to_async(delete_topic_handler)),
            )
            .service(
                web::resource("api/topic/{topic_name}/from")
                    .route(web::get().to_async(fetch_topic_detail_from_handler)),
            )
            .service(
                web::resource("api/v2/topic/{topic_name}/messages")
                    .route(web::get().to_async(fetch_messages)),
            )
            .service(
                web::resource("api/topic/{topic_name}/sendMessage")
                    .data(
                        web::JsonConfig::default()
                            .limit(10 * 1024 * 1024)
                            .error_handler(|err, _| {
                                error::InternalError::from_response(
                                    err,
                                    HttpResponse::BadRequest().finish(),
                                )
                                .into()
                            }),
                    )
                    .route(web::post().to_async(send_message_to_topic_handler)),
            )
            // static files
            .service(fs::Files::new("/", "static").index_file("static/index.html"))
            // default
            .default_service(
                web::resource("")
                    .route(web::get().to(redirect_to_index))
                    .route(
                        web::route()
                            .guard(guard::Not(guard::Get()))
                            .to(|| HttpResponse::MethodNotAllowed()),
                    ),
            )
    })
    .bind(&listen)?
    .start();

    println!("Starting http server: {}", listen);
    sys.run()
}
