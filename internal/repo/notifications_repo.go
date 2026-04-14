package repo

import (
	"context"
	"encoding/json"
	"time"
)

// UserNotification — уведомление в inbox пользователя
type UserNotification struct {
	ID        int             `json:"id"`
	UserID    int             `json:"user_id"`
	TypeCode  string          `json:"type_code"`
	Title     string          `json:"title"`
	Body      string          `json:"body"`
	Data      json.RawMessage `json:"data,omitempty"`
	IsRead    bool            `json:"is_read"`
	CreatedAt time.Time       `json:"created_at"`
}

// CreateNotification — отправить уведомление одному пользователю
func (r *Repository) CreateNotification(ctx context.Context,
	userID int, typeCode, title, body string, data map[string]any) error {
	var raw []byte
	if data != nil {
		var err error
		raw, err = json.Marshal(data)
		if err != nil {
			return err
		}
	}
	_, err := r.db.Exec(ctx, `
		INSERT INTO user_notifications (user_id, type_code, title, body, data)
		VALUES ($1, $2, $3, $4, $5)
	`, userID, typeCode, title, body, raw)
	return err
}

// CreateNotificationsForAdmins — отправить уведомление всем admin/regional_admin
// нужно для ШСО-заявок и новых мероприятий
func (r *Repository) CreateNotificationsForAdmins(ctx context.Context,
	typeCode, title, body string, data map[string]any) error {
	var raw []byte
	if data != nil {
		b, err := json.Marshal(data)
		if err != nil {
			return err
		}
		raw = b
	}
	_, err := r.db.Exec(ctx, `
		INSERT INTO user_notifications (user_id, type_code, title, body, data)
		SELECT u.id, $1, $2, $3, $4
		FROM users u
		JOIN unit_positions up ON up.id = u.unit_position_id
		JOIN system_roles   sr ON sr.id = up.system_role_id
		WHERE sr.code IN ('superadmin','regional_admin','local_admin')
		  AND u.is_blocked = false
	`, typeCode, title, body, raw)
	return err
}

// ListNotifications — список уведомлений пользователя (последние 50)
func (r *Repository) ListNotifications(ctx context.Context, userID int) ([]UserNotification, error) {
	rows, err := r.db.Query(ctx, `
		SELECT id, user_id, type_code, title, body,
		       COALESCE(data::text, '{}'), is_read, created_at
		FROM user_notifications
		WHERE user_id = $1
		ORDER BY created_at DESC
		LIMIT 50
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var result []UserNotification
	for rows.Next() {
		var n UserNotification
		var dataStr string
		if err := rows.Scan(&n.ID, &n.UserID, &n.TypeCode, &n.Title, &n.Body,
			&dataStr, &n.IsRead, &n.CreatedAt); err != nil {
			return nil, err
		}
		n.Data = json.RawMessage(dataStr)
		result = append(result, n)
	}
	return result, nil
}

// CountUnread — число непрочитанных уведомлений
func (r *Repository) CountUnread(ctx context.Context, userID int) (int, error) {
	var cnt int
	err := r.db.QueryRow(ctx, `
		SELECT COUNT(*) FROM user_notifications
		WHERE user_id=$1 AND is_read=false
	`, userID).Scan(&cnt)
	return cnt, err
}

// MarkAllRead — пометить все уведомления пользователя как прочитанные
func (r *Repository) MarkAllRead(ctx context.Context, userID int) error {
	_, err := r.db.Exec(ctx, `
		UPDATE user_notifications SET is_read=true
		WHERE user_id=$1 AND is_read=false
	`, userID)
	return err
}

// MarkOneRead — пометить одно уведомление как прочитанное
func (r *Repository) MarkOneRead(ctx context.Context, notifID, userID int) error {
	_, err := r.db.Exec(ctx, `
		UPDATE user_notifications SET is_read=true
		WHERE id=$1 AND user_id=$2
	`, notifID, userID)
	return err
}