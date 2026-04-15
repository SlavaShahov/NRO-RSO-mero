package httpapi

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"

	"rso-events/internal/middleware"
	"rso-events/internal/models"
	"rso-events/internal/repo"
	"context"
	"rso-events/internal/service"

	"github.com/go-chi/chi/v5"
)

type Handler struct{ svc *service.Service }

func New(svc *service.Service) *Handler { return &Handler{svc: svc} }

func (h *Handler) Register(r chi.Router) {
	r.Get("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, 200, map[string]any{"status": "ok"})
	})

	r.Route("/api/v1", func(r chi.Router) {
		// Публичные
		r.Post("/auth/register",  h.register)
		r.Post("/auth/login",     h.login)
		r.Post("/auth/refresh",   h.refresh)
		r.Get("/events",          h.listEvents)
		r.Get("/hqs",             h.listHQs)
		r.Get("/hqs/{hqID}/units", h.listUnits)
		r.Get("/positions",       h.listPositions)
		r.Get("/hq_positions",    h.listHQPositions)

		// Защищённые
		r.Group(func(r chi.Router) {
			r.Use(middleware.AuthRequired(h.svc))

			// Auth
			r.Post("/auth/logout", h.logout)

			// Profile
			r.Get("/me",                      h.me)
			r.Put("/me",                      h.updateProfile)
			r.Get("/portfolio",               h.portfolio)
			r.Get("/me/registrations",        h.myRegistrations)
			r.Get("/me/hq_units",             h.myHQUnits)

			// Members
			r.Get("/units/{unitID}/members",  h.unitMembers)

			// Events
			r.Post("/events",                         h.createEvent)
			r.Post("/events/{eventID}/register",      h.registerToEvent)
			r.Post("/events/{eventID}/quotas",        h.setEventQuota)
			r.Post("/attendance/scan",                h.scanAttendance)

			// HQ Staff
			r.Post("/hq_staff/request",         h.hqStaffRequest)
			r.Get("/hq_staff/pending",          h.hqStaffPending)
			r.Post("/hq_staff/{id}/review",     h.hqStaffReview)
			r.Get("/hq_staff/check_position",   h.hqStaffCheckPosition)

			// Avatar
			r.Post("/me/avatar",                h.uploadAvatar)
			r.Get("/me/avatar",                 h.getAvatar)

			// Notifications
			r.Get("/notifications",             h.listNotifications)
			r.Get("/notifications/unread",      h.countUnread)
			r.Post("/notifications/read_all",   h.markAllRead)
			r.Post("/notifications/{id}/read",  h.markOneRead)
		})
	})
}

// ── Auth ──────────────────────────────────────────────────────────────────────

func (h *Handler) register(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Email              string `json:"email"`
		Password           string `json:"password"`
		LastName           string `json:"last_name"`
		FirstName          string `json:"first_name"`
		MiddleName         string `json:"middle_name"`
		Phone              string `json:"phone"`
		MemberCardNumber   string `json:"member_card_number"`
		MemberCardLocation string `json:"member_card_location"`
		UnitID             *int   `json:"unit_id"`
		UnitPositionID     *int   `json:"unit_position_id"`
		HqID               *int   `json:"hq_id"`
		HqPositionID       *int   `json:"hq_position_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeError(w, 400, "invalid json"); return
	}
	if in.Email == "" || in.Password == "" || in.LastName == "" || in.FirstName == "" {
		writeError(w, 400, "email, password, last_name, first_name are required"); return
	}
	loc := in.MemberCardLocation
	if loc != "with_user" && loc != "in_hq" { loc = "with_user" }

	id, acc, ref, err := h.svc.Register(r.Context(), models.User{
		Email: in.Email, LastName: in.LastName, FirstName: in.FirstName,
		MiddleName: in.MiddleName, Phone: in.Phone,
		MemberCardNumber: in.MemberCardNumber, MemberCardLocation: loc,
		UnitID: in.UnitID, UnitPositionID: in.UnitPositionID,
	}, in.Password)
	if err != nil {
		if err.Error() == "password must be at least 8 characters" {
			writeError(w, 400, err.Error()); return
		}
		writeError(w, 409, "Пользователь уже существует или некорректные данные"); return
	}

	// ШСО-заявка: создаём и уведомляем администраторов
	if in.HqID != nil && in.HqPositionID != nil {
		reqID, err := h.svc.CreateHQStaffRequest(r.Context(), id, *in.HqID, *in.HqPositionID)
		if err == nil {
			// Формируем текст уведомления для администраторов
			applicantName := in.LastName + " " + in.FirstName
			if in.MiddleName != "" { applicantName += " " + in.MiddleName }
			body := "👤 " + applicantName
			if in.Phone != "" { body += "\n📞 " + in.Phone }
			if in.MemberCardNumber != "" { body += "\n🪪 Билет № " + in.MemberCardNumber }
			go func(bgCtx context.Context, rID int, b string) {
				_ = h.svc.NotifyAdmins(bgCtx, "hq_staff_request",
					"📋 Новая заявка на должность ШСО", b,
					map[string]any{"request_id": rID})
			}(context.Background(), reqID, body)
		}
	}

	writeJSON(w, 201, map[string]any{
		"user_id": id, "access_token": acc, "refresh_token": ref,
	})
}

func (h *Handler) login(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Email    string `json:"email"`
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeError(w, 400, "invalid json"); return
	}
	acc, ref, err := h.svc.Login(r.Context(), in.Email, in.Password)
	if err != nil { writeError(w, 401, "Неверный email или пароль"); return }
	writeJSON(w, 200, map[string]any{"access_token": acc, "refresh_token": ref})
}

func (h *Handler) refresh(w http.ResponseWriter, r *http.Request) {
	var in struct{ RefreshToken string `json:"refresh_token"` }
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil || in.RefreshToken == "" {
		writeError(w, 400, "refresh_token is required"); return
	}
	acc, ref, err := h.svc.Refresh(in.RefreshToken)
	if err != nil { writeError(w, 401, "Токен истёк или недействителен"); return }
	writeJSON(w, 200, map[string]any{"access_token": acc, "refresh_token": ref})
}

func (h *Handler) logout(w http.ResponseWriter, r *http.Request) {
	var in struct{ RefreshToken string `json:"refresh_token"` }
	_ = json.NewDecoder(r.Body).Decode(&in)
	accTok, _ := r.Context().Value(middleware.TokenKey).(string)
	_ = h.svc.Logout(accTok, in.RefreshToken)
	writeJSON(w, 200, map[string]any{"status": "logged_out"})
}

// ── Profile ───────────────────────────────────────────────────────────────────

func (h *Handler) me(w http.ResponseWriter, r *http.Request) {
	uid, ok := r.Context().Value(middleware.UserIDKey).(int)
	if !ok { writeError(w, 401, "unauthorized"); return }
	u, err := h.svc.Me(r.Context(), uid)
	if err != nil { writeError(w, 404, "user not found"); return }
	writeJSON(w, 200, u)
}

func (h *Handler) updateProfile(w http.ResponseWriter, r *http.Request) {
	uid, ok := r.Context().Value(middleware.UserIDKey).(int)
	if !ok { writeError(w, 401, "unauthorized"); return }
	var in struct {
		LastName           string `json:"last_name"`
		FirstName          string `json:"first_name"`
		MiddleName         string `json:"middle_name"`
		Phone              string `json:"phone"`
		MemberCardNumber   string `json:"member_card_number"`
		MemberCardLocation string `json:"member_card_location"`
	}
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeError(w, 400, "invalid json"); return
	}
	if in.LastName == "" || in.FirstName == "" {
		writeError(w, 400, "last_name and first_name are required"); return
	}
	loc := in.MemberCardLocation
	if loc != "with_user" && loc != "in_hq" { loc = "with_user" }
	if err := h.svc.UpdateProfile(r.Context(), uid,
		in.LastName, in.FirstName, in.MiddleName,
		in.Phone, in.MemberCardNumber, loc); err != nil {
		writeError(w, 500, "update failed"); return
	}
	u, _ := h.svc.Me(r.Context(), uid)
	writeJSON(w, 200, u)
}

func (h *Handler) myRegistrations(w http.ResponseWriter, r *http.Request) {
	uid, ok := r.Context().Value(middleware.UserIDKey).(int)
	if !ok { writeError(w, 401, "unauthorized"); return }
	regs, err := h.svc.GetMyRegistrations(r.Context(), uid)
	if err != nil { writeError(w, 500, "registrations query failed"); return }
	if regs == nil { regs = []repo.MyRegistration{} }
	writeJSON(w, 200, regs)
}

func (h *Handler) myHQUnits(w http.ResponseWriter, r *http.Request) {
	uid, ok := r.Context().Value(middleware.UserIDKey).(int)
	if !ok { writeError(w, 401, "unauthorized"); return }
	units, err := h.svc.GetHQUnitsForStaff(r.Context(), uid)
	if err != nil { writeError(w, 403, "not a hq staff member"); return }
	if units == nil { units = []models.Unit{} }
	writeJSON(w, 200, units)
}

func (h *Handler) unitMembers(w http.ResponseWriter, r *http.Request) {
	unitID, err := strconv.Atoi(chi.URLParam(r, "unitID"))
	if err != nil { writeError(w, 400, "invalid unit id"); return }
	members, err := h.svc.ListUnitMembers(r.Context(), unitID)
	if err != nil { writeError(w, 500, "members query failed"); return }
	if members == nil { members = []models.User{} }
	writeJSON(w, 200, members)
}

func (h *Handler) portfolio(w http.ResponseWriter, r *http.Request) {
	uid, ok := r.Context().Value(middleware.UserIDKey).(int)
	if !ok { writeError(w, 401, "unauthorized"); return }
	up, att, err := h.svc.Portfolio(r.Context(), uid)
	if err != nil { writeError(w, 500, "portfolio query failed"); return }
	writeJSON(w, 200, map[string]any{"user_id": uid, "upcoming": up, "attended": att})
}

// ── Refs ──────────────────────────────────────────────────────────────────────

func (h *Handler) listHQs(w http.ResponseWriter, r *http.Request) {
	hqs, err := h.svc.ListHQs(r.Context())
	if err != nil { writeError(w, 500, "hqs query failed"); return }
	writeJSON(w, 200, hqs)
}

func (h *Handler) listUnits(w http.ResponseWriter, r *http.Request) {
	hqID, err := strconv.Atoi(chi.URLParam(r, "hqID"))
	if err != nil { writeError(w, 400, "invalid hq id"); return }
	units, err := h.svc.ListUnitsByHQ(r.Context(), hqID)
	if err != nil { writeError(w, 500, "units query failed"); return }
	if units == nil { units = []models.Unit{} }
	writeJSON(w, 200, units)
}

func (h *Handler) listPositions(w http.ResponseWriter, r *http.Request) {
	p, err := h.svc.ListPositions(r.Context())
	if err != nil { writeError(w, 500, "positions query failed"); return }
	writeJSON(w, 200, p)
}

func (h *Handler) listHQPositions(w http.ResponseWriter, r *http.Request) {
	p, err := h.svc.ListHQPositions(r.Context())
	if err != nil { writeError(w, 500, "hq_positions query failed"); return }
	writeJSON(w, 200, p)
}

// ── Events ────────────────────────────────────────────────────────────────────

func (h *Handler) listEvents(w http.ResponseWriter, r *http.Request) {
	uid, _ := r.Context().Value(middleware.UserIDKey).(int)
	evs, err := h.svc.ListEvents(r.Context(), uid,
		r.URL.Query().Get("level"),
		r.URL.Query().Get("type"),
		r.URL.Query().Get("search"))
	if err != nil { writeError(w, 500, "events query failed"); return }
	if evs == nil { evs = []models.Event{} }
	writeJSON(w, 200, evs)
}

func (h *Handler) createEvent(w http.ResponseWriter, r *http.Request) {
	role, _ := r.Context().Value(middleware.RoleKey).(string)
	if !isAdminRole(role) { writeError(w, 403, "Недостаточно прав"); return }
	uid, _ := r.Context().Value(middleware.UserIDKey).(int)
	var in struct {
		Title             string `json:"title"`
		Description       string `json:"description"`
		Location          string `json:"location"`
		EventDate         string `json:"event_date"`
		StartTime         string `json:"start_time"`
		LevelCode         string `json:"level_code"`
		TypeCode          string `json:"type_code"`
		ParticipationMode string `json:"participation_mode"`
		MaxParticipants   *int   `json:"max_participants"`
		MaxSpectators     *int   `json:"max_spectators"`
	}
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeError(w, 400, "invalid json"); return
	}
	if in.Title == "" || in.EventDate == "" || in.StartTime == "" {
		writeError(w, 400, "title, event_date, start_time are required"); return
	}
	if in.LevelCode == ""        { in.LevelCode = "local" }
	if in.TypeCode == ""         { in.TypeCode = "other" }
	if in.ParticipationMode == "" { in.ParticipationMode = "open" }

	id, err := h.svc.CreateEvent(r.Context(), models.Event{
		Title: in.Title, Description: in.Description, Location: in.Location,
		EventDate: in.EventDate, StartTime: in.StartTime,
		LevelCode: in.LevelCode, TypeCode: in.TypeCode,
		ParticipationMode: in.ParticipationMode,
		MaxParticipants: in.MaxParticipants, MaxSpectators: in.MaxSpectators,
	}, uid)
	if err != nil { writeError(w, 500, "create event failed: "+err.Error()); return }

	// Уведомляем всех участников о новом мероприятии
	go func(bgCtx context.Context, title, date, loc string, eid int) {
		b := "📅 " + date
		if loc != "" { b += " • " + loc }
		_ = h.svc.NotifyAllParticipants(bgCtx, "new_event_created",
			"🎉 Новое мероприятие: "+title, b, map[string]any{"event_id": eid})
	}(context.Background(), in.Title, in.EventDate, in.Location, id)

	writeJSON(w, 201, map[string]any{"event_id": id, "status": "created"})
}

func (h *Handler) registerToEvent(w http.ResponseWriter, r *http.Request) {
	uid, ok := r.Context().Value(middleware.UserIDKey).(int)
	if !ok { writeError(w, 401, "unauthorized"); return }
	eid, err := strconv.Atoi(chi.URLParam(r, "eventID"))
	if err != nil { writeError(w, 400, "invalid event id"); return }

	var in struct {
		ParticipationType string `json:"participation_type"`
	}
	_ = json.NewDecoder(r.Body).Decode(&in)

	events, err := h.svc.ListEvents(r.Context(), 0, "", "", "")
	if err != nil { writeError(w, 500, "event lookup failed"); return }
	var target *models.Event
	for i := range events {
		if events[i].ID == eid { target = &events[i]; break }
	}
	if target == nil { writeError(w, 404, "Мероприятие не найдено"); return }

	if target.ParticipationMode == "spectators_only" {
		in.ParticipationType = "spectator"
	} else if target.ParticipationMode == "participants_only" || target.ParticipationMode == "open" {
		in.ParticipationType = "participant"
	} else if in.ParticipationType == "" {
		in.ParticipationType = "participant"
	}

	regID, qr, err := h.svc.RegisterToEvent(r.Context(), uid, *target)
	if err != nil {
		if errors.Is(err, service.ErrRegClosed) {
			writeError(w, 409, "Регистрация закрыта (менее 3 рабочих дней)")
		} else {
			writeError(w, 409, "Вы уже зарегистрированы или мероприятие недоступно")
		}
		return
	}
	writeJSON(w, 201, map[string]any{"registration_id": regID, "qr_code": qr.String()})
}

func (h *Handler) scanAttendance(w http.ResponseWriter, r *http.Request) {
	uid, ok := r.Context().Value(middleware.UserIDKey).(int)
	if !ok { writeError(w, 401, "unauthorized"); return }
	role, _ := r.Context().Value(middleware.RoleKey).(string)
	var in struct{ QRCode string `json:"qr_code"` }
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil || in.QRCode == "" {
		writeError(w, 400, "invalid qr_code"); return
	}
	info, err := h.svc.ScanAttendance(r.Context(), role, uid, in.QRCode)
	if err != nil {
		switch {
		case errors.Is(err, service.ErrForbidden):    writeError(w, 403, "Недостаточно прав")
		case errors.Is(err, service.ErrInvalidQR):    writeError(w, 400, "Неверный формат QR-кода")
		case errors.Is(err, repo.ErrAlreadyAttended): writeError(w, 409, "Посещение уже отмечено")
		case repo.IsNotFound(err):                    writeError(w, 404, "Регистрация не найдена")
		default:                                       writeError(w, 500, "scan failed")
		}
		return
	}
	writeJSON(w, 200, map[string]any{
		"status":          "attendance_marked",
		"registration_id": info.RegistrationID,
		"user": map[string]any{
			"user_id":              info.UserID,
			"full_name":            info.FullName,
			"avatar_base64":        info.AvatarBase64,
			"unit_name":            info.UnitName,
			"hq_name":              info.HqName,
			"position_name":        info.PositionName,
			"phone":                info.Phone,
			"member_card_number":   info.MemberCardNumber,
			"member_card_location": info.MemberCardLocation,
		},
		"event": map[string]any{
			"title":      info.EventTitle,
			"event_date": info.EventDate,
		},
	})
}

func (h *Handler) setEventQuota(w http.ResponseWriter, r *http.Request) {
	role, _ := r.Context().Value(middleware.RoleKey).(string)
	if !isAdminRole(role) { writeError(w, 403, "Недостаточно прав"); return }
	eid, err := strconv.Atoi(chi.URLParam(r, "eventID"))
	if err != nil { writeError(w, 400, "invalid event id"); return }
	var in struct {
		UnitID          int  `json:"unit_id"`
		MaxParticipants *int `json:"max_participants"`
		MaxSpectators   *int `json:"max_spectators"`
	}
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil || in.UnitID == 0 {
		writeError(w, 400, "unit_id required"); return
	}
	if err := h.svc.SetEventUnitQuota(r.Context(), models.EventUnitQuota{
		EventID: eid, UnitID: in.UnitID,
		MaxParticipants: in.MaxParticipants, MaxSpectators: in.MaxSpectators,
	}); err != nil {
		writeError(w, 500, "quota set failed"); return
	}
	writeJSON(w, 200, map[string]any{"status": "ok"})
}

// ── HQ Staff ──────────────────────────────────────────────────────────────────

func (h *Handler) hqStaffRequest(w http.ResponseWriter, r *http.Request) {
	uid, ok := r.Context().Value(middleware.UserIDKey).(int)
	if !ok { writeError(w, 401, "unauthorized"); return }
	var in struct {
		HQID       int `json:"hq_id"`
		PositionID int `json:"hq_position_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil || in.HQID == 0 || in.PositionID == 0 {
		writeError(w, 400, "hq_id and hq_position_id are required"); return
	}
	reqID, err := h.svc.CreateHQStaffRequest(r.Context(), uid, in.HQID, in.PositionID)
	if err != nil { writeError(w, 500, "request failed"); return }

	// Уведомляем администраторов
	u, _ := h.svc.Me(r.Context(), uid)
	body := "👤 " + u.LastName + " " + u.FirstName
	if u.Phone != "" { body += "\n📞 " + u.Phone }
	if u.MemberCardNumber != "" { body += "\n🪪 Билет № " + u.MemberCardNumber }
	go func(bgCtx context.Context, rID int, b string) {
		_ = h.svc.NotifyAdmins(bgCtx, "hq_staff_request",
			"📋 Новая заявка на должность ШСО", b, map[string]any{"request_id": rID})
	}(context.Background(), reqID, body)

	writeJSON(w, 201, map[string]any{"request_id": reqID, "status": "pending"})
}

func (h *Handler) hqStaffPending(w http.ResponseWriter, r *http.Request) {
	role, _ := r.Context().Value(middleware.RoleKey).(string)
	if role != "superadmin" && role != "regional_admin" && role != "local_admin" {
		writeError(w, 403, "Недостаточно прав"); return
	}
	hqID, err := strconv.Atoi(r.URL.Query().Get("hq_id"))
	if err != nil || hqID == 0 { writeError(w, 400, "hq_id required"); return }
	reqs, err := h.svc.ListPendingHQRequests(r.Context(), hqID)
	if err != nil { writeError(w, 500, "query failed"); return }
	if reqs == nil { reqs = []models.HQStaffRequest{} }
	writeJSON(w, 200, reqs)
}

func (h *Handler) hqStaffReview(w http.ResponseWriter, r *http.Request) {
	reviewerID, ok := r.Context().Value(middleware.UserIDKey).(int)
	if !ok { writeError(w, 401, "unauthorized"); return }
	role, _ := r.Context().Value(middleware.RoleKey).(string)
	if role != "superadmin" && role != "regional_admin" && role != "local_admin" {
		writeError(w, 403, "Недостаточно прав"); return
	}
	reqID, err := strconv.Atoi(chi.URLParam(r, "id"))
	if err != nil { writeError(w, 400, "invalid id"); return }
	var in struct {
		Approved bool   `json:"approved"`
		Comment  string `json:"comment"`
	}
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeError(w, 400, "invalid json"); return
	}
	if err := h.svc.ReviewHQStaffRequest(r.Context(), reqID, reviewerID, in.Approved, in.Comment); err != nil {
		if errors.Is(err, repo.ErrPositionTaken) {
			writeError(w, 409, "Эта должность уже занята в данном штабе. Сначала снимите предыдущего командира/комиссара.")
		} else {
			writeError(w, 500, "review failed")
		}
		return
	}
	status := "rejected"
	if in.Approved { status = "approved" }
	writeJSON(w, 200, map[string]any{"status": status})
}

// ── Notifications ─────────────────────────────────────────────────────────────

func (h *Handler) listNotifications(w http.ResponseWriter, r *http.Request) {
	uid, ok := r.Context().Value(middleware.UserIDKey).(int)
	if !ok { writeError(w, 401, "unauthorized"); return }
	notifs, err := h.svc.ListNotifications(r.Context(), uid)
	if err != nil { writeError(w, 500, "query failed"); return }
	if notifs == nil { notifs = []repo.UserNotification{} }
	writeJSON(w, 200, notifs)
}

func (h *Handler) countUnread(w http.ResponseWriter, r *http.Request) {
	uid, ok := r.Context().Value(middleware.UserIDKey).(int)
	if !ok { writeError(w, 401, "unauthorized"); return }
	cnt, err := h.svc.CountUnread(r.Context(), uid)
	if err != nil { writeError(w, 500, "query failed"); return }
	writeJSON(w, 200, map[string]int{"unread": cnt})
}

func (h *Handler) markAllRead(w http.ResponseWriter, r *http.Request) {
	uid, ok := r.Context().Value(middleware.UserIDKey).(int)
	if !ok { writeError(w, 401, "unauthorized"); return }
	if err := h.svc.MarkAllRead(r.Context(), uid); err != nil {
		writeError(w, 500, "update failed"); return
	}
	writeJSON(w, 200, map[string]any{"status": "ok"})
}

func (h *Handler) markOneRead(w http.ResponseWriter, r *http.Request) {
	uid, ok := r.Context().Value(middleware.UserIDKey).(int)
	if !ok { writeError(w, 401, "unauthorized"); return }
	nid, err := strconv.Atoi(chi.URLParam(r, "id"))
	if err != nil { writeError(w, 400, "invalid id"); return }
	if err := h.svc.MarkOneRead(r.Context(), nid, uid); err != nil {
		writeError(w, 500, "update failed"); return
	}
	writeJSON(w, 200, map[string]any{"status": "ok"})
}

// ── Helpers ───────────────────────────────────────────────────────────────────

func isAdminRole(role string) bool {
	switch role {
	case "superadmin", "regional_admin", "local_admin",
		"unit_commander", "unit_commissioner", "unit_master":
		return true
	}
	return false
}


// ── Avatar ────────────────────────────────────────────────────────────────────

func (h *Handler) uploadAvatar(w http.ResponseWriter, r *http.Request) {
	uid, ok := r.Context().Value(middleware.UserIDKey).(int)
	if !ok { writeError(w, 401, "unauthorized"); return }
	var in struct{ AvatarBase64 string `json:"avatar_base64"` }
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil || in.AvatarBase64 == "" {
		writeError(w, 400, "avatar_base64 is required"); return
	}
	if len(in.AvatarBase64) > 2*1024*1024 { // 2MB лимит
		writeError(w, 400, "avatar too large (max 2MB)"); return
	}
	if err := h.svc.SaveAvatar(r.Context(), uid, in.AvatarBase64); err != nil {
		writeError(w, 500, "save avatar failed"); return
	}
	writeJSON(w, 200, map[string]any{"status": "ok"})
}

func (h *Handler) getAvatar(w http.ResponseWriter, r *http.Request) {
	uid, ok := r.Context().Value(middleware.UserIDKey).(int)
	if !ok { writeError(w, 401, "unauthorized"); return }
	avatar, err := h.svc.GetAvatar(r.Context(), uid)
	if err != nil { writeError(w, 500, "get avatar failed"); return }
	writeJSON(w, 200, map[string]any{"avatar_base64": avatar})
}

// ── HQ Position availability check ───────────────────────────────────────────

func (h *Handler) hqStaffCheckPosition(w http.ResponseWriter, r *http.Request) {
	hqID, err1 := strconv.Atoi(r.URL.Query().Get("hq_id"))
	posID, err2 := strconv.Atoi(r.URL.Query().Get("position_id"))
	if err1 != nil || err2 != nil || hqID == 0 || posID == 0 {
		writeError(w, 400, "hq_id and position_id are required"); return
	}
	available, err := h.svc.IsHQPositionAvailable(r.Context(), hqID, posID)
	if err != nil { writeError(w, 500, "check failed"); return }
	writeJSON(w, 200, map[string]any{"available": available})
}

func writeJSON(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(data)
}

func writeError(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]any{
		"error": http.StatusText(status), "message": msg,
	})
}