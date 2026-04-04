CREATE TABLE IF NOT EXISTS revoked_tokens (
  jti VARCHAR(64) PRIMARY KEY, expires_at TIMESTAMP NOT NULL,
  revoked_at TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_revoked_tokens_expires ON revoked_tokens(expires_at);

CREATE OR REPLACE FUNCTION get_user_role(p_user_id INTEGER) RETURNS TEXT LANGUAGE sql STABLE AS $$
  SELECT sr.code FROM users u
  JOIN unit_positions up ON up.id=u.unit_position_id
  JOIN system_roles sr ON sr.id=up.system_role_id
  WHERE u.id=p_user_id;
$$;

CREATE OR REPLACE FUNCTION get_user_region(p_user_id INTEGER) RETURNS INTEGER LANGUAGE sql STABLE AS $$
  SELECT lh.regional_office_id FROM users u
  JOIN units un ON un.id=u.unit_id
  JOIN local_headquarters lh ON lh.id=un.local_headquarters_id
  WHERE u.id=p_user_id;
$$;

CREATE OR REPLACE FUNCTION get_unit_commander(p_unit_id INTEGER) RETURNS INTEGER LANGUAGE sql STABLE AS $$
  SELECT u.id FROM users u
  JOIN unit_positions up ON up.id=u.unit_position_id
  WHERE u.unit_id=p_unit_id AND up.code='commander' ORDER BY u.id LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION change_user_position(
  p_user_id INTEGER, p_new_position_id INTEGER, p_new_unit_id INTEGER,
  p_changed_by INTEGER, p_reason TEXT
) RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_old_pos INTEGER; v_old_unit INTEGER;
BEGIN
  SELECT unit_position_id,unit_id INTO v_old_pos,v_old_unit FROM users WHERE id=p_user_id;
  UPDATE users SET unit_position_id=p_new_position_id, unit_id=p_new_unit_id, updated_at=NOW() WHERE id=p_user_id;
  INSERT INTO user_position_history(user_id,old_unit_position_id,new_unit_position_id,old_unit_id,new_unit_id,changed_by,reason)
  VALUES(p_user_id,v_old_pos,p_new_position_id,v_old_unit,p_new_unit_id,p_changed_by,p_reason);
END $$;

CREATE OR REPLACE FUNCTION fn_update_registration_status() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  UPDATE registrations SET status_id=(SELECT id FROM registration_statuses WHERE code='attended')
  WHERE id=NEW.registration_id AND status_id<>(SELECT id FROM registration_statuses WHERE code='attended');
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_attendance_status ON attendances;
CREATE TRIGGER trg_attendance_status AFTER INSERT ON attendances
FOR EACH ROW EXECUTE FUNCTION fn_update_registration_status();

CREATE MATERIALIZED VIEW IF NOT EXISTS events_stats AS
SELECT e.id AS event_id, COUNT(r.id) AS participants_count, COUNT(a.id) AS attendees_count
FROM events e
LEFT JOIN registrations r ON r.event_id=e.id
LEFT JOIN attendances a   ON a.registration_id=r.id
GROUP BY e.id;

CREATE UNIQUE INDEX IF NOT EXISTS idx_events_stats_event ON events_stats(event_id);
