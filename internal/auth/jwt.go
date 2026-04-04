package auth

import (
	"errors"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

type Claims struct {
	UserID    int    `json:"user_id"`
	Role      string `json:"role"`
	TokenType string `json:"token_type"`
	jwt.RegisteredClaims
}

type JWTManager struct {
	secret     []byte
	accessTTL  time.Duration
	refreshTTL time.Duration
}

func NewJWTManager(secret string, accessTTL, refreshTTL time.Duration) *JWTManager {
	return &JWTManager{secret: []byte(secret), accessTTL: accessTTL, refreshTTL: refreshTTL}
}

func (m *JWTManager) IssueTokens(userID int, role string) (string, string, error) {
	now := time.Now()
	access, err := jwt.NewWithClaims(jwt.SigningMethodHS256, Claims{
		UserID: userID, Role: role, TokenType: "access",
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(now.Add(m.accessTTL)),
			IssuedAt:  jwt.NewNumericDate(now),
			ID:        uuid.NewString(),
		},
	}).SignedString(m.secret)
	if err != nil {
		return "", "", err
	}
	refresh, err := jwt.NewWithClaims(jwt.SigningMethodHS256, Claims{
		UserID: userID, Role: role, TokenType: "refresh",
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(now.Add(m.refreshTTL)),
			IssuedAt:  jwt.NewNumericDate(now),
			ID:        uuid.NewString(),
		},
	}).SignedString(m.secret)
	if err != nil {
		return "", "", err
	}
	return access, refresh, nil
}

// Parse — проверяет подпись и срок (библиотека делает это сама).
func (m *JWTManager) Parse(tokenStr, expectedType string) (*Claims, error) {
	t, err := jwt.ParseWithClaims(tokenStr, &Claims{}, func(token *jwt.Token) (any, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, errors.New("unexpected signing method")
		}
		return m.secret, nil
	})
	if err != nil {
		return nil, err
	}
	if !t.Valid {
		return nil, errors.New("invalid token")
	}
	claims, ok := t.Claims.(*Claims)
	if !ok {
		return nil, jwt.ErrTokenInvalidClaims
	}
	if expectedType != "" && claims.TokenType != expectedType {
		return nil, errors.New("wrong token type")
	}
	return claims, nil
}
