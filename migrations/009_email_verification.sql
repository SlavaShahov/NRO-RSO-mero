-- ═══════════════════════════════════════════════════════════════════════════
-- Миграция 009: Таблицы верификации email и сброса пароля
-- ═══════════════════════════════════════════════════════════════════════════

-- Коды подтверждения email при регистрации
CREATE TABLE IF NOT EXISTS email_verifications (
    user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    code       VARCHAR(6) NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    attempts   INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id)
);

-- Коды сброса пароля
CREATE TABLE IF NOT EXISTS password_resets (
    email      VARCHAR(255) NOT NULL,
    code       VARCHAR(6) NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    PRIMARY KEY (email)
);

CREATE INDEX IF NOT EXISTS idx_email_verif_user ON email_verifications(user_id);
CREATE INDEX IF NOT EXISTS idx_password_resets_email ON password_resets(email);