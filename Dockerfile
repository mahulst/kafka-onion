# ------------------------------------------------------------------------------
# Cargo Build Stage
# Weird copy step ahead to cache dependencies:
# https://github.com/rust-lang/cargo/issues/2644
# ------------------------------------------------------------------------------

ARG BASE_IMAGE=ekidd/rust-musl-builder:latest

# Our first FROM statement declares the build environment.
FROM ${BASE_IMAGE} AS builder

USER root
RUN curl -sL https://deb.nodesource.com/setup_10.x | bash -
RUN apt-get -y install nodejs

ENV OPENSSL_DIR /usr/local/
ENV OPENSSL_STATIC=1

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

# Fix permissions on source code.
RUN sudo chown -R rust:rust ./api

USER rust
RUN rustup target add x86_64-unknown-linux-musl

WORKDIR /usr/src/kafka-onion-api/api
ENV PKG_CONFIG_ALLOW_CROSS=1
RUN cargo build --target x86_64-unknown-linux-musl --release --bin web

# ------------------------------------------------------------------------------
# Final Stage
# ------------------------------------------------------------------------------

FROM alpine:3.8
RUN apk --no-cache add ca-certificates


RUN addgroup -g 1000 kafka-onion-api

RUN adduser -D -s /bin/sh -u 1000 -G kafka-onion-api kafka-onion-api

WORKDIR /home/kafka-onion-api/bin/

COPY --from=builder /usr/src/kafka-onion-api/api/target/x86_64-unknown-linux-musl/release/web .

RUN mkdir static
COPY --from=builder /usr/src/kafka-onion-api/frontend/build ./static

RUN chown kafka-onion-api:kafka-onion-api web

USER kafka-onion-api

CMD ["./web"]