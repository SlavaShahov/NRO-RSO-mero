package service

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"rso-events/internal/auth"
	"rso-events/internal/config"
	"rso-events/internal/models"
	"rso-events/internal/repo"

	"github.com/google/uuid"
	"golang.org/x/crypto/bcrypt"
	"golang.org/x/oauth2/google"
)

var (
	ErrForbidden = errors.New("forbidden")
	ErrInvalidQR = errors.New("invalid qr format")
	ErrRegClosed = errors.New("registration closed")
)

type Service struct {
	repo *repo.Repository
	jwt  *auth.JWTManager
	cfg  config.Config
}

func New(r *repo.Repository, j *auth.JWTManager, cfg config.Config) *Service {
	return &Service{repo: r, jwt: j, cfg: cfg}
}

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
			loc, _ := time.LoadLocation("Asia/Novosibirsk")
			if loc == nil { loc = time.FixedZone("NSK", 7*3600) }
			// Дедлайн: день мероприятия минус 3 рабочих дня, 00:00 НСК
			// Пример: мероприятие 8 мая (пт) → дедлайн 5 мая (вт) 00:00 НСК
			eventDate   := time.Date(year, time.Month(month), day, 0, 0, 0, 0, loc)
			deadlineDay := subtractWorkdays(eventDate, 3)
			deadline    := time.Date(deadlineDay.Year(), deadlineDay.Month(), deadlineDay.Day(), 0, 0, 0, 0, loc)
			if time.Now().In(loc).After(deadline) {
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

// ScanAttendance -> service_patch.go

func (s *Service) GetEventParticipants(ctx context.Context, eventID int) ([]repo.EventParticipantRow, error) {
	return s.repo.GetEventParticipants(ctx, eventID)
}

func (s *Service) SaveAvatar(ctx context.Context, userID int, base64Data string) error {
	return s.repo.SaveAvatar(ctx, userID, base64Data)
}

func (s *Service) GetAvatar(ctx context.Context, userID int) (string, error) {
	return s.repo.GetAvatar(ctx, userID)
}

func (s *Service) IsHQPositionAvailable(ctx context.Context, hqID, positionID int) (bool, error) {
	return s.repo.IsHQPositionAvailable(ctx, hqID, positionID)
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

// ── Брутфорс ──────────────────────────────────────────────────────────────────

func (s *Service) IsRateLimited(ctx context.Context, email, ip string) (bool, error) {
	return s.repo.IsRateLimited(ctx, email, ip)
}

func (s *Service) RecordLoginAttempt(ctx context.Context, email, ip string, success bool) {
	s.repo.RecordLoginAttempt(ctx, email, ip, success)
}

// ── Блокировка ────────────────────────────────────────────────────────────────

func (s *Service) BlockUser(ctx context.Context, userID int, reason string) error {
	return s.repo.BlockUser(ctx, userID, reason)
}

func (s *Service) UnblockUser(ctx context.Context, userID int) error {
	return s.repo.UnblockUser(ctx, userID)
}

func (s *Service) ListUsers(ctx context.Context, search string, blockedOnly bool) ([]models.User, error) {
	return s.repo.ListUsers(ctx, search, blockedOnly)
}

// ── Мероприятия (редактирование) ──────────────────────────────────────────────

func (s *Service) UpdateEvent(ctx context.Context, e models.Event) error {
	return s.repo.UpdateEvent(ctx, e)
}

func (s *Service) CancelEvent(ctx context.Context, eventID int) error {
	return s.repo.CancelEvent(ctx, eventID)
}

func (s *Service) GetEventByID(ctx context.Context, eventID int) (*models.Event, error) {
	return s.repo.GetEventByID(ctx, eventID)
}

// ── Баннер мероприятия ────────────────────────────────────────────────────────

func (s *Service) SaveEventBanner(ctx context.Context, eventID int, base64Data string) error {
	return s.repo.SaveEventBanner(ctx, eventID, base64Data)
}

func (s *Service) GetEventBanner(ctx context.Context, eventID int) (string, error) {
	return s.repo.GetEventBanner(ctx, eventID)
}

// ListUpcomingEventDates — для восстановления горутин при старте
func (s *Service) ListUpcomingEventDates(ctx context.Context) ([]repo.EventScheduleRow, error) {
	return s.repo.ListUpcomingEventDates(ctx)
}

// ─── FCM ──────────────────────────────────────────────────────────────────────

func (s *Service) SaveFcmToken(ctx context.Context, userID int, token string) error {
	return s.repo.SaveFcmToken(ctx, userID, token)
}

func (s *Service) SendFcmToUser(ctx context.Context, userID int, title, body string, data map[string]string) {
	if s.cfg.FCMCredentialsFile == "" { return }
	token, err := s.repo.GetFcmToken(ctx, userID)
	if err != nil || token == "" { return }
	sendFcmPush(ctx, s.cfg.FCMCredentialsFile, s.cfg.FCMProjectID, []string{token}, title, body, data)
}

func (s *Service) SendFcmToAdmins(ctx context.Context, title, body string, data map[string]string) {
	if s.cfg.FCMCredentialsFile == "" { return }
	tokens, err := s.repo.GetAdminFcmTokens(ctx)
	if err != nil || len(tokens) == 0 { return }
	sendFcmPush(ctx, s.cfg.FCMCredentialsFile, s.cfg.FCMProjectID, tokens, title, body, data)
}

// SendFcmToAll — push всем активным пользователям
func (s *Service) SendFcmToAll(ctx context.Context, title, body string, data map[string]string) {
	if s.cfg.FCMCredentialsFile == "" { return }
	tokens, err := s.repo.GetAllFcmTokens(ctx)
	if err != nil || len(tokens) == 0 { return }
	sendFcmPush(ctx, s.cfg.FCMCredentialsFile, s.cfg.FCMProjectID, tokens, title, body, data)
}

// ─── FCM HTTP v1 ──────────────────────────────────────────────────────────────

var (
	fcmMu          sync.Mutex
	fcmTokenCache  string
	fcmTokenExpiry time.Time
)

func getFcmAccessToken(ctx context.Context, credFile string) (string, error) {
	fcmMu.Lock()
	defer fcmMu.Unlock()
	if fcmTokenCache != "" && time.Now().Before(fcmTokenExpiry) {
		return fcmTokenCache, nil
	}
	data, err := os.ReadFile(credFile)
	if err != nil { return "", fmt.Errorf("fcm read creds: %w", err) }
	creds, err := google.CredentialsFromJSON(ctx, data,
		"https://www.googleapis.com/auth/firebase.messaging")
	if err != nil { return "", fmt.Errorf("fcm parse creds: %w", err) }
	token, err := creds.TokenSource.Token()
	if err != nil { return "", fmt.Errorf("fcm get token: %w", err) }
	fcmTokenCache = token.AccessToken
	fcmTokenExpiry = token.Expiry.Add(-60 * time.Second)
	return fcmTokenCache, nil
}

func sendFcmPush(ctx context.Context, credFile, projectID string, tokens []string, title, body string, data map[string]string) {
	if credFile == "" || projectID == "" || len(tokens) == 0 { return }
	go func() {
		accessToken, err := getFcmAccessToken(ctx, credFile)
		if err != nil { fmt.Printf("[fcm] auth: %v\n", err); return }
		url := fmt.Sprintf("https://fcm.googleapis.com/v1/projects/%s/messages:send", projectID)
		type notif struct {
			Title string `json:"title"`
			Body  string `json:"body"`
		}
		type androidCfg struct{ Priority string `json:"priority"` }
		type msg struct {
			Token   string            `json:"token"`
			Notif   notif             `json:"notification"`
			Data    map[string]string `json:"data,omitempty"`
			Android androidCfg        `json:"android"`
		}
		type payload struct{ Message msg `json:"message"` }
		for _, tok := range tokens {
			b, _ := json.Marshal(payload{Message: msg{
				Token:   tok,
				Notif:   notif{Title: title, Body: body},
				Data:    data,
				Android: androidCfg{Priority: "high"},
			}})
			req, _ := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(b))
			req.Header.Set("Content-Type", "application/json")
			req.Header.Set("Authorization", "Bearer "+accessToken)
			resp, err := http.DefaultClient.Do(req)
			if err != nil { fmt.Printf("[fcm] send: %v\n", err); continue }
			if resp.StatusCode != 200 {
				fmt.Printf("[fcm] status %d\n", resp.StatusCode)
			} else {
				fmt.Printf("[fcm] OK → %.10s...\n", tok)
			}
			resp.Body.Close()
		}
	}()
}

func (s *Service) MarkEventEmailSent(ctx context.Context, eventID int) error {
	return s.repo.MarkEventEmailSent(ctx, eventID)
}