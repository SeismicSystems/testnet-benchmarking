# Use official Rust image as base
FROM rustlang/rust:nightly-bullseye AS chef
RUN cargo install cargo-chef
WORKDIR /app

FROM chef AS planner

# Clone the seismic-reth repo
RUN git clone https://github.com/SeismicSystems/seismic-reth.git .
# Checkout the seismic branch
RUN git checkout m/seismic
#RUN git checkout seismic

# Build argument for genesis file URL
ARG GENESIS_URL=https://testnet-benchmarking.s3.us-west-2.amazonaws.com/bench_dev.json

RUN apt-get update && apt-get install -y curl
RUN curl -o crates/seismic/chainspec/res/genesis/dev.json "${GENESIS_URL}"

# Generate recipe file
RUN cargo chef prepare --recipe-path recipe.json

FROM chef AS builder
# Install git and other dependencies
RUN apt-get update && apt-get -y upgrade && apt-get install -y libclang-dev pkg-config

# Copy recipe and build dependencies
COPY --from=planner /app/recipe.json recipe.json
RUN cargo chef cook --release --recipe-path recipe.json

# Copy source code from planner stage instead of cloning again
COPY --from=planner /app .

# Build the project (dependencies are already cached)
RUN cargo build --release

# Runtime stage
FROM debian:11-slim AS runtime
RUN apt-get update && apt-get -y upgrade && apt-get install -y libclang-dev pkg-config

WORKDIR /app
# Copy the binary from builder stage
COPY --from=builder /app/target/release/seismic-reth /app/seismic-reth

# Copy the genesis file
COPY --from=builder /app/crates/seismic/chainspec/res/genesis/dev.json /app/genesis.json


# Define the ENTRYPOINT to run the reth node with the specified arguments
ENV HTTP_PORT=8545
ENV WS_PORT=8546
ENV AUTHRPC_PORT=8551
ENV METRICS_PORT=9001
ENV PEER_PORT=30303
ENV DISCOVERY_PORT=30303

# Expose the necessary ports
EXPOSE \
    $HTTP_PORT \
    $WS_PORT \
    $AUTHRPC_PORT \
    $METRICS_PORT \
    $PEER_PORT \
    $DISCOVERY_PORT \
    30303/udp


# Set the seismic-reth binary as the entrypoint
ENTRYPOINT ["./seismic-reth", "node", "--enclave.mock-server", "--enclave.endpoint-port", "1477", "--metrics", "0.0.0.0:9001"]
CMD ["--http", "--http.addr", "0.0.0.0", "--ws", "--ws.addr", "0.0.0.0", "--authrpc.addr", "0.0.0.0", "--auth-ipc", "--auth-ipc.path", "/tmp/reth_engine_api.ipc", "--rpc.max-connections", "40000", "--txpool.pending-max-count", "40000", "--txpool.pending-max-size", "160"]
