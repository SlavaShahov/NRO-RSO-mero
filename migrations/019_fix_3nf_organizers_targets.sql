-- ═══════════════════════════════════════════════════════════════════════════
-- Миграция 019: Исправление 3НФ — полиморфные FK в events и notifications
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. events: organizer_* → event_organizers ────────────────────────────
CREATE TABLE IF NOT EXISTS event_organizers (
    id             SERIAL PRIMARY KEY,
    event_id       INTEGER NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    organizer_type VARCHAR(20) NOT NULL
        CHECK (organizer_type IN ('regional','local','unit')),
    organizer_id   INTEGER NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_event_organizers_event
    ON event_organizers (event_id);
CREATE INDEX IF NOT EXISTS idx_event_organizers_type
    ON event_organizers (organizer_type, organizer_id);

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_name='events' AND column_name='organizer_regional_id') THEN
        INSERT INTO event_organizers (event_id, organizer_type, organizer_id)
        SELECT id, 'regional', organizer_regional_id
        FROM events WHERE organizer_regional_id IS NOT NULL
        ON CONFLICT DO NOTHING;

        ALTER TABLE events DROP COLUMN organizer_regional_id;
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_name='events' AND column_name='organizer_local_id') THEN
        INSERT INTO event_organizers (event_id, organizer_type, organizer_id)
        SELECT id, 'local', organizer_local_id
        FROM events WHERE organizer_local_id IS NOT NULL
        ON CONFLICT DO NOTHING;

        ALTER TABLE events DROP COLUMN organizer_local_id;
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_name='events' AND column_name='organizer_unit_id') THEN
        INSERT INTO event_organizers (event_id, organizer_type, organizer_id)
        SELECT id, 'unit', organizer_unit_id
        FROM events WHERE organizer_unit_id IS NOT NULL
        ON CONFLICT DO NOTHING;

        ALTER TABLE events DROP COLUMN organizer_unit_id;
    END IF;
END $$;

-- ── 2. notifications: target_* → notification_targets ────────────────────
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables
               WHERE table_name = 'notifications') THEN

        CREATE TABLE IF NOT EXISTS notification_targets (
            id              SERIAL PRIMARY KEY,
            notification_id INTEGER NOT NULL REFERENCES notifications(id) ON DELETE CASCADE,
            target_type     VARCHAR(20) NOT NULL
                CHECK (target_type IN ('regional','local','unit','direction','event','all')),
            target_id       INTEGER
        );
        CREATE INDEX IF NOT EXISTS idx_notif_targets_notif
            ON notification_targets (notification_id);

        IF EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='notifications' AND column_name='target_regional_id') THEN
            INSERT INTO notification_targets (notification_id, target_type, target_id)
            SELECT id,'regional',target_regional_id FROM notifications WHERE target_regional_id IS NOT NULL;
            ALTER TABLE notifications DROP COLUMN target_regional_id;
        END IF;

        IF EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='notifications' AND column_name='target_local_id') THEN
            INSERT INTO notification_targets (notification_id, target_type, target_id)
            SELECT id,'local',target_local_id FROM notifications WHERE target_local_id IS NOT NULL;
            ALTER TABLE notifications DROP COLUMN target_local_id;
        END IF;

        IF EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='notifications' AND column_name='target_unit_id') THEN
            INSERT INTO notification_targets (notification_id, target_type, target_id)
            SELECT id,'unit',target_unit_id FROM notifications WHERE target_unit_id IS NOT NULL;
            ALTER TABLE notifications DROP COLUMN target_unit_id;
        END IF;

        IF EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='notifications' AND column_name='target_direction_id') THEN
            INSERT INTO notification_targets (notification_id, target_type, target_id)
            SELECT id,'direction',target_direction_id FROM notifications WHERE target_direction_id IS NOT NULL;
            ALTER TABLE notifications DROP COLUMN target_direction_id;
        END IF;

        IF EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='notifications' AND column_name='target_event_id') THEN
            INSERT INTO notification_targets (notification_id, target_type, target_id)
            SELECT id,'event',target_event_id FROM notifications WHERE target_event_id IS NOT NULL;
            ALTER TABLE notifications DROP COLUMN target_event_id;
        END IF;

    END IF;
END $$;
