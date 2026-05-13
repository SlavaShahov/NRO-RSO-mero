-- ═══════════════════════════════════════════════════════════════════════════
-- Миграция 020: Исправление 3НФ — таблица files с nullable FK
-- ═══════════════════════════════════════════════════════════════════════════

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='files') THEN

        CREATE TABLE IF NOT EXISTS user_avatars (
            user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
            PRIMARY KEY (user_id),
            UNIQUE (file_id)
        );

        CREATE TABLE IF NOT EXISTS event_banners (
            event_id INTEGER NOT NULL REFERENCES events(id) ON DELETE CASCADE,
            file_id  INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
            PRIMARY KEY (event_id),
            UNIQUE (file_id)
        );

        CREATE TABLE IF NOT EXISTS file_reports (
            file_id    INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
            report_ref VARCHAR(100) NOT NULL,
            PRIMARY KEY (file_id)
        );

        IF EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='files' AND column_name='user_avatar_id') THEN
            INSERT INTO user_avatars (user_id, file_id)
            SELECT user_avatar_id, id FROM files WHERE user_avatar_id IS NOT NULL
            ON CONFLICT DO NOTHING;
            ALTER TABLE files DROP COLUMN user_avatar_id;
        END IF;

        IF EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='files' AND column_name='event_banner_id') THEN
            INSERT INTO event_banners (event_id, file_id)
            SELECT event_banner_id, id FROM files WHERE event_banner_id IS NOT NULL
            ON CONFLICT DO NOTHING;
            ALTER TABLE files DROP COLUMN event_banner_id;
        END IF;

        IF EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='files' AND column_name='report_ref') THEN
            INSERT INTO file_reports (file_id, report_ref)
            SELECT id, report_ref FROM files WHERE report_ref IS NOT NULL
            ON CONFLICT DO NOTHING;
            ALTER TABLE files DROP COLUMN report_ref;
        END IF;

        ALTER TABLE files DROP CONSTRAINT IF EXISTS chk_files_one_owner;
    END IF;
END $$;
