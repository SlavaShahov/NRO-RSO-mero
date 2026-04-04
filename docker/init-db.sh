#!/bin/sh
set -eu
echo "Applying SQL migrations..."
for file in /migrations/*.sql; do
  echo "Running $file"
  psql "$POSTGRES_DSN" -v ON_ERROR_STOP=1 -f "$file"
done
echo "All migrations applied."
