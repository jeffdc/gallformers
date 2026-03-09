#!/bin/sh
# Docker entrypoint for Gallformers preview deploys
# Runs migrations then starts the server (no Litestream replication)

set -e

DATABASE_PATH="${DATABASE_PATH:-/app/data/gallformers.sqlite}"

# Symlink boundaries PMTiles into static assets
if [ -f /app/data/boundaries.pmtiles ]; then
  mkdir -p /app/lib/gallformers-0.1.0/priv/static/data
  ln -sf /app/data/boundaries.pmtiles /app/lib/gallformers-0.1.0/priv/static/data/boundaries.pmtiles
fi

# Skip migrations — the database is baked into the image at build time
# with all migrations already applied. Running eval here would boot the
# entire BEAM VM a second time just to no-op, roughly doubling cold start.

echo "Starting server..."
exec /app/bin/server
