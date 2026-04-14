package repo

import (
	"context"
	"encoding/json"

	"rso-events/internal/models"
)

// GetHQStaffRequestByID — получить заявку по ID (для уведомлений после review)
func (r *Repository) GetHQStaffRequestByID(ctx context.Context, requestID int) (*models.HQStaffRequest, error) {
	var s models.HQStaffRequest
	err := r.db.QueryRow(ctx, `
		SELECT hs.id, hs.user_id,
		       u.last_name||' '||u.first_name,
		       lh.id, lh.name,
		       hp.id, hp.name,
		       hs.status, hs.requested_at,
		       COALESCE(hs.review_comment,'')
		FROM hq_staff hs
		JOIN users              u  ON u.id  = hs.user_id
		JOIN local_headquarters lh ON lh.id = hs.local_headquarters_id
		JOIN hq_positions       hp ON hp.id = hs.hq_position_id
		WHERE hs.id = $1
	`, requestID).Scan(&s.ID, &s.UserID, &s.FullName,
		&s.HQID, &s.HQName, &s.PositionID, &s.PositionName,
		&s.Status, &s.RequestedAt, &s.Comment)
	if IsNotFound(err) { return nil, nil }
	if err != nil { return nil, err }
	return &s, nil
}

// CreateNotificationsForAll — уведомить всех активных пользователей (новое мероприятие)
func (r *Repository) CreateNotificationsForAll(ctx context.Context,
	typeCode, title, body string, data map[string]any) error {
	var raw []byte
	if data != nil {
		b, err := json.Marshal(data)
		if err != nil { return err }
		raw = b
	}
	_, err := r.db.Exec(ctx, `
		INSERT INTO user_notifications (user_id, type_code, title, body, data)
		SELECT u.id, $1, $2, $3, $4
		FROM users u
		WHERE u.is_blocked = false
	`, typeCode, title, body, raw)
	return err
}