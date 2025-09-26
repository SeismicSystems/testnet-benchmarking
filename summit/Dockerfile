# Use official Rust image as base
FROM rust:latest AS chef
RUN cargo install cargo-chef
WORKDIR /app

FROM chef AS planner
# Accept build arguments
ARG mode=prom

# Clone the repository using PAT
RUN git clone https://github.com/SeismicSystems/summit.git .

# Checkout specific branch if needed
RUN git fetch
#RUN git checkout m/benchnet
RUN git checkout m/benchmarks

# Generate recipe file
RUN cargo chef prepare --recipe-path recipe.json

FROM chef AS builder
# Accept build arguments in builder stage
ARG mode=prom

# Install dependencies
RUN apt-get update && apt-get -y upgrade && apt-get install -y \
    clang \
    git \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy recipe and build dependencies
COPY --from=planner /app/recipe.json recipe.json
RUN cargo chef cook --features ${mode} --release --recipe-path recipe.json

# Copy source code from planner stage (PAT is not included here)
COPY --from=planner /app .

# Build the project
RUN cargo build --features ${mode} --release

# Save git commit info
RUN git log -1 --format="%H %cd %s" > /tmp/git-info.txt

# Runtime stage
FROM debian:bookworm-slim AS runtime
RUN apt-get update && apt-get -y upgrade && apt-get install -y \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy the binary from builder stage
COPY --from=builder /app/target/release/summit /app/summit

# Copy git commit info from builder stage
COPY --from=builder /tmp/git-info.txt /app/git-info.txt

# Environment variables for the consensus arguments

ENV PORT=8080
ENV PROM_PORT=9090
ENV IPC_PATH="/tmp/reth_engine_api.ipc"

EXPOSE \
    $PORT \
    $PROM_PORT


# Run summit directly
ENTRYPOINT ["./summit", "run"]
CMD ["--prom-port", "9090", \
     "--engine-ipc-path", "/tmp/reth_engine_api.ipc", \
     "--share-path", "./share.pem", \
     "--key-path", "./key.pem", \
     "--store-path", "./store"]
