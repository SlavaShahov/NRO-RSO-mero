-- ═══════════════════════════════════════════════════════════════════════════
-- Миграция 005: Членский билет, ШСО-должности, квоты на мероприятия
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Членский билет и дополнительные поля пользователя ─────────────────
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS phone         VARCHAR(20),
    ADD COLUMN IF NOT EXISTS member_card_number VARCHAR(30),
    ADD COLUMN IF NOT EXISTS member_card_location VARCHAR(20) DEFAULT 'with_user'
        CHECK (member_card_location IN ('with_user', 'in_hq')),
    ADD COLUMN IF NOT EXISTS account_status VARCHAR(20) DEFAULT 'active'
        CHECK (account_status IN ('active', 'pending_approval', 'rejected'));

-- Уникальный номер билета (если указан)
CREATE UNIQUE INDEX IF NOT EXISTS users_member_card_number_uq
    ON users (member_card_number)
    WHERE member_card_number IS NOT NULL;

-- ── 2. Должности штаба (ШСО) ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS hq_positions (
    id   SERIAL PRIMARY KEY,
    code VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(100) NOT NULL,
    sort_order INT DEFAULT 0
);

INSERT INTO hq_positions (code, name, sort_order) VALUES
    ('commander',   'Командир штаба',  1),
    ('commissioner','Комиссар штаба',  2),
    ('engineer',    'Инженер штаба',   3),
    ('worker',      'Работник штаба',  4)
ON CONFLICT (code) DO NOTHING;

-- Таблица назначений штабников
CREATE TABLE IF NOT EXISTS hq_staff (
    id                   SERIAL PRIMARY KEY,
    user_id              INTEGER NOT NULL REFERENCES users(id),
    local_headquarters_id INTEGER NOT NULL REFERENCES local_headquarters(id),
    hq_position_id       INTEGER NOT NULL REFERENCES hq_positions(id),
    status               VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'approved', 'rejected')),
    requested_at         TIMESTAMP NOT NULL DEFAULT NOW(),
    reviewed_at          TIMESTAMP,
    reviewed_by          INTEGER REFERENCES users(id),
    review_comment       TEXT,
    UNIQUE (user_id, local_headquarters_id)  -- один человек — одна роль в штабе
);

CREATE INDEX IF NOT EXISTS hq_staff_hq_idx     ON hq_staff (local_headquarters_id);
CREATE INDEX IF NOT EXISTS hq_staff_user_idx   ON hq_staff (user_id);
CREATE INDEX IF NOT EXISTS hq_staff_status_idx ON hq_staff (status);

-- ── 3. Квоты на мероприятие ───────────────────────────────────────────────

-- Режим доступа к мероприятию
ALTER TABLE events
    ADD COLUMN IF NOT EXISTS participation_mode VARCHAR(20) DEFAULT 'open'
        CHECK (participation_mode IN (
            'open',           -- свободный вход, без регистрации
            'spectators_only',-- только зрители
            'participants_only',-- только участники (спортивные)
            'both'            -- и зрители, и участники
        )),
    ADD COLUMN IF NOT EXISTS max_spectators     INTEGER,  -- общий лимит зрителей
    ADD COLUMN IF NOT EXISTS max_participants   INTEGER;  -- (уже есть, но добавим если нет)

-- Квоты отряда на конкретное мероприятие
CREATE TABLE IF NOT EXISTS event_unit_quotas (
    id           SERIAL PRIMARY KEY,
    event_id     INTEGER NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    unit_id      INTEGER NOT NULL REFERENCES units(id),
    max_participants INTEGER,
    max_spectators   INTEGER,
    UNIQUE (event_id, unit_id)
);

CREATE INDEX IF NOT EXISTS event_unit_quotas_event_idx ON event_unit_quotas (event_id);

-- Тип участия в регистрации
ALTER TABLE registrations
    ADD COLUMN IF NOT EXISTS participation_type VARCHAR(20) DEFAULT 'participant'
        CHECK (participation_type IN ('participant', 'spectator'));

-- ── 4. Системная роль для штабников ──────────────────────────────────────
INSERT INTO system_roles (code, name, priority)
VALUES ('hq_staff', 'Работник штаба', 50)
ON CONFLICT (code) DO NOTHING;

-- ── 5. Вью: штабники с информацией о штабе ───────────────────────────────
CREATE OR REPLACE VIEW v_hq_staff AS
SELECT
    hs.id            AS assignment_id,
    u.id             AS user_id,
    u.last_name, u.first_name, u.middle_name,
    COALESCE(u.phone,'') AS phone,
    COALESCE(u.member_card_number,'') AS member_card_number,
    u.member_card_location,
    lh.id            AS hq_id,
    lh.name          AS hq_name,
    hp.id            AS hq_position_id,
    hp.code          AS hq_position_code,
    hp.name          AS hq_position_name,
    hs.status        AS approval_status,
    hs.requested_at,
    hs.reviewed_at
FROM hq_staff hs
JOIN users              u  ON u.id  = hs.user_id
JOIN local_headquarters lh ON lh.id = hs.local_headquarters_id
JOIN hq_positions       hp ON hp.id = hs.hq_position_id
WHERE u.is_blocked = FALSE;