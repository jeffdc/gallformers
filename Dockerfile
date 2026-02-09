# Gallformers V2 - Phoenix Dockerfile
# Multi-stage build for Phoenix release with Litestream

# Stage 1: Build Elixir release
FROM hexpm/elixir:1.17.3-erlang-27.1.2-alpine-3.20.3 AS builder

# Install build dependencies (including nodejs/npm for asset dependencies)
# vips-dev is needed to compile the vix NIF for image processing
RUN apk add --no-cache build-base git nodejs npm vips-dev

WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Set build ENV
ENV MIX_ENV=prod

# Install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# Copy compile-time config files
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

# Copy application code
COPY lib lib
COPY priv priv
COPY assets assets
COPY API_VERSION API_VERSION

# Copy release overlays (server, migrate scripts)
COPY rel rel

# Copy runtime config
COPY config/runtime.exs config/

# Compile first (needed for colocated hooks)
RUN mix compile

# Install npm dependencies for assets (d3, topojson, etc.)
RUN cd assets && npm install

# Build assets (esbuild + tailwind are installed via mix)
RUN mix assets.deploy

# Build the release
RUN mix release

# Stage 2: Runtime
FROM alpine:3.20 AS runtime

# Runtime dependencies + aws-cli for database reset workflow
# vips is needed for image processing (resizing variants)
RUN apk add --no-cache libstdc++ openssl ncurses-libs sqlite su-exec aws-cli vips

# Install Litestream for continuous SQLite replication
ADD https://github.com/benbjohnson/litestream/releases/download/v0.3.13/litestream-v0.3.13-linux-amd64.tar.gz /tmp/litestream.tar.gz
RUN tar -C /usr/local/bin -xzf /tmp/litestream.tar.gz && rm /tmp/litestream.tar.gz

WORKDIR /app

# Create non-root user
RUN addgroup -g 1000 gallformers && \
    adduser -u 1000 -G gallformers -s /bin/sh -D gallformers

# Copy release from builder
COPY --from=builder --chown=gallformers:gallformers /app/_build/prod/rel/gallformers ./
COPY --chown=gallformers:gallformers litestream.yml /etc/litestream.yml

# Create data directory
RUN mkdir -p /data && chown gallformers:gallformers /data

# Copy entrypoint script (runs as root to fix permissions, then drops to gallformers)
COPY --chmod=755 docker-entrypoint.sh /app/docker-entrypoint.sh

ENV HOME=/app
ENV DATABASE_PATH=/data/gallformers.sqlite

EXPOSE 4000

# Run entrypoint as root - it fixes permissions then drops to gallformers user
CMD ["/app/docker-entrypoint.sh"]
