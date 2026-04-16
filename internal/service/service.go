package service

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"rso-events/internal/auth"
	"rso-events/internal/models"
	"rso-events/internal/repo"

	"github.com/google/uuid"
	"golang.org/x/crypto/bcrypt"
)

type AttendanceInfo struct {
	RegistrationID     int    `json:"registration_id"`
	UserID             int    `json:"user_id"`
	FullName           string `json:"full_name"`
	AvatarBase64       string `json:"avatar_base64"`
	UnitName           string `json:"unit_name"`
	HqName             string `json:"hq_name"`
	PositionName       string `json:"position_name"`
	Phone              string `json:"phone"`
	MemberCardNumber   string `json:"member_card_number"`
	MemberCardLocation string `json:"member_card_location"`
	EventTitle         string `json:"event_title"`
	EventDate          string `json:"event_date"`
}

var (
	ErrForbidden = errors.New("forbidden")
	ErrInvalidQR = errors.New("invalid qr format")
	ErrRegClosed = errors.New("registration closed")
)

type Service struct {
	repo *repo.Repository
	jwt  *auth.JWTManager
}

func New(r *repo.Repository, j *auth.JWTManager) *Service { return &Service{repo: r, jwt: j} }

// ── Auth ──────────────────────────────────────────────────────────────────────

func (s *Service) Register(ctx context.Context, in models.User, rawPassword string) (int, string, string, error) {
	if len(rawPassword) < 8 {
		return 0, "", "", errors.New("password must be at least 8 characters")
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(rawPassword), bcrypt.DefaultCost)
	if err != nil { return 0, "", "", err }
	in.Email        = strings.ToLower(strings.TrimSpace(in.Email))
	in.PasswordHash = string(hash)
	id, err := s.repo.CreateUser(ctx, in)
	if err != nil { return 0, "", "", err }
	access, refresh, err := s.jwt.IssueTokens(id, "participant")
	return id, access, refresh, err
}

func (s *Service) Login(ctx context.Context, email, password string) (string, string, error) {
	u, err := s.repo.GetUserByEmail(ctx, strings.ToLower(strings.TrimSpace(email)))
	if err != nil { return "", "", errors.New("invalid credentials") }
	if bcrypt.CompareHashAndPassword([]byte(u.PasswordHash), []byte(password)) != nil {
		return "", "", errors.New("invalid credentials")
	}
	_ = s.repo.UpdateLastLogin(ctx, u.ID)
	return s.jwt.IssueTokens(u.ID, u.RoleCode)
}

func (s *Service) ParseToken(token string) (*auth.Claims, error) {
	return s.jwt.Parse(token, "access")
}

func (s *Service) Refresh(refreshToken string) (string, string, error) {
	claims, err := s.jwt.Parse(refreshToken, "refresh")
	if err != nil { return "", "", err }
	revoked, err := s.repo.IsTokenRevoked(context.Background(), claims.ID)
	if err != nil || revoked { return "", "", errors.New("token revoked") }
	return s.jwt.IssueTokens(claims.UserID, claims.Role)
}

func (s *Service) Logout(accessToken, refreshToken string) error {
	ctx := context.Background()
	if accessToken != "" {
		if claims, err := s.jwt.Parse(accessToken, "access"); err == nil {
			_ = s.repo.RevokeToken(ctx, claims.ID, claims.ExpiresAt.Time)
		}
	}
	if refreshToken != "" {
		if claims, err := s.jwt.Parse(refreshToken, "refresh"); err == nil {
			_ = s.repo.RevokeToken(ctx, claims.ID, claims.ExpiresAt.Time)
		}
	}
	return nil
}

// ── Users ─────────────────────────────────────────────────────────────────────
/*
func (s *Service) Me(ctx context.Context, userID int) (models.User, error) {
	u, err := s.repo.GetUserByID(ctx, userID)
	if err != nil { return u, err }
	// Проверяем статус ШСО-заявки
	staff, _ := s.repo.GetHQStaffByUser(ctx, userID)
	if staff != nil && staff.Status == "pending" {
		u.AccountStatus = "pending_approval"
	} else if staff != nil && staff.Status == "approved" {
		u.AccountStatus = "active"
	}
	return u, nil
}
*/
func (s *Service) UpdateProfile(ctx context.Context, userID int,
	lastName, firstName, middleName, phone, memberCardNumber, memberCardLocation string) error {
	return s.repo.UpdateProfile(ctx, userID,
		lastName, firstName, middleName, phone, memberCardNumber, memberCardLocation)
}

func (s *Service) ListUnitMembers(ctx context.Context, unitID int) ([]models.User, error) {
	return s.repo.ListUnitMembers(ctx, unitID)
}

func (s *Service) GetHQUnitsForStaff(ctx context.Context, userID int) ([]models.Unit, error) {
	staff, err := s.repo.GetHQStaffByUser(ctx, userID)
	if err != nil { return nil, err }
	if staff == nil { return nil, errors.New("not a hq staff member") }
	return s.repo.ListUnitsByHQ(ctx, staff.HQID)
}

// ── Refs ──────────────────────────────────────────────────────────────────────

func (s *Service) ListHQs(ctx context.Context) ([]models.HQ, error) {
	return s.repo.ListHQs(ctx)
}

func (s *Service) ListUnitsByHQ(ctx context.Context, hqID int) ([]models.Unit, error) {
	return s.repo.ListUnitsByHQ(ctx, hqID)
}

func (s *Service) ListPositions(ctx context.Context) ([]models.Position, error) {
	return s.repo.ListPositions(ctx)
}

func (s *Service) ListHQPositions(ctx context.Context) ([]models.HQPosition, error) {
	return s.repo.ListHQPositions(ctx)
}

// ── HQ Staff ──────────────────────────────────────────────────────────────────

func (s *Service) CreateHQStaffRequest(ctx context.Context, userID, hqID, positionID int) (int, error) {
	return s.repo.CreateHQStaffRequest(ctx, userID, hqID, positionID)
}

func (s *Service) ListPendingHQRequests(ctx context.Context, hqID int) ([]models.HQStaffRequest, error) {
	return s.repo.ListPendingHQRequests(ctx, hqID)
}

// ReviewHQStaffRequest — одобрить/отклонить + уведомить пользователя
/*func (s *Service) ReviewHQStaffRequest(ctx context.Context,
	requestID, reviewerID int, approved bool, comment string) error {
	if err := s.repo.ReviewHQStaffRequest(ctx, requestID, reviewerID, approved, comment); err != nil {
		return err
	}
	// Получаем данные заявки для уведомления
	reqs, _ := s.repo.GetHQStaffRequestByID(ctx, requestID)
	if reqs != nil {
		typeCode := "hq_staff_rejected"
		title    := "❌ Заявка ШСО отклонена"
		body     := fmt.Sprintf("Ваша заявка на должность «%s» в %s была отклонена.", reqs.PositionName, reqs.HQName)
		if approved {
			typeCode = "hq_staff_approved"
			title    = "✅ Заявка ШСО одобрена"
			body     = fmt.Sprintf("Ваша заявка на должность «%s» в %s одобрена!", reqs.PositionName, reqs.HQName)
		}
		if comment != "" { body += "\nКомментарий: " + comment }
		_ = s.repo.CreateNotification(ctx, reqs.UserID, typeCode, title, body,
			map[string]any{"request_id": requestID})
	}
	return nil
}
*/
// ── Events ────────────────────────────────────────────────────────────────────

func (s *Service) ListEvents(ctx context.Context, userID int,
	level, eventType, search string) ([]models.Event, error) {
	return s.repo.ListEvents(ctx, userID, level, eventType, search)
}

func (s *Service) CreateEvent(ctx context.Context, e models.Event, createdBy int) (int, error) {
	return s.repo.CreateEvent(ctx, e, createdBy)
}

func (s *Service) SetEventUnitQuota(ctx context.Context, q models.EventUnitQuota) error {
	return s.repo.SetEventUnitQuota(ctx, q)
}

func (s *Service) GetMyRegistrations(ctx context.Context, userID int) ([]repo.MyRegistration, error) {
	return s.repo.GetMyRegistrations(ctx, userID)
}

func (s *Service) RegisterToEvent(ctx context.Context, userID int, event models.Event) (int, uuid.UUID, error) {
	dateParts := strings.Split(event.EventDate, "-")
	if len(dateParts) == 3 {
		var year, month, day int
		if _, err := fmt.Sscanf(event.EventDate, "%d-%d-%d", &year, &month, &day); err == nil {
			eventDate := time.Date(year, time.Month(month), day, 0, 0, 0, 0, time.UTC)
			// Последний день регистрации включительно (до 23:59:59)
			lastDay  := subtractWorkdays(eventDate, 3)
			deadline := time.Date(lastDay.Year(), lastDay.Month(), lastDay.Day(),
				23, 59, 59, 0, time.UTC)
			if time.Now().UTC().After(deadline) {
				return 0, uuid.UUID{}, ErrRegClosed
			}
		}
	}
	pType := "participant"
	if event.ParticipationMode == "spectators_only" {
		pType = "spectator"
	}
	return s.repo.CreateRegistration(ctx, userID, event.ID, pType)
}

func (s *Service) ScanAttendance(ctx context.Context, role string, scannerID int, qrCode string) (*AttendanceInfo, error) {
	if !isManagerRole(role) {
		return nil, ErrForbidden
	}
	
	parsed, err := uuid.Parse(qrCode)
	if err != nil {
		return nil, ErrInvalidQR
	}
	
	regID, err := s.repo.FindRegistrationByQR(ctx, parsed)
	if err != nil {
		return nil, err
	}
	
	info, err := s.repo.GetRegistrationInfo(ctx, regID)
	if err != nil {
		return nil, err
	}
	if info == nil {
		return nil, errors.New("registration info not found")
	}
	
	if err := s.repo.MarkAttendance(ctx, regID, scannerID); err != nil {
		return nil, err
	}
	
	return &AttendanceInfo{
		RegistrationID:     info.RegistrationID,
		UserID:             info.UserID,
		FullName:           info.FullName,
		AvatarBase64:       info.AvatarBase64,
		UnitName:           info.UnitName,
		HqName:             info.HqName,
		PositionName:       info.PositionName,
		Phone:              info.Phone,
		MemberCardNumber:   info.MemberCardNumber,
		MemberCardLocation: info.MemberCardLocation,
		EventTitle:         info.EventTitle,
		EventDate:          info.EventDate,
	}, nil
}

func (s *Service) Portfolio(ctx context.Context, userID int) (int, int, error) {
	return s.repo.GetPortfolioStats(ctx, userID)
}

// ── Notifications ─────────────────────────────────────────────────────────────

func (s *Service) ListNotifications(ctx context.Context, userID int) ([]repo.UserNotification, error) {
	return s.repo.ListNotifications(ctx, userID)
}

func (s *Service) CountUnread(ctx context.Context, userID int) (int, error) {
	return s.repo.CountUnread(ctx, userID)
}

func (s *Service) MarkAllRead(ctx context.Context, userID int) error {
	return s.repo.MarkAllRead(ctx, userID)
}

func (s *Service) MarkOneRead(ctx context.Context, notifID, userID int) error {
	return s.repo.MarkOneRead(ctx, notifID, userID)
}

// NotifyAdmins — уведомить всех администраторов
func (s *Service) NotifyAdmins(ctx context.Context, typeCode, title, body string, data map[string]any) error {
	return s.repo.CreateNotificationsForAdmins(ctx, typeCode, title, body, data)
}

// NotifyAllParticipants — уведомить всех активных пользователей
func (s *Service) NotifyAllParticipants(ctx context.Context, typeCode, title, body string, data map[string]any) error {
	return s.repo.CreateNotificationsForAll(ctx, typeCode, title, body, data)
}

// ── Helpers ───────────────────────────────────────────────────────────────────

func isManagerRole(role string) bool {
	switch role {
	case "superadmin", "regional_admin", "local_admin",
		"unit_commander", "unit_commissioner", "unit_master":
		return true
	}
	return false
}

func subtractWorkdays(t time.Time, days int) time.Time {
	result := t
	for subtracted := 0; subtracted < days; {
		result = result.AddDate(0, 0, -1)
		if result.Weekday() != time.Saturday && result.Weekday() != time.Sunday {
			subtracted++
		}
	}
	return result
}