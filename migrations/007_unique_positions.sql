-- ═══════════════════════════════════════════════════════════════════════════
-- Миграция 007: Уникальность должностей командира/комиссара/мастера в отряде
-- и командира/комиссара/мастера штаба в штабе
-- ═══════════════════════════════════════════════════════════════════════════

-- В отряде может быть только один командир, один комиссар, один мастер.
-- Бойцов и кандидатов — сколько угодно.
CREATE UNIQUE INDEX IF NOT EXISTS users_unique_commander
    ON users (unit_id, unit_position_id)
    WHERE unit_id IS NOT NULL
      AND unit_position_id IN (
          SELECT id FROM unit_positions WHERE code IN ('commander','commissioner','master')
      );

-- В штабе может быть только один командир штаба, один комиссар штаба и один мастер штаба.
-- работников — сколько угодно.
CREATE UNIQUE INDEX IF NOT EXISTS hq_staff_unique_commander
    ON hq_staff (local_headquarters_id, hq_position_id)
    WHERE status = 'approved'
      AND hq_position_id IN (
          SELECT id FROM hq_positions WHERE code IN ('commander','commissioner', 'master')
      );