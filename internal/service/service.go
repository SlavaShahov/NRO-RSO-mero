package service

import (
	"context"
	"errors"
	"strings"

	"rso-events/internal/auth"
	"rso-events/internal/models"
	"rso-events/internal/repo"

	"github.com/google/uuid"
	"golang.org/x/crypto/bcrypt"
)

var (
	ErrForbidden    = errors.New("forbidden")
	ErrInvalidQR    = errors.New("invalid qr code format")
	ErrInvalidCreds = errors.New("invalid credentials")
)

type Service struct {
	repo *repo.Repository
	jwt  *auth.JWTManager
}

func New(r *repo.Repository, j *auth.JWTManager) *Service {
	return &Service{repo: r, jwt: j}
}

func (s *Service) Register(ctx context.Context, in models.User, pw string) (int, string, string, error) {
	if len(pw) < 6 {
		return 0, "", "", errors.New("password must be at least 6 characters")
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(pw), bcrypt.DefaultCost)
	if err != nil {
		return 0, "", "", err
	}
	in.Email = strings.ToLower(strings.TrimSpace(in.Email))
	in.PasswordHash = string(hash)

	id, err := s.repo.CreateUser(ctx, in)
	if err != nil {
		return 0, "", "", err
	}
	u, err := s.repo.GetUserByID(ctx, id)
	if err != nil {
		return 0, "", "", err
	}
	acc, ref, err := s.jwt.IssueTokens(id, u.RoleCode)
	return id, acc, ref, err
}

func (s *Service) Login(ctx context.Context, email, pw string) (string, string, error) {
	email = strings.ToLower(strings.TrimSpace(email))
	u, err := s.repo.GetUserByEmail(ctx, email)
	if err != nil {
		// Не раскрываем причину — всегда "invalid credentials"
		return "", "", ErrInvalidCreds
	}

	if !checkPassword(pw, u.PasswordHash) {
		return "", "", ErrInvalidCreds
	}

	_ = s.repo.UpdateLastLogin(ctx, u.ID)
	return s.jwt.IssueTokens(u.ID, u.RoleCode)
}

// checkPassword проверяет пароль против хеша.
// Поддерживает два формата:
//  1. bcrypt Go ($2a$) — созданные через bcrypt.GenerateFromPassword
//  2. pgcrypto blowfish ($2a$) — созданные через crypt(pw, gen_salt('bf'))
//     Оба используют один и тот же алгоритм, Go bcrypt верифицирует оба.
func checkPassword(plaintext, hash string) bool {
	// Оба формата ($2a$, $2b$) верифицируются стандартным bcrypt.CompareHashAndPassword
	err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(plaintext))
	return err == nil
}

func (s *Service) ParseToken(token string) (*auth.Claims, error) {
	claims, err := s.jwt.Parse(token, "access")
	if err != nil {
		return nil, err
	}
	revoked, err := s.repo.IsTokenRevoked(context.Background(), claims.ID)
	if err != nil {
		return nil, err
	}
	if revoked {
		return nil, errors.New("token revoked")
	}
	return claims, nil
}

func (s *Service) Refresh(rt string) (string, string, error) {
	claims, err := s.jwt.Parse(rt, "refresh")
	if err != nil {
		return "", "", err
	}
	revoked, err := s.repo.IsTokenRevoked(context.Background(), claims.ID)
	if err != nil {
		return "", "", err
	}
	if revoked {
		return "", "", errors.New("token revoked")
	}
	if err := s.repo.RevokeToken(context.Background(), claims.ID, claims.ExpiresAt.Time); err != nil {
		return "", "", err
	}
	return s.jwt.IssueTokens(claims.UserID, claims.Role)
}

func (s *Service) Logout(acc, ref string) error {
	for _, t := range []string{acc, ref} {
		if t == "" {
			continue
		}
		if cl, err := s.jwt.Parse(t, ""); err == nil && cl.ExpiresAt != nil {
			_ = s.repo.RevokeToken(context.Background(), cl.ID, cl.ExpiresAt.Time)
		}
	}
	return nil
}

func (s *Service) Me(ctx context.Context, id int) (models.User, error) {
	return s.repo.GetUserByID(ctx, id)
}

func (s *Service) ListHQs(ctx context.Context) ([]models.HQ, error) {
	return s.repo.ListHQs(ctx)
}

func (s *Service) ListUnitsByHQ(ctx context.Context, hqID int) ([]models.Unit, error) {
	return s.repo.ListUnitsByHQ(ctx, hqID)
}

func (s *Service) ListPositions(ctx context.Context) ([]models.Position, error) {
	return s.repo.ListPositions(ctx)
}

func (s *Service) ListEvents(ctx context.Context, uid int, level, eType, search string) ([]models.Event, error) {
	return s.repo.ListEvents(ctx, uid, level, eType, search)
}

func (s *Service) RegisterToEvent(ctx context.Context, uid, eid int) (int, uuid.UUID, error) {
	return s.repo.CreateRegistration(ctx, uid, eid)
}

func (s *Service) Portfolio(ctx context.Context, uid int) (int, int, error) {
	return s.repo.GetPortfolioStats(ctx, uid)
}

func (s *Service) ScanAttendance(ctx context.Context, role string, scannerID int, qr string) (int, error) {
	if !isManager(role) {
		return 0, ErrForbidden
	}
	parsed, err := uuid.Parse(qr)
	if err != nil {
		return 0, ErrInvalidQR
	}
	regID, err := s.repo.FindRegistrationByQR(ctx, parsed)
	if err != nil {
		return 0, err
	}
	if err := s.repo.MarkAttendance(ctx, regID, scannerID); err != nil {
		return 0, err
	}
	return regID, nil
}

func isManager(role string) bool {
	switch role {
	case "superadmin", "regional_admin", "local_admin",
		"unit_commander", "unit_commissioner", "unit_master":
		return true
	}
	return false
}