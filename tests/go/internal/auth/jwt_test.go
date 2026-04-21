package auth_test

import (
	"testing"
	"time"

	"rso-events/internal/auth"
)

const testSecret = "test-secret-at-least-32-chars-long!"

func mgr(accessTTL, refreshTTL time.Duration) *auth.JWTManager {
	return auth.NewJWTManager(testSecret, accessTTL, refreshTTL)
}

// ── IssueTokens ───────────────────────────────────────────────────────────────

func TestIssue_ReturnsTwoNonEmptyDistinctTokens(t *testing.T) {
	acc, ref, err := mgr(time.Hour, time.Hour).IssueTokens(1, "participant")
	if err != nil  { t.Fatalf("error: %v", err) }
	if acc == ""   { t.Error("access empty") }
	if ref == ""   { t.Error("refresh empty") }
	if acc == ref  { t.Error("access == refresh") }
}

func TestIssue_DifferentUsers_DifferentTokens(t *testing.T) {
	m := mgr(time.Hour, time.Hour)
	a1, _, _ := m.IssueTokens(1, "participant")
	a2, _, _ := m.IssueTokens(2, "participant")
	if a1 == a2 { t.Error("different users must get different tokens") }
}

func TestIssue_DifferentRoles_DifferentTokens(t *testing.T) {
	m := mgr(time.Hour, time.Hour)
	a1, _, _ := m.IssueTokens(1, "participant")
	a2, _, _ := m.IssueTokens(1, "superadmin")
	if a1 == a2 { t.Error("different roles must get different tokens") }
}

func TestIssue_JTI_Unique(t *testing.T) {
	m := mgr(time.Hour, time.Hour)
	a1, _, _ := m.IssueTokens(1, "participant")
	a2, _, _ := m.IssueTokens(1, "participant")
	c1, _ := m.Parse(a1, "access")
	c2, _ := m.Parse(a2, "access")
	if c1.ID == c2.ID { t.Error("JTI must be unique per token") }
}

// ── Parse access ─────────────────────────────────────────────────────────────

func TestParse_AccessToken_CorrectClaims(t *testing.T) {
	m := mgr(time.Hour, time.Hour)
	acc, _, _ := m.IssueTokens(42, "superadmin")
	c, err := m.Parse(acc, "access")
	if err != nil              { t.Fatalf("parse error: %v", err) }
	if c.UserID != 42          { t.Errorf("userID: want 42, got %d", c.UserID) }
	if c.Role != "superadmin"  { t.Errorf("role: want superadmin, got %s", c.Role) }
	if c.TokenType != "access" { t.Errorf("type: want access, got %s", c.TokenType) }
}

func TestParse_RefreshToken_CorrectClaims(t *testing.T) {
	m := mgr(time.Hour, time.Hour)
	_, ref, _ := m.IssueTokens(7, "hq_staff")
	c, err := m.Parse(ref, "refresh")
	if err != nil               { t.Fatalf("parse error: %v", err) }
	if c.UserID != 7            { t.Errorf("userID: want 7, got %d", c.UserID) }
	if c.TokenType != "refresh" { t.Errorf("type: want refresh, got %s", c.TokenType) }
}

// ── Error cases ───────────────────────────────────────────────────────────────

func TestParse_AccessAsRefresh_Error(t *testing.T) {
	m := mgr(time.Hour, time.Hour)
	acc, _, _ := m.IssueTokens(1, "participant")
	if _, err := m.Parse(acc, "refresh"); err == nil {
		t.Fatal("expected error: access used as refresh")
	}
}

func TestParse_RefreshAsAccess_Error(t *testing.T) {
	m := mgr(time.Hour, time.Hour)
	_, ref, _ := m.IssueTokens(1, "participant")
	if _, err := m.Parse(ref, "access"); err == nil {
		t.Fatal("expected error: refresh used as access")
	}
}

func TestParse_ExpiredToken_Error(t *testing.T) {
	m := mgr(-time.Second, -time.Second)
	acc, _, _ := m.IssueTokens(1, "participant")
	if _, err := m.Parse(acc, "access"); err == nil {
		t.Fatal("expected error for expired token")
	}
}

func TestParse_WrongSecret_Error(t *testing.T) {
	m1 := auth.NewJWTManager("secret-one-111111111111111111111111", time.Hour, time.Hour)
	m2 := auth.NewJWTManager("secret-two-222222222222222222222222", time.Hour, time.Hour)
	acc, _, _ := m1.IssueTokens(1, "participant")
	if _, err := m2.Parse(acc, "access"); err == nil {
		t.Fatal("expected error for wrong secret")
	}
}

func TestParse_GarbageToken_Error(t *testing.T) {
	m := mgr(time.Hour, time.Hour)
	if _, err := m.Parse("not.a.jwt.token", "access"); err == nil {
		t.Fatal("expected error for garbage")
	}
}

func TestParse_EmptyToken_Error(t *testing.T) {
	m := mgr(time.Hour, time.Hour)
	if _, err := m.Parse("", "access"); err == nil {
		t.Fatal("expected error for empty token")
	}
}

// ── All roles round-trip ──────────────────────────────────────────────────────

func TestParse_AllRoles_RoundTrip(t *testing.T) {
	roles := []string{
		"participant", "candidate",
		"unit_commander", "unit_commissioner", "unit_master",
		"hq_staff",
		"local_admin", "regional_admin", "superadmin",
	}
	m := mgr(time.Hour, time.Hour)
	for _, role := range roles {
		acc, _, err := m.IssueTokens(1, role)
		if err != nil { t.Errorf("%s: issue error: %v", role, err) }
		c, err := m.Parse(acc, "access")
		if err != nil { t.Errorf("%s: parse error: %v", role, err) }
		if c.Role != role { t.Errorf("%s: got role %s", role, c.Role) }
	}
}
