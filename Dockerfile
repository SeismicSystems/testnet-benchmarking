# --- Stage 1: Prepare build dependencies with cargo-chef ---
FROM lukemathwalker/cargo-chef:latest-rust-1 AS chef

WORKDIR /workspace

# Clone and prepare seismic-reth repo
RUN git clone https://github.com/SeismicSystems/seismic-reth.git \
    && cd seismic-reth && git checkout seismic \
    && cp crates/optimism/chainspec/res/genesis/base.json crates/seismic/chainspec/res/genesis/dev.json
WORKDIR /workspace/seismic-reth
RUN cargo chef prepare --recipe-path recipe-seismic-reth.json

# Clone and prepare second repo
#WORKDIR /workspace
#RUN git clone https://github.com/your-org/repo-two.git
#WORKDIR /workspace/repo-two
#RUN cargo chef prepare --recipe-path recipe-two.json

# --- Stage 2: Build dependencies using cached layers ---
FROM lukemathwalker/cargo-chef:latest-rust-1 AS builder

WORKDIR /workspace

# Clone repos again
RUN git clone https://github.com/SeismicSystems/seismic-reth.git \
    && cd seismic-reth && git checkout seismic \
    && cp crates/optimism/chainspec/res/genesis/base.json crates/seismic/chainspec/res/genesis/dev.json
#RUN git clone https://github.com/your-org/repo-two.git

# Build dependencies for seismic-reth
WORKDIR /workspace/seismic-reth
COPY --from=chef /workspace/seismic-reth/recipe-seismic-reth.json recipe.json
RUN cargo chef cook --recipe-path recipe.json

# Build dependencies for repo-two
#WORKDIR /workspace/repo-two
#COPY --from=chef /workspace/repo-two/recipe-two.json recipe.json
#RUN cargo chef cook --recipe-path recipe.json

# Now build both apps
WORKDIR /workspace/seismic-reth
RUN cargo build --release

#WORKDIR /workspace/repo-two
#RUN cargo build --release

# --- Stage 3: Minimal runtime image ---
FROM ubuntu:latest AS runtime

WORKDIR /app

# Copy the binaries
COPY --from=builder /workspace/seismic-reth/target/release/seismic-reth ./reth
#COPY --from=builder /workspace/repo-two/target/release/repo-two-binary ./repo-two

# Add non-root user (optional security)
RUN useradd -m appuser
USER appuser

# Reth ports
ENV HTTP_PORT=8545
ENV WS_PORT=8546
ENV AUTHRPC_PORT=8551
ENV METRICS_PORT=9001
ENV PEER_PORT=30303
ENV DISCOVERY_PORT=30303

# Consensus ports 


# Expose the necessary ports
EXPOSE \
    $HTTP_PORT \
    $WS_PORT \
    $AUTHRPC_PORT \
    $METRICS_PORT \
    $PEER_PORT \
    $DISCOVERY_PORT \
    30303/udp 

# Run both binaries (use wait to keep container alive)
#CMD ./repo-one & ./repo-two && wait
CMD ["./reth"]