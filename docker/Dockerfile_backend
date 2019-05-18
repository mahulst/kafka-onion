# ------------------------------------------------------------------------------
# Cargo Build Stage
# Weird copy step ahead to cache dependencies:
# https://github.com/rust-lang/cargo/issues/2644
# ------------------------------------------------------------------------------

FROM rust:latest as cargo-build
WORKDIR /usr/src/kafka-onion-api

COPY . .
RUN cargo build --release --bin web

# ------------------------------------------------------------------------------
# Final Stage
# ------------------------------------------------------------------------------

FROM rust:slim-stretch

RUN addgroup kafka-onion-api

RUN adduser --ingroup kafka-onion-api kafka-onion-api

WORKDIR /home/kafka-onion-api/bin/

COPY --from=cargo-build /usr/src/kafka-onion-api/target/release/web .

RUN chown kafka-onion-api:kafka-onion-api web

USER kafka-onion-api

CMD ["./web"]