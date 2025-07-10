# Multi-stage build for tx-sender
FROM rust:1.75-slim as builder

WORKDIR /app

# Copy Cargo files
COPY Cargo.toml Cargo.lock ./

# Create a dummy main.rs to build dependencies
RUN mkdir src && echo "fn main() {}" > src/main.rs

# Build dependencies
RUN cargo build --release

# Remove dummy main.rs and copy real source
RUN rm src/main.rs
COPY src/ ./src/

# Build the application
RUN cargo build --release

# Runtime stage
FROM debian:bookworm-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy the binary
COPY --from=builder /app/target/release/tx-sender ./tx-sender

# Copy transaction data
COPY raw_transactions.json ./

# Create non-root user
RUN useradd -m appuser
USER appuser

# Expose port for metrics/health checks
EXPOSE 8080

# Run the application
CMD ["./tx-sender"] 