package service

import (
	"context"
	"fmt"

	"rso-events/internal/models"
	"rso-events/internal/repo"

	"github.com/google/uuid"
)

func (s *Service) Me(ctx context.Context, userID int) (models.User, error) {
	u, err := s.repo.GetUserByID(ctx, userID)
	if err != nil { return u, err }
	staff, _ := s.repo.GetHQStaffByUser(ctx, userID)
	if staff != nil {
		switch staff.Status {
		case "pending":  u.AccountStatus = "pending_approval"
		case "approved": u.AccountStatus = "active"
		case "rejected": u.AccountStatus = "active"
		}
	}
	return u, nil
}

func (s *Service) ReviewHQStaffRequest(ctx context.Context,
	requestID, reviewerID int, approved bool, comment string) error {
	if err := s.repo.ReviewHQStaffRequest(ctx, requestID, reviewerID, approved, comment); err != nil {
		return err
	}
	reqs, _ := s.repo.GetHQStaffRequestByID(ctx, requestID)
	if reqs != nil {
		typeCode := "hq_staff_rejected"
		title    := "❌ Заявка ШСО отклонена"
		body     := fmt.Sprintf("Ваша заявка на должность «%s» в %s была отклонена.", reqs.PositionName, reqs.HQName)
		if approved {
			typeCode = "hq_staff_approved"
			title    = "✅ Заявка ШСО одобрена!"
			body     = fmt.Sprintf("Поздравляем! Ваша заявка на должность «%s» в %s одобрена.", reqs.PositionName, reqs.HQName)
		}
		if comment != "" { body += "\nКомментарий: " + comment }
		_ = s.repo.CreateNotification(ctx, reqs.UserID, typeCode, title, body,
			map[string]any{"request_id": requestID, "approved": approved})
	}
	return nil
}

// ScanAttendance — возвращает полные данные участника включая avatar_url из БД
func (s *Service) ScanAttendance(ctx context.Context, role string, scannerID int, qrCode string) (*repo.RegistrationInfo, error) {
	if !isManagerRole(role) { return nil, ErrForbidden }
	parsed, err := uuid.Parse(qrCode)
	if err != nil { return nil, ErrInvalidQR }
	regID, err := s.repo.FindRegistrationByQR(ctx, parsed)
	if err != nil { return nil, err }
	if err := s.repo.MarkAttendance(ctx, regID, scannerID); err != nil { return nil, err }
	info, err := s.repo.GetRegistrationInfo(ctx, regID)
	if err != nil || info == nil {
		return &repo.RegistrationInfo{RegistrationID: regID}, nil
	}
	return info, nil
}

func isManagerRole(role string) bool {
	switch role {
	case "superadmin", "regional_admin", "local_admin",
		"unit_commander", "unit_commissioner", "unit_master":
		return true
	}
	return false
}