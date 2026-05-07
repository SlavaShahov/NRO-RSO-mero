#!/bin/sh
set -eu
: "${POSTGRES_DSN:?POSTGRES_DSN is required}"
: "${CLEANUP_INTERVAL_SECONDS:=300}"

echo "cleanup worker started; interval=${CLEANUP_INTERVAL_SECONDS}s"

while true; do
  # 1. Отозванные JWT-токены с истёкшим сроком
  psql "$POSTGRES_DSN" -v ON_ERROR_STOP=1 -c \
    "DELETE FROM revoked_tokens WHERE expires_at <= NOW();"

  # 2. Прочитанные уведомления старше 30 дней
  psql "$POSTGRES_DSN" -v ON_ERROR_STOP=1 -c \
    "DELETE FROM user_notifications
     WHERE is_read = true
       AND created_at < NOW() - INTERVAL '30 days';"

  # 3. Непрочитанные уведомления старше 90 дней
  psql "$POSTGRES_DSN" -v ON_ERROR_STOP=1 -c \
    "DELETE FROM user_notifications
     WHERE is_read = false
       AND created_at < NOW() - INTERVAL '90 days';"

  # 4. Попытки входа старше 24 часов (они нужны только для брутфорс-защиты)
  psql "$POSTGRES_DSN" -v ON_ERROR_STOP=1 -c \
    "DELETE FROM login_attempts
     WHERE attempted_at < NOW() - INTERVAL '24 hours';"

  # 5. Коды верификации email старше 1 часа (expires_at уже прошёл)
  psql "$POSTGRES_DSN" -v ON_ERROR_STOP=1 -c \
    "DELETE FROM email_verifications
     WHERE expires_at < NOW() - INTERVAL '1 hour';"

  # 6. Коды сброса пароля с истёкшим сроком
  psql "$POSTGRES_DSN" -v ON_ERROR_STOP=1 -c \
    "DELETE FROM password_resets
     WHERE expires_at < NOW() - INTERVAL '1 hour';"

  # 7. Запросы смены email с истёкшим сроком
  psql "$POSTGRES_DSN" -v ON_ERROR_STOP=1 -c \
    "DELETE FROM email_change_requests
     WHERE expires_at < NOW() - INTERVAL '1 hour';"

  sleep "$CLEANUP_INTERVAL_SECONDS"
done
