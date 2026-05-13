-- ═══════════════════════════════════════════════════════════════════════════
-- Миграция 018: Исправление 3НФ — удаление account_status из users
-- ═══════════════════════════════════════════════════════════════════════════

-- Вью для обратной совместимости — вычисляет статус из hq_staff
CREATE OR REPLACE VIEW v_user_account_status AS
SELECT
    u.id AS user_id,
    CASE
        WHEN hs.status = 'pending' THEN 'pending_approval'
        WHEN u.is_blocked = true   THEN 'blocked'
        ELSE 'active'
    END AS account_status
FROM users u
LEFT JOIN hq_staff hs ON hs.user_id = u.id AND hs.status = 'pending';

-- Удаляем колонку только если она существует
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name='users' AND column_name='account_status'
    ) THEN
        ALTER TABLE users DROP COLUMN account_status;
    END IF;
END $$;
