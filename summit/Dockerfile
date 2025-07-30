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
RUN git checkout d/threshold-simplex

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
ENV ENGINE_JWT=""
ENV PORT=8080
ENV PROM_PORT=9090

EXPOSE \
    $PORT \
    $PROM_PORT

# JWT secret configuration (no default - must be provided)
ENV JWT_FILE="./jwt.hex"

# Create startup script
RUN echo '#!/bin/bash\n\
# Create JWT secret file from environment variable\n\
echo "$JWT_SECRET" > "$JWT_FILE"\n\
# Run summit with the JWT secret\n\
exec ./summit --engine-jwt-path "$JWT_FILE" --prom-port "$PROM_PORT" --share-path ./share.pem --key-path ./key.pem --store-path ./store "$@" run' > /app/start.sh && \
chmod +x /app/start.sh


# Set the startup script as the entrypoint
ENTRYPOINT ["/app/start.sh"]
