package httpapi

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"

	"rso-events/internal/middleware"
	"rso-events/internal/models"
	"rso-events/internal/repo"
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
		r.Post("/auth/register", h.register)
		r.Post("/auth/login", h.login)
		r.Post("/auth/refresh", h.refresh)
		r.Get("/events", h.listEvents)

		// Справочники — публичные (нужны при регистрации без токена)
		r.Get("/hqs", h.listHQs)
		r.Get("/hqs/{hqID}/units", h.listUnits)
		r.Get("/positions", h.listPositions)

		// Защищённые
		r.Group(func(r chi.Router) {
			r.Use(middleware.AuthRequired(h.svc))
			r.Post("/auth/logout", h.logout)
			r.Get("/me", h.me)
			r.Get("/portfolio", h.portfolio)
			r.Post("/events/{eventID}/register", h.registerToEvent)
			r.Post("/attendance/scan", h.scanAttendance)
		})
	})
}

func (h *Handler) register(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Email          string `json:"email"`
		Password       string `json:"password"`
		LastName       string `json:"last_name"`
		FirstName      string `json:"first_name"`
		MiddleName     string `json:"middle_name"`
		UnitID         *int   `json:"unit_id"`
		UnitPositionID *int   `json:"unit_position_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeError(w, 400, "invalid json")
		return
	}
	if in.Email == "" || in.Password == "" || in.LastName == "" || in.FirstName == "" {
		writeError(w, 400, "email, password, last_name, first_name are required")
		return
	}
	id, acc, ref, err := h.svc.Register(r.Context(), models.User{
		Email: in.Email, LastName: in.LastName, FirstName: in.FirstName,
		MiddleName: in.MiddleName, UnitID: in.UnitID, UnitPositionID: in.UnitPositionID,
	}, in.Password)
	if err != nil {
		if err.Error() == "password must be at least 6 characters" {
			writeError(w, 400, err.Error())
			return
		}
		writeError(w, 409, "user already exists or invalid data")
		return
	}
	writeJSON(w, 201, map[string]any{"user_id": id, "access_token": acc, "refresh_token": ref})
}

func (h *Handler) login(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Email    string `json:"email"`
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeError(w, 400, "invalid json")
		return
	}
	acc, ref, err := h.svc.Login(r.Context(), in.Email, in.Password)
	if err != nil {
		writeError(w, 401, "Неверный email или пароль")
		return
	}
	writeJSON(w, 200, map[string]any{"access_token": acc, "refresh_token": ref})
}

func (h *Handler) refresh(w http.ResponseWriter, r *http.Request) {
	var in struct {
		RefreshToken string `json:"refresh_token"`
	}
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil || in.RefreshToken == "" {
		writeError(w, 400, "refresh_token is required")
		return
	}
	acc, ref, err := h.svc.Refresh(in.RefreshToken)
	if err != nil {
		writeError(w, 401, "invalid or expired refresh token")
		return
	}
	writeJSON(w, 200, map[string]any{"access_token": acc, "refresh_token": ref})
}

func (h *Handler) logout(w http.ResponseWriter, r *http.Request) {
	var in struct {
		RefreshToken string `json:"refresh_token"`
	}
	_ = json.NewDecoder(r.Body).Decode(&in)
	accTok, _ := r.Context().Value(middleware.TokenKey).(string)
	_ = h.svc.Logout(accTok, in.RefreshToken)
	writeJSON(w, 200, map[string]any{"status": "logged_out"})
}

func (h *Handler) me(w http.ResponseWriter, r *http.Request) {
	uid, ok := r.Context().Value(middleware.UserIDKey).(int)
	if !ok {
		writeError(w, 401, "unauthorized")
		return
	}
	u, err := h.svc.Me(r.Context(), uid)
	if err != nil {
		writeError(w, 404, "user not found")
		return
	}
	writeJSON(w, 200, u)
}

func (h *Handler) listHQs(w http.ResponseWriter, r *http.Request) {
	hqs, err := h.svc.ListHQs(r.Context())
	if err != nil {
		writeError(w, 500, "hqs query failed")
		return
	}
	writeJSON(w, 200, hqs)
}

func (h *Handler) listUnits(w http.ResponseWriter, r *http.Request) {
	hqID, err := strconv.Atoi(chi.URLParam(r, "hqID"))
	if err != nil {
		writeError(w, 400, "invalid hq id")
		return
	}
	units, err := h.svc.ListUnitsByHQ(r.Context(), hqID)
	if err != nil {
		writeError(w, 500, "units query failed")
		return
	}
	writeJSON(w, 200, units)
}

func (h *Handler) listPositions(w http.ResponseWriter, r *http.Request) {
	positions, err := h.svc.ListPositions(r.Context())
	if err != nil {
		writeError(w, 500, "positions query failed")
		return
	}
	writeJSON(w, 200, positions)
}

func (h *Handler) listEvents(w http.ResponseWriter, r *http.Request) {
	uid, _ := r.Context().Value(middleware.UserIDKey).(int)
	evs, err := h.svc.ListEvents(r.Context(), uid,
		r.URL.Query().Get("level"),
		r.URL.Query().Get("type"),
		r.URL.Query().Get("search"))
	if err != nil {
		writeError(w, 500, "events query failed")
		return
	}
	writeJSON(w, 200, evs)
}

func (h *Handler) registerToEvent(w http.ResponseWriter, r *http.Request) {
	uid, ok := r.Context().Value(middleware.UserIDKey).(int)
	if !ok {
		writeError(w, 401, "unauthorized")
		return
	}
	eid, err := strconv.Atoi(chi.URLParam(r, "eventID"))
	if err != nil {
		writeError(w, 400, "invalid event id")
		return
	}
	regID, qr, err := h.svc.RegisterToEvent(r.Context(), uid, eid)
	if err != nil {
		writeError(w, 409, "already registered or event unavailable")
		return
	}
	writeJSON(w, 201, map[string]any{"registration_id": regID, "qr_code": qr.String()})
}

func (h *Handler) scanAttendance(w http.ResponseWriter, r *http.Request) {
	uid, ok := r.Context().Value(middleware.UserIDKey).(int)
	if !ok {
		writeError(w, 401, "unauthorized")
		return
	}
	role, _ := r.Context().Value(middleware.RoleKey).(string)
	var in struct {
		QRCode string `json:"qr_code"`
	}
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil || in.QRCode == "" {
		writeError(w, 400, "invalid qr_code")
		return
	}
	regID, err := h.svc.ScanAttendance(r.Context(), role, uid, in.QRCode)
	if err != nil {
		switch {
		case errors.Is(err, service.ErrForbidden):
			writeError(w, 403, "insufficient role")
		case errors.Is(err, service.ErrInvalidQR):
			writeError(w, 400, "invalid qr code format")
		case errors.Is(err, repo.ErrAlreadyAttended):
			writeError(w, 409, "attendance already marked")
		case repo.IsNotFound(err):
			writeError(w, 404, "registration not found")
		default:
			writeError(w, 500, "scan failed")
		}
		return
	}
	writeJSON(w, 200, map[string]any{"status": "attendance_marked", "registration_id": regID})
}

func (h *Handler) portfolio(w http.ResponseWriter, r *http.Request) {
	uid, ok := r.Context().Value(middleware.UserIDKey).(int)
	if !ok {
		writeError(w, 401, "unauthorized")
		return
	}
	up, att, err := h.svc.Portfolio(r.Context(), uid)
	if err != nil {
		writeError(w, 500, "portfolio query failed")
		return
	}
	writeJSON(w, 200, map[string]any{
		"user_id": uid, "upcoming": up, "attended": att, "total_attended": att,
	})
}

func writeJSON(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(data)
}

func writeError(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]any{"error": http.StatusText(status), "message": msg})
}