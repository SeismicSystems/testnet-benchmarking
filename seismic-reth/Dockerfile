# Use official Rust image as base
FROM rust:latest AS chef
RUN cargo install cargo-chef
WORKDIR /app

FROM chef AS planner

# Clone the seismic-reth repo
RUN git clone https://github.com/SeismicSystems/seismic-reth.git .
# Checkout the seismic branch
RUN git checkout seismic
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
FROM debian:bookworm-slim AS runtime
RUN apt-get update && apt-get -y upgrade && apt-get install -y libclang-dev pkg-config

WORKDIR /app
# Copy the binary from builder stage
COPY --from=builder /app/target/release/seismic-reth /app/seismic-reth

# Copy the genesis file
COPY --from=builder /app/crates/optimism/chainspec/res/genesis/base.json /app/genesis.json


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


# JWT secret configuration (no default - must be provided)
ENV JWT_FILE="./jwt.hex"

# Create startup script
RUN echo '#!/bin/bash\n\
# Create JWT secret file from environment variable\n\
echo "$JWT_SECRET" > "$JWT_FILE"\n\
# Initialize the database if not already done\n\
if [ ! -f "/app/.initialized" ]; then\n\
    echo "Initializing seismic-reth database..."\n\
    ./seismic-reth init --chain /app/genesis.json\n\
    touch /app/.initialized\n\
fi\n\
# Run seismic-reth with the JWT secret\n\
exec ./seismic-reth node --chain /app/genesis.json --authrpc.jwtsecret "$JWT_FILE" "$@"' > /app/start.sh && \
chmod +x /app/start.sh


# Set the startup script as the entrypoint
ENTRYPOINT ["/app/start.sh"]
CMD ["--http", "--http.addr", "0.0.0.0", "--ws", "--ws.addr", "0.0.0.0", "--authrpc.addr", "0.0.0.0"]
