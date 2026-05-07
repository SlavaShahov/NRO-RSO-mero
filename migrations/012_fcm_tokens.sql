-- Миграция 012: FCM-токены для push-уведомлений
CREATE TABLE IF NOT EXISTS user_fcm_tokens (
    id         SERIAL PRIMARY KEY,
    user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token      TEXT NOT NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (user_id)
);
CREATE INDEX IF NOT EXISTS idx_fcm_tokens_user ON user_fcm_tokens (user_id);
