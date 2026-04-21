CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS system_roles (
    id SERIAL PRIMARY KEY, code VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(100) NOT NULL, priority INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS unit_positions (
    id SERIAL PRIMARY KEY, code VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(100) NOT NULL, system_role_id INTEGER NOT NULL REFERENCES system_roles(id)
);
CREATE TABLE IF NOT EXISTS event_levels (id SERIAL PRIMARY KEY, code VARCHAR(30) UNIQUE NOT NULL, name VARCHAR(100) NOT NULL);
CREATE TABLE IF NOT EXISTS event_types  (id SERIAL PRIMARY KEY, code VARCHAR(30) UNIQUE NOT NULL, name VARCHAR(100) NOT NULL);
CREATE TABLE IF NOT EXISTS event_statuses (id SERIAL PRIMARY KEY, code VARCHAR(30) UNIQUE NOT NULL, name VARCHAR(100) NOT NULL);
CREATE TABLE IF NOT EXISTS registration_statuses (id SERIAL PRIMARY KEY, code VARCHAR(30) UNIQUE NOT NULL, name VARCHAR(100) NOT NULL);

CREATE TABLE IF NOT EXISTS regional_offices (
    id SERIAL PRIMARY KEY, name VARCHAR(255) NOT NULL, region VARCHAR(100) NOT NULL,
    description TEXT, contacts JSONB, created_at TIMESTAMP NOT NULL DEFAULT NOW(), updated_at TIMESTAMP
);
CREATE TABLE IF NOT EXISTS directions (
    id SERIAL PRIMARY KEY, code VARCHAR(20) UNIQUE NOT NULL, name VARCHAR(100) NOT NULL,
    description TEXT, color VARCHAR(7), created_at TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS local_headquarters (
    id SERIAL PRIMARY KEY, regional_office_id INTEGER NOT NULL REFERENCES regional_offices(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL, educational_institution VARCHAR(255), address VARCHAR(255),
    contacts JSONB, is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(), updated_at TIMESTAMP
);
CREATE TABLE IF NOT EXISTS units (
    id SERIAL PRIMARY KEY, local_headquarters_id INTEGER NOT NULL REFERENCES local_headquarters(id) ON DELETE CASCADE,
    direction_id INTEGER NOT NULL REFERENCES directions(id), name VARCHAR(255) NOT NULL,
    full_name TEXT, description TEXT, is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(), updated_at TIMESTAMP
);
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY, email VARCHAR(255) UNIQUE NOT NULL, password_hash VARCHAR(255) NOT NULL,
    last_name VARCHAR(100) NOT NULL, first_name VARCHAR(100) NOT NULL, middle_name VARCHAR(100),
    avatar_url TEXT, phone VARCHAR(20), birth_date DATE,
    unit_id INTEGER REFERENCES units(id), unit_position_id INTEGER REFERENCES unit_positions(id),
    is_blocked BOOLEAN NOT NULL DEFAULT FALSE, email_verified BOOLEAN NOT NULL DEFAULT FALSE,
    verification_token VARCHAR(255), last_login TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(), updated_at TIMESTAMP
);
CREATE TABLE IF NOT EXISTS user_position_history (
    id SERIAL PRIMARY KEY, user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    old_unit_position_id INTEGER REFERENCES unit_positions(id), new_unit_position_id INTEGER REFERENCES unit_positions(id),
    old_unit_id INTEGER REFERENCES units(id), new_unit_id INTEGER REFERENCES units(id),
    changed_by INTEGER REFERENCES users(id), reason TEXT, changed_at TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS events (
    id SERIAL PRIMARY KEY, title VARCHAR(255) NOT NULL, description TEXT,
    short_description VARCHAR(500), level_id INTEGER NOT NULL REFERENCES event_levels(id),
    type_id INTEGER NOT NULL REFERENCES event_types(id), direction_id INTEGER REFERENCES directions(id),
    status_id INTEGER NOT NULL REFERENCES event_statuses(id), event_date DATE NOT NULL,
    start_time TIME NOT NULL, end_time TIME, location VARCHAR(255),
    location_coordinates POINT, location_details TEXT,
    organizer_regional_id INTEGER REFERENCES regional_offices(id),
    organizer_local_id INTEGER REFERENCES local_headquarters(id),
    organizer_unit_id INTEGER REFERENCES units(id),
    responsible_user_id INTEGER REFERENCES users(id),
    contacts JSONB, max_participants INTEGER, is_registration_required BOOLEAN NOT NULL DEFAULT TRUE,
    banner_image_url TEXT, created_by INTEGER REFERENCES users(id),
    created_at TIMESTAMP NOT NULL DEFAULT NOW(), updated_at TIMESTAMP,
    CONSTRAINT chk_events_organizer CHECK (num_nonnulls(organizer_regional_id,organizer_local_id,organizer_unit_id) <= 1)
);
CREATE TABLE IF NOT EXISTS event_target_directions (
    event_id INTEGER NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    direction_id INTEGER NOT NULL REFERENCES directions(id) ON DELETE CASCADE,
    PRIMARY KEY(event_id,direction_id)
);
CREATE TABLE IF NOT EXISTS event_target_positions (
    event_id INTEGER NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    unit_position_id INTEGER NOT NULL REFERENCES unit_positions(id) ON DELETE CASCADE,
    PRIMARY KEY(event_id,unit_position_id)
);
CREATE TABLE IF NOT EXISTS registrations (
    id SERIAL PRIMARY KEY, user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    event_id INTEGER NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    qr_code UUID NOT NULL UNIQUE DEFAULT gen_random_uuid(), qr_code_data TEXT,
    status_id INTEGER NOT NULL REFERENCES registration_statuses(id),
    registered_at TIMESTAMP NOT NULL DEFAULT NOW(), cancelled_at TIMESTAMP,
    UNIQUE(user_id,event_id)
);
CREATE TABLE IF NOT EXISTS attendances (
    id SERIAL PRIMARY KEY, registration_id INTEGER NOT NULL UNIQUE REFERENCES registrations(id) ON DELETE CASCADE,
    scanner_id INTEGER NOT NULL REFERENCES users(id),
    attended_at TIMESTAMP NOT NULL DEFAULT NOW(), scan_time TIMESTAMP NOT NULL DEFAULT NOW(),
    scan_location POINT, ip_address INET, device_info TEXT
);
CREATE TABLE IF NOT EXISTS notification_types (id SERIAL PRIMARY KEY, code VARCHAR(50) UNIQUE NOT NULL, name VARCHAR(100) NOT NULL);
CREATE TABLE IF NOT EXISTS notifications (
    id SERIAL PRIMARY KEY, title VARCHAR(255) NOT NULL, body TEXT NOT NULL,
    type_id INTEGER REFERENCES notification_types(id), action_data JSONB,
    target_regional_id INTEGER REFERENCES regional_offices(id),
    target_local_id INTEGER REFERENCES local_headquarters(id),
    target_unit_id INTEGER REFERENCES units(id),
    target_direction_id INTEGER REFERENCES directions(id),
    target_event_id INTEGER REFERENCES events(id),
    filters JSONB, status VARCHAR(50) NOT NULL DEFAULT 'draft',
    sent_by INTEGER REFERENCES users(id), scheduled_for TIMESTAMP, sent_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS notification_recipients (
    notification_id INTEGER NOT NULL REFERENCES notifications(id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    PRIMARY KEY(notification_id,user_id)
);
CREATE TABLE IF NOT EXISTS notification_receipts (
    id SERIAL PRIMARY KEY, notification_id INTEGER NOT NULL REFERENCES notifications(id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    is_read BOOLEAN NOT NULL DEFAULT FALSE, read_at TIMESTAMP,
    delivered_at TIMESTAMP NOT NULL DEFAULT NOW(), UNIQUE(notification_id,user_id)
);
CREATE TABLE IF NOT EXISTS user_activity_logs (
    id SERIAL PRIMARY KEY, user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    action VARCHAR(100) NOT NULL, entity_type VARCHAR(50), entity_id INTEGER,
    details JSONB, ip_address INET, user_agent TEXT, created_at TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS files (
    id SERIAL PRIMARY KEY, filename VARCHAR(255) NOT NULL, original_filename VARCHAR(255),
    file_path VARCHAR(500), file_size INTEGER, mime_type VARCHAR(100),
    user_avatar_id INTEGER REFERENCES users(id), event_banner_id INTEGER REFERENCES events(id),
    report_ref VARCHAR(100), uploaded_by INTEGER REFERENCES users(id),
    uploaded_at TIMESTAMP NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_files_one_owner CHECK(num_nonnulls(user_avatar_id,event_banner_id,report_ref)=1)
);

CREATE INDEX IF NOT EXISTS idx_events_date        ON events(event_date);
CREATE INDEX IF NOT EXISTS idx_events_level       ON events(level_id);
CREATE INDEX IF NOT EXISTS idx_events_type        ON events(type_id);
CREATE INDEX IF NOT EXISTS idx_events_status      ON events(status_id);
CREATE INDEX IF NOT EXISTS idx_registrations_user ON registrations(user_id);
CREATE INDEX IF NOT EXISTS idx_registrations_event ON registrations(event_id);
CREATE INDEX IF NOT EXISTS idx_registrations_qr   ON registrations(qr_code);
CREATE INDEX IF NOT EXISTS idx_notif_receipts_user ON notification_receipts(user_id,is_read);
CREATE INDEX IF NOT EXISTS idx_activity_logs_user ON user_activity_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_activity_logs_time ON user_activity_logs(created_at);

INSERT INTO system_roles(code,name,priority) VALUES
  ('superadmin','Супер администратор',100),('regional_admin','Администратор регионального штаба',80),
  ('local_admin','Администратор местного штаба',60),('unit_commander','Командир отряда',40),
  ('unit_commissioner','Комиссар отряда',35),('unit_master','Мастер отряда',30),
  ('participant','Боец',10),('candidate','Кандидат',5)
ON CONFLICT(code) DO NOTHING;

INSERT INTO unit_positions(code,name,system_role_id) SELECT 'commander','Командир',id FROM system_roles WHERE code='unit_commander' ON CONFLICT(code) DO NOTHING;
INSERT INTO unit_positions(code,name,system_role_id) SELECT 'commissioner','Комиссар',id FROM system_roles WHERE code='unit_commissioner' ON CONFLICT(code) DO NOTHING;
INSERT INTO unit_positions(code,name,system_role_id) SELECT 'master','Инженер',id FROM system_roles WHERE code='unit_master' ON CONFLICT(code) DO NOTHING;
INSERT INTO unit_positions(code,name,system_role_id) SELECT 'fighter','Боец',id FROM system_roles WHERE code='participant' ON CONFLICT(code) DO NOTHING;
INSERT INTO unit_positions(code,name,system_role_id) SELECT 'candidate','Кандидат',id FROM system_roles WHERE code='candidate' ON CONFLICT(code) DO NOTHING;
INSERT INTO unit_positions(code,name,system_role_id) SELECT 'superadmin','Супер администратор',id FROM system_roles WHERE code='superadmin' ON CONFLICT(code) DO NOTHING;
INSERT INTO unit_positions(code,name,system_role_id) SELECT 'regional_admin','Администратор региона',id FROM system_roles WHERE code='regional_admin' ON CONFLICT(code) DO NOTHING;

INSERT INTO event_levels(code,name) VALUES('federal','Федеральное'),('regional','Региональное'),('local','Вузовское'),('unit','Внутриотрядное') ON CONFLICT(code) DO NOTHING;
INSERT INTO event_types(code,name) VALUES('sport','Спортивное'),('culture','Культурное'),('education','Обучающее'),('headquarters','Штабное'),('labor','Трудовое') ON CONFLICT(code) DO NOTHING;
INSERT INTO event_statuses(code,name) VALUES('draft','Черновик'),('published','Опубликовано'),('active','Идёт'),('completed','Завершено'),('cancelled','Отменено') ON CONFLICT(code) DO NOTHING;
INSERT INTO registration_statuses(code,name) VALUES('registered','Зарегистрирован'),('attended','Посетил'),('cancelled','Отменено'),('no_show','Не явился') ON CONFLICT(code) DO NOTHING;
INSERT INTO notification_types(code,name) VALUES
  ('new_event','Новое мероприятие'),('event_reminder','Напоминание'),('registration_confirmed','Подтверждение регистрации'),
  ('attendance_recorded','Отметка посещения'),('event_cancelled','Мероприятие отменено'),('role_changed','Изменение роли'),('system_message','Системное сообщение')
ON CONFLICT(code) DO NOTHING;

INSERT INTO directions(code,name,color) VALUES
  ('ССО','Студенческие строительные отряды','#1E3A8A'),
  ('СПО','Студенческие педагогические отряды','#059669'),
  ('СОП','Студенческие отряды проводников','#DC2626'),
  ('ССхО','Студенческие сельскохозяйственные отряды','#D97706'),
  ('СПуО','Студенческие путинные отряды','#7C3AED'),
  ('СМО','Студенческие медицинские отряды','#DB2777'),
  ('ССервО','Студенческие сервисные отряды','#0891B2'),
  ('Спец','Специализированные отряды','#6B7280')
ON CONFLICT(code) DO NOTHING;
