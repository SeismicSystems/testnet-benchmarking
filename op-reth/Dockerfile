# Use official Rust image as base
FROM rust:latest AS chef
RUN cargo install cargo-chef
WORKDIR /app

FROM chef AS planner

# Clone the seismic-reth repo
RUN git clone https://github.com/SeismicSystems/seismic-reth.git .
# Checkout the seismic branch
RUN git checkout m/reth-benchmark

RUN apt-get update && apt-get install -y curl

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
RUN cargo build --bin op-reth --package op-reth --release

# Runtime stage
FROM debian:bookworm-slim AS runtime
RUN apt-get update && apt-get -y upgrade && apt-get install -y libclang-dev pkg-config

WORKDIR /app
# Copy the binary from builder stage
COPY --from=builder /app/target/release/op-reth /app/op-reth


# Configuration matching bash script
ENV HTTP_PORT=8545
ENV WS_PORT=8546
ENV ENGINE_PORT=8551
ENV METRICS_PORT=9001
ENV P2P_PORT=30303
ENV DATA_DIR="/app/data"
ENV IPC_PATH="/tmp/reth-engine.ipc"

# Expose the necessary ports
EXPOSE \
    $HTTP_PORT \
    $WS_PORT \
    $ENGINE_PORT \
    $METRICS_PORT \
    $P2P_PORT \
    30303/udp

# Create data directory
RUN mkdir -p "$DATA_DIR"

# Run seismic-reth directly with Base mainnet configuration
ENTRYPOINT ["./op-reth", "node"]
CMD ["--chain", "base", \
     "--datadir", "/app/data", \
     "--port", "30303", \
     "--http", \
     "--http.port", "8545", \
     "--http.addr", "0.0.0.0", \
     "--http.corsdomain", "*", \
     "--ws", \
     "--ws.port", "8546", \
     "--ws.addr", "0.0.0.0", \
     "--auth-ipc", \
     "--auth-ipc.path", "/tmp/reth-engine.ipc", \
     "--full", \
     "--discovery.port", "30303", \
     "--metrics", "0.0.0.0:9001", \
     "--log.stdout.filter", "info", \
     "-vvv"]
