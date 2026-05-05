-- ═══════════════════════════════════════════════════════════════════════════
-- Миграция 010: Смена email + заявки на смену должности
-- ═══════════════════════════════════════════════════════════════════════════

-- Таблица запросов на смену email
CREATE TABLE IF NOT EXISTS email_change_requests (
    user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    new_email  VARCHAR(255) NOT NULL,
    code       VARCHAR(6) NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id)
);

-- Таблица заявок на смену должности
CREATE TABLE IF NOT EXISTS position_change_requests (
    id                   SERIAL PRIMARY KEY,
    user_id              INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    new_unit_position_id INTEGER NOT NULL REFERENCES unit_positions(id),
    new_unit_id          INTEGER REFERENCES units(id),
    status               VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending','approved','rejected')),
    review_comment       TEXT,
    reviewed_by          INTEGER REFERENCES users(id),
    reviewed_at          TIMESTAMP,
    requested_at         TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Частичный уникальный индекс: один пользователь — одна активная заявка
-- (UNIQUE WHERE нельзя в CREATE TABLE, только как отдельный индекс)
CREATE UNIQUE INDEX IF NOT EXISTS idx_position_req_user_pending
    ON position_change_requests (user_id)
    WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_position_req_status
    ON position_change_requests (status);

CREATE INDEX IF NOT EXISTS idx_email_change_user
    ON email_change_requests (user_id);