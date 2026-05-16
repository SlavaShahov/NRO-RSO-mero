package models_test

import (
	"strings"
	"encoding/json"
	"testing"
	"time"

	"rso-events/internal/models"
	"rso-events/internal/repo"
)

// ── models.User ──────────────────────────────────────────────────────────────

func TestUser_JSONSerialization(t *testing.T) {
	u := models.User{
		ID: 1, Email: "test@rso.ru",
		LastName: "Иванов", FirstName: "Иван",
		RoleCode: "participant",
		PasswordHash: "secret", // не должен выйти в JSON
	}
	b, err := json.Marshal(u)
	if err != nil {
		t.Fatalf("Marshal: %v", err)
	}
	s := string(b)
	if strings.Contains(s, "secret") {
		t.Error("password_hash must not appear in JSON output (tag: json:\"-\")")
	}
	if !strings.Contains(s, "test@rso.ru") {
		t.Error("email should be in JSON")
	}
}

func TestUser_JSONDeserialization(t *testing.T) {
	raw := `{"id":5,"email":"u@rso.ru","last_name":"Смирнов","first_name":"Андрей","role_code":"unit_commander"}`
	var u models.User
	if err := json.Unmarshal([]byte(raw), &u); err != nil {
		t.Fatalf("Unmarshal: %v", err)
	}
	if u.ID != 5 || u.Email != "u@rso.ru" {
		t.Errorf("unexpected user: %+v", u)
	}
}

// ── models.Event ─────────────────────────────────────────────────────────────

func TestEvent_JSONSerialization(t *testing.T) {
	now := time.Now()
	e := models.Event{
		ID: 1, Title: "Дартс",
		EventDate: "2026-05-15",
		StartTime: "09:00",
		StatusCode: "published",
		CreatedAt: now,
	}
	b, err := json.Marshal(e)
	if err != nil {
		t.Fatalf("Marshal Event: %v", err)
	}
	if !strings.Contains(string(b), "Дартс") {
		t.Error("title should be in JSON")
	}
}

// ── repo.UserNotification ────────────────────────────────────────────────────

func TestUserNotification_RefFields(t *testing.T) {
	id := 42
	tp := "request"
	approved := true
	n := repo.UserNotification{
		ID: 1, UserID: 10,
		TypeCode: "hq_staff_approved",
		Title: "Заявка одобрена",
		Body: "Ваша заявка в ШСО одобрена",
		RefID: &id,
		RefType: &tp,
		RefApproved: &approved,
		IsRead: false,
		CreatedAt: time.Now(),
	}
	b, err := json.Marshal(n)
	if err != nil {
		t.Fatalf("Marshal: %v", err)
	}
	s := string(b)
	if !strings.Contains(s, "ref_id") {
		t.Error("ref_id should be in JSON")
	}
	if !strings.Contains(s, "ref_type") {
		t.Error("ref_type should be in JSON")
	}
	if !strings.Contains(s, "ref_approved") {
		t.Error("ref_approved should be in JSON")
	}
}

func TestUserNotification_NilRefFields_OmitEmpty(t *testing.T) {
	n := repo.UserNotification{
		ID: 2, UserID: 1,
		TypeCode: "new_event_created",
		Title: "Новое мероприятие", Body: "...",
		IsRead: false, CreatedAt: time.Now(),
	}
	b, _ := json.Marshal(n)
	s := string(b)
	// nil pointer поля с omitempty не должны выходить в JSON
	if strings.Contains(s, "ref_id") {
		t.Error("ref_id should be omitted when nil")
	}
}

// ── repo.EventScheduleRow ────────────────────────────────────────────────────

func TestEventScheduleRow_EmailSentField(t *testing.T) {
	row := repo.EventScheduleRow{
		ID: 5, EventDate: "2026-05-20", EmailSent: true,
	}
	if !row.EmailSent {
		t.Error("EmailSent should be true")
	}
	row2 := repo.EventScheduleRow{ID: 6, EventDate: "2026-06-01", EmailSent: false}
	if row2.EmailSent {
		t.Error("EmailSent should be false")
	}
}
