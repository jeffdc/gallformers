#!/usr/bin/env bash
#
# Postgres data loading pipeline
#
# Converts SQLite production data to Postgres and loads it into a Fly Postgres
# instance. Used for both preview refreshes and production cutover.
#
# Usage:
#   scripts/pg-load.sh -u <username> -a <fly-db-app> [-d <dbname>] [-A <fly-app>]
#
# Credentials are loaded from .env.pg-load if present. Command-line flags
# override the file. Any values still missing are prompted interactively.
#
# See runbooks/postgres-cutover.md for full documentation.

set -euo pipefail

# Defaults
USERNAME="${PG_USERNAME:-}"
PASSWORD="${PG_PASSWORD:-}"
DB_APP="${PG_DB_APP:-}"
DBNAME="${PG_DBNAME:-}"
FLY_APP="${PG_FLY_APP:-}"
LOCAL_DB="gallformers_dev"
DUMP_FILE="/tmp/gallformers.dump"
PROXY_PORT=15432
PROXY_PID=""
SQLITE_FILE="priv/gallformers.sqlite"
ENV_FILE=".env.pg-load"

# --- Load config file ---

if [ -f "$ENV_FILE" ]; then
  echo "Loading config from $ENV_FILE"
  set -a
  # shellcheck source=/dev/null
  . "$ENV_FILE"
  set +a
  # Map env file vars to script vars (env file takes precedence over defaults,
  # but command-line flags will override below)
  USERNAME="${PG_USERNAME:-$USERNAME}"
  PASSWORD="${PG_PASSWORD:-$PASSWORD}"
  DB_APP="${PG_DB_APP:-$DB_APP}"
  DBNAME="${PG_DBNAME:-$DBNAME}"
  FLY_APP="${PG_FLY_APP:-$FLY_APP}"
fi

usage() {
  cat <<EOF
Usage: $0 -u <username> -a <fly-db-app> [-d <dbname>] [-A <fly-app>]

Loads local Postgres data into a Fly Postgres instance.

Required (via flags, .env.pg-load, or interactive prompt):
  -u  Postgres username on Fly (PG_USERNAME)
  -a  Fly Postgres app name (PG_DB_APP)

Optional:
  -d  Database name, defaults to username (PG_DBNAME)
  -A  Fly app name for DATABASE_URL and deploy (PG_FLY_APP)

Config file (.env.pg-load):
  PG_USERNAME=gallformers_preview
  PG_PASSWORD=<password>
  PG_DB_APP=gallformers-db
  PG_DBNAME=gallformers_preview
  PG_FLY_APP=gallformers-preview
  LITESTREAM_ACCESS_KEY_ID=<key>
  LITESTREAM_SECRET_ACCESS_KEY=<secret>

Priority: command-line flags > .env.pg-load > interactive prompt
EOF
  exit 1
}

# --- Argument parsing (overrides config file) ---

while getopts "u:a:d:A:h" opt; do
  case $opt in
    u) USERNAME=$OPTARG ;;
    a) DB_APP=$OPTARG ;;
    d) DBNAME=$OPTARG ;;
    A) FLY_APP=$OPTARG ;;
    h) usage ;;
    *) usage ;;
  esac
done

# Prompt for any required values still missing
if [ -z "$USERNAME" ]; then
  read -p "Postgres username: " -r USERNAME
fi
if [ -z "$DB_APP" ]; then
  read -p "Fly Postgres app name: " -r DB_APP
fi
DBNAME="${DBNAME:-$USERNAME}"

# Prompt for password if not set
if [ -z "$PASSWORD" ]; then
  echo -n "Password for $USERNAME: "
  read -rs PASSWORD
  echo
fi

# --- Cleanup on exit ---

cleanup() {
  if [ -n "$PROXY_PID" ] && kill -0 "$PROXY_PID" 2>/dev/null; then
    echo ""
    echo "Stopping fly proxy (PID $PROXY_PID)..."
    kill "$PROXY_PID"
    wait "$PROXY_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# --- Helpers ---

confirm() {
  local description=$1
  shift
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  $description"
  echo "  Command: $*"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  read -p "  Proceed? [Y/n] " -r
  echo
  if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo "  Skipped."
    return 1
  fi
  return 0
}

fail() {
  echo "FAILED: $1" >&2
  exit 1
}

# --- Precondition checks ---

echo ""
echo "Checking preconditions..."
echo ""

# Check required tools
for cmd in psql pg_dump pg_restore fly mix; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    fail "$cmd is not installed or not in PATH"
  fi
  echo "  ✓ $cmd found"
done

# Check Fly CLI is authenticated
if ! fly auth whoami >/dev/null 2>&1; then
  fail "Fly CLI not authenticated. Run 'fly auth login' first."
fi
echo "  ✓ Fly CLI authenticated"

# Check local Postgres is running and database exists
if ! psql -d "$LOCAL_DB" -c "SELECT 1" >/dev/null 2>&1; then
  fail "Local Postgres database '$LOCAL_DB' is not accessible. Is Postgres running?"
fi
echo "  ✓ Local database '$LOCAL_DB' accessible"

# Check litestream availability and credentials
if command -v litestream >/dev/null 2>&1; then
  if [ -n "${LITESTREAM_ACCESS_KEY_ID:-}" ] && [ -n "${LITESTREAM_SECRET_ACCESS_KEY:-}" ]; then
    echo "  ✓ litestream found, credentials set"
    HAS_LITESTREAM=true
    LS_CREDS_SET=true
  else
    echo "  ✓ litestream found, credentials not set (will prompt if needed)"
    HAS_LITESTREAM=true
    LS_CREDS_SET=false
  fi
else
  echo "  - litestream not found (S3 download still available)"
  HAS_LITESTREAM=false
  LS_CREDS_SET=false
fi

# Check Fly Postgres app exists
if ! fly status -a "$DB_APP" >/dev/null 2>&1; then
  fail "Fly Postgres app '$DB_APP' not found or not accessible."
fi
echo "  ✓ Fly Postgres app '$DB_APP' accessible"

# Check port is available
if lsof -i :"$PROXY_PORT" >/dev/null 2>&1; then
  fail "Port $PROXY_PORT is already in use. Is another proxy running?"
fi
echo "  ✓ Port $PROXY_PORT available"

echo ""
echo "All preconditions met."

# --- Step 0: Get SQLite database ---

if [ -f "$SQLITE_FILE" ]; then
  SQLITE_SIZE=$(ls -lh "$SQLITE_FILE" | awk '{print $5}')
  echo ""
  echo "Found existing SQLite file: $SQLITE_FILE ($SQLITE_SIZE)"
  read -p "Use it? [Y/n] " -r
  echo
  if [[ $REPLY =~ ^[Nn]$ ]]; then
    NEED_SQLITE=true
  else
    NEED_SQLITE=false
  fi
else
  NEED_SQLITE=true
fi

if [ "$NEED_SQLITE" = true ]; then
  echo ""
  echo "How do you want to get the SQLite database?"
  echo "  1) Download from S3 (daily public snapshot — good for preview refreshes)"
  echo "  2) Restore from Litestream (latest data — required for production cutover)"
  read -p "Choice [1/2]: " -r SQLITE_CHOICE
  echo

  case $SQLITE_CHOICE in
    2)
      if [ "$HAS_LITESTREAM" = false ]; then
        fail "litestream is not installed. Install it first: https://litestream.io/install/"
      fi
      if [ "$LS_CREDS_SET" = false ]; then
        echo -n "LITESTREAM_ACCESS_KEY_ID: "
        read -r LITESTREAM_ACCESS_KEY_ID
        echo -n "LITESTREAM_SECRET_ACCESS_KEY: "
        read -rs LITESTREAM_SECRET_ACCESS_KEY
        echo
        export LITESTREAM_ACCESS_KEY_ID LITESTREAM_SECRET_ACCESS_KEY
      fi
      if confirm "Restore latest SQLite from Litestream" \
        "litestream restore -o $SQLITE_FILE s3://gallformers-backups/litestream"; then
        litestream restore -o "$SQLITE_FILE" s3://gallformers-backups/litestream
        SQLITE_SIZE=$(ls -lh "$SQLITE_FILE" | awk '{print $5}')
        echo "  ✓ Restored: $SQLITE_FILE ($SQLITE_SIZE)"
      fi
      ;;
    *)
      if confirm "Download SQLite from S3" "make download-db"; then
        make download-db
      fi
      ;;
  esac
fi

# Verify SQLite file exists after acquisition
if [ ! -f "$SQLITE_FILE" ]; then
  fail "SQLite file not found at $SQLITE_FILE after acquisition step."
fi

echo ""
echo "Pipeline: SQLite → local Postgres → pg_dump → fly proxy → pg_restore → Fly Postgres"
echo "  Local DB:    $LOCAL_DB"
echo "  Remote:      $USERNAME@$DB_APP / $DBNAME"
echo "  Dump file:   $DUMP_FILE"
if [ -n "$FLY_APP" ]; then
  echo "  Deploy to:   $FLY_APP"
fi

# --- Step 1: Convert SQLite to local Postgres ---

if confirm "Reset local database and convert SQLite data" "mix ecto.reset && mix convert_sqlite"; then
  mix ecto.reset
  mix convert_sqlite
fi

# --- Step 2: Verify local conversion ---

if confirm "Verify local conversion (species count)" "psql -d $LOCAL_DB -c 'SELECT count(*) FROM species;'"; then
  psql -d "$LOCAL_DB" -c "SELECT count(*) FROM species;"
fi

# --- Step 3: Dump local Postgres ---

if confirm "Dump local Postgres to $DUMP_FILE" "pg_dump --format=custom --no-owner --no-acl $LOCAL_DB > $DUMP_FILE"; then
  pg_dump --format=custom --no-owner --no-acl "$LOCAL_DB" > "$DUMP_FILE"
  DUMP_SIZE=$(ls -lh "$DUMP_FILE" | awk '{print $5}')
  echo "  Dump created: $DUMP_FILE ($DUMP_SIZE)"
fi

# --- Step 4: Start fly proxy ---

if confirm "Start fly proxy to $DB_APP on localhost:$PROXY_PORT" "fly proxy $PROXY_PORT:5432 -a $DB_APP"; then
  fly proxy "$PROXY_PORT":5432 -a "$DB_APP" &
  PROXY_PID=$!
  echo "  Proxy started (PID $PROXY_PID), waiting for connection..."
  sleep 3

  # Verify proxy is working
  if ! PGPASSWORD="$PASSWORD" psql --host=localhost --port="$PROXY_PORT" --username="$USERNAME" --dbname=postgres -c "SELECT 1" >/dev/null 2>&1; then
    fail "Could not connect through proxy. Check credentials and that the Fly Postgres machine is running."
  fi
  echo "  ✓ Proxy connection verified"
fi

# --- Step 5: Drop and recreate remote database ---

if confirm "Drop and recreate remote database '$DBNAME' (terminates existing sessions)" \
  "psql ... DROP DATABASE / CREATE DATABASE"; then
  PGPASSWORD="$PASSWORD" psql \
    --host=localhost --port="$PROXY_PORT" \
    --username="$USERNAME" --dbname=postgres <<SQL
SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$DBNAME' AND pid <> pg_backend_pid();
DROP DATABASE $DBNAME;
CREATE DATABASE $DBNAME OWNER $USERNAME;
SQL
  echo "  ✓ Database recreated"
fi

# --- Step 6: Restore dump into remote database ---

if confirm "Restore dump into remote database '$DBNAME'" \
  "pg_restore --host=localhost --port=$PROXY_PORT --username=$USERNAME --dbname=$DBNAME $DUMP_FILE"; then
  PGPASSWORD="$PASSWORD" pg_restore \
    --host=localhost \
    --port="$PROXY_PORT" \
    --username="$USERNAME" \
    --dbname="$DBNAME" \
    --no-owner \
    --no-acl \
    "$DUMP_FILE"
  echo "  ✓ Restore complete"
fi

# --- Step 7: Verify remote data ---

if confirm "Verify remote data (species count)" \
  "psql ... SELECT count(*) FROM species;"; then
  echo "  Remote:"
  PGPASSWORD="$PASSWORD" psql \
    --host=localhost --port="$PROXY_PORT" \
    --username="$USERNAME" --dbname="$DBNAME" \
    -c "SELECT count(*) FROM species;"
  echo "  Local:"
  psql -d "$LOCAL_DB" -c "SELECT count(*) FROM species;"
fi

# --- Stop proxy ---

if [ -n "$PROXY_PID" ] && kill -0 "$PROXY_PID" 2>/dev/null; then
  echo ""
  echo "Stopping fly proxy..."
  kill "$PROXY_PID"
  wait "$PROXY_PID" 2>/dev/null || true
  PROXY_PID=""
fi

# --- Step 8: Set DATABASE_URL (if fly app specified) ---

if [ -n "$FLY_APP" ]; then
  DB_URL="postgres://$USERNAME:$PASSWORD@$DB_APP.flycast:5432/$DBNAME"
  if confirm "Set DATABASE_URL on $FLY_APP" \
    "fly secrets set DATABASE_URL=postgres://$USERNAME:***@$DB_APP.flycast:5432/$DBNAME -a $FLY_APP"; then
    fly secrets set "DATABASE_URL=$DB_URL" -a "$FLY_APP"
  fi
fi

# --- Step 9: Deploy (if fly app specified) ---

if [ -n "$FLY_APP" ]; then
  if confirm "Deploy to $FLY_APP" "make preview"; then
    make preview
  fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Done!"
if [ -n "$FLY_APP" ]; then
  echo "  Verify at: https://$FLY_APP.fly.dev"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
