-- ─── Мероприятия ─────────────────────────────────────────────────────────────
INSERT INTO events(title, description, short_description, level_id, type_id, status_id,
    event_date, start_time, end_time, location, organizer_regional_id)
SELECT 'Дартс',
    'Соревнования по дартсу среди участников студенческих отрядов НСО. Открытый турнир, участие принимают все желающие.',
    'Открытый турнир по дартсу',
    (SELECT id FROM event_levels  WHERE code = 'regional'),
    (SELECT id FROM event_types   WHERE code = 'sport'),
    (SELECT id FROM event_statuses WHERE code = 'published'),
    '2026-04-05', '09:00', '13:00',
    'Новосибирск, ул. Советская, 22 — актовый зал',
    (SELECT id FROM regional_offices LIMIT 1)
WHERE NOT EXISTS (SELECT 1 FROM events WHERE title = 'Дартс');

INSERT INTO events(title, description, short_description, level_id, type_id, status_id,
    event_date, start_time, end_time, location, organizer_regional_id)
SELECT 'Чирлидинг',
    'Показательные выступления и соревнования по чирлидингу. Приглашаются команды от штабов и линейных отрядов.',
    'Соревнования по чирлидингу',
    (SELECT id FROM event_levels  WHERE code = 'regional'),
    (SELECT id FROM event_types   WHERE code = 'sport'),
    (SELECT id FROM event_statuses WHERE code = 'published'),
    '2026-04-12', '09:00', '13:00',
    'Новосибирск, СибГУТИ — спортивный зал',
    (SELECT id FROM regional_offices LIMIT 1)
WHERE NOT EXISTS (SELECT 1 FROM events WHERE title = 'Чирлидинг');

INSERT INTO events(title, description, short_description, level_id, type_id, status_id,
    event_date, start_time, end_time, location, organizer_regional_id)
SELECT 'Закрытие спартакиады',
    'Торжественное закрытие спартакиады студенческих отрядов. Подведение итогов, награждение победителей, праздничная программа.',
    'Торжественное закрытие и награждение',
    (SELECT id FROM event_levels  WHERE code = 'regional'),
    (SELECT id FROM event_types   WHERE code = 'sport'),
    (SELECT id FROM event_statuses WHERE code = 'published'),
    '2026-04-12', '14:00', '18:00',
    'Новосибирск, ДК «Академия» — большой зал',
    (SELECT id FROM regional_offices LIMIT 1)
WHERE NOT EXISTS (SELECT 1 FROM events WHERE title = 'Закрытие спартакиады');

-- ─── Тестовые пользователи ────────────────────────────────────────────────────
-- Пароль у ВСЕХ: Demo123!
-- Хеши генерируются прямо в PostgreSQL через pgcrypto (crypt + blowfish = bcrypt)
-- 100% совместимо с golang.org/x/crypto/bcrypt
DO $$
DECLARE
    v_fighter        INTEGER;
    v_commander      INTEGER;
    v_superadmin_pos INTEGER;
    v_regional_pos   INTEGER;
    v_unit_sgups     INTEGER;
    v_unit_ngtu      INTEGER;
    v_pw             TEXT := 'Demo123!';
BEGIN
    SELECT id INTO v_fighter        FROM unit_positions WHERE code = 'fighter';
    SELECT id INTO v_commander      FROM unit_positions WHERE code = 'commander';
    SELECT id INTO v_superadmin_pos FROM unit_positions WHERE code = 'superadmin';
    SELECT id INTO v_regional_pos   FROM unit_positions WHERE code = 'regional_admin';

    SELECT u.id INTO v_unit_sgups
    FROM units u
    JOIN local_headquarters lh ON lh.id = u.local_headquarters_id
    WHERE lh.name = 'ШСО СГУПС' AND u.name = 'СОП «Передовик»' LIMIT 1;

    SELECT u.id INTO v_unit_ngtu
    FROM units u
    JOIN local_headquarters lh ON lh.id = u.local_headquarters_id
    WHERE lh.name = 'ШСО НГТУ' AND u.name = 'ССО «Энергия»' LIMIT 1;

    -- superadmin
    INSERT INTO users(email, password_hash, last_name, first_name,
        unit_position_id, email_verified)
    VALUES(
        'admin@rso-nsk.ru',
        crypt(v_pw, gen_salt('bf', 8)),
        'Администратор', 'Системный',
        v_superadmin_pos, true
    ) ON CONFLICT (email) DO UPDATE
        SET password_hash = crypt(v_pw, gen_salt('bf', 8));

    -- regional_admin
    INSERT INTO users(email, password_hash, last_name, first_name,
        unit_position_id, email_verified)
    VALUES(
        'regional@rso-nsk.ru',
        crypt(v_pw, gen_salt('bf', 8)),
        'Регионов', 'Андрей',
        v_regional_pos, true
    ) ON CONFLICT (email) DO UPDATE
        SET password_hash = crypt(v_pw, gen_salt('bf', 8));

    -- командир СОП «Передовик» СГУПС
    INSERT INTO users(email, password_hash, last_name, first_name, middle_name,
        unit_id, unit_position_id, email_verified)
    VALUES(
        'commander@rso-nsk.ru',
        crypt(v_pw, gen_salt('bf', 8)),
        'Смирнов', 'Александр', 'Викторович',
        v_unit_sgups, v_commander, true
    ) ON CONFLICT (email) DO UPDATE
        SET password_hash = crypt(v_pw, gen_salt('bf', 8)),
            unit_id = v_unit_sgups,
            unit_position_id = v_commander;

    -- боец ССО «Энергия» НГТУ
    INSERT INTO users(email, password_hash, last_name, first_name, middle_name,
        unit_id, unit_position_id, email_verified)
    VALUES(
        'demo@rso-nsk.ru',
        crypt(v_pw, gen_salt('bf', 8)),
        'Иванова', 'Мария', 'Сергеевна',
        v_unit_ngtu, v_fighter, true
    ) ON CONFLICT (email) DO UPDATE
        SET password_hash = crypt(v_pw, gen_salt('bf', 8)),
            unit_id = v_unit_ngtu,
            unit_position_id = v_fighter;

END $$;