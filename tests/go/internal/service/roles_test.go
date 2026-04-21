package service_test

import (
	"strings"
	"testing"
)

// Точные копии из service.go / handlers.go
func isManagerRole(role string) bool {
	switch role {
	case "superadmin", "regional_admin", "local_admin",
		"unit_commander", "unit_commissioner", "unit_master":
		return true
	}
	return false
}

func posOrder(name string, hq bool) int {
	if hq {
		if strings.Contains(name, "Командир") { return 1 }
		if strings.Contains(name, "Комиссар") { return 2 }
		if strings.Contains(name, "Инженер")  { return 3 }
		return 4
	}
	if strings.Contains(name, "Командир") { return 5 }
	if strings.Contains(name, "Комиссар") { return 6 }
	if strings.Contains(name, "Мастер")   { return 7 }
	return 8
}

func displayName(name string) string {
	if name == "Кандидат" || name == "" { return "Боец" }
	return name
}

// ── isManagerRole ─────────────────────────────────────────────────────────────

func TestRole_AdminsAreManagers(t *testing.T) {
	for _, r := range []string{"superadmin", "regional_admin", "local_admin"} {
		if !isManagerRole(r) { t.Errorf("%s should be manager", r) }
	}
}

func TestRole_UnitLeadersAreManagers(t *testing.T) {
	for _, r := range []string{"unit_commander", "unit_commissioner", "unit_master"} {
		if !isManagerRole(r) { t.Errorf("%s should be manager", r) }
	}
}

func TestRole_HQStaff_NotManager(t *testing.T) {
	if isManagerRole("hq_staff") { t.Error("hq_staff must NOT be manager") }
}

func TestRole_Participants_NotManager(t *testing.T) {
	for _, r := range []string{"participant", "candidate", ""} {
		if isManagerRole(r) { t.Errorf("%s should NOT be manager", r) }
	}
}

// ── posOrder ──────────────────────────────────────────────────────────────────

func TestPosOrder_ExactValues(t *testing.T) {
	cases := []struct {
		name string
		hq   bool
		want int
	}{
		{"Командир штаба",  true,  1},
		{"Комиссар штаба",  true,  2},
		{"Инженер штаба",   true,  3},
		{"Работник штаба",  true,  4},
		{"Командир",        false, 5},
		{"Комиссар",        false, 6},
		{"Мастер",          false, 7},
		{"Боец",            false, 8},
		{"Кандидат",        false, 8},
		{"",                false, 8},
	}
	for _, c := range cases {
		got := posOrder(c.name, c.hq)
		if got != c.want {
			t.Errorf("posOrder(%q, hq=%v)=%d, want %d", c.name, c.hq, got, c.want)
		}
	}
}

func TestPosOrder_HQAlwaysBeforeUnit(t *testing.T) {
	hqPos := []string{"Командир штаба", "Комиссар штаба", "Инженер штаба", "Работник штаба"}
	unitPos := []string{"Командир", "Комиссар", "Мастер", "Боец", "Кандидат", ""}
	for _, hq := range hqPos {
		for _, u := range unitPos {
			if posOrder(hq, true) >= posOrder(u, false) {
				t.Errorf("'%s'(hq) должен быть выше '%s'(unit)", hq, u)
			}
		}
	}
}

func TestPosOrder_HQOrder_Monotone(t *testing.T) {
	hq := []string{"Командир штаба", "Комиссар штаба", "Инженер штаба", "Работник штаба"}
	for i := 1; i < len(hq); i++ {
		if posOrder(hq[i-1], true) >= posOrder(hq[i], true) {
			t.Errorf("порядок ШСО нарушен: %s >= %s", hq[i-1], hq[i])
		}
	}
}

func TestPosOrder_UnitOrder_Monotone(t *testing.T) {
	unit := []string{"Командир", "Комиссар", "Мастер", "Боец"}
	for i := 1; i < len(unit); i++ {
		if posOrder(unit[i-1], false) >= posOrder(unit[i], false) {
			t.Errorf("порядок отряда нарушен: %s >= %s", unit[i-1], unit[i])
		}
	}
}

func TestPosOrder_CandidateEqualsFighter(t *testing.T) {
	if posOrder("Кандидат", false) != posOrder("Боец", false) {
		t.Error("Кандидат и Боец должны иметь одинаковый приоритет")
	}
}

// ── displayName ───────────────────────────────────────────────────────────────

func TestDisplayName_Table(t *testing.T) {
	cases := map[string]string{
		"Кандидат":       "Боец",
		"":               "Боец",
		"Боец":           "Боец",
		"Командир":       "Командир",
		"Комиссар":       "Комиссар",
		"Мастер":         "Мастер",
		"Командир штаба": "Командир штаба",
		"Инженер штаба":  "Инженер штаба",
	}
	for in, want := range cases {
		got := displayName(in)
		if got != want {
			t.Errorf("displayName(%q)=%q, want %q", in, got, want)
		}
	}
}
