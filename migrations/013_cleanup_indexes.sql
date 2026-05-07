-- Миграция 013: индексы для быстрой очистки устаревших данных
-- Без этих индексов DELETE по временным полям делает seq scan всей таблицы

-- user_notifications — очистка по дате и флагу прочтения
CREATE INDEX IF NOT EXISTS idx_user_notif_cleanup
    ON user_notifications (is_read, created_at);

-- login_attempts — очистка по дате
CREATE INDEX IF NOT EXISTS idx_login_attempts_cleanup
    ON login_attempts (attempted_at);

-- email_verifications — очистка по сроку
CREATE INDEX IF NOT EXISTS idx_email_verif_cleanup
    ON email_verifications (expires_at);

-- password_resets — очистка по сроку
CREATE INDEX IF NOT EXISTS idx_password_resets_cleanup
    ON password_resets (expires_at);

-- email_change_requests — очистка по сроку
CREATE INDEX IF NOT EXISTS idx_email_change_cleanup
    ON email_change_requests (expires_at);
