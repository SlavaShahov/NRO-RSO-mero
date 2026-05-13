-- ═══════════════════════════════════════════════════════════════════════════
-- Миграция 015: Исправление 1НФ — замена contacts JSONB на реляционные таблицы
-- JSONB содержит составной объект (телефон, email, сайт и т.д.)
-- Нарушение 1НФ: домен содержит не скалярные значения
-- ═══════════════════════════════════════════════════════════════════════════

-- 1. Таблица контактов для регионального офиса
CREATE TABLE IF NOT EXISTS regional_office_contacts (
    id          SERIAL PRIMARY KEY,
    office_id   INTEGER NOT NULL REFERENCES regional_offices(id) ON DELETE CASCADE,
    type        VARCHAR(30) NOT NULL  -- 'phone', 'email', 'website', 'address', 'vk', 'telegram'
        CHECK (type IN ('phone','email','website','address','vk','telegram','other')),
    value       VARCHAR(255) NOT NULL,
    label       VARCHAR(100),         -- подпись: 'Приёмная', 'Директор' и т.п.
    sort_order  INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_ro_contacts_office
    ON regional_office_contacts (office_id);

-- 2. Таблица контактов для штаба (local_headquarters)
CREATE TABLE IF NOT EXISTS hq_contacts (
    id          SERIAL PRIMARY KEY,
    hq_id       INTEGER NOT NULL REFERENCES local_headquarters(id) ON DELETE CASCADE,
    type        VARCHAR(30) NOT NULL
        CHECK (type IN ('phone','email','website','address','vk','telegram','other')),
    value       VARCHAR(255) NOT NULL,
    label       VARCHAR(100),
    sort_order  INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_hq_contacts_hq
    ON hq_contacts (hq_id);

-- 3. Переносим существующие данные из JSONB в новые таблицы
-- Типичная структура contacts JSONB: {"phone": "...", "email": "...", "website": "..."}
INSERT INTO regional_office_contacts (office_id, type, value)
SELECT id, 'phone', contacts->>'phone'
FROM regional_offices
WHERE contacts->>'phone' IS NOT NULL AND contacts->>'phone' != '';

INSERT INTO regional_office_contacts (office_id, type, value)
SELECT id, 'email', contacts->>'email'
FROM regional_offices
WHERE contacts->>'email' IS NOT NULL AND contacts->>'email' != '';

INSERT INTO regional_office_contacts (office_id, type, value)
SELECT id, 'website', contacts->>'website'
FROM regional_offices
WHERE contacts->>'website' IS NOT NULL AND contacts->>'website' != '';

INSERT INTO hq_contacts (hq_id, type, value)
SELECT id, 'phone', contacts->>'phone'
FROM local_headquarters
WHERE contacts->>'phone' IS NOT NULL AND contacts->>'phone' != '';

INSERT INTO hq_contacts (hq_id, type, value)
SELECT id, 'email', contacts->>'email'
FROM local_headquarters
WHERE contacts->>'email' IS NOT NULL AND contacts->>'email' != '';

-- 4. Удаляем JSONB-поля
ALTER TABLE regional_offices    DROP COLUMN IF EXISTS contacts;
ALTER TABLE local_headquarters  DROP COLUMN IF EXISTS contacts;
