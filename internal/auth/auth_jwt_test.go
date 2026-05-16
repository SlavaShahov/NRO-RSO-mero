// Файл: internal/auth/auth_jwt_test.go
// Полные тесты JWT менеджера
package auth_test

import (
	"testing"
	"time"

	"rso-events/internal/auth"
)

func mgr() *auth.JWTManager {
	return auth.NewJWTManager("test-secret-32-bytes-minimum!!!", 15*time.Minute, 7*24*time.Hour)
}

// ── IssueTokens ──────────────────────────────────────────────────────────────
func TestIssueTokens_ReturnsNonEmpty(t *testing.T) {
	a, r, err := mgr().IssueTokens(1, "participant")
	if err != nil || a == "" || r == "" {
		t.Fatalf("IssueTokens failed: err=%v access=%q refresh=%q", err, a, r)
	}
}

func TestIssueTokens_AccessAndRefreshDiffer(t *testing.T) {
	a, r, _ := mgr().IssueTokens(1, "participant")
	if a == r {
		t.Error("access and refresh tokens must differ")
	}
}

func TestIssueTokens_UniqueJTIPerCall(t *testing.T) {
	m := mgr()
	a1, _, _ := m.IssueTokens(1, "participant")
	a2, _, _ := m.IssueTokens(1, "participant")
	c1, _ := m.Parse(a1, "access")
	c2, _ := m.Parse(a2, "access")
	if c1.ID == c2.ID {
		t.Error("each token must have unique JTI")
	}
}

// ── Parse access ─────────────────────────────────────────────────────────────
func TestParse_Access_UserID(t *testing.T) {
	m := mgr()
	a, _, _ := m.IssueTokens(42, "superadmin")
	c, err := m.Parse(a, "access")
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	if c.UserID != 42 {
		t.Errorf("want UserID=42, got %d", c.UserID)
	}
}

func TestParse_Access_Role(t *testing.T) {
	m := mgr()
	a, _, _ := m.IssueTokens(1, "regional_admin")
	c, _ := m.Parse(a, "access")
	if c.Role != "regional_admin" {
		t.Errorf("want role=regional_admin, got %s", c.Role)
	}
}

func TestParse_Access_TokenType(t *testing.T) {
	m := mgr()
	a, _, _ := m.IssueTokens(1, "participant")
	c, _ := m.Parse(a, "access")
	if c.TokenType != "access" {
		t.Errorf("want token_type=access, got %s", c.TokenType)
	}
}

// ── Parse refresh ─────────────────────────────────────────────────────────────
func TestParse_Refresh_TokenType(t *testing.T) {
	m := mgr()
	_, r, _ := m.IssueTokens(7, "participant")
	c, err := m.Parse(r, "refresh")
	if err != nil {
		t.Fatalf("Parse refresh: %v", err)
	}
	if c.TokenType != "refresh" {
		t.Errorf("want token_type=refresh, got %s", c.TokenType)
	}
}

func TestParse_Refresh_UserID(t *testing.T) {
	m := mgr()
	_, r, _ := m.IssueTokens(99, "participant")
	c, _ := m.Parse(r, "refresh")
	if c.UserID != 99 {
		t.Errorf("want UserID=99, got %d", c.UserID)
	}
}

// ── Ошибочные сценарии ────────────────────────────────────────────────────────
func TestParse_AccessAsRefresh_Fails(t *testing.T) {
	m := mgr()
	a, _, _ := m.IssueTokens(1, "participant")
	_, err := m.Parse(a, "refresh")
	if err == nil {
		t.Fatal("access token must not be accepted as refresh")
	}
}

func TestParse_RefreshAsAccess_Fails(t *testing.T) {
	m := mgr()
	_, r, _ := m.IssueTokens(1, "participant")
	_, err := m.Parse(r, "access")
	if err == nil {
		t.Fatal("refresh token must not be accepted as access")
	}
}

func TestParse_WrongSecret_Fails(t *testing.T) {
	other := auth.NewJWTManager("other-secret-32-bytes-minimum!!!", time.Hour, time.Hour)
	a, _, _ := other.IssueTokens(1, "participant")
	_, err := mgr().Parse(a, "access")
	if err == nil {
		t.Fatal("token with wrong signature must be rejected")
	}
}

func TestParse_Expired_Fails(t *testing.T) {
	m := auth.NewJWTManager("test-secret-32-bytes-minimum!!!", -time.Second, time.Hour)
	a, _, _ := m.IssueTokens(1, "participant")
	_, err := mgr().Parse(a, "access")
	if err == nil {
		t.Fatal("expired token must be rejected")
	}
}

func TestParse_Empty_Fails(t *testing.T) {
	_, err := mgr().Parse("", "access")
	if err == nil {
		t.Fatal("empty token must be rejected")
	}
}

func TestParse_Garbage_Fails(t *testing.T) {
	_, err := mgr().Parse("not.a.jwt", "access")
	if err == nil {
		t.Fatal("garbage token must be rejected")
	}
}

func TestParse_TruncatedToken_Fails(t *testing.T) {
	m := mgr()
	a, _, _ := m.IssueTokens(1, "participant")
	_, err := m.Parse(a[:len(a)/2], "access")
	if err == nil {
		t.Fatal("truncated token must be rejected")
	}
}

// ── Разные роли ───────────────────────────────────────────────────────────────
func TestIssueTokens_AllRoles(t *testing.T) {
	m := mgr()
	roles := []string{"superadmin", "regional_admin", "local_admin",
		"unit_commander", "unit_commissioner", "unit_master",
		"hq_staff", "participant", "candidate"}
	for _, role := range roles {
		a, _, err := m.IssueTokens(1, role)
		if err != nil {
			t.Errorf("IssueTokens failed for role=%s: %v", role, err)
		}
		c, err := m.Parse(a, "access")
		if err != nil {
			t.Errorf("Parse failed for role=%s: %v", role, err)
		}
		if c.Role != role {
			t.Errorf("want role=%s, got %s", role, c.Role)
		}
	}
}
