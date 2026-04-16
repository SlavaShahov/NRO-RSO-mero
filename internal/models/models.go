package models

import "time"

type User struct {
	ID                  int    `json:"id"`
	Email               string `json:"email"`
	PasswordHash        string `json:"-"`
	LastName            string `json:"last_name"`
	FirstName           string `json:"first_name"`
	MiddleName          string `json:"middle_name,omitempty"`
	Phone               string `json:"phone,omitempty"`
	MemberCardNumber    string `json:"member_card_number,omitempty"`
	MemberCardLocation  string `json:"member_card_location,omitempty"` // with_user | in_hq
	AccountStatus       string `json:"account_status,omitempty"`       // active | pending_approval | rejected
	UnitID              *int   `json:"unit_id,omitempty"`
	UnitPositionID      *int   `json:"unit_position_id,omitempty"`
	UnitName            string `json:"unit_name,omitempty"`
	HqName              string `json:"hq_name,omitempty"`
	PositionName        string `json:"position_name,omitempty"`
	RoleCode            string `json:"role_code"`
	AvatarBase64        string `json:"avatar_base64,omitempty"`
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
	ParticipationMode      string    `json:"participation_mode"` // open|spectators_only|participants_only|both
	IsRegistrationRequired bool      `json:"is_registration_required"`
	MaxParticipants        *int      `json:"max_participants,omitempty"`
	MaxSpectators          *int      `json:"max_spectators,omitempty"`
	ParticipantsCount      int       `json:"participants_count"`
	SpectatorsCount        int       `json:"spectators_count"`
	CreatedAt              time.Time `json:"created_at"`
	UserRegistrationStatus *string   `json:"user_registration_status,omitempty"`
	UserParticipationType  *string   `json:"user_participation_type,omitempty"`
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

type Position struct {
	ID   int    `json:"id"`
	Code string `json:"code"`
	Name string `json:"name"`
}

// HQPosition — должность в штабе (ШСО)
type HQPosition struct {
	ID   int    `json:"id"`
	Code string `json:"code"`
	Name string `json:"name"`
}

// HQStaffRequest — заявка на должность штабника
type HQStaffRequest struct {
	ID           int       `json:"id"`
	UserID       int       `json:"user_id"`
	FullName     string    `json:"full_name"`
	HQID         int       `json:"hq_id"`
	HQName       string    `json:"hq_name"`
	PositionID   int       `json:"position_id"`
	PositionName string    `json:"position_name"`
	Status       string    `json:"status"` // pending|approved|rejected
	RequestedAt  time.Time `json:"requested_at"`
	Comment      string    `json:"comment,omitempty"`
}

// EventUnitQuota — квота отряда на мероприятие
type EventUnitQuota struct {
	EventID         int  `json:"event_id"`
	UnitID          int  `json:"unit_id"`
	MaxParticipants *int `json:"max_participants,omitempty"`
	MaxSpectators   *int `json:"max_spectators,omitempty"`
}