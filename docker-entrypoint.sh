#!/bin/sh
# Docker entrypoint for Gallformers V2
# Downloads data files if needed, runs migrations, then starts the app

set -e

DISK_WARN_PERCENT=80

# Check disk usage and warn if above threshold
check_disk_usage() {
  usage=$(df /data | awk 'NR==2 {gsub(/%/,""); print $5}')
  if [ "$usage" -ge "$DISK_WARN_PERCENT" ]; then
    echo "WARNING: /data volume is ${usage}% full — consider extending the volume"
  fi
}

# Fix ownership of data directory
if [ -d /data ]; then
  chown -R gallformers:gallformers /data 2>/dev/null || echo "WARNING: Could not chown all files in /data — continuing"
fi

check_disk_usage

# Download data files from public S3 if not already on the volume
S3_BASE="https://gallformers-backups.s3.amazonaws.com/public"

if [ ! -f /data/boundaries.pmtiles ]; then
  echo "Downloading boundaries.pmtiles from S3..."
  if curl -fSL -o /data/boundaries.pmtiles "$S3_BASE/boundaries.pmtiles"; then
    chown gallformers:gallformers /data/boundaries.pmtiles
    echo "boundaries.pmtiles downloaded."
  else
    echo "WARNING: Failed to download boundaries.pmtiles — maps will not work"
    rm -f /data/boundaries.pmtiles
  fi
fi

if [ ! -f /data/wcvp.sqlite ]; then
  echo "Downloading wcvp.sqlite from S3..."
  if curl -fSL -o /data/wcvp.sqlite "$S3_BASE/wcvp.sqlite"; then
    chown gallformers:gallformers /data/wcvp.sqlite
    echo "wcvp.sqlite downloaded."
  else
    echo "WARNING: Failed to download wcvp.sqlite — WCVP lookups will not be available"
    rm -f /data/wcvp.sqlite
  fi
fi

# Symlink boundaries PMTiles from volume into static assets
if [ -f /data/boundaries.pmtiles ]; then
  mkdir -p /app/lib/gallformers-0.1.0/priv/static/data
  ln -sf /data/boundaries.pmtiles /app/lib/gallformers-0.1.0/priv/static/data/boundaries.pmtiles
fi

# Run database migrations
echo "Running database migrations..."
attempts=0
max_attempts=3
until su-exec gallformers /app/bin/gallformers eval 'Gallformers.Release.migrate()'; do
  attempts=$((attempts + 1))
  if [ "$attempts" -ge "$max_attempts" ]; then
    echo "ERROR: Migrations failed after $max_attempts attempts"
    exit 1
  fi
  echo "Migration attempt $attempts failed, retrying in 5s..."
  sleep 5
done

# Switch to gallformers user and start the app
exec su-exec gallformers /app/bin/server
