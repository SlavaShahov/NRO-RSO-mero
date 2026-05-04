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

// DeleteAccount — использует GetUserByIDWithHash (не затирает пароль)
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

// ChangePassword — использует GetUserByIDWithHash (не затирает пароль)
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

func generateCode() (string, error) {
	var sb strings.Builder
	for i := 0; i < 6; i++ {
		n, err := rand.Int(rand.Reader, big.NewInt(10))
		if err != nil { return "", err }
		sb.WriteByte('0' + byte(n.Int64()))
	}
	return sb.String(), nil
}

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

func (s *Service) SendPasswordResetCode(ctx context.Context, email string) error {
	email = strings.ToLower(strings.TrimSpace(email))
	_, err := s.repo.GetUserByEmail(ctx, email)
	if err != nil { return nil } // не раскрываем что пользователь не найден
	code, err := generateCode()
	if err != nil { return err }
	if err := s.repo.SavePasswordResetCode(ctx, email, code); err != nil { return err }
	go s.sendEmail(email, "Сброс пароля РСО",
		fmt.Sprintf("Код для сброса пароля: %s\n\nКод действителен 15 минут.\nЕсли вы не запрашивали сброс — проигнорируйте это письмо.", code))
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