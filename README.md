[![Build Status](https://travis-ci.org/mahulst/kafka-onion.svg?branch=master)](https://travis-ci.org/mahulst/kafka-onion)

# Kafka Onion

A tiny, lightweight interface you can used to inspect kafka topics while developing.

**Warning** This has not been tested in any production environment so no guarantees...

A docker image is pushed by this repository to [docker hub.](https://cloud.docker.com/repository/docker/mahulst/kafka-ui)

You can view the docker-compose.yml on how you can use it.

## Screenshot

![Preview of interface][screenshot]

## Development

To develop there are two parts you need to start:

1) `./frontend`  
2) `./api`


For 1) you need to be in the frontend folder and run the following commands:  

1) `$ npm install` (only once)  
2) `$ npm run start`

A development server with hot reloading will be started on http://localhost:3000


For 2) you just need to run:
`$ cargo run --bin web`


[screenshot]: https://raw.githubusercontent.com/mahulst/kafka-onion/master/docs/screenshot.png "Preview of interface"
