# ------------------------------------------------------------------------------
# Cargo Build Stage
# ------------------------------------------------------------------------------

ARG BASE_IMAGE=ekidd/rust-musl-builder:latest

# Our first FROM statement declares the build environment.
FROM rust AS builder

USER root
RUN curl -sL https://deb.nodesource.com/setup_10.x | bash -
RUN apt-get -y install nodejs

WORKDIR /usr/src/kafka-onion-api
RUN mkdir frontend
COPY frontend/package.json ./frontend

WORKDIR /usr/src/kafka-onion-api/frontend
RUN npm install

WORKDIR /usr/src/kafka-onion-api/
COPY frontend ./frontend

WORKDIR /usr/src/kafka-onion-api/frontend
RUN npm run build

WORKDIR /usr/src/kafka-onion-api/
COPY api ./api

WORKDIR /usr/src/kafka-onion-api/api
RUN apt-get install -y llvm-3.9-dev libclang-3.9-dev clang-3.9

RUN cargo build --release --bin web

# ------------------------------------------------------------------------------
# Final Stage
# ------------------------------------------------------------------------------

FROM rust:slim

RUN adduser kafka-onion-api

WORKDIR /home/kafka-onion-api/bin/

COPY --from=builder /usr/src/kafka-onion-api/api/target/release/web .

RUN mkdir static
COPY --from=builder /usr/src/kafka-onion-api/frontend/build ./static

RUN chown kafka-onion-api:kafka-onion-api web

USER kafka-onion-api

CMD ["./web"]
