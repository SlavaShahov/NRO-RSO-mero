// Файл: internal/models/models_full_test.go
package models_test

import (
	"encoding/json"
	"strings"
	"testing"
	"time"

	"rso-events/internal/models"
	"rso-events/internal/repo"
)

// ── models.User ──────────────────────────────────────────────────────────────

func TestUser_PasswordHash_NotInJSON(t *testing.T) {
	u := models.User{ID: 1, Email: "x@rso.ru", PasswordHash: "secret", RoleCode: "participant"}
	b, _ := json.Marshal(u)
	if strings.Contains(string(b), "secret") {
		t.Error("PasswordHash must not appear in JSON")
	}
}

func TestUser_AllFieldsSerialized(t *testing.T) {
	uid := 5
	u := models.User{
		ID: 1, Email: "u@rso.ru",
		LastName: "Иванов", FirstName: "Иван", MiddleName: "Петрович",
		Phone: "+79130000000", MemberCardNumber: "001",
		MemberCardLocation: "with_user", AccountStatus: "active",
		UnitID: &uid, RoleCode: "participant",
		UnitName: "ССО", HqName: "ШСО НГТУ", PositionName: "Боец",
	}
	b, _ := json.Marshal(u)
	s := string(b)
	for _, want := range []string{"Иванов", "u@rso.ru", "with_user", "participant"} {
		if !strings.Contains(s, want) {
			t.Errorf("expected %q in JSON", want)
		}
	}
}

func TestUser_OptionalFields_OmitEmpty(t *testing.T) {
	u := models.User{ID: 1, Email: "u@rso.ru", RoleCode: "participant"}
	b, _ := json.Marshal(u)
	s := string(b)
	// omitempty поля не должны появляться когда пустые
	if strings.Contains(s, `"phone"`) {
		t.Error("phone should be omitted when empty")
	}
	if strings.Contains(s, `"middle_name"`) {
		t.Error("middle_name should be omitted when empty")
	}
}

func TestUser_JSON_RoundTrip(t *testing.T) {
	uid := 3
	u := models.User{
		ID: 1, Email: "u@rso.ru",
		LastName: "Смирнов", FirstName: "Андрей",
		UnitID: &uid, RoleCode: "unit_commander",
	}
	b, _ := json.Marshal(u)
	var u2 models.User
	if err := json.Unmarshal(b, &u2); err != nil {
		t.Fatalf("Unmarshal: %v", err)
	}
	if u2.Email != "u@rso.ru" || u2.LastName != "Смирнов" {
		t.Errorf("round-trip mismatch: %+v", u2)
	}
}

// ── models.Event ─────────────────────────────────────────────────────────────

func TestEvent_AllFields(t *testing.T) {
	max := 50
	e := models.Event{
		ID: 1, Title: "Дартс",
		Description: "Турнир", EventDate: "2026-05-20",
		StartTime: "09:00", EndTime: "13:00", Location: "НСО",
		LevelCode: "regional", TypeCode: "sport", StatusCode: "published",
		ParticipationMode: "both", IsRegistrationRequired: true,
		MaxParticipants: &max, ParticipantsCount: 5,
		CreatedAt: time.Now(),
	}
	b, _ := json.Marshal(e)
	s := string(b)
	for _, want := range []string{"Дартс", "regional", "sport", "published"} {
		if !strings.Contains(s, want) {
			t.Errorf("expected %q in JSON", want)
		}
	}
}

func TestEvent_BannerBase64_OmitWhenEmpty(t *testing.T) {
	e := models.Event{ID: 1, Title: "T", EventDate: "2026-05-20",
		StartTime: "09:00", StatusCode: "published", CreatedAt: time.Now()}
	b, _ := json.Marshal(e)
	if strings.Contains(string(b), "banner_base64") {
		t.Error("banner_base64 must be omitted when empty")
	}
}

func TestEvent_UserRegistrationStatus_OmitWhenNil(t *testing.T) {
	e := models.Event{ID: 1, Title: "T", EventDate: "2026-05-20",
		StartTime: "09:00", StatusCode: "published", CreatedAt: time.Now()}
	b, _ := json.Marshal(e)
	if strings.Contains(string(b), "user_registration_status") {
		t.Error("user_registration_status must be omitted when nil")
	}
}

func TestEvent_UserRegistrationStatus_InJSON_WhenSet(t *testing.T) {
	status := "registered"
	e := models.Event{
		ID: 1, Title: "T", EventDate: "2026-05-20",
		StartTime: "09:00", StatusCode: "published",
		CreatedAt: time.Now(), UserRegistrationStatus: &status,
	}
	b, _ := json.Marshal(e)
	if !strings.Contains(string(b), "registered") {
		t.Error("user_registration_status must be in JSON when set")
	}
}

// ── models.HQ, Unit, Position ────────────────────────────────────────────────

func TestHQ_JSON(t *testing.T) {
	hq := models.HQ{ID: 1, Name: "ШСО НГТУ"}
	b, _ := json.Marshal(hq)
	if !strings.Contains(string(b), "ШСО НГТУ") {
		t.Error("HQ name missing in JSON")
	}
}

func TestUnit_JSON(t *testing.T) {
	u := models.Unit{ID: 1, Name: "ССО «Энергия»", DirectionCode: "ССО", HqName: "ШСО НГТУ"}
	b, _ := json.Marshal(u)
	s := string(b)
	if !strings.Contains(s, "ССО") || !strings.Contains(s, "ШСО НГТУ") {
		t.Error("Unit fields missing in JSON")
	}
}

func TestPosition_JSON(t *testing.T) {
	p := models.Position{ID: 1, Code: "commander", Name: "Командир"}
	b, _ := json.Marshal(p)
	if !strings.Contains(string(b), "commander") {
		t.Error("Position code missing in JSON")
	}
}

func TestHQPosition_JSON(t *testing.T) {
	p := models.HQPosition{ID: 1, Code: "commander", Name: "Командир ШСО"}
	b, _ := json.Marshal(p)
	if !strings.Contains(string(b), "Командир ШСО") {
		t.Error("HQPosition name missing in JSON")
	}
}

// ── repo.UserNotification ─────────────────────────────────────────────────────

func TestUserNotification_WithAllRefFields(t *testing.T) {
	id, approved := 42, true
	tp := "request"
	n := repo.UserNotification{
		ID: 1, UserID: 10, TypeCode: "hq_staff_approved",
		Title: "Одобрено", Body: "Заявка одобрена",
		RefID: &id, RefType: &tp, RefApproved: &approved,
		IsRead: false, CreatedAt: time.Now(),
	}
	b, _ := json.Marshal(n)
	s := string(b)
	checks := []string{`"ref_id":42`, `"ref_type":"request"`, `"ref_approved":true`}
	for _, c := range checks {
		if !strings.Contains(s, c) {
			t.Errorf("expected %q in JSON, got: %s", c, s)
		}
	}
}

func TestUserNotification_NilRefs_OmittedInJSON(t *testing.T) {
	n := repo.UserNotification{ID: 1, UserID: 1, TypeCode: "new_event_created",
		Title: "T", Body: "B", CreatedAt: time.Now()}
	b, _ := json.Marshal(n)
	s := string(b)
	for _, bad := range []string{"ref_id", "ref_type", "ref_approved"} {
		if strings.Contains(s, bad) {
			t.Errorf("%q must be omitted when nil", bad)
		}
	}
}

func TestUserNotification_AllTypeCodes_Marshal(t *testing.T) {
	types := []string{
		"hq_staff_request", "hq_staff_approved", "hq_staff_rejected",
		"new_event_created", "position_change_approved", "position_change_rejected",
		"system_message",
	}
	for _, tc := range types {
		n := repo.UserNotification{ID: 1, UserID: 1, TypeCode: tc,
			Title: "T", Body: "B", CreatedAt: time.Now()}
		b, err := json.Marshal(n)
		if err != nil {
			t.Errorf("Marshal failed for type_code=%s: %v", tc, err)
		}
		if !strings.Contains(string(b), tc) {
			t.Errorf("type_code=%s not in JSON", tc)
		}
	}
}

// ── repo.EventScheduleRow ─────────────────────────────────────────────────────

func TestEventScheduleRow_EmailSent_True(t *testing.T) {
	r := repo.EventScheduleRow{ID: 5, EventDate: "2026-05-20", EmailSent: true}
	if !r.EmailSent {
		t.Error("EmailSent should be true")
	}
}

func TestEventScheduleRow_EmailSent_FalseDefault(t *testing.T) {
	r := repo.EventScheduleRow{ID: 6, EventDate: "2026-06-01"}
	if r.EmailSent {
		t.Error("EmailSent should default to false")
	}
}

func TestEventScheduleRow_AllFields(t *testing.T) {
	r := repo.EventScheduleRow{ID: 10, EventDate: "2026-07-15", EmailSent: true}
	if r.ID != 10 || r.EventDate != "2026-07-15" || !r.EmailSent {
		t.Errorf("unexpected row: %+v", r)
	}
}

// ── models.HQStaffRequest ─────────────────────────────────────────────────────

func TestHQStaffRequest_JSON(t *testing.T) {
	req := models.HQStaffRequest{
		ID: 1, UserID: 5, FullName: "Иванов Иван",
		HQID: 2, HQName: "ШСО НГТУ",
		PositionID: 1, PositionName: "Командир ШСО",
		Status: "pending",
	}
	b, _ := json.Marshal(req)
	s := string(b)
	if !strings.Contains(s, "pending") || !strings.Contains(s, "ШСО НГТУ") {
		t.Error("HQStaffRequest fields missing in JSON")
	}
}

// ── models.EventUnitQuota ─────────────────────────────────────────────────────

func TestEventUnitQuota_JSON(t *testing.T) {
	maxP, maxS := 10, 20
	q := models.EventUnitQuota{EventID: 1, UnitID: 2, MaxParticipants: &maxP, MaxSpectators: &maxS}
	b, _ := json.Marshal(q)
	s := string(b)
	if !strings.Contains(s, "10") || !strings.Contains(s, "20") {
		t.Error("EventUnitQuota quota values missing in JSON")
	}
}
