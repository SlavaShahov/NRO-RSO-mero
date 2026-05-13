-- Миграция 022: поле email_sent_at в events
-- Используется планировщиком чтобы не дублировать письма при перезапуске
ALTER TABLE events ADD COLUMN IF NOT EXISTS email_sent_at TIMESTAMP;
CREATE INDEX IF NOT EXISTS idx_events_email_sent ON events (email_sent_at)
    WHERE email_sent_at IS NOT NULL;
 