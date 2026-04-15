-- ═══════════════════════════════════════════════════════════════════════════
-- Миграция 007: Уникальность должностей (командир, комиссар, мастер)
-- ═══════════════════════════════════════════════════════════════════════════

-- 1. В одном отряде может быть только один командир, один комиссар и один мастер
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_unique_unit_leader_positions
    ON users (unit_id, unit_position_id)
    WHERE unit_id IS NOT NULL 
      AND unit_position_id IN (1, 2, 3);   -- IDs командира, комиссара, мастера

-- 2. В одном штабе может быть только один командир штаба, комиссар и инженер/мастер
CREATE UNIQUE INDEX IF NOT EXISTS idx_hq_staff_unique_leader_positions
    ON hq_staff (local_headquarters_id, hq_position_id)
    WHERE status = 'approved'
      AND hq_position_id IN (1, 2, 3);     -- IDs должностей штаба (commander, commissioner, engineer)