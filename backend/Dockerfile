FROM rust:1.65 AS builder

COPY . .
RUN cargo build --config net.git-fetch-with-cli=true --release

FROM debian:buster-slim
COPY --from=builder ./target/release/aptos-hong-bao-backend /bin/aptos-hong-bao-backend
CMD ["/bin/aptos-hong-bao-backend"]
