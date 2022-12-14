FROM rust:1.65 AS builder

COPY . .

RUN apt-get update && apt-get install -y \
    binutils \
    cmake \
    curl \
    clang \
    git \
    pkg-config \
    libssl-dev \
    libpq-dev \
    lld \
    libssl1.1 \
    ca-certificates \
    linux-perf \
    sudo \
    procps \
    gdb \
    curl \
    # postgres client lib required for indexer
    libpq-dev

RUN cargo build --config net.git-fetch-with-cli=true --release

FROM debian:buster-slim
COPY --from=builder ./target/release/aptos-hong-bao-backend /bin/aptos-hong-bao-backend

RUN apt-get update && apt-get install -y \
    libssl1.1 \
    ca-certificates \
    net-tools \
    tcpdump \
    iproute2 \
    netcat \
    libpq-dev

CMD ["/bin/aptos-hong-bao-backend"]
