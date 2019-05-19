#[macro_use]
extern crate serde_derive;

#[macro_use]
extern crate actix_web;

use std::{env, io};

use actix_files as fs;
use actix_web::http::StatusCode;
use actix_web::middleware::cors::Cors;
use actix_web::{error, guard, middleware, web, App, Error, HttpResponse, HttpServer, Result};
use futures::Future;
use read_topic_api::{
    fetch_from_topic_detail, fetch_latest_topic_detail, fetch_topics, get_client, PartitionOffsets,
};

#[get("/favicon")]
fn favicon() -> Result<fs::NamedFile> {
    Ok(fs::NamedFile::open("static/favicon.ico")?)
}

fn redirect_to_index() -> Result<fs::NamedFile> {
    eprintln!("@@");
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
struct PartitionFromRequest {
    topic_name: String,
    partition_offsets: PartitionOffsets,
}

fn fetch_topic_detail_from_handler(
    item: web::Json<PartitionFromRequest>,
) -> impl Future<Item=HttpResponse, Error=Error> {
    web::block(move || {
        let mut client = get_client();

        fetch_from_topic_detail(&mut client, &item.topic_name, &item.partition_offsets)
    })
        .then(|res| match res {
            Ok(topics) => Ok(HttpResponse::Ok().json(topics)),
            Err(_) => Ok(HttpResponse::InternalServerError().into()),
        })
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
                    .allowed_origin("http://localhost:3000")
                    .allowed_methods(vec!["GET", "POST"])
            )
            .service(favicon)
            .service(web::resource("api/topics").route(web::get().to_async(fetch_topics_handler)))
            .service(
                web::resource("api/topic/{topic_name}")
                    .route(web::get().to_async(fetch_topic_detail_handler)),
            )
            .service(
                web::resource("api/topic/{topic_name}/from")
                    .data(
                        web::JsonConfig::default()
                            .limit(4096)
                            .error_handler(|err, _| {
                                error::InternalError::from_response(
                                    err,
                                    HttpResponse::Conflict().finish(),
                                )
                                    .into()
                            }),
                    )
                    .route(web::get().to_async(fetch_topic_detail_from_handler)),
            )
            // static files
            .service(fs::Files::new("/", "static").show_files_listing())
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
