-- ═══════════════════════════════════════════════════════════════════════════
-- Миграция 006: Migration lock + уведомления для ШСО-заявок и мероприятий
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Migration lock — чтобы данные не дублировались при перезапуске ───────
-- Таблица хранит выполненные миграции. docker-entrypoint.sh проверяет её
-- и пропускает уже применённые файлы.
CREATE TABLE IF NOT EXISTS schema_migrations (
    version     VARCHAR(255) PRIMARY KEY,
    applied_at  TIMESTAMP NOT NULL DEFAULT NOW()
);

-- ── 2. Дополнительные типы уведомлений ───────────────────────────────────────
INSERT INTO notification_types(code, name) VALUES
    ('hq_staff_request',   'Заявка на должность ШСО'),
    ('hq_staff_approved',  'Заявка ШСО одобрена'),
    ('hq_staff_rejected',  'Заявка ШСО отклонена'),
    ('new_event_created',  'Создано новое мероприятие')
ON CONFLICT (code) DO NOTHING;

-- ── 3. Таблица пользовательских уведомлений (inbox) ─────────────────────────
-- Каждое уведомление адресовано конкретному пользователю
CREATE TABLE IF NOT EXISTS user_notifications (
    id          SERIAL PRIMARY KEY,
    user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type_code   VARCHAR(50) NOT NULL,
    title       VARCHAR(255) NOT NULL,
    body        TEXT NOT NULL,
    data        JSONB,            -- доп. данные (request_id, event_id и т.п.)
    is_read     BOOLEAN NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS user_notif_user_idx  ON user_notifications (user_id);
CREATE INDEX IF NOT EXISTS user_notif_read_idx  ON user_notifications (user_id, is_read);
CREATE INDEX IF NOT EXISTS user_notif_time_idx  ON user_notifications (created_at DESC);