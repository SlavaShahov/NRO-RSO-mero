package auth_test

import (
	"testing"
	"time"

	"rso-events/internal/auth"
)

func newManager() *auth.JWTManager {
	return auth.NewJWTManager("test-secret-key-32-bytes-minimum!", 15*time.Minute, 7*24*time.Hour)
}

// IssueTokens — возвращает непустые токены
func TestIssueTokens_ReturnsTokens(t *testing.T) {
	m := newManager()
	access, refresh, err := m.IssueTokens(1, "participant")
	if err != nil {
		t.Fatalf("IssueTokens error: %v", err)
	}
	if access == "" || refresh == "" {
		t.Fatal("expected non-empty tokens")
	}
}

// Parse access token — корректные claims
func TestParse_AccessToken_ValidClaims(t *testing.T) {
	m := newManager()
	access, _, err := m.IssueTokens(42, "superadmin")
	if err != nil {
		t.Fatalf("IssueTokens: %v", err)
	}
	claims, err := m.Parse(access, "access")
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	if claims.UserID != 42 {
		t.Errorf("want UserID=42, got %d", claims.UserID)
	}
	if claims.Role != "superadmin" {
		t.Errorf("want role=superadmin, got %s", claims.Role)
	}
	if claims.TokenType != "access" {
		t.Errorf("want token_type=access, got %s", claims.TokenType)
	}
}

// Parse refresh token — корректные claims
func TestParse_RefreshToken_ValidClaims(t *testing.T) {
	m := newManager()
	_, refresh, err := m.IssueTokens(7, "regional_admin")
	if err != nil {
		t.Fatalf("IssueTokens: %v", err)
	}
	claims, err := m.Parse(refresh, "refresh")
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	if claims.UserID != 7 {
		t.Errorf("want UserID=7, got %d", claims.UserID)
	}
}

// Access token не проходит как refresh
func TestParse_WrongType_Fails(t *testing.T) {
	m := newManager()
	access, _, _ := m.IssueTokens(1, "participant")
	_, err := m.Parse(access, "refresh")
	if err == nil {
		t.Fatal("expected error when using access token as refresh")
	}
}

// Неверная подпись отклоняется
func TestParse_InvalidSignature_Fails(t *testing.T) {
	m := newManager()
	other := auth.NewJWTManager("different-secret-key-32-bytes!!!", 15*time.Minute, 7*24*time.Hour)
	access, _, _ := other.IssueTokens(1, "participant")
	_, err := m.Parse(access, "access")
	if err == nil {
		t.Fatal("expected error for wrong signature")
	}
}

// Истёкший токен отклоняется
func TestParse_ExpiredToken_Fails(t *testing.T) {
	m := auth.NewJWTManager("test-secret-key-32-bytes-minimum!", -1*time.Second, 7*24*time.Hour)
	access, _, _ := m.IssueTokens(1, "participant")
	_, err := m.Parse(access, "access")
	if err == nil {
		t.Fatal("expected error for expired token")
	}
}

// Пустая строка отклоняется
func TestParse_EmptyToken_Fails(t *testing.T) {
	m := newManager()
	_, err := m.Parse("", "access")
	if err == nil {
		t.Fatal("expected error for empty token")
	}
}

// Мусорная строка отклоняется
func TestParse_GarbageToken_Fails(t *testing.T) {
	m := newManager()
	_, err := m.Parse("not.a.jwt.token", "access")
	if err == nil {
		t.Fatal("expected error for garbage token")
	}
}

// Два токена для одного пользователя имеют разные JTI
func TestIssueTokens_UniqueJTI(t *testing.T) {
	m := newManager()
	a1, _, _ := m.IssueTokens(1, "participant")
	a2, _, _ := m.IssueTokens(1, "participant")
	c1, _ := m.Parse(a1, "access")
	c2, _ := m.Parse(a2, "access")
	if c1.ID == c2.ID {
		t.Error("expected different JTI for each token")
	}
}
