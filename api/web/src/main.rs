#[macro_use]
extern crate serde_derive;

#[macro_use]
extern crate actix_web;

use std::{env, io};

use actix_files as fs;
use actix_web::http::StatusCode;
use actix_web::middleware::cors::Cors;
use actix_web::web::Query;
use actix_web::{error, guard, middleware, web, App, Error, HttpResponse, HttpServer, Result};
use futures::Future;
use read_topic_api::{
    fetch_from_topic_detail, fetch_latest_topic_detail, fetch_topics, get_client,
    send_message_to_topic, PartitionOffsets,
};
use std::collections::HashMap;

#[get("/favicon")]
fn favicon() -> Result<fs::NamedFile> {
    Ok(fs::NamedFile::open("static/favicon.ico")?)
}

fn redirect_to_index() -> Result<fs::NamedFile> {
    Ok(fs::NamedFile::open("static/index.html")?.set_status_code(StatusCode::OK))
}

fn fetch_topics_handler() -> impl Future<Item=HttpResponse, Error=Error> {
    web::block(move || {
        let mut client = get_client();

        fetch_topics(&mut client)
    })
        .then(|res| match res {
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
) -> impl Future<Item=HttpResponse, Error=Error> {
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
    let mut partition_offsets = HashMap::new();
    let partition_offsets: HashMap<i32, i64> =
        partitions
            .iter()
            .fold(partition_offsets, |mut acc, (partition, offset)| {
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
) -> impl Future<Item=HttpResponse, Error=Error> {
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
) -> impl Future<Item=HttpResponse, Error=Error> {
    web::block(move || {
        let mut client = get_client();

        send_message_to_topic(&mut client, &topic_name, item.partition, &item.message)
    })
        .then(|res| match res {
            Ok(topics) => Ok(HttpResponse::Ok().finish()),
            Err(_) => Ok(HttpResponse::InternalServerError().into()),
        })
}

fn string_to_static_str(s: String) -> &'static str {
    Box::leak(s.into_boxed_str())
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
            .wrap(
                Cors::new()
                    .allowed_methods(vec!["GET", "POST"]),
            )
            .service(favicon)
            .service(web::resource("api/topics").route(web::get().to_async(fetch_topics_handler)))
            .service(
                web::resource("api/topic/{topic_name}")
                    .route(web::get().to_async(fetch_topic_detail_handler)),
            )
            .service(
                web::resource("api/topic/{topic_name}/from")
                    .route(web::get().to_async(fetch_topic_detail_from_handler)),
            )
            .service(
                web::resource("api/topic/{topic_name}/sendMessage")
                    .data(
                        web::JsonConfig::default()
                            .limit(4096) // <- limit size of the payload
                            .error_handler(|err, _| {
                                // <- create custom error response
                                error::InternalError::from_response(
                                    err,
                                    HttpResponse::Conflict().finish(),
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
