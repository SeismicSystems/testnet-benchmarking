
# ──────────────────────────────────────────────
# Base nightly image (rolling latest)
# ──────────────────────────────────────────────
FROM rustlang/rust:nightly-bookworm AS chef
WORKDIR /app

# ✅ Copy rust-toolchain.toml so Cargo pins nightly automatically
COPY rust-toolchain.toml .

# ✅ Install cargo-chef (will use pinned nightly)
RUN cargo install cargo-chef

# Copy everything for planning
COPY . .

# Prepare recipe.json
RUN cargo chef prepare --recipe-path recipe.json


# ──────────────────────────────────────────────
FROM rustlang/rust:nightly-bookworm AS cacher
WORKDIR /app

COPY rust-toolchain.toml .
RUN cargo install cargo-chef
COPY --from=chef /app/recipe.json recipe.json

# ✅ Cargo will auto-pull pinned nightly from rust-toolchain.toml
RUN cargo chef cook --release --recipe-path recipe.json


# ──────────────────────────────────────────────
FROM rustlang/rust:nightly-bookworm AS builder
WORKDIR /app

COPY rust-toolchain.toml .
COPY --from=cacher /app/target target
COPY --from=cacher /usr/local/cargo /usr/local/cargo
COPY . .

# Build your binary
RUN cargo build --release


# ──────────────────────────────────────────────
FROM debian:bookworm-slim AS runtime
WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
 && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/target/release/tx-sender /usr/local/bin/tx-sender
CMD ["tx-sender"]

