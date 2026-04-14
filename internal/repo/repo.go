package repo

import (
	"context"
	"fmt"
	"strings"
	"time"

	"rso-events/internal/models"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Repository struct{ db *pgxpool.Pool }

func New(db *pgxpool.Pool) *Repository { return &Repository{db: db} }

// ── Users ────────────────────────────────────────────────────────────────────

func (r *Repository) CreateUser(ctx context.Context, u models.User) (int, error) {
	var id int
	err := r.db.QueryRow(ctx, `
		INSERT INTO users (email, password_hash, last_name, first_name, middle_name,
		                   phone, member_card_number, unit_id, unit_position_id, email_verified)
		VALUES ($1,$2,$3,$4,NULLIF($5,''),NULLIF($6,''),NULLIF($7,''),$8,$9,true)
		RETURNING id
	`, u.Email, u.PasswordHash, u.LastName, u.FirstName, u.MiddleName,
		u.Phone, u.MemberCardNumber, u.UnitID, u.UnitPositionID).Scan(&id)
	if err != nil {
		// Проверяем нарушение уникальности должности
		if strings.Contains(err.Error(), "users_unique_commander") {
			return 0, ErrPositionTaken
		}
	}
	return id, err
}

// ErrPositionTaken — должность уже занята в этом отряде/штабе
var ErrPositionTaken = fmt.Errorf("position already taken")

// userSelect — читает пользователя с учётом ШСО-заявки
const userSelect = `
	SELECT u.id, u.email, u.password_hash,
	       u.last_name, u.first_name, COALESCE(u.middle_name,''),
	       COALESCE(u.phone,''),
	       COALESCE(u.member_card_number,''),
	       COALESCE(u.member_card_location,'with_user'),
	       COALESCE(u.account_status,'active'),
	       u.unit_id, u.unit_position_id,
	       COALESCE(un.name,''),
	       CASE
	           WHEN hs.status = 'approved' THEN COALESCE(lh_hs.name,'')
	           ELSE COALESCE(lh_u.name,'')
	       END AS hq_name,
	       CASE
	           WHEN hs.status = 'approved' THEN COALESCE(hp.name,'')
	           ELSE COALESCE(up.name,'')
	       END AS position_name,
	       CASE
	           WHEN hs.status = 'approved' THEN 'hq_staff'
	           ELSE COALESCE(sr.code,'participant')
	       END AS role_code
	FROM users u
	LEFT JOIN units              un    ON un.id    = u.unit_id
	LEFT JOIN local_headquarters lh_u  ON lh_u.id = un.local_headquarters_id
	LEFT JOIN unit_positions     up    ON up.id    = u.unit_position_id
	LEFT JOIN system_roles       sr    ON sr.id    = up.system_role_id
	LEFT JOIN hq_staff           hs    ON hs.user_id = u.id AND hs.status = 'approved'
	LEFT JOIN local_headquarters lh_hs ON lh_hs.id = hs.local_headquarters_id
	LEFT JOIN hq_positions       hp    ON hp.id    = hs.hq_position_id
`

func scanUser(row pgx.Row) (models.User, error) {
	var u models.User
	err := row.Scan(
		&u.ID, &u.Email, &u.PasswordHash,
		&u.LastName, &u.FirstName, &u.MiddleName,
		&u.Phone, &u.MemberCardNumber, &u.MemberCardLocation, &u.AccountStatus,
		&u.UnitID, &u.UnitPositionID,
		&u.UnitName, &u.HqName, &u.PositionName, &u.RoleCode)
	return u, err
}

func (r *Repository) GetUserByEmail(ctx context.Context, email string) (models.User, error) {
	return scanUser(r.db.QueryRow(ctx,
		userSelect+" WHERE u.email=$1 AND u.is_blocked=false", email))
}

func (r *Repository) GetUserByID(ctx context.Context, id int) (models.User, error) {
	u, err := scanUser(r.db.QueryRow(ctx, userSelect+" WHERE u.id=$1", id))
	u.PasswordHash = ""
	return u, err
}

func (r *Repository) UpdateLastLogin(ctx context.Context, id int) error {
	_, err := r.db.Exec(ctx, `UPDATE users SET last_login=NOW() WHERE id=$1`, id)
	return err
}

func (r *Repository) UpdateProfile(ctx context.Context, userID int,
	lastName, firstName, middleName, phone, memberCardNumber, memberCardLocation string) error {
	loc := memberCardLocation
	if loc != "with_user" && loc != "in_hq" { loc = "with_user" }
	_, err := r.db.Exec(ctx, `
		UPDATE users SET
		    last_name            = $2,
		    first_name           = $3,
		    middle_name          = NULLIF($4,''),
		    phone                = NULLIF($5,''),
		    member_card_number   = NULLIF($6,''),
		    member_card_location = $7,
		    updated_at           = NOW()
		WHERE id = $1
	`, userID, lastName, firstName, middleName, phone, memberCardNumber, loc)
	return err
}

func (r *Repository) ListUnitMembers(ctx context.Context, unitID int) ([]models.User, error) {
	rows, err := r.db.Query(ctx, `
		SELECT u.id, u.email, '',
		       u.last_name, u.first_name, COALESCE(u.middle_name,''),
		       COALESCE(u.phone,''),
		       COALESCE(u.member_card_number,''),
		       COALESCE(u.member_card_location,'with_user'),
		       COALESCE(u.account_status,'active'),
		       u.unit_id, u.unit_position_id,
		       COALESCE(un.name,''), COALESCE(lh.name,''), COALESCE(up.name,''),
		       COALESCE(sr.code,'participant')
		FROM users u
		LEFT JOIN units              un ON un.id = u.unit_id
		LEFT JOIN local_headquarters lh ON lh.id = un.local_headquarters_id
		LEFT JOIN unit_positions     up ON up.id = u.unit_position_id
		LEFT JOIN system_roles       sr ON sr.id = up.system_role_id
		WHERE u.unit_id=$1 AND u.is_blocked=false
		ORDER BY
		    CASE up.code WHEN 'commander' THEN 1 WHEN 'commissioner' THEN 2
		    WHEN 'master' THEN 3 WHEN 'fighter' THEN 4 ELSE 5 END,
		    u.last_name, u.first_name
	`, unitID)
	if err != nil { return nil, err }
	defer rows.Close()
	return scanUsers(rows)
}

func scanUsers(rows pgx.Rows) ([]models.User, error) {
	var result []models.User
	for rows.Next() {
		var u models.User
		if err := rows.Scan(
			&u.ID, &u.Email, &u.PasswordHash,
			&u.LastName, &u.FirstName, &u.MiddleName,
			&u.Phone, &u.MemberCardNumber, &u.MemberCardLocation, &u.AccountStatus,
			&u.UnitID, &u.UnitPositionID,
			&u.UnitName, &u.HqName, &u.PositionName, &u.RoleCode); err != nil {
			return nil, err
		}
		result = append(result, u)
	}
	return result, nil
}

// RegistrationInfo — данные участника для показа после сканирования QR
type RegistrationInfo struct {
	RegistrationID     int    `json:"registration_id"`
	UserID             int    `json:"user_id"`
	FullName           string `json:"full_name"`
	UnitName           string `json:"unit_name"`
	HqName             string `json:"hq_name"`
	PositionName       string `json:"position_name"`
	Phone              string `json:"phone"`
	MemberCardNumber   string `json:"member_card_number"`
	MemberCardLocation string `json:"member_card_location"`
	EventTitle         string `json:"event_title"`
	EventDate          string `json:"event_date"`
}

// GetRegistrationInfo — полные данные о регистрации для отображения при сканировании
func (r *Repository) GetRegistrationInfo(ctx context.Context, registrationID int) (*RegistrationInfo, error) {
	var info RegistrationInfo
	err := r.db.QueryRow(ctx, `
		SELECT
		    reg.id,
		    u.id,
		    u.last_name||' '||u.first_name||COALESCE(' '||NULLIF(u.middle_name,''),''),
		    COALESCE(un.name,''),
		    CASE WHEN hs.status='approved' THEN COALESCE(lh_hs.name,'') ELSE COALESCE(lh_u.name,'') END,
		    CASE WHEN hs.status='approved' THEN COALESCE(hp.name,'') ELSE COALESCE(up.name,'') END,
		    COALESCE(u.phone,''),
		    COALESCE(u.member_card_number,''),
		    COALESCE(u.member_card_location,'with_user'),
		    e.title,
		    e.event_date::text
		FROM registrations reg
		JOIN users u ON u.id = reg.user_id
		JOIN events e ON e.id = reg.event_id
		LEFT JOIN units              un    ON un.id    = u.unit_id
		LEFT JOIN local_headquarters lh_u  ON lh_u.id = un.local_headquarters_id
		LEFT JOIN unit_positions     up    ON up.id    = u.unit_position_id
		LEFT JOIN hq_staff           hs    ON hs.user_id = u.id AND hs.status='approved'
		LEFT JOIN local_headquarters lh_hs ON lh_hs.id = hs.local_headquarters_id
		LEFT JOIN hq_positions       hp    ON hp.id    = hs.hq_position_id
		WHERE reg.id = $1
	`, registrationID).Scan(
		&info.RegistrationID, &info.UserID, &info.FullName,
		&info.UnitName, &info.HqName, &info.PositionName,
		&info.Phone, &info.MemberCardNumber, &info.MemberCardLocation,
		&info.EventTitle, &info.EventDate)
	if IsNotFound(err) { return nil, nil }
	if err != nil { return nil, err }
	return &info, nil
}

// ── HQ Staff ─────────────────────────────────────────────────────────────────

func (r *Repository) ListHQPositions(ctx context.Context) ([]models.HQPosition, error) {
	rows, err := r.db.Query(ctx,
		`SELECT id, code, name FROM hq_positions ORDER BY sort_order`)
	if err != nil { return nil, err }
	defer rows.Close()
	var res []models.HQPosition
	for rows.Next() {
		var p models.HQPosition
		if err := rows.Scan(&p.ID, &p.Code, &p.Name); err != nil { return nil, err }
		res = append(res, p)
	}
	return res, nil
}

func (r *Repository) GetHQStaffByUser(ctx context.Context, userID int) (*models.HQStaffRequest, error) {
	var s models.HQStaffRequest
	err := r.db.QueryRow(ctx, `
		SELECT hs.id, hs.user_id,
		       u.last_name||' '||u.first_name,
		       lh.id, lh.name,
		       hp.id, hp.name,
		       hs.status, hs.requested_at,
		       COALESCE(hs.review_comment,'')
		FROM hq_staff hs
		JOIN users u ON u.id = hs.user_id
		JOIN local_headquarters lh ON lh.id = hs.local_headquarters_id
		JOIN hq_positions hp ON hp.id = hs.hq_position_id
		WHERE hs.user_id = $1
		ORDER BY hs.requested_at DESC LIMIT 1
	`, userID).Scan(&s.ID, &s.UserID, &s.FullName,
		&s.HQID, &s.HQName, &s.PositionID, &s.PositionName,
		&s.Status, &s.RequestedAt, &s.Comment)
	if err == pgx.ErrNoRows { return nil, nil }
	if err != nil { return nil, err }
	return &s, nil
}

func (r *Repository) CreateHQStaffRequest(ctx context.Context, userID, hqID, positionID int) (int, error) {
	var id int
	err := r.db.QueryRow(ctx, `
		INSERT INTO hq_staff (user_id, local_headquarters_id, hq_position_id, status)
		VALUES ($1,$2,$3,'pending')
		ON CONFLICT (user_id, local_headquarters_id)
		DO UPDATE SET hq_position_id=$3, status='pending', requested_at=NOW(), reviewed_at=NULL
		RETURNING id
	`, userID, hqID, positionID).Scan(&id)
	return id, err
}

func (r *Repository) ListPendingHQRequests(ctx context.Context, hqID int) ([]models.HQStaffRequest, error) {
	rows, err := r.db.Query(ctx, `
		SELECT hs.id, hs.user_id,
		       u.last_name||' '||u.first_name||' ('||u.email||')',
		       lh.id, lh.name,
		       hp.id, hp.name,
		       hs.status, hs.requested_at,
		       COALESCE(hs.review_comment,'')
		FROM hq_staff hs
		JOIN users              u  ON u.id  = hs.user_id
		JOIN local_headquarters lh ON lh.id = hs.local_headquarters_id
		JOIN hq_positions       hp ON hp.id = hs.hq_position_id
		WHERE hs.local_headquarters_id=$1 AND hs.status='pending'
		ORDER BY hs.requested_at ASC
	`, hqID)
	if err != nil { return nil, err }
	defer rows.Close()
	var res []models.HQStaffRequest
	for rows.Next() {
		var s models.HQStaffRequest
		if err := rows.Scan(&s.ID, &s.UserID, &s.FullName,
			&s.HQID, &s.HQName, &s.PositionID, &s.PositionName,
			&s.Status, &s.RequestedAt, &s.Comment); err != nil {
			return nil, err
		}
		res = append(res, s)
	}
	return res, nil
}

func (r *Repository) ReviewHQStaffRequest(ctx context.Context,
	requestID, reviewerID int, approved bool, comment string) error {
	status := "rejected"
	if approved { status = "approved" }
	tx, err := r.db.Begin(ctx)
	if err != nil { return err }
	defer tx.Rollback(ctx)
	_, err = tx.Exec(ctx, `
		UPDATE hq_staff SET
		    status = $2, reviewed_at = NOW(), reviewed_by = $3, review_comment = $4
		WHERE id = $1
	`, requestID, status, reviewerID, comment)
	if err != nil {
		if strings.Contains(err.Error(), "hq_staff_unique_commander") {
			return fmt.Errorf("эта должность уже занята в данном штабе")
		}
		return err
	}
	_, err = tx.Exec(ctx, `
		UPDATE users SET account_status = 'active'
		WHERE id = (SELECT user_id FROM hq_staff WHERE id = $1)
	`, requestID)
	if err != nil { return err }
	return tx.Commit(ctx)
}

// ── Refs ─────────────────────────────────────────────────────────────────────

func (r *Repository) ListHQs(ctx context.Context) ([]models.HQ, error) {
	rows, err := r.db.Query(ctx,
		`SELECT id, name FROM local_headquarters WHERE is_active=true ORDER BY name`)
	if err != nil { return nil, err }
	defer rows.Close()
	var res []models.HQ
	for rows.Next() {
		var h models.HQ
		if err := rows.Scan(&h.ID, &h.Name); err != nil { return nil, err }
		res = append(res, h)
	}
	return res, nil
}

func (r *Repository) ListUnitsByHQ(ctx context.Context, hqID int) ([]models.Unit, error) {
	rows, err := r.db.Query(ctx, `
		SELECT u.id, u.name, d.code, lh.name
		FROM units u
		JOIN directions d ON d.id = u.direction_id
		JOIN local_headquarters lh ON lh.id = u.local_headquarters_id
		WHERE u.local_headquarters_id=$1 AND u.is_active=true
		ORDER BY d.code, u.name
	`, hqID)
	if err != nil { return nil, err }
	defer rows.Close()
	var res []models.Unit
	for rows.Next() {
		var u models.Unit
		if err := rows.Scan(&u.ID, &u.Name, &u.DirectionCode, &u.HqName); err != nil { return nil, err }
		res = append(res, u)
	}
	return res, nil
}

func (r *Repository) ListPositions(ctx context.Context) ([]models.Position, error) {
	rows, err := r.db.Query(ctx, `
		SELECT id, code, name FROM unit_positions
		WHERE code IN ('commander','commissioner','master','fighter','candidate')
		ORDER BY CASE code
		    WHEN 'commander' THEN 1 WHEN 'commissioner' THEN 2
		    WHEN 'master'    THEN 3 WHEN 'fighter'      THEN 4 ELSE 5 END
	`)
	if err != nil { return nil, err }
	defer rows.Close()
	var res []models.Position
	for rows.Next() {
		var p models.Position
		if err := rows.Scan(&p.ID, &p.Code, &p.Name); err != nil { return nil, err }
		res = append(res, p)
	}
	return res, nil
}

// ── Events ───────────────────────────────────────────────────────────────────

func (r *Repository) ListEvents(ctx context.Context, userID int,
	level, eventType, search string) ([]models.Event, error) {
	safeSearch := strings.NewReplacer(`%`, `\%`, `_`, `\_`).Replace(search)
	rows, err := r.db.Query(ctx, `
		SELECT e.id, e.title,
		       COALESCE(e.short_description, e.description, ''),
		       e.event_date::text, e.start_time::text,
		       COALESCE(e.end_time::text, ''),
		       COALESCE(e.location, ''),
		       el.code, et.code, es.code,
		       COALESCE(e.participation_mode,'open'),
		       COALESCE(e.is_registration_required, true),
		       e.max_participants, e.max_spectators,
		       e.created_at,
		       (SELECT COUNT(*) FROM registrations rg2
		        JOIN registration_statuses rs2 ON rs2.id=rg2.status_id
		        WHERE rg2.event_id=e.id AND rs2.code IN ('registered','attended')
		          AND COALESCE(rg2.participation_type,'participant')='participant'),
		       (SELECT COUNT(*) FROM registrations rg3
		        JOIN registration_statuses rs3 ON rs3.id=rg3.status_id
		        WHERE rg3.event_id=e.id AND rs3.code IN ('registered','attended')
		          AND rg3.participation_type='spectator'),
		       CASE WHEN $1>0 THEN (
		           SELECT rs.code FROM registrations rg
		           JOIN registration_statuses rs ON rs.id=rg.status_id
		           WHERE rg.event_id=e.id AND rg.user_id=$1 LIMIT 1
		       ) ELSE NULL END,
		       CASE WHEN $1>0 THEN (
		           SELECT COALESCE(rg.participation_type,'participant')
		           FROM registrations rg WHERE rg.event_id=e.id AND rg.user_id=$1 LIMIT 1
		       ) ELSE NULL END
		FROM events e
		JOIN event_levels   el ON el.id=e.level_id
		JOIN event_types    et ON et.id=e.type_id
		JOIN event_statuses es ON es.id=e.status_id
		WHERE ($2='' OR el.code=$2)
		  AND ($3='' OR et.code=$3)
		  AND ($4='' OR e.title ILIKE '%'||$4||'%' ESCAPE '\')
		  AND es.code IN ('published','active')
		ORDER BY e.event_date ASC, e.start_time ASC LIMIT 200
	`, userID, level, eventType, safeSearch)
	if err != nil { return nil, fmt.Errorf("list events: %w", err) }
	defer rows.Close()
	var evs []models.Event
	for rows.Next() {
		var e models.Event
		if err := rows.Scan(
			&e.ID, &e.Title, &e.Description,
			&e.EventDate, &e.StartTime, &e.EndTime,
			&e.Location, &e.LevelCode, &e.TypeCode, &e.StatusCode,
			&e.ParticipationMode,
			&e.IsRegistrationRequired, &e.MaxParticipants, &e.MaxSpectators,
			&e.CreatedAt, &e.ParticipantsCount, &e.SpectatorsCount,
			&e.UserRegistrationStatus, &e.UserParticipationType); err != nil {
			return nil, err
		}
		evs = append(evs, e)
	}
	return evs, nil
}

func (r *Repository) CreateEvent(ctx context.Context, e models.Event, createdBy int) (int, error) {
	mode := e.ParticipationMode
	if mode == "" { mode = "open" }
	var id int
	err := r.db.QueryRow(ctx, `
		INSERT INTO events (title, description, level_id, type_id, status_id,
		                    event_date, start_time, location, is_registration_required,
		                    max_participants, max_spectators, participation_mode, created_by)
		VALUES (
		    $1,$2,
		    (SELECT id FROM event_levels WHERE code=$3),
		    (SELECT id FROM event_types  WHERE code=$4),
		    (SELECT id FROM event_statuses WHERE code='published'),
		    $5,$6,NULLIF($7,''),true,$8,$9,$10,$11
		) RETURNING id
	`, e.Title, e.Description, e.LevelCode, e.TypeCode,
		e.EventDate, e.StartTime, e.Location,
		e.MaxParticipants, e.MaxSpectators, mode, createdBy).Scan(&id)
	return id, err
}

func (r *Repository) SetEventUnitQuota(ctx context.Context, q models.EventUnitQuota) error {
	_, err := r.db.Exec(ctx, `
		INSERT INTO event_unit_quotas (event_id, unit_id, max_participants, max_spectators)
		VALUES ($1,$2,$3,$4)
		ON CONFLICT (event_id, unit_id) DO UPDATE SET max_participants=$3, max_spectators=$4
	`, q.EventID, q.UnitID, q.MaxParticipants, q.MaxSpectators)
	return err
}

// ── Registrations ─────────────────────────────────────────────────────────────

type MyRegistration struct {
	RegistrationID    int    `json:"registration_id"`
	QRCode            string `json:"qr_code"`
	Status            string `json:"status"`
	ParticipationType string `json:"participation_type"`
	RegisteredAt      string `json:"registered_at"`
	EventID           int    `json:"event_id"`
	EventTitle        string `json:"event_title"`
	EventDate         string `json:"event_date"`
	StartTime         string `json:"start_time"`
	Location          string `json:"location"`
	LevelCode         string `json:"level_code"`
	TypeCode          string `json:"type_code"`
}

func (r *Repository) GetMyRegistrations(ctx context.Context, userID int) ([]MyRegistration, error) {
	rows, err := r.db.Query(ctx, `
		SELECT reg.id, reg.qr_code::text, rs.code,
		       COALESCE(reg.participation_type,'participant'),
		       reg.registered_at::text,
		       e.id, e.title, e.event_date::text, e.start_time::text,
		       COALESCE(e.location,''), el.code, et.code
		FROM registrations reg
		JOIN registration_statuses rs ON rs.id=reg.status_id
		JOIN events e                  ON e.id=reg.event_id
		JOIN event_levels el           ON el.id=e.level_id
		JOIN event_types  et           ON et.id=e.type_id
		WHERE reg.user_id=$1 AND rs.code IN ('registered','attended')
		ORDER BY e.event_date ASC, e.start_time ASC
	`, userID)
	if err != nil { return nil, err }
	defer rows.Close()
	var result []MyRegistration
	for rows.Next() {
		var m MyRegistration
		if err := rows.Scan(&m.RegistrationID, &m.QRCode, &m.Status,
			&m.ParticipationType, &m.RegisteredAt,
			&m.EventID, &m.EventTitle, &m.EventDate, &m.StartTime,
			&m.Location, &m.LevelCode, &m.TypeCode); err != nil {
			return nil, err
		}
		result = append(result, m)
	}
	return result, nil
}

func (r *Repository) CreateRegistration(ctx context.Context,
	userID, eventID int, participationType string) (int, uuid.UUID, error) {
	if participationType == "" { participationType = "participant" }
	var regID int
	var qr uuid.UUID
	err := r.db.QueryRow(ctx, `
		INSERT INTO registrations (user_id, event_id, status_id, participation_type)
		VALUES ($1,$2,(SELECT id FROM registration_statuses WHERE code='registered'),$3)
		RETURNING id, qr_code
	`, userID, eventID, participationType).Scan(&regID, &qr)
	return regID, qr, err
}

func (r *Repository) FindRegistrationByQR(ctx context.Context, code uuid.UUID) (int, error) {
	var id int
	err := r.db.QueryRow(ctx,
		`SELECT id FROM registrations WHERE qr_code=$1`, code).Scan(&id)
	return id, err
}

func (r *Repository) MarkAttendance(ctx context.Context, registrationID, scannerID int) error {
	tx, err := r.db.Begin(ctx)
	if err != nil { return err }
	defer tx.Rollback(ctx)
	var cnt int
	if err := tx.QueryRow(ctx,
		`SELECT COUNT(*) FROM attendances WHERE registration_id=$1`,
		registrationID).Scan(&cnt); err != nil { return err }
	if cnt > 0 { return ErrAlreadyAttended }
	if _, err := tx.Exec(ctx, `
		INSERT INTO attendances (registration_id, scanner_id, attended_at, scan_time)
		VALUES ($1,$2,NOW(),NOW())
	`, registrationID, scannerID); err != nil { return err }
	return tx.Commit(ctx)
}

func (r *Repository) GetPortfolioStats(ctx context.Context, userID int) (int, int, error) {
	var up, att int
	err := r.db.QueryRow(ctx, `
		SELECT
		    COUNT(*) FILTER (WHERE rs.code='registered') AS upcoming,
		    COUNT(*) FILTER (WHERE rs.code='attended')   AS attended
		FROM registrations rg
		JOIN registration_statuses rs ON rs.id=rg.status_id
		WHERE rg.user_id=$1
	`, userID).Scan(&up, &att)
	return up, att, err
}

// ── Tokens ───────────────────────────────────────────────────────────────────

func (r *Repository) RevokeToken(ctx context.Context, jti string, expiresAt time.Time) error {
	_, err := r.db.Exec(ctx, `
		INSERT INTO revoked_tokens (jti, expires_at) VALUES ($1,$2)
		ON CONFLICT (jti) DO UPDATE SET expires_at=EXCLUDED.expires_at
	`, jti, expiresAt)
	return err
}

func (r *Repository) IsTokenRevoked(ctx context.Context, jti string) (bool, error) {
	var ex bool
	err := r.db.QueryRow(ctx, `
		SELECT EXISTS(SELECT 1 FROM revoked_tokens WHERE jti=$1 AND expires_at>NOW())
	`, jti).Scan(&ex)
	return ex, err
}

func (r *Repository) CleanupExpiredRevokedTokens(ctx context.Context) error {
	_, err := r.db.Exec(ctx, `DELETE FROM revoked_tokens WHERE expires_at<=NOW()`)
	return err
}

var ErrAlreadyAttended = fmt.Errorf("attendance already marked")

func IsNotFound(err error) bool { return err == pgx.ErrNoRows }