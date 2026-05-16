# Gallformers V2 - Phoenix Dockerfile
# Multi-stage build for Phoenix release

# Stage 0: Install JS production dependencies in isolation.
# Running npm ci here (rather than copying the npm binary into the builder stage)
# avoids breakage when node:22-alpine updates npm's internal layout.
FROM node:22-alpine AS assets
WORKDIR /assets
COPY assets/package.json assets/package-lock.json ./
RUN npm ci --omit=dev

# Stage 1: Build Elixir release
FROM hexpm/elixir:1.17.3-erlang-27.1.2-alpine-3.20.3 AS builder

# Install build dependencies
# vips-dev is needed to compile the vix NIF for image processing
RUN apk add --no-cache build-base git python3 py3-pip vips-dev

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

# Vendor the Python extractor dependencies into priv/python for release images.
RUN python3 -m pip install --no-cache-dir --target /app/priv/python/vendor /app/priv/python

# Compile first (needed for colocated hooks)
RUN mix compile

# Pull the pre-built node_modules from the assets stage.
COPY --from=assets /assets/node_modules ./assets/node_modules

# Build assets (esbuild + tailwind are installed via mix)
RUN mix assets.deploy

# Build the release
RUN mix release

# Stage 2: Runtime
FROM alpine:3.20 AS runtime

# Runtime dependencies
# python3 is needed for the PDF text extractor shipped under priv/python
# vips is needed for image processing (resizing variants)
# curl is needed for downloading data files from S3 on first boot
RUN apk add --no-cache libstdc++ openssl ncurses-libs python3 su-exec vips curl

# Install Typst for PDF generation of identification keys
ADD https://github.com/typst/typst/releases/download/v0.14.2/typst-x86_64-unknown-linux-musl.tar.xz /tmp/typst.tar.xz
RUN tar -C /usr/local/bin -xf /tmp/typst.tar.xz --strip-components=1 typst-x86_64-unknown-linux-musl/typst && rm /tmp/typst.tar.xz

WORKDIR /app

# Create non-root user
RUN addgroup -g 1000 gallformers && \
    adduser -u 1000 -G gallformers -s /bin/sh -D gallformers

# Copy release from builder
COPY --from=builder --chown=gallformers:gallformers /app/_build/prod/rel/gallformers ./

# Create data directory
RUN mkdir -p /data && chown gallformers:gallformers /data

# Copy entrypoint script (runs as root to fix permissions, then drops to gallformers)
COPY --chmod=755 docker-entrypoint.sh /app/docker-entrypoint.sh

ENV HOME=/app

EXPOSE 4000

# Run entrypoint as root - it fixes permissions then drops to gallformers user
CMD ["/app/docker-entrypoint.sh"]
