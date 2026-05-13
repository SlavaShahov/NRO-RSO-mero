-- ═══════════════════════════════════════════════════════════════════════════
-- Миграция 021: Исправление бага в 007_unique_positions.sql
-- PostgreSQL не поддерживает подзапросы в WHERE индексов —
-- используем динамический SQL через EXECUTE в DO блоке
-- ═══════════════════════════════════════════════════════════════════════════

DROP INDEX IF EXISTS idx_users_unique_unit_leader_positions;
DROP INDEX IF EXISTS idx_hq_staff_unique_leader_positions;

DO $$
DECLARE
    v_commander_id   INTEGER;
    v_commissioner_id INTEGER;
    v_master_id      INTEGER;
    v_hq_cmd_id      INTEGER;
    v_hq_com_id      INTEGER;
    v_hq_eng_id      INTEGER;
BEGIN
    -- Получаем ID должностей по code (не хардкодим числа)
    SELECT id INTO v_commander_id    FROM unit_positions WHERE code = 'commander';
    SELECT id INTO v_commissioner_id FROM unit_positions WHERE code = 'commissioner';
    SELECT id INTO v_master_id       FROM unit_positions WHERE code = 'master';

    SELECT id INTO v_hq_cmd_id FROM hq_positions WHERE code = 'commander';
    SELECT id INTO v_hq_com_id FROM hq_positions WHERE code = 'commissioner';
    SELECT id INTO v_hq_eng_id FROM hq_positions WHERE code = 'engineer';

    -- Создаём индекс с конкретными ID через динамический SQL
    IF v_commander_id IS NOT NULL AND v_commissioner_id IS NOT NULL AND v_master_id IS NOT NULL THEN
        EXECUTE format(
            'CREATE UNIQUE INDEX idx_users_unique_unit_leader_positions
             ON users (unit_id, unit_position_id)
             WHERE unit_id IS NOT NULL
               AND unit_position_id IN (%s, %s, %s)',
            v_commander_id, v_commissioner_id, v_master_id
        );
    END IF;

    IF v_hq_cmd_id IS NOT NULL AND v_hq_com_id IS NOT NULL AND v_hq_eng_id IS NOT NULL THEN
        EXECUTE format(
            'CREATE UNIQUE INDEX idx_hq_staff_unique_leader_positions
             ON hq_staff (local_headquarters_id, hq_position_id)
             WHERE status = ''approved''
               AND hq_position_id IN (%s, %s, %s)',
            v_hq_cmd_id, v_hq_com_id, v_hq_eng_id
        );
    END IF;
END $$;