-- ═══════════════════════════════════════════════════════════════════════════
-- Миграция 017: Исправление 1НФ — замена JSONB в notifications и user_notifications
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. notifications (если таблица существует) ────────────────────────────
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_name = 'notifications'
    ) THEN
        -- action_data JSONB → скалярные поля
        IF EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_name='notifications' AND column_name='action_data'
        ) THEN
            ALTER TABLE notifications
                ADD COLUMN IF NOT EXISTS action_url      VARCHAR(500),
                ADD COLUMN IF NOT EXISTS action_event_id INTEGER REFERENCES events(id) ON DELETE SET NULL;

            UPDATE notifications
            SET action_url      = action_data->>'url',
                action_event_id = (action_data->>'event_id')::INTEGER
            WHERE action_data IS NOT NULL;

            ALTER TABLE notifications DROP COLUMN action_data;
        END IF;

        -- filters JSONB → таблица notification_filters
        IF EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_name='notifications' AND column_name='filters'
        ) THEN
            CREATE TABLE IF NOT EXISTS notification_filters (
                id              SERIAL PRIMARY KEY,
                notification_id INTEGER NOT NULL REFERENCES notifications(id) ON DELETE CASCADE,
                filter_type     VARCHAR(50) NOT NULL
                    CHECK (filter_type IN ('role','direction','hq','unit','position')),
                filter_value    VARCHAR(100) NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_notif_filters_notif
                ON notification_filters (notification_id);

            ALTER TABLE notifications DROP COLUMN filters;
        END IF;
    END IF;
END $$;

-- ── 2. user_notifications: data JSONB → скалярные поля ───────────────────
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name='user_notifications' AND column_name='data'
    ) THEN
        ALTER TABLE user_notifications
            ADD COLUMN IF NOT EXISTS ref_id       INTEGER,
            ADD COLUMN IF NOT EXISTS ref_type     VARCHAR(50),
            ADD COLUMN IF NOT EXISTS ref_approved BOOLEAN;

        -- Переносим данные из JSONB в скалярные поля
        UPDATE user_notifications
        SET ref_id       = COALESCE(
                               (data->>'request_id')::INTEGER,
                               (data->>'event_id')::INTEGER
                           ),
            ref_type     = CASE
                               WHEN data->>'request_id' IS NOT NULL THEN 'request'
                               WHEN data->>'event_id'   IS NOT NULL THEN 'event'
                               ELSE NULL
                           END,
            ref_approved = (data->>'approved')::BOOLEAN
        WHERE data IS NOT NULL AND data::text != '{}';

        ALTER TABLE user_notifications DROP COLUMN data;
    END IF;
END $$;

-- Индексы для новых полей
CREATE INDEX IF NOT EXISTS idx_user_notif_ref ON user_notifications (ref_type, ref_id)
    WHERE ref_id IS NOT NULL;
