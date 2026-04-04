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
		                   unit_id, unit_position_id, email_verified)
		VALUES ($1, $2, $3, $4, NULLIF($5,''), $6, $7, true)
		RETURNING id
	`, u.Email, u.PasswordHash, u.LastName, u.FirstName, u.MiddleName,
		u.UnitID, u.UnitPositionID).Scan(&id)
	return id, err
}

const userSelect = `
	SELECT u.id, u.email, u.password_hash,
	       u.last_name, u.first_name, COALESCE(u.middle_name,''),
	       u.unit_id, u.unit_position_id,
	       COALESCE(un.name,''), COALESCE(lh.name,''), COALESCE(up.name,''),
	       COALESCE(sr.code,'participant')
	FROM users u
	LEFT JOIN units              un ON un.id = u.unit_id
	LEFT JOIN local_headquarters lh ON lh.id = un.local_headquarters_id
	LEFT JOIN unit_positions     up ON up.id = u.unit_position_id
	LEFT JOIN system_roles       sr ON sr.id = up.system_role_id
`

func scanUser(row pgx.Row) (models.User, error) {
	var u models.User
	err := row.Scan(&u.ID, &u.Email, &u.PasswordHash,
		&u.LastName, &u.FirstName, &u.MiddleName,
		&u.UnitID, &u.UnitPositionID,
		&u.UnitName, &u.HqName, &u.PositionName, &u.RoleCode)
	return u, err
}

func (r *Repository) GetUserByEmail(ctx context.Context, email string) (models.User, error) {
	return scanUser(r.db.QueryRow(ctx,
		userSelect+" WHERE u.email = $1 AND u.is_blocked = false", email))
}

func (r *Repository) GetUserByID(ctx context.Context, id int) (models.User, error) {
	u, err := scanUser(r.db.QueryRow(ctx, userSelect+" WHERE u.id = $1", id))
	u.PasswordHash = ""
	return u, err
}

func (r *Repository) UpdateLastLogin(ctx context.Context, id int) error {
	_, err := r.db.Exec(ctx, `UPDATE users SET last_login = NOW() WHERE id = $1`, id)
	return err
}

// ── Refs ─────────────────────────────────────────────────────────────────────

func (r *Repository) ListHQs(ctx context.Context) ([]models.HQ, error) {
	rows, err := r.db.Query(ctx,
		`SELECT id, name FROM local_headquarters WHERE is_active = true ORDER BY name`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var res []models.HQ
	for rows.Next() {
		var h models.HQ
		if err := rows.Scan(&h.ID, &h.Name); err != nil {
			return nil, err
		}
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
		WHERE u.local_headquarters_id = $1 AND u.is_active = true
		ORDER BY d.code, u.name
	`, hqID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var res []models.Unit
	for rows.Next() {
		var u models.Unit
		if err := rows.Scan(&u.ID, &u.Name, &u.DirectionCode, &u.HqName); err != nil {
			return nil, err
		}
		res = append(res, u)
	}
	return res, nil
}

// ListPositions — только «пользовательские» должности (не служебные роли admin)
func (r *Repository) ListPositions(ctx context.Context) ([]models.Position, error) {
	rows, err := r.db.Query(ctx, `
		SELECT id, code, name
		FROM unit_positions
		WHERE code IN ('commander', 'commissioner', 'master', 'fighter', 'candidate')
		ORDER BY
		    CASE code
		        WHEN 'commander'    THEN 1
		        WHEN 'commissioner' THEN 2
		        WHEN 'master'       THEN 3
		        WHEN 'fighter'      THEN 4
		        WHEN 'candidate'    THEN 5
		    END
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var res []models.Position
	for rows.Next() {
		var p models.Position
		if err := rows.Scan(&p.ID, &p.Code, &p.Name); err != nil {
			return nil, err
		}
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
		       COALESCE(e.is_registration_required, true),
		       e.max_participants,
		       e.created_at,
		       COALESCE(st.participants_count, 0),
		       CASE WHEN $1 > 0 THEN (
		           SELECT rs.code FROM registrations rg
		           JOIN registration_statuses rs ON rs.id = rg.status_id
		           WHERE rg.event_id = e.id AND rg.user_id = $1
		           LIMIT 1
		       ) ELSE NULL END
		FROM events e
		JOIN event_levels   el ON el.id = e.level_id
		JOIN event_types    et ON et.id = e.type_id
		JOIN event_statuses es ON es.id = e.status_id
		LEFT JOIN events_stats st ON st.event_id = e.id
		WHERE ($2 = '' OR el.code = $2)
		  AND ($3 = '' OR et.code = $3)
		  AND ($4 = '' OR e.title ILIKE '%' || $4 || '%' ESCAPE '\')
		  AND es.code IN ('published', 'active')
		ORDER BY e.event_date ASC, e.start_time ASC
		LIMIT 200
	`, userID, level, eventType, safeSearch)
	if err != nil {
		return nil, fmt.Errorf("list events: %w", err)
	}
	defer rows.Close()

	var evs []models.Event
	for rows.Next() {
		var e models.Event
		if err := rows.Scan(&e.ID, &e.Title, &e.Description,
			&e.EventDate, &e.StartTime, &e.EndTime,
			&e.Location, &e.LevelCode, &e.TypeCode, &e.StatusCode,
			&e.IsRegistrationRequired, &e.MaxParticipants,
			&e.CreatedAt, &e.ParticipantsCount,
			&e.UserRegistrationStatus); err != nil {
			return nil, err
		}
		evs = append(evs, e)
	}
	return evs, nil
}

// ── Registrations ─────────────────────────────────────────────────────────────

func (r *Repository) CreateRegistration(ctx context.Context, userID, eventID int) (int, uuid.UUID, error) {
	var regID int
	var qr uuid.UUID
	err := r.db.QueryRow(ctx, `
		INSERT INTO registrations (user_id, event_id, status_id)
		VALUES ($1, $2, (SELECT id FROM registration_statuses WHERE code = 'registered'))
		RETURNING id, qr_code
	`, userID, eventID).Scan(&regID, &qr)
	return regID, qr, err
}

func (r *Repository) FindRegistrationByQR(ctx context.Context, code uuid.UUID) (int, error) {
	var id int
	err := r.db.QueryRow(ctx,
		`SELECT id FROM registrations WHERE qr_code = $1`, code).Scan(&id)
	return id, err
}

func (r *Repository) MarkAttendance(ctx context.Context, registrationID, scannerID int) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	var cnt int
	if err := tx.QueryRow(ctx,
		`SELECT COUNT(*) FROM attendances WHERE registration_id = $1`,
		registrationID).Scan(&cnt); err != nil {
		return err
	}
	if cnt > 0 {
		return ErrAlreadyAttended
	}

	if _, err := tx.Exec(ctx, `
		INSERT INTO attendances (registration_id, scanner_id, attended_at, scan_time)
		VALUES ($1, $2, NOW(), NOW())
	`, registrationID, scannerID); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func (r *Repository) GetPortfolioStats(ctx context.Context, userID int) (int, int, error) {
	var up, att int
	err := r.db.QueryRow(ctx, `
		SELECT
		    COUNT(*) FILTER (WHERE rs.code = 'registered') AS upcoming,
		    COUNT(*) FILTER (WHERE rs.code = 'attended')   AS attended
		FROM registrations rg
		JOIN registration_statuses rs ON rs.id = rg.status_id
		WHERE rg.user_id = $1
	`, userID).Scan(&up, &att)
	return up, att, err
}

// ── Tokens ───────────────────────────────────────────────────────────────────

func (r *Repository) RevokeToken(ctx context.Context, jti string, expiresAt time.Time) error {
	_, err := r.db.Exec(ctx, `
		INSERT INTO revoked_tokens (jti, expires_at)
		VALUES ($1, $2)
		ON CONFLICT (jti) DO UPDATE SET expires_at = EXCLUDED.expires_at
	`, jti, expiresAt)
	return err
}

func (r *Repository) IsTokenRevoked(ctx context.Context, jti string) (bool, error) {
	var ex bool
	err := r.db.QueryRow(ctx, `
		SELECT EXISTS(
		    SELECT 1 FROM revoked_tokens
		    WHERE jti = $1 AND expires_at > NOW()
		)
	`, jti).Scan(&ex)
	return ex, err
}

func (r *Repository) CleanupExpiredRevokedTokens(ctx context.Context) error {
	_, err := r.db.Exec(ctx, `DELETE FROM revoked_tokens WHERE expires_at <= NOW()`)
	return err
}

// ── Helpers ──────────────────────────────────────────────────────────────────

var ErrAlreadyAttended = fmt.Errorf("attendance already marked")

func IsNotFound(err error) bool { return err == pgx.ErrNoRows }