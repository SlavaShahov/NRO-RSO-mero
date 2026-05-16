// Файл: internal/http/email_helpers_test.go
// Тесты вспомогательных функций email.go — они в пакете httpapi, whitebox тесты
package httpapi

import (
	"strings"
	"testing"
)

// ── positionSortOrder ────────────────────────────────────────────────────────

func TestPositionSortOrder_HQStaff_Ordering(t *testing.T) {
	// Штабники должны идти перед бойцами (1..4 < 5..8)
	cases := []struct {
		name      string
		isHQ      bool
		wantRange [2]int // min..max включительно
	}{
		{"Командир ШСО", true, [2]int{1, 1}},
		{"Комиссар ШСО", true, [2]int{2, 2}},
		{"Инженер ШСО",  true, [2]int{3, 3}},
		{"Работник ШСО", true, [2]int{4, 4}},
		{"Командир отряда", false, [2]int{5, 5}},
		{"Комиссар отряда", false, [2]int{6, 6}},
		{"Мастер отряда",   false, [2]int{7, 7}},
		{"Боец",            false, [2]int{8, 8}},
	}
	for _, tc := range cases {
		got := positionSortOrder(tc.name, tc.isHQ)
		if got < tc.wantRange[0] || got > tc.wantRange[1] {
			t.Errorf("positionSortOrder(%q, hq=%v) = %d, want %d..%d",
				tc.name, tc.isHQ, got, tc.wantRange[0], tc.wantRange[1])
		}
	}
}

func TestPositionSortOrder_HQBeforeUnit(t *testing.T) {
	hqOrder := positionSortOrder("Работник ШСО", true)   // worst HQ = 4
	unitOrder := positionSortOrder("Командир отряда", false) // best unit = 5
	if hqOrder >= unitOrder {
		t.Errorf("any HQ position (%d) should sort before unit positions (%d)", hqOrder, unitOrder)
	}
}

func TestPositionSortOrder_UnknownHQ_Returns4(t *testing.T) {
	got := positionSortOrder("Неизвестная должность ШСО", true)
	if got != 4 {
		t.Errorf("unknown HQ position should return 4, got %d", got)
	}
}

func TestPositionSortOrder_UnknownUnit_Returns8(t *testing.T) {
	got := positionSortOrder("Кандидат", false)
	if got != 8 {
		t.Errorf("unknown unit position should return 8, got %d", got)
	}
}

// ── positionDisplayName ──────────────────────────────────────────────────────

func TestPositionDisplayName_Kandidat_ReturnsBoyets(t *testing.T) {
	if got := positionDisplayName("Кандидат"); got != "Боец" {
		t.Errorf("want «Боец», got %q", got)
	}
}

func TestPositionDisplayName_Empty_ReturnsBoyets(t *testing.T) {
	if got := positionDisplayName(""); got != "Боец" {
		t.Errorf("want «Боец» for empty, got %q", got)
	}
}

func TestPositionDisplayName_Commander_Unchanged(t *testing.T) {
	if got := positionDisplayName("Командир"); got != "Командир" {
		t.Errorf("want «Командир», got %q", got)
	}
}

func TestPositionDisplayName_HQCommissioner_Unchanged(t *testing.T) {
	if got := positionDisplayName("Комиссар ШСО"); got != "Комиссар ШСО" {
		t.Errorf("want «Комиссар ШСО», got %q", got)
	}
}

// ── sanitizeFilename ─────────────────────────────────────────────────────────

func TestSanitizeFilename_ReplacesSlash(t *testing.T) {
	got := sanitizeFilename("Мероприятие/2026")
	if strings.Contains(got, "/") {
		t.Errorf("slash not replaced: %q", got)
	}
}

func TestSanitizeFilename_ReplacesBackslash(t *testing.T) {
	got := sanitizeFilename(`Отчёт\2026`)
	if strings.Contains(got, `\`) {
		t.Errorf("backslash not replaced: %q", got)
	}
}

func TestSanitizeFilename_ReplacesColon(t *testing.T) {
	got := sanitizeFilename("Дартс: финал")
	if strings.Contains(got, ":") {
		t.Errorf("colon not replaced: %q", got)
	}
}

func TestSanitizeFilename_ReplacesAsterisk(t *testing.T) {
	got := sanitizeFilename("Турнир*2026")
	if strings.Contains(got, "*") {
		t.Errorf("asterisk not replaced: %q", got)
	}
}

func TestSanitizeFilename_ReplacesQuestion(t *testing.T) {
	got := sanitizeFilename("Что?")
	if strings.Contains(got, "?") {
		t.Errorf("question not replaced: %q", got)
	}
}

func TestSanitizeFilename_ReplacesQuote(t *testing.T) {
	got := sanitizeFilename(`"Дартс"`)
	if strings.Contains(got, `"`) {
		t.Errorf("quote not replaced: %q", got)
	}
}

func TestSanitizeFilename_ReplacesAngleBrackets(t *testing.T) {
	got := sanitizeFilename("<Дартс>")
	if strings.Contains(got, "<") || strings.Contains(got, ">") {
		t.Errorf("angle brackets not replaced: %q", got)
	}
}

func TestSanitizeFilename_ReplacesPipe(t *testing.T) {
	got := sanitizeFilename("А|Б")
	if strings.Contains(got, "|") {
		t.Errorf("pipe not replaced: %q", got)
	}
}

func TestSanitizeFilename_NormalName_Unchanged(t *testing.T) {
	name := "Дартс НСО 2026"
	got := sanitizeFilename(name)
	if got != name {
		t.Errorf("normal name should be unchanged: %q → %q", name, got)
	}
}

func TestSanitizeFilename_CyrillicPreserved(t *testing.T) {
	got := sanitizeFilename("Закрытие спартакиады")
	if !strings.Contains(got, "Закрытие") {
		t.Errorf("Cyrillic text should be preserved: %q", got)
	}
}

// ── buildExcel ────────────────────────────────────────────────────────────────

func TestBuildExcel_ReturnsNonEmptyBytes(t *testing.T) {
	participants := []EventParticipant{
		{Num: 1, EventTitle: "Дартс", LastName: "Иванов", FirstName: "Иван",
			CardNumber: "001", UnitName: "ССО «Энергия»",
			PositionName: "Командир", PositionCode: "commander", IsHQStaff: false},
	}
	b, err := buildExcel("Дартс НСО 2026", participants)
	if err != nil {
		t.Fatalf("buildExcel: %v", err)
	}
	if len(b) == 0 {
		t.Error("expected non-empty xlsx bytes")
	}
	// XLSX начинается с PK (zip magic bytes)
	if len(b) < 2 || b[0] != 'P' || b[1] != 'K' {
		t.Errorf("expected XLSX (ZIP) magic bytes PK, got %x %x", b[0], b[1])
	}
}

func TestBuildExcel_EmptyParticipants(t *testing.T) {
	b, err := buildExcel("Пустое мероприятие", []EventParticipant{})
	if err != nil {
		t.Fatalf("buildExcel with no participants: %v", err)
	}
	if len(b) == 0 {
		t.Error("expected bytes even for empty participants")
	}
}

func TestBuildExcel_MultipleParticipants(t *testing.T) {
	parts := make([]EventParticipant, 10)
	for i := range parts {
		parts[i] = EventParticipant{
			Num: i + 1, LastName: "Фамилия",
			FirstName: "Имя", PositionName: "Боец",
		}
	}
	b, err := buildExcel("Тест", parts)
	if err != nil {
		t.Fatalf("buildExcel 10 participants: %v", err)
	}
	if len(b) == 0 {
		t.Error("expected non-empty result")
	}
}

// ── isAdminRole ───────────────────────────────────────────────────────────────

func TestIsAdminRole_AdminRoles(t *testing.T) {
	adminRoles := []string{"superadmin", "regional_admin", "local_admin",
		"unit_commander", "unit_commissioner", "unit_master"}
	for _, role := range adminRoles {
		if !isAdminRole(role) {
			t.Errorf("isAdminRole(%q) should be true", role)
		}
	}
}

func TestIsAdminRole_NonAdminRoles(t *testing.T) {
	nonAdmin := []string{"participant", "candidate", "hq_staff", ""}
	for _, role := range nonAdmin {
		if isAdminRole(role) {
			t.Errorf("isAdminRole(%q) should be false", role)
		}
	}
}
