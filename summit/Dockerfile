# Use official Rust image as base
FROM rust:latest AS chef
RUN cargo install cargo-chef
WORKDIR /app

FROM chef AS planner
# Accept PAT as build argument (not stored in final image)

# Clone the repository using PAT
RUN git clone https://github.com/SeismicSystems/summit.git .

# Checkout specific branch if needed
#RUN git checkout devnet
RUN git fetch
RUN git checkout m/tests

# Generate recipe file
RUN cargo chef prepare --recipe-path recipe.json

FROM chef AS builder
# Install dependencies
RUN apt-get update && apt-get -y upgrade && apt-get install -y \
    clang \
    git \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy recipe and build dependencies
COPY --from=planner /app/recipe.json recipe.json
RUN cargo chef cook --features prom --release --recipe-path recipe.json

# Copy source code from planner stage (PAT is not included here)
COPY --from=planner /app .

# Build the project
RUN cargo build --features prom --release

# Runtime stage
FROM debian:bookworm-slim AS runtime
RUN apt-get update && apt-get -y upgrade && apt-get install -y \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy the binary from builder stage
COPY --from=builder /app/target/release/summit /app/summit

# Environment variables for the consensus arguments

ENV PORT=8080
ENV PROM_PORT=9090
ENV IPC_PATH="/tmp/reth_engine_api.ipc"

EXPOSE \
    $PORT \
    $PROM_PORT


# Create startup script
RUN echo '#!/bin/bash\n\
# Run summit with IPC path\n\
exec ./summit run --prom-port "$PROM_PORT" --engine-ipc-path "$IPC_PATH" --share-path ./share.pem --key-path ./key.pem --store-path ./store "$@"' > /app/start.sh && \
chmod +x /app/start.sh


# Set the startup script as the entrypoint
ENTRYPOINT ["/app/start.sh"]
