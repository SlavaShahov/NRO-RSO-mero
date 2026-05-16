// Файл: internal/service/service_helpers_test.go
// Whitebox тесты вспомогательных функций service.go и service_patch.go
package service

import (
	"testing"
	"time"
)

// ── subtractWorkdays ─────────────────────────────────────────────────────────
// subtractWorkdays просто вычитает N рабочих дней от времени t.
// Время (часы/минуты) сохраняется — полночь выставляется снаружи через time.Date.

func TestSubtractWorkdays_Wednesday_Minus3_GivesFriday(t *testing.T) {
	nsk, _ := time.LoadLocation("Asia/Novosibirsk")
	// Среда 20 мая 2026 — 3 рабочих дня назад = пятница 15 мая
	event := time.Date(2026, 5, 20, 9, 0, 0, 0, nsk)
	got := subtractWorkdays(event, 3)
	if got.Year() != 2026 || got.Month() != 5 || got.Day() != 15 {
		t.Errorf("want 2026-05-15, got %v", got)
	}
}

func TestSubtractWorkdays_Monday_Minus3_SkipsWeekend(t *testing.T) {
	nsk, _ := time.LoadLocation("Asia/Novosibirsk")
	// Понедельник 18 мая — 3 рабочих дня назад = среда 13 мая
	event := time.Date(2026, 5, 18, 9, 0, 0, 0, nsk)
	got := subtractWorkdays(event, 3)
	if got.Year() != 2026 || got.Month() != 5 || got.Day() != 13 {
		t.Errorf("want 2026-05-13, got %v", got)
	}
}

func TestSubtractWorkdays_Friday_Minus3_SkipsTwoWeekendDays(t *testing.T) {
	nsk, _ := time.LoadLocation("Asia/Novosibirsk")
	// Пятница 22 мая — 3 рабочих дня назад = вторник 19 мая
	event := time.Date(2026, 5, 22, 9, 0, 0, 0, nsk)
	got := subtractWorkdays(event, 3)
	if got.Year() != 2026 || got.Month() != 5 || got.Day() != 19 {
		t.Errorf("want 2026-05-19, got %v", got)
	}
}

func TestSubtractWorkdays_TimePreserved(t *testing.T) {
	// subtractWorkdays не обнуляет время — оно сохраняется
	nsk, _ := time.LoadLocation("Asia/Novosibirsk")
	event := time.Date(2026, 6, 5, 14, 30, 45, 0, nsk)
	got := subtractWorkdays(event, 3)
	if got.Hour() != 14 || got.Minute() != 30 || got.Second() != 45 {
		t.Errorf("time must be preserved (not reset): got %v", got)
	}
}

func TestSubtractWorkdays_MidnightViaTimeDate(t *testing.T) {
	// Полночь NSK выставляется снаружи через time.Date — как в handlers.go
	nsk, _ := time.LoadLocation("Asia/Novosibirsk")
	event := time.Date(2026, 6, 5, 14, 30, 0, 0, nsk)
	dayResult := subtractWorkdays(event, 3)
	deadline := time.Date(dayResult.Year(), dayResult.Month(), dayResult.Day(), 0, 0, 0, 0, nsk)
	if deadline.Hour() != 0 || deadline.Minute() != 0 || deadline.Second() != 0 {
		t.Errorf("deadline at midnight should be 00:00:00, got %v", deadline)
	}
}

func TestSubtractWorkdays_ResultIsWeekday(t *testing.T) {
	nsk, _ := time.LoadLocation("Asia/Novosibirsk")
	dates := []time.Time{
		time.Date(2026, 1, 10, 9, 0, 0, 0, nsk),
		time.Date(2026, 3, 15, 9, 0, 0, 0, nsk),
		time.Date(2026, 6, 30, 9, 0, 0, 0, nsk),
		time.Date(2026, 12,  1, 9, 0, 0, 0, nsk),
	}
	for _, d := range dates {
		got := subtractWorkdays(d, 3)
		if got.Weekday() == time.Saturday || got.Weekday() == time.Sunday {
			t.Errorf("subtractWorkdays(%v) = %v which is a weekend", d, got)
		}
	}
}

func TestSubtractWorkdays_1Day(t *testing.T) {
	nsk, _ := time.LoadLocation("Asia/Novosibirsk")
	// Вторник — 1 рабочий день назад = понедельник
	event := time.Date(2026, 5, 19, 9, 0, 0, 0, nsk) // вторник
	got := subtractWorkdays(event, 1)
	if got.Weekday() != time.Monday {
		t.Errorf("1 workday before Tuesday should be Monday, got %v", got.Weekday())
	}
}

func TestSubtractWorkdays_0Days_SameDay(t *testing.T) {
	nsk, _ := time.LoadLocation("Asia/Novosibirsk")
	event := time.Date(2026, 5, 20, 9, 0, 0, 0, nsk)
	got := subtractWorkdays(event, 0)
	if got != event {
		t.Errorf("0 workdays: want same time, got %v", got)
	}
}

// ── isLeadershipPosition ─────────────────────────────────────────────────────

func TestIsLeadershipPosition_Leaders(t *testing.T) {
	for _, code := range []string{"commander", "commissioner", "master"} {
		if !isLeadershipPosition(code) {
			t.Errorf("isLeadershipPosition(%q) should be true", code)
		}
	}
}

func TestIsLeadershipPosition_NonLeaders(t *testing.T) {
	for _, code := range []string{"fighter", "candidate", "superadmin", ""} {
		if isLeadershipPosition(code) {
			t.Errorf("isLeadershipPosition(%q) should be false", code)
		}
	}
}

// ── isManagerRole ─────────────────────────────────────────────────────────────

func TestIsManagerRole_ManagerRoles(t *testing.T) {
	for _, role := range []string{"superadmin", "regional_admin", "local_admin",
		"unit_commander", "unit_commissioner", "unit_master"} {
		if !isManagerRole(role) {
			t.Errorf("isManagerRole(%q) should be true", role)
		}
	}
}

func TestIsManagerRole_NonManagerRoles(t *testing.T) {
	for _, role := range []string{"participant", "candidate", "hq_staff", ""} {
		if isManagerRole(role) {
			t.Errorf("isManagerRole(%q) should be false", role)
		}
	}
}

// ── generateCode ─────────────────────────────────────────────────────────────

func TestGenerateCode_Returns6Digits(t *testing.T) {
	code, err := generateCode()
	if err != nil {
		t.Fatalf("generateCode: %v", err)
	}
	if len(code) != 6 {
		t.Errorf("expected 6-digit code, got %q (len=%d)", code, len(code))
	}
}

func TestGenerateCode_OnlyDigits(t *testing.T) {
	for i := 0; i < 20; i++ {
		code, _ := generateCode()
		for _, ch := range code {
			if ch < '0' || ch > '9' {
				t.Errorf("code %q contains non-digit %q", code, ch)
			}
		}
	}
}

func TestGenerateCode_Unique(t *testing.T) {
	seen := make(map[string]bool)
	for i := 0; i < 50; i++ {
		code, _ := generateCode()
		seen[code] = true
	}
	if len(seen) < 2 {
		t.Error("generateCode produced all identical codes — not random")
	}
}