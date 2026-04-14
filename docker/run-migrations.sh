#!/bin/sh
# Идемпотентный runner миграций.
# Каждый .sql файл применяется РОВНО ОДИН РАЗ.
# При перезапуске контейнера уже применённые файлы пропускаются.
set -e

PGHOST="${POSTGRES_HOST:-rso-postgres}"
PGPORT="${POSTGRES_PORT:-5432}"
PGUSER="${POSTGRES_USER:-postgres}"
PGPASSWORD="${POSTGRES_PASSWORD}"
PGDB="${POSTGRES_DB:-rso_events}"

export PGPASSWORD

# Ждём пока postgres готов
for i in $(seq 1 30); do
  psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDB" -c "SELECT 1" > /dev/null 2>&1 && break
  echo "Waiting for postgres... ($i/30)"
  sleep 2
done

# Создаём таблицу lock если её ещё нет
psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDB" -c "
CREATE TABLE IF NOT EXISTS schema_migrations (
    version    VARCHAR(255) PRIMARY KEY,
    applied_at TIMESTAMP NOT NULL DEFAULT NOW()
);" > /dev/null 2>&1 || true

echo "Running migrations..."

for f in $(ls /migrations/*.sql | sort); do
    version=$(basename "$f")

    already=$(psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDB" -tAc \
        "SELECT COUNT(*) FROM schema_migrations WHERE version='$version';" 2>/dev/null || echo "0")
    already=$(echo "$already" | tr -d ' \n\r')

    if [ "$already" = "1" ]; then
        echo "  skip: $version"
        continue
    fi

    echo "  apply: $version"
    psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDB" \
        -v ON_ERROR_STOP=1 -f "$f"

    psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDB" -c \
        "INSERT INTO schema_migrations(version) VALUES('$version') ON CONFLICT DO NOTHING;" > /dev/null
done

echo "Done."