# ------------------------------------------------------------------------------
# Cargo Build Stage
# Weird copy step ahead to cache dependencies:
# https://github.com/rust-lang/cargo/issues/2644
# ------------------------------------------------------------------------------

FROM rust:latest as cargo-build

RUN apt-get update
RUN curl -sL https://deb.nodesource.com/setup_10.x | bash -
RUN apt-get install -y nodejs

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
RUN cargo build --bin --release web

# ------------------------------------------------------------------------------
# Final Stage
# ------------------------------------------------------------------------------

FROM rust:slim-stretch

RUN addgroup kafka-onion-api

RUN adduser --ingroup kafka-onion-api kafka-onion-api

WORKDIR /home/kafka-onion-api/bin/

COPY --from=cargo-build /usr/src/kafka-onion-api/api/target/release/web .

RUN mkdir static
COPY --from=cargo-build /usr/src/kafka-onion-api/frontend/build ./static

RUN chown kafka-onion-api:kafka-onion-api web

USER kafka-onion-api

CMD ["./web"]