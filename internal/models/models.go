package models

import "time"

type User struct {
	ID             int    `json:"id"`
	Email          string `json:"email"`
	PasswordHash   string `json:"-"`
	LastName       string `json:"last_name"`
	FirstName      string `json:"first_name"`
	MiddleName     string `json:"middle_name,omitempty"`
	UnitID         *int   `json:"unit_id,omitempty"`
	UnitPositionID *int   `json:"unit_position_id,omitempty"`
	UnitName       string `json:"unit_name,omitempty"`
	HqName         string `json:"hq_name,omitempty"`
	PositionName   string `json:"position_name,omitempty"`
	RoleCode       string `json:"role_code"`
}

type Event struct {
	ID                     int       `json:"id"`
	Title                  string    `json:"title"`
	Description            string    `json:"description"`
	EventDate              string    `json:"event_date"`
	StartTime              string    `json:"start_time"`
	EndTime                string    `json:"end_time,omitempty"`
	Location               string    `json:"location"`
	LevelCode              string    `json:"level_code"`
	TypeCode               string    `json:"type_code"`
	StatusCode             string    `json:"status_code"`
	IsRegistrationRequired bool      `json:"is_registration_required"`
	MaxParticipants        *int      `json:"max_participants,omitempty"`
	ParticipantsCount      int       `json:"participants_count"`
	CreatedAt              time.Time `json:"created_at"`
	UserRegistrationStatus *string   `json:"user_registration_status,omitempty"`
}

type HQ struct {
	ID   int    `json:"id"`
	Name string `json:"name"`
}

type Unit struct {
	ID            int    `json:"id"`
	Name          string `json:"name"`
	DirectionCode string `json:"direction_code"`
	HqName        string `json:"hq_name"`
}

// Position — должность в отряде (только те что можно выбрать при регистрации)
type Position struct {
	ID   int    `json:"id"`
	Code string `json:"code"`
	Name string `json:"name"`
}