#!/bin/sh
set -eu
: "${POSTGRES_DSN:?POSTGRES_DSN is required}"
: "${CLEANUP_INTERVAL_SECONDS:=300}"
echo "revoked_tokens cleanup worker started; interval=${CLEANUP_INTERVAL_SECONDS}s"
while true; do
  psql "$POSTGRES_DSN" -v ON_ERROR_STOP=1 -c "DELETE FROM revoked_tokens WHERE expires_at <= NOW();"
  sleep "$CLEANUP_INTERVAL_SECONDS"
done
