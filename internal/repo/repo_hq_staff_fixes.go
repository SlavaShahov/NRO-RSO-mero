package repo

// ── Патч к существующему repo.go ─────────────────────────────────────────────
//
// Замените в repo.go:
//   1. const userSelect — добавить LEFT JOIN hq_staff и логику роли
//   2. func ReviewHQStaffRequest — добавить UPDATE users SET account_status
//
// Либо добавьте этот файл как отдельный файл в пакет repo/ —
// он переопределяет нужные части через новые функции.

import (
	"context"

	"rso-events/internal/models"

	"github.com/jackc/pgx/v5"
)

// userSelectV2 — расширенный запрос, учитывает роль штабника из hq_staff.
// Использует COALESCE: если есть одобренная ШСО-заявка, берём роль оттуда.
const userSelectV2 = `
	SELECT u.id, u.email, u.password_hash,
	       u.last_name, u.first_name, COALESCE(u.middle_name,''),
	       COALESCE(u.phone,''),
	       COALESCE(u.member_card_number,''),
	       COALESCE(u.member_card_location,'with_user'),
	       COALESCE(u.account_status,'active'),
	       u.unit_id, u.unit_position_id,
	       COALESCE(un.name,''), COALESCE(lh.name,''), COALESCE(up.name,''),
	       -- Роль: если есть одобренная ШСО-заявка — 'hq_staff', иначе из unit_positions
	       CASE
	           WHEN hs.status = 'approved' THEN 'hq_staff'
	           ELSE COALESCE(sr.code,'participant')
	       END AS role_code
	FROM users u
	LEFT JOIN units              un ON un.id = u.unit_id
	LEFT JOIN local_headquarters lh ON lh.id = un.local_headquarters_id
	LEFT JOIN unit_positions     up ON up.id = u.unit_position_id
	LEFT JOIN system_roles       sr ON sr.id = up.system_role_id
	LEFT JOIN hq_staff           hs ON hs.user_id = u.id AND hs.status = 'approved'
`

// GetUserByEmailV2 — использует расширенный запрос с ролью штабника
func (r *Repository) GetUserByEmailV2(ctx context.Context, email string) (models.User, error) {
	return scanUserV2(r.db.QueryRow(ctx,
		userSelectV2+" WHERE u.email = $1 AND u.is_blocked = false", email))
}

// GetUserByIDV2 — использует расширенный запрос с ролью штабника
func (r *Repository) GetUserByIDV2(ctx context.Context, id int) (models.User, error) {
	u, err := scanUserV2(r.db.QueryRow(ctx, userSelectV2+" WHERE u.id = $1", id))
	u.PasswordHash = ""
	return u, err
}

func scanUserV2(row pgx.Row) (models.User, error) {
	var u models.User
	err := row.Scan(
		&u.ID, &u.Email, &u.PasswordHash,
		&u.LastName, &u.FirstName, &u.MiddleName,
		&u.Phone, &u.MemberCardNumber, &u.MemberCardLocation, &u.AccountStatus,
		&u.UnitID, &u.UnitPositionID,
		&u.UnitName, &u.HqName, &u.PositionName, &u.RoleCode)
	return u, err
}

// ReviewHQStaffRequestV2 — одобрить/отклонить + обновить account_status пользователя
func (r *Repository) ReviewHQStaffRequestV2(ctx context.Context,
	requestID, reviewerID int, approved bool, comment string) error {

	status := "rejected"
	if approved { status = "approved" }

	tx, err := r.db.Begin(ctx)
	if err != nil { return err }
	defer tx.Rollback(ctx)

	// 1. Обновляем статус заявки
	_, err = tx.Exec(ctx, `
		UPDATE hq_staff SET
		    status         = $2,
		    reviewed_at    = NOW(),
		    reviewed_by    = $3,
		    review_comment = $4
		WHERE id = $1
	`, requestID, status, reviewerID, comment)
	if err != nil { return err }

	// 2. Обновляем account_status пользователя и hq_name в профиле
	if approved {
		_, err = tx.Exec(ctx, `
			UPDATE users SET account_status = 'active'
			WHERE id = (SELECT user_id FROM hq_staff WHERE id = $1)
		`, requestID)
		if err != nil { return err }
	} else {
		_, err = tx.Exec(ctx, `
			UPDATE users SET account_status = 'active'
			WHERE id = (SELECT user_id FROM hq_staff WHERE id = $1)
		`, requestID)
		if err != nil { return err }
	}

	return tx.Commit(ctx)
}

// GetHQNameForUser — возвращает название штаба для штабника (из одобренной заявки)
func (r *Repository) GetHQNameForUser(ctx context.Context, userID int) string {
	var name string
	_ = r.db.QueryRow(ctx, `
		SELECT lh.name FROM hq_staff hs
		JOIN local_headquarters lh ON lh.id = hs.local_headquarters_id
		WHERE hs.user_id = $1 AND hs.status = 'approved'
		LIMIT 1
	`, userID).Scan(&name)
	return name
}