-- ═══════════════════════════════════════════════════════════════════
-- Миграция 011: защита от брутфорса, баннер мероприятия, блокировка
-- ═══════════════════════════════════════════════════════════════════

-- 1. Таблица попыток входа (брутфорс)
CREATE TABLE IF NOT EXISTS login_attempts (
    id         SERIAL PRIMARY KEY,
    email      VARCHAR(255) NOT NULL,
    ip_address VARCHAR(45),
    success    BOOLEAN NOT NULL DEFAULT FALSE,
    attempted_at TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_login_attempts_email ON login_attempts (email, attempted_at DESC);
CREATE INDEX IF NOT EXISTS idx_login_attempts_ip    ON login_attempts (ip_address, attempted_at DESC);

-- 2. Баннер мероприятия (base64, хранится в БД как аватар)
ALTER TABLE events ADD COLUMN IF NOT EXISTS banner_base64 TEXT;

-- 3. Причина блокировки
ALTER TABLE users ADD COLUMN IF NOT EXISTS block_reason TEXT;