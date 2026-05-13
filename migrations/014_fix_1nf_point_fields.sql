-- ═══════════════════════════════════════════════════════════════════════════
-- Миграция 014: Исправление 1НФ — замена POINT на скалярные поля
-- POINT — составной тип (x,y), нарушает требование атомарности атрибутов
-- ═══════════════════════════════════════════════════════════════════════════

-- 1. events: добавляем скалярные поля взамен POINT
-- (location_coordinates может уже отсутствовать — используем IF NOT EXISTS)
ALTER TABLE events
    ADD COLUMN IF NOT EXISTS location_lat DECIMAL(9,6),
    ADD COLUMN IF NOT EXISTS location_lng DECIMAL(9,6);

-- Переносим данные только если колонка существует
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name='events' AND column_name='location_coordinates'
    ) THEN
        UPDATE events
        SET location_lat = location_coordinates[0],
            location_lng = location_coordinates[1]
        WHERE location_coordinates IS NOT NULL;

        ALTER TABLE events DROP COLUMN location_coordinates;
    END IF;
END $$;

-- 2. attendances: добавляем скалярные поля взамен POINT
ALTER TABLE attendances
    ADD COLUMN IF NOT EXISTS scan_lat DECIMAL(9,6),
    ADD COLUMN IF NOT EXISTS scan_lng DECIMAL(9,6);

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name='attendances' AND column_name='scan_location'
    ) THEN
        UPDATE attendances
        SET scan_lat = scan_location[0],
            scan_lng = scan_location[1]
        WHERE scan_location IS NOT NULL;

        ALTER TABLE attendances DROP COLUMN scan_location;
    END IF;
END $$;

-- 3. attendances: убираем дублирующее поле attended_at (есть scan_time)
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name='attendances' AND column_name='attended_at'
    ) THEN
        ALTER TABLE attendances DROP COLUMN attended_at;
    END IF;
END $$;