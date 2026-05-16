package httpapi

import (
	"context"
	"encoding/json"
	"sort"
	"fmt"
	"time"
	"strings"
	"errors"
	"net/http"
	"strconv"
	
  "rso-events/internal/middleware"
	"rso-events/internal/models"
	"rso-events/internal/repo"
	"rso-events/internal/config"
	"rso-events/internal/service"

	"github.com/go-chi/chi/v5"
)

type Handler struct{
	svc *service.Service
	cfg config.Config
}

func New(svc *service.Service, cfg config.Config) *Handler {
	return &Handler{svc: svc, cfg: cfg}
}

func (h *Handler) Register(r chi.Router) {
	r.Get("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, 200, map[string]any{"status": "ok"})
	})

	r.Route("/api/v1", func(r chi.Router) {
		// Публичные
		r.Post("/auth/register",        h.register)
		r.Post("/auth/login",           h.login)
		r.Post("/auth/refresh",         h.refresh)
		r.Post("/auth/verify-email",    h.verifyEmail)
		r.Post("/auth/resend-code",     h.resendCode)
		r.Post("/auth/forgot-password", h.forgotPassword)
		r.Post("/auth/reset-password",  h.resetPassword)
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
			r.Post("/events",                             h.createEvent)
			r.Put("/events/{eventID}",                    h.updateEvent)
			r.Post("/events/{eventID}/cancel",            h.cancelEvent)
			r.Post("/events/{eventID}/banner",            h.uploadEventBanner)
			r.Get("/events/{eventID}/banner",             h.getEventBanner)
			r.Post("/events/{eventID}/register",          h.registerToEvent)
			r.Post("/events/{eventID}/quotas",            h.setEventQuota)
			r.Post("/attendance/scan",                    h.scanAttendance)
			r.Get("/admin/users",                         h.listUsers)
			r.Post("/admin/users/{userID}/block",         h.blockUser)
			r.Post("/admin/users/{userID}/unblock",       h.unblockUser)

			// HQ Staff
			r.Post("/hq_staff/request",         h.hqStaffRequest)
			r.Get("/hq_staff/pending",          h.hqStaffPending)
			r.Post("/hq_staff/{id}/review",     h.hqStaffReview)
			r.Get("/hq_staff/check_position",   h.hqStaffCheckPosition)
			r.Put("/me/password",               h.changePassword)
			r.Delete("/me",                     h.deleteAccount)
			r.Post("/me/email/change",          h.requestEmailChange)
			r.Post("/me/email/confirm",         h.confirmEmailChange)
			r.Post("/me/position/change",       h.requestPositionChange)
			r.Get("/admin/position-requests",   h.listPositionRequests)
			r.Post("/admin/position-requests/{id}/review", h.reviewPositionRequest)
			r.Post("/me/fcm-token",             h.saveFcmToken)
			r.Post("/me/avatar",                h.uploadAvatar)
			r.Get("/me/avatar",                 h.getAvatar)
			r.Delete("/me/avatar",              h.deleteAvatar)

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
				// FCM push всем админам
				h.svc.SendFcmToAdmins(bgCtx, "📋 Новая заявка на должность ШСО", b,
					map[string]string{"type": "hq_staff_request"})
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
	// Брутфорс: max 5 неудачных попыток за 15 минут
	ip := r.Header.Get("X-Real-IP")
	if ip == "" { ip = r.RemoteAddr }
	if limited, _ := h.svc.IsRateLimited(r.Context(), in.Email, ip); limited {
		writeError(w, 429, "Слишком много попыток. Подождите 15 минут.")
		return
	}
	acc, ref, err := h.svc.Login(r.Context(), in.Email, in.Password)
	if err != nil {
		h.svc.RecordLoginAttempt(r.Context(), in.Email, ip, false)
		writeError(w, 401, "Неверный email или пароль"); return
	}
	h.svc.RecordLoginAttempt(r.Context(), in.Email, ip, true)
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
	// Добавляем флаг is_registration_closed чтобы Flutter
	// скрывал кнопку регистрации до попытки
	loc, _ := time.LoadLocation("Asia/Novosibirsk")
	if loc == nil { loc = time.FixedZone("NSK", 7*3600) }
	type eventWithClosed struct {
		models.Event
		IsRegistrationClosed bool `json:"is_registration_closed"`
	}
	result := make([]eventWithClosed, len(evs))
	for i, e := range evs {
		closed := false
		var year, month, day int
		if _, err := fmt.Sscanf(e.EventDate, "%d-%d-%d", &year, &month, &day); err == nil {
			eventDate   := time.Date(year, time.Month(month), day, 0, 0, 0, 0, loc)
			deadlineDay := registrationDeadline(eventDate)
			deadline    := time.Date(deadlineDay.Year(), deadlineDay.Month(), deadlineDay.Day(), 0, 0, 0, 0, loc)
			closed = time.Now().In(loc).After(deadline)
		}
		result[i] = eventWithClosed{Event: e, IsRegistrationClosed: closed}
	}
	writeJSON(w, 200, result)
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
		// Inbox уведомление — сохраняется в БД
		_ = h.svc.NotifyAllParticipants(bgCtx, "new_event_created",
			"🎉 Новое мероприятие: "+title, b, map[string]any{"event_id": eid})
		// FCM push — доставка на заблокированный экран
		h.svc.SendFcmToAll(bgCtx, "🎉 Новое мероприятие: "+title, b,
			map[string]string{"type": "new_event_created", "event_id": fmt.Sprint(eid)})
	}(context.Background(), in.Title, in.EventDate, in.Location, id)

	// Запускаем отложенную отправку списка участников
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
	// Письмо отправляется ТОЛЬКО после закрытия регистрации (не сразу)
	go h.scheduleAndSendEmail(context.Background(), eid, target.EventDate)
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
		HQID         int    `json:"hq_id"`
		PositionID   int    `json:"hq_position_id"`
		HQName       string `json:"hq_name"`
		PositionName string `json:"position_name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil || in.HQID == 0 || in.PositionID == 0 {
		writeError(w, 400, "hq_id and hq_position_id are required"); return
	}
	reqID, err := h.svc.CreateHQStaffRequest(r.Context(), uid, in.HQID, in.PositionID)
	if err != nil { writeError(w, 500, "request failed"); return }

	u, _ := h.svc.Me(r.Context(), uid)
	applicant := u.LastName + " " + u.FirstName
	notifBody := fmt.Sprintf("👤 %s\n🏢 Штаб: %s\n💼 Должность: %s",
		applicant, in.HQName, in.PositionName)
	if u.Phone != "" { notifBody += "\n📞 " + u.Phone }
	if u.MemberCardNumber != "" { notifBody += "\n🪪 Билет № " + u.MemberCardNumber }
	notifTitle := fmt.Sprintf("📋 Заявка ШСО: %s в %s", in.PositionName, in.HQName)
	if notifTitle == "📋 Заявка ШСО:  в " { notifTitle = "📋 Новая заявка на должность ШСО" }
	go func(bgCtx context.Context, rID int, title, b string) {
		_ = h.svc.NotifyAdmins(bgCtx, "hq_staff_request", title, b,
			map[string]any{"request_id": rID})
		// FCM push всем админам
		h.svc.SendFcmToAdmins(bgCtx, title, b,
			map[string]string{"type": "hq_staff_request"})
	}(context.Background(), reqID, notifTitle, notifBody)

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
		if errors.Is(err, repo.ErrHQPositionTaken) {
			writeError(w, 409, "Эта должность уже занята в данном штабе")
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
		writeError(w, 400, "avatar_base64 required"); return
	}
	if len(in.AvatarBase64) > 2*1024*1024 {
		writeError(w, 400, "avatar too large"); return
	}
	if err := h.svc.SaveAvatar(r.Context(), uid, in.AvatarBase64); err != nil {
		writeError(w, 500, "save failed"); return
	}
	writeJSON(w, 200, map[string]any{"status": "ok"})
}

func (h *Handler) getAvatar(w http.ResponseWriter, r *http.Request) {
	uid, ok := r.Context().Value(middleware.UserIDKey).(int)
	if !ok { writeError(w, 401, "unauthorized"); return }
	avatar, err := h.svc.GetAvatar(r.Context(), uid)
	if err != nil { writeError(w, 500, "get failed"); return }
	writeJSON(w, 200, map[string]any{"avatar_base64": avatar})
}

func (h *Handler) deleteAvatar(w http.ResponseWriter, r *http.Request) {
	uid, ok := r.Context().Value(middleware.UserIDKey).(int)
	if !ok { writeError(w, 401, "unauthorized"); return }
	if err := h.svc.SaveAvatar(r.Context(), uid, ""); err != nil {
		writeError(w, 500, "delete avatar failed"); return
	}
	writeJSON(w, 200, map[string]any{"status": "deleted"})
}

// ── HQ Position check ─────────────────────────────────────────────────────────

func (h *Handler) hqStaffCheckPosition(w http.ResponseWriter, r *http.Request) {
	hqID, err1 := strconv.Atoi(r.URL.Query().Get("hq_id"))
	posID, err2 := strconv.Atoi(r.URL.Query().Get("position_id"))
	if err1 != nil || err2 != nil || hqID == 0 || posID == 0 {
		writeError(w, 400, "hq_id and position_id required"); return
	}
	avail, err := h.svc.IsHQPositionAvailable(r.Context(), hqID, posID)
	if err != nil { writeError(w, 500, "check failed"); return }
	writeJSON(w, 200, map[string]any{"available": avail})
}

// ── Email participants list ───────────────────────────────────────────────────

func (h *Handler) sendParticipantsEmail(ctx context.Context, eventID int) {
	if h.cfg.EmailTo == "" { return }
	rows, err := h.svc.GetEventParticipants(ctx, eventID)
	if err != nil || len(rows) == 0 { return }

	var participants []EventParticipant
	for i, r := range rows {
		participants = append(participants, EventParticipant{
			Num:          i + 1,
			EventTitle:   r.EventTitle,
			CardNumber:   r.CardNumber,
			LastName:     r.LastName,
			FirstName:    r.FirstName,
			MiddleName:   r.MiddleName,
			Institution:  r.HqName,
			UnitName:     r.UnitName,
			PositionName: r.PositionName,
			PositionCode: r.PositionCode,
			Phone:        r.Phone,
		})
	}

	// Сортировка: ВУЗ → Отряд → Должность → Фамилия
	sort.SliceStable(participants, func(i, j int) bool {
		pi, pj := participants[i], participants[j]
		// 1. По учебному заведению
		if pi.Institution != pj.Institution { return pi.Institution < pj.Institution }
		// 2. По отряду
		if pi.UnitName != pj.UnitName { return pi.UnitName < pj.UnitName }
		// 3. По должности
		iHQ := strings.Contains(pi.PositionName, "штаба") || strings.Contains(pi.PositionName, "ШСО")
		jHQ := strings.Contains(pj.PositionName, "штаба") || strings.Contains(pj.PositionName, "ШСО")
		oi := positionSortOrder(pi.PositionName, iHQ)
		oj := positionSortOrder(pj.PositionName, jHQ)
		if oi != oj { return oi < oj }
		// 4. По фамилии
		return pi.LastName < pj.LastName
	})

	// Перенумеровываем после сортировки
	for i := range participants { participants[i].Num = i + 1 }

	eventTitle := ""
	if len(participants) > 0 { eventTitle = participants[0].EventTitle }
	SendParticipantList(h.cfg, eventTitle, participants)
}


// ── Schedule email after registration deadline ────────────────────────────────


// RestoreSchedules — при старте сервера восстанавливает горутины для всех
// предстоящих мероприятий у которых дедлайн рассылки ещё не прошёл.
// Без этого горутины пропадают при перезапуске сервера.
func (h *Handler) RestoreSchedules(ctx context.Context) {
	if h.cfg.EmailTo == "" { return }
	events, err := h.svc.ListUpcomingEventDates(ctx)
	if err != nil {
		fmt.Printf("[scheduler] failed to load upcoming events: %v\n", err)
		return
	}
	count := 0
	for _, ev := range events {
		var year, month, day int
		if _, err := fmt.Sscanf(ev.EventDate, "%d-%d-%d", &year, &month, &day); err != nil { continue }
		nsk, _ := time.LoadLocation("Asia/Novosibirsk")
		if nsk == nil { nsk = time.FixedZone("NSK", 7*3600) }
		eventDate := time.Date(year, time.Month(month), day, 0, 0, 0, 0, nsk)
		deadlineDay := emailSubWorkdays(eventDate, 3)
		deadline := time.Date(deadlineDay.Year(), deadlineDay.Month(), deadlineDay.Day(),
			0, 0, 0, 0, nsk)
		eid  := ev.ID
		date := ev.EventDate
		now  := time.Now().In(nsk)
		eventNotPast := now.Before(eventDate.Add(24 * time.Hour))
		if !eventNotPast { continue }
		if now.Before(deadline) {
			go h.scheduleAndSendEmail(ctx, eid, date)
			count++
			fmt.Printf("[scheduler] restored schedule for event %d (%s), deadline %s\n",
				eid, date, deadline.Format("2006-01-02 15:04:05"))
		} else if !ev.EmailSent {
			go h.sendParticipantsEmail(ctx, eid)
			count++
			fmt.Printf("[scheduler] missed deadline for event %d (%s), sending now\n",
				eid, date)
		} else {
			fmt.Printf("[scheduler] email already sent for event %d, skipping\n", eid)
		}
	}
	fmt.Printf("[scheduler] restored %d schedules\n", count)
}

func (h *Handler) scheduleAndSendEmail(ctx context.Context, eventID int, eventDateStr string) {
	if h.cfg.EmailTo == "" { return }
	var year, month, day int
	if _, err := fmt.Sscanf(eventDateStr, "%d-%d-%d", &year, &month, &day); err != nil { return }
	nsk, _ := time.LoadLocation("Asia/Novosibirsk")
	if nsk == nil { nsk = time.FixedZone("NSK", 7*3600) }
	eventDate := time.Date(year, time.Month(month), day, 0, 0, 0, 0, nsk)
	lastDay := emailSubWorkdays(eventDate, 3)
	// Дедлайн совпадает с закрытием регистрации: 3 раб. дня до мероприятия, 00:00 НСК
	deadline := time.Date(lastDay.Year(), lastDay.Month(), lastDay.Day(), 0, 0, 0, 0, nsk)
	now := time.Now().In(nsk)
	if now.Before(deadline) {
		select {
		case <-time.After(deadline.Sub(now)):
		case <-ctx.Done():
			return
		}
	}
	h.sendParticipantsEmail(ctx, eventID)
	_ = h.svc.MarkEventEmailSent(ctx, eventID)
}

func emailSubWorkdays(t time.Time, n int) time.Time {
	r := t
	for s := 0; s < n; {
		r = r.AddDate(0, 0, -1)
		if r.Weekday() != time.Saturday && r.Weekday() != time.Sunday { s++ }
	}
	return r
}

// ── Change password ────────────────────────────────────────────────────────────

func (h *Handler) changePassword(w http.ResponseWriter, r *http.Request) {
	uid, ok := r.Context().Value(middleware.UserIDKey).(int)
	if !ok { writeError(w, 401, "unauthorized"); return }
	var in struct {
		OldPassword string `json:"old_password"`
		NewPassword string `json:"new_password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil ||
		in.OldPassword == "" || in.NewPassword == "" {
		writeError(w, 400, "old_password and new_password required"); return
	}
	if len(in.NewPassword) < 8 {
		writeError(w, 400, "Новый пароль: минимум 8 символов"); return
	}
	if err := h.svc.ChangePassword(r.Context(), uid, in.OldPassword, in.NewPassword); err != nil {
		if errors.Is(err, service.ErrForbidden) {
			writeError(w, 403, "Неверный текущий пароль")
		} else {
			writeError(w, 500, "change password failed")
		}
		return
	}
	writeJSON(w, 200, map[string]any{"status": "password changed"})
}

// ── Delete account ────────────────────────────────────────────────────────────

func (h *Handler) deleteAccount(w http.ResponseWriter, r *http.Request) {
	uid, ok := r.Context().Value(middleware.UserIDKey).(int)
	if !ok { writeError(w, 401, "unauthorized"); return }
	accTok, _ := r.Context().Value(middleware.TokenKey).(string)
	var in struct {
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil || in.Password == "" {
		writeError(w, 400, "password required"); return
	}
	if err := h.svc.DeleteAccount(r.Context(), uid, in.Password, accTok); err != nil {
		if errors.Is(err, service.ErrForbidden) {
			writeError(w, 403, "Неверный пароль")
		} else {
			writeError(w, 500, "delete failed")
		}
		return
	}
	writeJSON(w, 200, map[string]any{"status": "deleted"})
}


// ── Email change ──────────────────────────────────────────────────────────────

func (h *Handler) requestEmailChange(w http.ResponseWriter, r *http.Request) {
	uid, ok := r.Context().Value(middleware.UserIDKey).(int)
	if !ok { writeError(w, 401, "unauthorized"); return }
	var in struct { NewEmail string `json:"new_email"` }
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil || in.NewEmail == "" {
		writeError(w, 400, "new_email required"); return
	}
	if err := h.svc.SendEmailChangeCode(r.Context(), uid, in.NewEmail); err != nil {
		if strings.HasPrefix(err.Error(), "email_duplicate:") {
			writeError(w, 409, strings.TrimPrefix(err.Error(), "email_duplicate: "))
		} else {
			writeError(w, 500, "send failed")
		}
		return
	}
	writeJSON(w, 200, map[string]any{"status": "code sent"})
}

func (h *Handler) confirmEmailChange(w http.ResponseWriter, r *http.Request) {
	uid, ok := r.Context().Value(middleware.UserIDKey).(int)
	if !ok { writeError(w, 401, "unauthorized"); return }
	var in struct { Code string `json:"code"` }
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil || in.Code == "" {
		writeError(w, 400, "code required"); return
	}
	if err := h.svc.ConfirmEmailChange(r.Context(), uid, in.Code); err != nil {
		writeError(w, 400, err.Error()); return
	}
	writeJSON(w, 200, map[string]any{"status": "email changed"})
}

// ── Position change ───────────────────────────────────────────────────────────

func (h *Handler) requestPositionChange(w http.ResponseWriter, r *http.Request) {
	uid, ok := r.Context().Value(middleware.UserIDKey).(int)
	if !ok { writeError(w, 401, "unauthorized"); return }
	var in struct {
		PositionID   int    `json:"position_id"`
		PositionCode string `json:"position_code"`
		PositionName string `json:"position_name"`
		UnitName     string `json:"unit_name"`
		HQName       string `json:"hq_name"`
		UnitID       *int   `json:"unit_id,omitempty"`
	}
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil || in.PositionID == 0 {
		writeError(w, 400, "position_id required"); return
	}
	applied, err := h.svc.RequestPositionChange(r.Context(),
		uid, in.PositionID, in.UnitID, in.PositionCode, in.PositionName, in.UnitName, in.HQName)
	if err != nil { writeError(w, 500, "request failed"); return }
	if applied {
		writeJSON(w, 200, map[string]any{"status": "applied"})
	} else {
		writeJSON(w, 200, map[string]any{
			"status":  "pending_review",
			"message": fmt.Sprintf("Заявка на должность «%s» отправлена администратору", in.PositionName),
		})
	}
}

func (h *Handler) listPositionRequests(w http.ResponseWriter, r *http.Request) {
	role, _ := r.Context().Value(middleware.RoleKey).(string)
	if !isAdminRole(role) { writeError(w, 403, "Недостаточно прав"); return }
	reqs, err := h.svc.ListPendingPositionRequests(r.Context())
	if err != nil { writeError(w, 500, "fetch failed"); return }
	if reqs == nil { reqs = []map[string]any{} }
	writeJSON(w, 200, reqs)
}

func (h *Handler) reviewPositionRequest(w http.ResponseWriter, r *http.Request) {
	reviewerID, _ := r.Context().Value(middleware.UserIDKey).(int)
	role, _ := r.Context().Value(middleware.RoleKey).(string)
	if !isAdminRole(role) { writeError(w, 403, "Недостаточно прав"); return }
	reqID, err := strconv.Atoi(chi.URLParam(r, "id"))
	if err != nil { writeError(w, 400, "invalid id"); return }
	var in struct {
		Approved bool   `json:"approved"`
		Comment  string `json:"comment"`
	}
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeError(w, 400, "invalid body"); return
	}
	if err := h.svc.ReviewPositionRequest(r.Context(), reqID, reviewerID, in.Approved, in.Comment); err != nil {
		writeError(w, 500, "review failed"); return
	}
	writeJSON(w, 200, map[string]any{"status": "reviewed"})
}


// ── Редактирование мероприятия ────────────────────────────────────────────────

func (h *Handler) updateEvent(w http.ResponseWriter, r *http.Request) {
	role, _ := r.Context().Value(middleware.RoleKey).(string)
	if !isAdminRole(role) { writeError(w, 403, "Недостаточно прав"); return }
	eid, err := strconv.Atoi(chi.URLParam(r, "eventID"))
	if err != nil { writeError(w, 400, "invalid event id"); return }
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
	}
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeError(w, 400, "invalid json"); return
	}
	if in.Title == "" { writeError(w, 400, "title required"); return }
	err = h.svc.UpdateEvent(r.Context(), models.Event{
		ID: eid, Title: in.Title, Description: in.Description,
		Location: in.Location, EventDate: in.EventDate, StartTime: in.StartTime,
		LevelCode: in.LevelCode, TypeCode: in.TypeCode,
		ParticipationMode: in.ParticipationMode, MaxParticipants: in.MaxParticipants,
	})
	if err != nil { writeError(w, 500, "update failed"); return }
	writeJSON(w, 200, map[string]any{"status": "updated"})
}

func (h *Handler) cancelEvent(w http.ResponseWriter, r *http.Request) {
	role, _ := r.Context().Value(middleware.RoleKey).(string)
	if !isAdminRole(role) { writeError(w, 403, "Недостаточно прав"); return }
	eid, err := strconv.Atoi(chi.URLParam(r, "eventID"))
	if err != nil { writeError(w, 400, "invalid event id"); return }
	if err := h.svc.CancelEvent(r.Context(), eid); err != nil {
		writeError(w, 500, "cancel failed"); return
	}
	writeJSON(w, 200, map[string]any{"status": "cancelled"})
}

// ── Баннер мероприятия ────────────────────────────────────────────────────────

func (h *Handler) uploadEventBanner(w http.ResponseWriter, r *http.Request) {
	role, _ := r.Context().Value(middleware.RoleKey).(string)
	if !isAdminRole(role) { writeError(w, 403, "Недостаточно прав"); return }
	eid, err := strconv.Atoi(chi.URLParam(r, "eventID"))
	if err != nil { writeError(w, 400, "invalid event id"); return }
	var in struct { Image string `json:"image"` }
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil || in.Image == "" {
		writeError(w, 400, "image required"); return
	}
	if err := h.svc.SaveEventBanner(r.Context(), eid, in.Image); err != nil {
		writeError(w, 500, "save banner failed"); return
	}
	writeJSON(w, 200, map[string]any{"status": "saved"})
}

func (h *Handler) getEventBanner(w http.ResponseWriter, r *http.Request) {
	eid, err := strconv.Atoi(chi.URLParam(r, "eventID"))
	if err != nil { writeError(w, 400, "invalid event id"); return }
	b64, err := h.svc.GetEventBanner(r.Context(), eid)
	if err != nil { writeError(w, 500, "get banner failed"); return }
	writeJSON(w, 200, map[string]any{"image": b64})
}

// ── Управление пользователями (F-19) ─────────────────────────────────────────

func (h *Handler) listUsers(w http.ResponseWriter, r *http.Request) {
	role, _ := r.Context().Value(middleware.RoleKey).(string)
	if !isAdminRole(role) { writeError(w, 403, "Недостаточно прав"); return }
	search := r.URL.Query().Get("search")
	blockedOnly := r.URL.Query().Get("blocked") == "true"
	users, err := h.svc.ListUsers(r.Context(), search, blockedOnly)
	if err != nil { writeError(w, 500, "list users failed"); return }
	if users == nil { users = []models.User{} }
	writeJSON(w, 200, users)
}

func (h *Handler) blockUser(w http.ResponseWriter, r *http.Request) {
	role, _ := r.Context().Value(middleware.RoleKey).(string)
	if !isAdminRole(role) { writeError(w, 403, "Недостаточно прав"); return }
	userID, err := strconv.Atoi(chi.URLParam(r, "userID"))
	if err != nil { writeError(w, 400, "invalid user id"); return }
	var in struct { Reason string `json:"reason"` }
	_ = json.NewDecoder(r.Body).Decode(&in)
	if err := h.svc.BlockUser(r.Context(), userID, in.Reason); err != nil {
		writeError(w, 500, "block failed"); return
	}
	writeJSON(w, 200, map[string]any{"status": "blocked"})
}

func (h *Handler) unblockUser(w http.ResponseWriter, r *http.Request) {
	role, _ := r.Context().Value(middleware.RoleKey).(string)
	if !isAdminRole(role) { writeError(w, 403, "Недостаточно прав"); return }
	userID, err := strconv.Atoi(chi.URLParam(r, "userID"))
	if err != nil { writeError(w, 400, "invalid user id"); return }
	if err := h.svc.UnblockUser(r.Context(), userID); err != nil {
		writeError(w, 500, "unblock failed"); return
	}
	writeJSON(w, 200, map[string]any{"status": "unblocked"})
}


// ── Email verification & password reset ──────────────────────────────────────

func (h *Handler) verifyEmail(w http.ResponseWriter, r *http.Request) {
	var in struct {
		UserID int    `json:"user_id"`
		Code   string `json:"code"`
	}
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeError(w, 400, "invalid json"); return
	}
	if in.UserID == 0 || in.Code == "" {
		writeError(w, 400, "user_id and code required"); return
	}
	if err := h.svc.VerifyEmail(r.Context(), in.UserID, in.Code); err != nil {
		writeError(w, 400, err.Error()); return
	}
	writeJSON(w, 200, map[string]any{"status": "verified"})
}

func (h *Handler) resendCode(w http.ResponseWriter, r *http.Request) {
	var in struct {
		UserID int    `json:"user_id"`
		Email  string `json:"email"`
	}
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeError(w, 400, "invalid json"); return
	}
	if in.UserID == 0 || in.Email == "" {
		writeError(w, 400, "user_id and email required"); return
	}
	if err := h.svc.SendVerificationCode(r.Context(), in.UserID, in.Email); err != nil {
		writeError(w, 500, "send failed"); return
	}
	writeJSON(w, 200, map[string]any{"status": "sent"})
}

func (h *Handler) forgotPassword(w http.ResponseWriter, r *http.Request) {
	var in struct{ Email string `json:"email"` }
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil || in.Email == "" {
		writeError(w, 400, "email required"); return
	}
	_ = h.svc.SendPasswordResetCode(r.Context(), in.Email)
	writeJSON(w, 200, map[string]any{"status": "sent"})
}

func (h *Handler) resetPassword(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Email       string `json:"email"`
		Code        string `json:"code"`
		NewPassword string `json:"new_password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeError(w, 400, "invalid json"); return
	}
	if in.Email == "" || in.Code == "" || in.NewPassword == "" {
		writeError(w, 400, "email, code and new_password required"); return
	}
	if err := h.svc.ResetPassword(r.Context(), in.Email, in.Code, in.NewPassword); err != nil {
		writeError(w, 400, err.Error()); return
	}
	writeJSON(w, 200, map[string]any{"status": "password_reset"})
}


func (h *Handler) saveFcmToken(w http.ResponseWriter, r *http.Request) {
	uid, ok := r.Context().Value(middleware.UserIDKey).(int)
	if !ok { writeError(w, 401, "unauthorized"); return }
	var in struct{ Token string `json:"token"` }
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil || in.Token == "" {
		writeError(w, 400, "token required"); return
	}
	if err := h.svc.SaveFcmToken(r.Context(), uid, in.Token); err != nil {
		writeError(w, 500, "save token failed"); return
	}
	writeJSON(w, 200, map[string]any{"status": "ok"})
}

// registrationDeadline — день закрытия регистрации (3 рабочих дня до мероприятия)
func registrationDeadline(eventDate time.Time) time.Time {
	result := eventDate
	for subtracted := 0; subtracted < 3; {
		result = result.AddDate(0, 0, -1)
		if result.Weekday() != time.Saturday && result.Weekday() != time.Sunday {
			subtracted++
		}
	}
	return result
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