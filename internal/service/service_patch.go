package service

import (
	"context"
	"crypto/rand"
	"crypto/tls"
	"encoding/base64"
	"errors"
	"fmt"
	"math/big"
	"net/smtp"
	"strings"

	"rso-events/internal/models"
	"rso-events/internal/repo"

	"github.com/google/uuid"
	"golang.org/x/crypto/bcrypt"
)

func (s *Service) Me(ctx context.Context, userID int) (models.User, error) {
	// GetUserByIDV2: возвращает правильные positionName и roleCode
	// (штабная должность из hq_positions если hq_staff.status=approved)
	u, err := s.repo.GetUserByIDV2(ctx, userID)
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


// DeleteAccount — проверяет пароль, отзывает токен и удаляет аккаунт
func (s *Service) DeleteAccount(ctx context.Context, userID int, password, accessToken string) error {
	u, err := s.repo.GetUserByIDWithHash(ctx, userID)
	if err != nil { return err }
	if bcrypt.CompareHashAndPassword([]byte(u.PasswordHash), []byte(password)) != nil {
		return ErrForbidden
	}
	if accessToken != "" {
		if claims, e := s.jwt.Parse(accessToken, "access"); e == nil {
			_ = s.repo.RevokeToken(ctx, claims.ID, claims.ExpiresAt.Time)
		}
	}
	return s.repo.DeleteUser(ctx, userID)
}

// ChangePassword — проверяет старый пароль и устанавливает новый
func (s *Service) ChangePassword(ctx context.Context, userID int, oldPassword, newPassword string) error {
	u, err := s.repo.GetUserByIDWithHash(ctx, userID)
	if err != nil { return err }
	if bcrypt.CompareHashAndPassword([]byte(u.PasswordHash), []byte(oldPassword)) != nil {
		return ErrForbidden
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(newPassword), bcrypt.DefaultCost)
	if err != nil { return err }
	return s.repo.UpdatePasswordHash(ctx, userID, string(hash))
}


// ── Генерация кода ────────────────────────────────────────────────────────────

func generateCode() (string, error) {
	var sb strings.Builder
	for i := 0; i < 6; i++ {
		n, err := rand.Int(rand.Reader, big.NewInt(10))
		if err != nil { return "", err }
		sb.WriteByte('0' + byte(n.Int64()))
	}
	return sb.String(), nil
}

// ── Верификация email ─────────────────────────────────────────────────────────

func (s *Service) SendVerificationCode(ctx context.Context, userID int, email string) error {
	code, err := generateCode()
	if err != nil { return err }
	if err := s.repo.SaveVerificationCode(ctx, userID, code); err != nil { return err }
	go s.sendEmail(email, "Подтверждение регистрации",
		fmt.Sprintf("Ваш код подтверждения: %s\n\nКод действителен 10 минут.", code))
	return nil
}

func (s *Service) VerifyEmail(ctx context.Context, userID int, code string) error {
	ok, err := s.repo.VerifyEmailCode(ctx, userID, code)
	if err != nil { return err }
	if !ok { return errors.New("неверный или истёкший код") }
	return s.repo.MarkEmailVerified(ctx, userID)
}

// ── Сброс пароля ──────────────────────────────────────────────────────────────

func (s *Service) SendPasswordResetCode(ctx context.Context, email string) error {
	email = strings.ToLower(strings.TrimSpace(email))
	_, err := s.repo.GetUserByEmail(ctx, email)
	if err != nil { return nil }
	code, err := generateCode()
	if err != nil { return err }
	if err := s.repo.SavePasswordResetCode(ctx, email, code); err != nil { return err }
	go s.sendEmail(email, "Сброс пароля РСО",
		fmt.Sprintf("Код для сброса пароля: %s\n\nКод действителен 15 минут.", code))
	return nil
}

func (s *Service) ResetPassword(ctx context.Context, email, code, newPassword string) error {
	if len(newPassword) < 8 { return errors.New("пароль: минимум 8 символов") }
	email = strings.ToLower(strings.TrimSpace(email))
	ok, err := s.repo.VerifyResetCode(ctx, email, code)
	if err != nil { return err }
	if !ok { return errors.New("неверный или истёкший код") }
	hash, err := bcrypt.GenerateFromPassword([]byte(newPassword), bcrypt.DefaultCost)
	if err != nil { return err }
	return s.repo.ResetPassword(ctx, email, string(hash))
}

// ── Смена email ───────────────────────────────────────────────────────────────

func (s *Service) SendEmailChangeCode(ctx context.Context, userID int, newEmail string) error {
	newEmail = strings.ToLower(strings.TrimSpace(newEmail))
	_, err := s.repo.GetUserByEmail(ctx, newEmail)
	if err == nil { return errors.New("email_duplicate: этот email уже зарегистрирован") }
	code, err := generateCode()
	if err != nil { return err }
	if err := s.repo.SaveEmailChangeCode(ctx, userID, newEmail, code); err != nil { return err }
	go s.sendEmail(newEmail, "Подтверждение смены email",
		fmt.Sprintf("Код подтверждения смены email: %s\n\nКод действителен 10 минут.", code))
	return nil
}

func (s *Service) ConfirmEmailChange(ctx context.Context, userID int, code string) error {
	newEmail, err := s.repo.VerifyEmailChangeCode(ctx, userID, code)
	if err != nil { return err }
	return s.repo.UpdateEmail(ctx, userID, newEmail)
}

// ── Смена должности ───────────────────────────────────────────────────────────

var leadershipPositionCodes = []string{"commander", "commissioner", "master"}

func isLeadershipPosition(code string) bool {
	for _, c := range leadershipPositionCodes {
		if c == code { return true }
	}
	return false
}

// RequestPositionChange — ВАЖНО: отправляет request_id в уведомление (не user_id!)
// чтобы кнопки одобрить/отклонить в уведомлении работали корректно.
func (s *Service) RequestPositionChange(ctx context.Context,
	userID, newPositionID int, newUnitID *int,
	positionCode, positionName, unitName, hqName string) (bool, error) {
	if isLeadershipPosition(positionCode) {
		// Создаём заявку — получаем request_id
		requestID, err := s.repo.CreatePositionChangeRequest(ctx, userID, newPositionID, newUnitID)
		if err != nil { return false, err }
		u, _ := s.repo.GetUserByID(ctx, userID)
		applicant := u.LastName + " " + u.FirstName
		// Формируем текст уведомления
		unitInfo := ""
		if unitName != "" { unitInfo += fmt.Sprintf("\n🏠 Отряд: %s", unitName) }
		if hqName != "" { unitInfo += fmt.Sprintf("\n🏢 Штаб: %s", hqName) }
		notifBody := fmt.Sprintf("👤 %s запрашивает должность «%s»%s",
			applicant, positionName, unitInfo)
		// Отправляем request_id — это ключ для кнопок одобрить/отклонить
		_ = s.repo.CreateNotificationsForAdmins(ctx, "position_change_request",
			fmt.Sprintf("📋 Смена должности: %s", positionName),
			notifBody,
			map[string]any{"request_id": requestID})
		return false, nil
	}
	// Обычная должность (боец, кандидат) — меняем сразу
	if err := s.repo.UpdateUserPosition(ctx, userID, newPositionID, newUnitID); err != nil {
		return false, err
	}
	// Если пользователь был штабником — деактивируем hq_staff
	// иначе roleCode останется hq_staff несмотря на смену должности
	_ = s.repo.DeactivateHQStaff(ctx, userID)
	return true, nil
}

func (s *Service) ReviewPositionRequest(ctx context.Context,
	requestID, reviewerID int, approved bool, comment string) error {
	if err := s.repo.ReviewPositionRequest(ctx, requestID, reviewerID, approved, comment); err != nil {
		return err
	}
	// Уведомляем пользователя о результате
	req, _ := s.repo.GetPositionRequestByID(ctx, requestID)
	if req != nil {
		typeCode := "position_change_rejected"
		title    := "❌ Заявка на смену должности отклонена"
		body     := fmt.Sprintf("Ваша заявка на должность «%s» была отклонена.", req["position_name"])
		if approved {
			typeCode = "position_change_approved"
			title    = "✅ Должность изменена!"
			body     = fmt.Sprintf("Ваша должность изменена на «%s».", req["position_name"])
		}
		if comment != "" { body += "\nКомментарий: " + comment }
		userID, _ := req["user_id"].(int)
		_ = s.repo.CreateNotification(ctx, userID, typeCode, title, body,
			map[string]any{"request_id": requestID, "approved": approved})
	}
	return nil
}

func (s *Service) ListPendingPositionRequests(ctx context.Context) ([]map[string]any, error) {
	return s.repo.ListPendingPositionRequests(ctx)
}

// ── Отправка email ────────────────────────────────────────────────────────────

func (s *Service) sendEmail(to, subject, body string) {
	if s.cfg.SMTPUser == "" { return }
	encodedSubj := "=?UTF-8?B?" + base64.StdEncoding.EncodeToString([]byte(subject)) + "?="
	encodedBody := base64.StdEncoding.EncodeToString([]byte(body))
	msg := "From: " + s.cfg.SMTPUser + "\r\nTo: " + to + "\r\nSubject: " + encodedSubj +
		"\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\n" +
		"Content-Transfer-Encoding: base64\r\n\r\n" + encodedBody
	addr := fmt.Sprintf("%s:%d", s.cfg.SMTPHost, s.cfg.SMTPPort)
	auth := smtp.PlainAuth("", s.cfg.SMTPUser, s.cfg.SMTPPassword, s.cfg.SMTPHost)
	if s.cfg.SMTPPort == 465 {
		conn, err := tls.Dial("tcp", addr, &tls.Config{ServerName: s.cfg.SMTPHost})
		if err != nil { return }
		defer conn.Close()
		c, err := smtp.NewClient(conn, s.cfg.SMTPHost)
		if err != nil { return }
		if c.Auth(auth) != nil { return }
		if c.Mail(s.cfg.SMTPUser) != nil { return }
		if c.Rcpt(to) != nil { return }
		w, err := c.Data()
		if err != nil { return }
		fmt.Fprint(w, msg)
		w.Close()
		c.Quit()
	} else {
		smtp.SendMail(addr, auth, s.cfg.SMTPUser, []string{to}, []byte(msg))
	}
}

func isManagerRole(role string) bool {
	switch role {
	case "superadmin", "regional_admin", "local_admin",
		"unit_commander", "unit_commissioner", "unit_master":
		return true
	}
	return false
}