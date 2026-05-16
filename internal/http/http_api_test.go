// Файл: internal/http/http_api_test.go
package httpapi_test

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func apiWriteJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

type testSrv struct {
	users    map[string]string // email -> password
	revoked  map[string]bool
}

func newTestSrv() *testSrv {
	return &testSrv{users: make(map[string]string), revoked: make(map[string]bool)}
}

func (s *testSrv) mkHandler() http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		apiWriteJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	mux.HandleFunc("/api/v1/auth/register", func(w http.ResponseWriter, r *http.Request) {
		var b map[string]any
		_ = json.NewDecoder(r.Body).Decode(&b)
		email, _ := b["email"].(string)
		password, _ := b["password"].(string)
		lastName, _ := b["last_name"].(string)
		firstName, _ := b["first_name"].(string)
		if email == "" || password == "" || lastName == "" || firstName == "" {
			apiWriteJSON(w, http.StatusBadRequest, map[string]string{"error": "missing fields"}); return
		}
		if len(password) < 8 {
			apiWriteJSON(w, http.StatusBadRequest, map[string]string{"error": "password too short"}); return
		}
		email = strings.ToLower(email)
		if _, exists := s.users[email]; exists {
			apiWriteJSON(w, http.StatusConflict, map[string]string{"error": "email exists"}); return
		}
		s.users[email] = password
		apiWriteJSON(w, http.StatusCreated, map[string]any{
			"user_id": 1, "access_token": "access." + email, "refresh_token": "refresh." + email,
		})
	})

	mux.HandleFunc("/api/v1/auth/login", func(w http.ResponseWriter, r *http.Request) {
		var b map[string]any
		_ = json.NewDecoder(r.Body).Decode(&b)
		email := strings.ToLower(b["email"].(string))
		pass, _ := b["password"].(string)
		stored, ok := s.users[email]
		if !ok || stored != pass {
			apiWriteJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid credentials"}); return
		}
		apiWriteJSON(w, http.StatusOK, map[string]any{
			"access_token": "access." + email, "refresh_token": "refresh." + email,
		})
	})

	mux.HandleFunc("/api/v1/auth/refresh", func(w http.ResponseWriter, r *http.Request) {
		var b map[string]any
		_ = json.NewDecoder(r.Body).Decode(&b)
		tok, _ := b["refresh_token"].(string)
		if !strings.HasPrefix(tok, "refresh.") || s.revoked[tok] {
			apiWriteJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid"}); return
		}
		email := strings.TrimPrefix(tok, "refresh.")
		apiWriteJSON(w, http.StatusOK, map[string]any{
			"access_token": "access." + email, "refresh_token": "refresh.new." + email,
		})
	})

	mux.HandleFunc("/api/v1/auth/logout", func(w http.ResponseWriter, r *http.Request) {
		var b map[string]any
		_ = json.NewDecoder(r.Body).Decode(&b)
		if rt, ok := b["refresh_token"].(string); ok { s.revoked[rt] = true }
		if auth := r.Header.Get("Authorization"); strings.HasPrefix(auth, "Bearer ") {
			s.revoked[strings.TrimPrefix(auth, "Bearer ")] = true
		}
		apiWriteJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	mux.HandleFunc("/api/v1/auth/verify-email", func(w http.ResponseWriter, r *http.Request) {
		var b map[string]any
		_ = json.NewDecoder(r.Body).Decode(&b)
		code, _ := b["code"].(string)
		if code == "123456" {
			apiWriteJSON(w, http.StatusOK, map[string]string{"status": "verified"}); return
		}
		apiWriteJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid code"})
	})

	mux.HandleFunc("/api/v1/auth/forgot-password", func(w http.ResponseWriter, _ *http.Request) {
		apiWriteJSON(w, http.StatusOK, map[string]string{"status": "sent"})
	})

	mux.HandleFunc("/api/v1/auth/reset-password", func(w http.ResponseWriter, r *http.Request) {
		var b map[string]any
		_ = json.NewDecoder(r.Body).Decode(&b)
		code, _ := b["code"].(string)
		newPw, _ := b["new_password"].(string)
		if code != "654321" {
			apiWriteJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid code"}); return
		}
		if len(newPw) < 8 {
			apiWriteJSON(w, http.StatusBadRequest, map[string]string{"error": "too short"}); return
		}
		apiWriteJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	authorized := func(w http.ResponseWriter, r *http.Request) (string, bool) {
		h := r.Header.Get("Authorization")
		if !strings.HasPrefix(h, "Bearer ") {
			apiWriteJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"}); return "", false
		}
		tok := strings.TrimPrefix(h, "Bearer ")
		if s.revoked[tok] || !strings.HasPrefix(tok, "access.") {
			apiWriteJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid token"}); return "", false
		}
		return strings.TrimPrefix(tok, "access."), true
	}

	mux.HandleFunc("/api/v1/me", func(w http.ResponseWriter, r *http.Request) {
		email, ok := authorized(w, r); if !ok { return }
		if r.Method == http.MethodPatch {
			apiWriteJSON(w, http.StatusOK, map[string]string{"status": "updated"}); return
		}
		apiWriteJSON(w, http.StatusOK, map[string]any{
			"id": 1, "email": email, "role_code": "participant",
			"last_name": "Тест", "first_name": "Пользователь", "account_status": "active",
		})
	})

	mux.HandleFunc("/api/v1/me/avatar", func(w http.ResponseWriter, r *http.Request) {
		if _, ok := authorized(w, r); !ok { return }
		switch r.Method {
		case http.MethodPost:
			apiWriteJSON(w, http.StatusOK, map[string]string{"status": "ok"})
		case http.MethodGet:
			apiWriteJSON(w, http.StatusOK, map[string]string{"avatar_base64": ""})
		case http.MethodDelete:
			apiWriteJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
		default:
			w.WriteHeader(http.StatusMethodNotAllowed)
		}
	})

	mux.HandleFunc("/api/v1/me/password", func(w http.ResponseWriter, r *http.Request) {
		if _, ok := authorized(w, r); !ok { return }
		var b map[string]any
		_ = json.NewDecoder(r.Body).Decode(&b)
		newPw, _ := b["new_password"].(string)
		if len(newPw) < 8 {
			apiWriteJSON(w, http.StatusBadRequest, map[string]string{"error": "too short"}); return
		}
		apiWriteJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	mux.HandleFunc("/api/v1/me/registrations", func(w http.ResponseWriter, r *http.Request) {
		if _, ok := authorized(w, r); !ok { return }
		apiWriteJSON(w, http.StatusOK, []any{})
	})

	mux.HandleFunc("/api/v1/me/fcm-token", func(w http.ResponseWriter, r *http.Request) {
		if _, ok := authorized(w, r); !ok { return }
		apiWriteJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	mux.HandleFunc("/api/v1/me/hq_units", func(w http.ResponseWriter, r *http.Request) {
		if _, ok := authorized(w, r); !ok { return }
		apiWriteJSON(w, http.StatusOK, []any{})
	})

	mux.HandleFunc("/api/v1/me/position/change", func(w http.ResponseWriter, r *http.Request) {
		if _, ok := authorized(w, r); !ok { return }
		apiWriteJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	mux.HandleFunc("/api/v1/me/hq-staff/request", func(w http.ResponseWriter, r *http.Request) {
		if _, ok := authorized(w, r); !ok { return }
		apiWriteJSON(w, http.StatusOK, map[string]any{"request_id": 1})
	})

	mux.HandleFunc("/api/v1/events", func(w http.ResponseWriter, r *http.Request) {
		if _, ok := authorized(w, r); !ok { return }
		if r.Method == http.MethodPost {
			apiWriteJSON(w, http.StatusCreated, map[string]any{"event_id": 1}); return
		}
		apiWriteJSON(w, http.StatusOK, []any{})
	})

	mux.HandleFunc("/api/v1/hqs", func(w http.ResponseWriter, _ *http.Request) {
		apiWriteJSON(w, http.StatusOK, []any{})
	})

	mux.HandleFunc("/api/v1/positions", func(w http.ResponseWriter, _ *http.Request) {
		apiWriteJSON(w, http.StatusOK, []any{})
	})

	mux.HandleFunc("/api/v1/hq_positions", func(w http.ResponseWriter, _ *http.Request) {
		apiWriteJSON(w, http.StatusOK, []any{})
	})

	mux.HandleFunc("/api/v1/portfolio", func(w http.ResponseWriter, r *http.Request) {
		if _, ok := authorized(w, r); !ok { return }
		apiWriteJSON(w, http.StatusOK, map[string]any{"events_count": 0})
	})

	mux.HandleFunc("/api/v1/notifications", func(w http.ResponseWriter, r *http.Request) {
		if _, ok := authorized(w, r); !ok { return }
		apiWriteJSON(w, http.StatusOK, []any{})
	})

	mux.HandleFunc("/api/v1/notifications/read-all", func(w http.ResponseWriter, r *http.Request) {
		if _, ok := authorized(w, r); !ok { return }
		apiWriteJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	mux.HandleFunc("/api/v1/notifications/unread-count", func(w http.ResponseWriter, r *http.Request) {
		if _, ok := authorized(w, r); !ok { return }
		apiWriteJSON(w, http.StatusOK, map[string]int{"count": 0})
	})

	mux.HandleFunc("/api/v1/attendance/scan", func(w http.ResponseWriter, r *http.Request) {
		if _, ok := authorized(w, r); !ok { return }
		var b map[string]any
		_ = json.NewDecoder(r.Body).Decode(&b)
		qr, _ := b["qr_code"].(string)
		if qr == "" {
			apiWriteJSON(w, http.StatusBadRequest, map[string]string{"error": "qr required"}); return
		}
		apiWriteJSON(w, http.StatusOK, map[string]string{"status": "attended"})
	})

	return mux
}

// Хелперы
func (s *testSrv) reg(srv *httptest.Server, email, pass string) {
	apiPost(srv, "/api/v1/auth/register", map[string]any{
		"email": email, "password": pass,
		"last_name": "Т", "first_name": "П",
	}, "")
}
func (s *testSrv) login(srv *httptest.Server, email, pass string) (string, string) {
	r := apiPost(srv, "/api/v1/auth/login", map[string]any{"email": email, "password": pass}, "")
	defer r.Body.Close()
	var b map[string]any
	_ = json.NewDecoder(r.Body).Decode(&b)
	a, _ := b["access_token"].(string)
	rf, _ := b["refresh_token"].(string)
	return a, rf
}

func apiPost(srv *httptest.Server, path string, body any, token string) *http.Response {
	b, _ := json.Marshal(body)
	req, _ := http.NewRequest(http.MethodPost, srv.URL+path, bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")
	if token != "" { req.Header.Set("Authorization", "Bearer "+token) }
	r, _ := http.DefaultClient.Do(req)
	return r
}
func apiGet(srv *httptest.Server, path, token string) *http.Response {
	req, _ := http.NewRequest(http.MethodGet, srv.URL+path, nil)
	if token != "" { req.Header.Set("Authorization", "Bearer "+token) }
	r, _ := http.DefaultClient.Do(req)
	return r
}
func apiPatch(srv *httptest.Server, path string, body any, token string) *http.Response {
	b, _ := json.Marshal(body)
	req, _ := http.NewRequest(http.MethodPatch, srv.URL+path, bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")
	if token != "" { req.Header.Set("Authorization", "Bearer "+token) }
	r, _ := http.DefaultClient.Do(req)
	return r
}
func apiDelete(srv *httptest.Server, path, token string) *http.Response {
	req, _ := http.NewRequest(http.MethodDelete, srv.URL+path, nil)
	if token != "" { req.Header.Set("Authorization", "Bearer "+token) }
	r, _ := http.DefaultClient.Do(req)
	return r
}
func readAPIBody(r *http.Response) map[string]any {
	defer r.Body.Close()
	b, _ := io.ReadAll(r.Body)
	var m map[string]any; _ = json.Unmarshal(b, &m); return m
}
func newSrv() (*httptest.Server, *testSrv) {
	s := newTestSrv(); return httptest.NewServer(s.mkHandler()), s
}

// ════════════════════════════════════════════════════════════════════════════
// Тесты
// ════════════════════════════════════════════════════════════════════════════

func TestAPIRegister_201(t *testing.T) {
	srv, s := newSrv(); defer srv.Close()
	r := apiPost(srv, "/api/v1/auth/register", map[string]any{
		"email": "n@rso.ru", "password": "Password123!", "last_name": "Н", "first_name": "П",
	}, "")
	if r.StatusCode != http.StatusCreated { t.Errorf("want 201, got %d", r.StatusCode) }
	body := readAPIBody(r)
	if body["access_token"] == nil { t.Error("expected access_token") }
	_ = s
}

func TestAPIRegister_ShortPassword_400(t *testing.T) {
	srv, _ := newSrv(); defer srv.Close()
	r := apiPost(srv, "/api/v1/auth/register", map[string]any{
		"email": "x@rso.ru", "password": "short", "last_name": "X", "first_name": "X",
	}, "")
	if r.StatusCode != http.StatusBadRequest { t.Errorf("want 400, got %d", r.StatusCode) }
	r.Body.Close()
}

func TestAPIRegister_MissingFields_400(t *testing.T) {
	srv, _ := newSrv(); defer srv.Close()
	r := apiPost(srv, "/api/v1/auth/register", map[string]any{
		"email": "x@rso.ru", "password": "Password123!",
	}, "")
	if r.StatusCode != http.StatusBadRequest { t.Errorf("want 400, got %d", r.StatusCode) }
	r.Body.Close()
}

func TestAPIRegister_Duplicate_409(t *testing.T) {
	srv, s := newSrv(); defer srv.Close()
	s.reg(srv, "dup@rso.ru", "Password123!")
	r := apiPost(srv, "/api/v1/auth/register", map[string]any{
		"email": "dup@rso.ru", "password": "Password123!", "last_name": "A", "first_name": "B",
	}, "")
	if r.StatusCode != http.StatusConflict { t.Errorf("want 409, got %d", r.StatusCode) }
	r.Body.Close()
}

func TestAPIRegister_CaseInsensitive_409(t *testing.T) {
	srv, s := newSrv(); defer srv.Close()
	s.reg(srv, "ci@rso.ru", "Password123!")
	r := apiPost(srv, "/api/v1/auth/register", map[string]any{
		"email": "CI@RSO.RU", "password": "Password123!", "last_name": "A", "first_name": "B",
	}, "")
	if r.StatusCode != http.StatusConflict { t.Errorf("want 409, got %d", r.StatusCode) }
	r.Body.Close()
}

func TestAPIRegister_ContentType_JSON(t *testing.T) {
	srv, _ := newSrv(); defer srv.Close()
	r := apiPost(srv, "/api/v1/auth/register", map[string]any{
		"email": "ct@rso.ru", "password": "Password123!", "last_name": "Т", "first_name": "Т",
	}, "")
	ct := r.Header.Get("Content-Type")
	r.Body.Close()
	if !strings.Contains(ct, "json") { t.Errorf("want JSON Content-Type, got %s", ct) }
}

func TestAPILogin_200(t *testing.T) {
	srv, s := newSrv(); defer srv.Close()
	s.reg(srv, "u@rso.ru", "Password123!")
	r := apiPost(srv, "/api/v1/auth/login", map[string]any{"email": "u@rso.ru", "password": "Password123!"}, "")
	if r.StatusCode != http.StatusOK { t.Errorf("want 200, got %d", r.StatusCode) }
	body := readAPIBody(r)
	if body["access_token"] == nil || body["refresh_token"] == nil { t.Error("expected tokens") }
}

func TestAPILogin_WrongPassword_401(t *testing.T) {
	srv, s := newSrv(); defer srv.Close()
	s.reg(srv, "u@rso.ru", "Password123!")
	r := apiPost(srv, "/api/v1/auth/login", map[string]any{"email": "u@rso.ru", "password": "Wrong!"}, "")
	if r.StatusCode != http.StatusUnauthorized { t.Errorf("want 401, got %d", r.StatusCode) }
	r.Body.Close()
}

func TestAPILogin_UnknownEmail_401(t *testing.T) {
	srv, _ := newSrv(); defer srv.Close()
	r := apiPost(srv, "/api/v1/auth/login", map[string]any{"email": "n@rso.ru", "password": "Pass1!"}, "")
	if r.StatusCode != http.StatusUnauthorized { t.Errorf("want 401, got %d", r.StatusCode) }
	r.Body.Close()
}

func TestAPILogin_CaseInsensitive_200(t *testing.T) {
	srv, s := newSrv(); defer srv.Close()
	s.reg(srv, "case@rso.ru", "Password123!")
	r := apiPost(srv, "/api/v1/auth/login", map[string]any{"email": "CASE@RSO.RU", "password": "Password123!"}, "")
	if r.StatusCode != http.StatusOK { t.Errorf("want 200, got %d", r.StatusCode) }
	r.Body.Close()
}

func TestAPILogin_ContentType_JSON(t *testing.T) {
	srv, s := newSrv(); defer srv.Close()
	s.reg(srv, "ct@rso.ru", "Password123!")
	r := apiPost(srv, "/api/v1/auth/login", map[string]any{"email": "ct@rso.ru", "password": "Password123!"}, "")
	ct := r.Header.Get("Content-Type")
	r.Body.Close()
	if !strings.Contains(ct, "json") { t.Errorf("want JSON Content-Type, got %s", ct) }
}

func TestAPIRefresh_Valid_200(t *testing.T) {
	srv, s := newSrv(); defer srv.Close()
	s.reg(srv, "r@rso.ru", "Password123!")
	_, ref := s.login(srv, "r@rso.ru", "Password123!")
	r := apiPost(srv, "/api/v1/auth/refresh", map[string]any{"refresh_token": ref}, "")
	if r.StatusCode != http.StatusOK { t.Errorf("want 200, got %d", r.StatusCode) }
	r.Body.Close()
}

func TestAPIRefresh_Invalid_401(t *testing.T) {
	srv, _ := newSrv(); defer srv.Close()
	r := apiPost(srv, "/api/v1/auth/refresh", map[string]any{"refresh_token": "garbage"}, "")
	if r.StatusCode != http.StatusUnauthorized { t.Errorf("want 401, got %d", r.StatusCode) }
	r.Body.Close()
}

func TestAPIRefresh_Revoked_401(t *testing.T) {
	srv, s := newSrv(); defer srv.Close()
	s.reg(srv, "rv@rso.ru", "Password123!")
	acc, ref := s.login(srv, "rv@rso.ru", "Password123!")
	apiPost(srv, "/api/v1/auth/logout", map[string]any{"refresh_token": ref}, acc).Body.Close()
	r := apiPost(srv, "/api/v1/auth/refresh", map[string]any{"refresh_token": ref}, "")
	if r.StatusCode != http.StatusUnauthorized { t.Errorf("want 401, got %d", r.StatusCode) }
	r.Body.Close()
}

func TestAPILogout_200(t *testing.T) {
	srv, s := newSrv(); defer srv.Close()
	s.reg(srv, "lo@rso.ru", "Password123!")
	acc, ref := s.login(srv, "lo@rso.ru", "Password123!")
	r := apiPost(srv, "/api/v1/auth/logout", map[string]any{"refresh_token": ref}, acc)
	if r.StatusCode != http.StatusOK { t.Errorf("want 200, got %d", r.StatusCode) }
	r.Body.Close()
}

func TestAPILogout_Me_401(t *testing.T) {
	srv, s := newSrv(); defer srv.Close()
	s.reg(srv, "lo2@rso.ru", "Password123!")
	acc, ref := s.login(srv, "lo2@rso.ru", "Password123!")
	apiPost(srv, "/api/v1/auth/logout", map[string]any{"refresh_token": ref}, acc).Body.Close()
	r := apiGet(srv, "/api/v1/me", acc)
	if r.StatusCode != http.StatusUnauthorized { t.Errorf("after logout want 401, got %d", r.StatusCode) }
	r.Body.Close()
}

func TestAPIVerifyEmail_Correct_200(t *testing.T) {
	srv, s := newSrv(); defer srv.Close()
	s.reg(srv, "v@rso.ru", "Password123!")
	acc, _ := s.login(srv, "v@rso.ru", "Password123!")
	r := apiPost(srv, "/api/v1/auth/verify-email", map[string]any{"code": "123456"}, acc)
	if r.StatusCode != http.StatusOK { t.Errorf("want 200, got %d", r.StatusCode) }
	r.Body.Close()
}

func TestAPIVerifyEmail_Wrong_400(t *testing.T) {
	srv, s := newSrv(); defer srv.Close()
	s.reg(srv, "v2@rso.ru", "Password123!")
	acc, _ := s.login(srv, "v2@rso.ru", "Password123!")
	r := apiPost(srv, "/api/v1/auth/verify-email", map[string]any{"code": "000000"}, acc)
	if r.StatusCode != http.StatusBadRequest { t.Errorf("want 400, got %d", r.StatusCode) }
	r.Body.Close()
}

func TestAPIForgotPassword_200(t *testing.T) {
	srv, _ := newSrv(); defer srv.Close()
	r := apiPost(srv, "/api/v1/auth/forgot-password", map[string]any{"email": "any@rso.ru"}, "")
	if r.StatusCode != http.StatusOK { t.Errorf("want 200, got %d", r.StatusCode) }
	r.Body.Close()
}

func TestAPIResetPassword_Valid_200(t *testing.T) {
	srv, _ := newSrv(); defer srv.Close()
	r := apiPost(srv, "/api/v1/auth/reset-password", map[string]any{
		"email": "rp@rso.ru", "code": "654321", "new_password": "NewPassword1!",
	}, "")
	if r.StatusCode != http.StatusOK { t.Errorf("want 200, got %d", r.StatusCode) }
	r.Body.Close()
}

func TestAPIResetPassword_WrongCode_400(t *testing.T) {
	srv, _ := newSrv(); defer srv.Close()
	r := apiPost(srv, "/api/v1/auth/reset-password", map[string]any{
		"email": "rp@rso.ru", "code": "000000", "new_password": "NewPassword1!",
	}, "")
	if r.StatusCode != http.StatusBadRequest { t.Errorf("want 400, got %d", r.StatusCode) }
	r.Body.Close()
}

func TestAPIResetPassword_ShortNew_400(t *testing.T) {
	srv, _ := newSrv(); defer srv.Close()
	r := apiPost(srv, "/api/v1/auth/reset-password", map[string]any{
		"email": "rp@rso.ru", "code": "654321", "new_password": "short",
	}, "")
	if r.StatusCode != http.StatusBadRequest { t.Errorf("want 400, got %d", r.StatusCode) }
	r.Body.Close()
}

func TestAPIMe_200(t *testing.T) {
	srv, s := newSrv(); defer srv.Close()
	s.reg(srv, "me@rso.ru", "Password123!")
	acc, _ := s.login(srv, "me@rso.ru", "Password123!")
	r := apiGet(srv, "/api/v1/me", acc)
	if r.StatusCode != http.StatusOK { t.Errorf("want 200, got %d", r.StatusCode) }
	body := readAPIBody(r)
	if body["email"] == nil { t.Error("expected email in /me") }
}

func TestAPIMe_NoToken_401(t *testing.T) {
	srv, _ := newSrv(); defer srv.Close()
	r := apiGet(srv, "/api/v1/me", "")
	if r.StatusCode != http.StatusUnauthorized { t.Errorf("want 401, got %d", r.StatusCode) }
	r.Body.Close()
}

func TestAPIMe_InvalidToken_401(t *testing.T) {
	srv, _ := newSrv(); defer srv.Close()
	r := apiGet(srv, "/api/v1/me", "garbage")
	if r.StatusCode != http.StatusUnauthorized { t.Errorf("want 401, got %d", r.StatusCode) }
	r.Body.Close()
}

func TestAPIMe_Update_200(t *testing.T) {
	srv, s := newSrv(); defer srv.Close()
	s.reg(srv, "up@rso.ru", "Password123!")
	acc, _ := s.login(srv, "up@rso.ru", "Password123!")
	r := apiPatch(srv, "/api/v1/me", map[string]any{"last_name": "Новый"}, acc)
	if r.StatusCode != http.StatusOK { t.Errorf("want 200, got %d", r.StatusCode) }
	r.Body.Close()
}

func TestAPIChangePassword_200(t *testing.T) {
	srv, s := newSrv(); defer srv.Close()
	s.reg(srv, "cp@rso.ru", "Password123!")
	acc, _ := s.login(srv, "cp@rso.ru", "Password123!")
	r := apiPost(srv, "/api/v1/me/password", map[string]any{
		"old_password": "Password123!", "new_password": "NewPassword456!",
	}, acc)
	if r.StatusCode != http.StatusOK { t.Errorf("want 200, got %d", r.StatusCode) }
	r.Body.Close()
}

func TestAPIChangePassword_ShortNew_400(t *testing.T) {
	srv, s := newSrv(); defer srv.Close()
	s.reg(srv, "cp2@rso.ru", "Password123!")
	acc, _ := s.login(srv, "cp2@rso.ru", "Password123!")
	r := apiPost(srv, "/api/v1/me/password", map[string]any{
		"old_password": "Password123!", "new_password": "short",
	}, acc)
	if r.StatusCode != http.StatusBadRequest { t.Errorf("want 400, got %d", r.StatusCode) }
	r.Body.Close()
}

func TestAPIAvatar_Upload_200(t *testing.T) {
	srv, s := newSrv(); defer srv.Close()
	s.reg(srv, "av@rso.ru", "Password123!")
	acc, _ := s.login(srv, "av@rso.ru", "Password123!")
	r := apiPost(srv, "/api/v1/me/avatar", map[string]any{"avatar_base64": "abc"}, acc)
	if r.StatusCode != http.StatusOK { t.Errorf("want 200, got %d", r.StatusCode) }
	r.Body.Close()
}

func TestAPIAvatar_Get_200(t *testing.T) {
	srv, s := newSrv(); defer srv.Close()
	s.reg(srv, "av2@rso.ru", "Password123!")
	acc, _ := s.login(srv, "av2@rso.ru", "Password123!")
	r := apiGet(srv, "/api/v1/me/avatar", acc)
	if r.StatusCode != http.StatusOK { t.Errorf("want 200, got %d", r.StatusCode) }
	r.Body.Close()
}

func TestAPIAvatar_Delete_200(t *testing.T) {
	srv, s := newSrv(); defer srv.Close()
	s.reg(srv, "av3@rso.ru", "Password123!")
	acc, _ := s.login(srv, "av3@rso.ru", "Password123!")
	r := apiDelete(srv, "/api/v1/me/avatar", acc)
	if r.StatusCode != http.StatusOK { t.Errorf("want 200, got %d", r.StatusCode) }
	r.Body.Close()
}

func TestAPIAvatar_NoToken_401(t *testing.T) {
	srv, _ := newSrv(); defer srv.Close()
	r := apiGet(srv, "/api/v1/me/avatar", "")
	if r.StatusCode != http.StatusUnauthorized { t.Errorf("want 401, got %d", r.StatusCode) }
	r.Body.Close()
}

func TestAPIEvents_List_200(t *testing.T) {
	srv, s := newSrv(); defer srv.Close()
	s.reg(srv, "ev@rso.ru", "Password123!")
	acc, _ := s.login(srv, "ev@rso.ru", "Password123!")
	r := apiGet(srv, "/api/v1/events", acc)
	if r.StatusCode != http.StatusOK { t.Errorf("want 200, got %d", r.StatusCode) }
	r.Body.Close()
}

func TestAPIEvents_NoToken_401(t *testing.T) {
	srv, _ := newSrv(); defer srv.Close()
	r := apiGet(srv, "/api/v1/events", "")
	if r.StatusCode != http.StatusUnauthorized { t.Errorf("want 401, got %d", r.StatusCode) }
	r.Body.Close()
}

func TestAPIEvents_Create_201(t *testing.T) {
	srv, s := newSrv(); defer srv.Close()
	s.reg(srv, "ce@rso.ru", "Password123!")
	acc, _ := s.login(srv, "ce@rso.ru", "Password123!")
	r := apiPost(srv, "/api/v1/events", map[string]any{"title": "Дартс"}, acc)
	if r.StatusCode != http.StatusCreated { t.Errorf("want 201, got %d", r.StatusCode) }
	r.Body.Close()
}

func TestAPIScan_WithQR_200(t *testing.T) {
	srv, s := newSrv(); defer srv.Close()
	s.reg(srv, "sc@rso.ru", "Password123!")
	acc, _ := s.login(srv, "sc@rso.ru", "Password123!")
	r := apiPost(srv, "/api/v1/attendance/scan", map[string]any{"qr_code": "some-uuid"}, acc)
	if r.StatusCode != http.StatusOK { t.Errorf("want 200, got %d", r.StatusCode) }
	r.Body.Close()
}

func TestAPIScan_EmptyQR_400(t *testing.T) {
	srv, s := newSrv(); defer srv.Close()
	s.reg(srv, "sc2@rso.ru", "Password123!")
	acc, _ := s.login(srv, "sc2@rso.ru", "Password123!")
	r := apiPost(srv, "/api/v1/attendance/scan", map[string]any{"qr_code": ""}, acc)
	if r.StatusCode != http.StatusBadRequest { t.Errorf("want 400, got %d", r.StatusCode) }
	r.Body.Close()
}

func TestAPIScan_NoToken_401(t *testing.T) {
	srv, _ := newSrv(); defer srv.Close()
	r := apiPost(srv, "/api/v1/attendance/scan", map[string]any{"qr_code": "uuid"}, "")
	if r.StatusCode != http.StatusUnauthorized { t.Errorf("want 401, got %d", r.StatusCode) }
	r.Body.Close()
}

func TestAPINotifications_200(t *testing.T) {
	srv, s := newSrv(); defer srv.Close()
	s.reg(srv, "nt@rso.ru", "Password123!")
	acc, _ := s.login(srv, "nt@rso.ru", "Password123!")
	r := apiGet(srv, "/api/v1/notifications", acc)
	if r.StatusCode != http.StatusOK { t.Errorf("want 200, got %d", r.StatusCode) }
	r.Body.Close()
}

func TestAPINotifications_NoToken_401(t *testing.T) {
	srv, _ := newSrv(); defer srv.Close()
	r := apiGet(srv, "/api/v1/notifications", "")
	if r.StatusCode != http.StatusUnauthorized { t.Errorf("want 401, got %d", r.StatusCode) }
	r.Body.Close()
}

func TestAPIMarkAllRead_200(t *testing.T) {
	srv, s := newSrv(); defer srv.Close()
	s.reg(srv, "mr@rso.ru", "Password123!")
	acc, _ := s.login(srv, "mr@rso.ru", "Password123!")
	r := apiPost(srv, "/api/v1/notifications/read-all", nil, acc)
	if r.StatusCode != http.StatusOK { t.Errorf("want 200, got %d", r.StatusCode) }
	r.Body.Close()
}

func TestAPIUnreadCount_200(t *testing.T) {
	srv, s := newSrv(); defer srv.Close()
	s.reg(srv, "uc@rso.ru", "Password123!")
	acc, _ := s.login(srv, "uc@rso.ru", "Password123!")
	r := apiGet(srv, "/api/v1/notifications/unread-count", acc)
	if r.StatusCode != http.StatusOK { t.Errorf("want 200, got %d", r.StatusCode) }
	r.Body.Close()
}

func TestAPIFCMToken_200(t *testing.T) {
	srv, s := newSrv(); defer srv.Close()
	s.reg(srv, "fcm@rso.ru", "Password123!")
	acc, _ := s.login(srv, "fcm@rso.ru", "Password123!")
	r := apiPost(srv, "/api/v1/me/fcm-token", map[string]any{"token": "fcm-tok"}, acc)
	if r.StatusCode != http.StatusOK { t.Errorf("want 200, got %d", r.StatusCode) }
	r.Body.Close()
}

func TestAPIHQs_200(t *testing.T) {
	srv, _ := newSrv(); defer srv.Close()
	r := apiGet(srv, "/api/v1/hqs", "")
	if r.StatusCode != http.StatusOK { t.Errorf("want 200, got %d", r.StatusCode) }
	r.Body.Close()
}

func TestAPIPositions_200(t *testing.T) {
	srv, _ := newSrv(); defer srv.Close()
	r := apiGet(srv, "/api/v1/positions", "")
	if r.StatusCode != http.StatusOK { t.Errorf("want 200, got %d", r.StatusCode) }
	r.Body.Close()
}

func TestAPIHQPositions_200(t *testing.T) {
	srv, _ := newSrv(); defer srv.Close()
	r := apiGet(srv, "/api/v1/hq_positions", "")
	if r.StatusCode != http.StatusOK { t.Errorf("want 200, got %d", r.StatusCode) }
	r.Body.Close()
}

func TestAPIRegistrations_200(t *testing.T) {
	srv, s := newSrv(); defer srv.Close()
	s.reg(srv, "rg@rso.ru", "Password123!")
	acc, _ := s.login(srv, "rg@rso.ru", "Password123!")
	r := apiGet(srv, "/api/v1/me/registrations", acc)
	if r.StatusCode != http.StatusOK { t.Errorf("want 200, got %d", r.StatusCode) }
	r.Body.Close()
}

func TestAPIPortfolio_200(t *testing.T) {
	srv, s := newSrv(); defer srv.Close()
	s.reg(srv, "pf@rso.ru", "Password123!")
	acc, _ := s.login(srv, "pf@rso.ru", "Password123!")
	r := apiGet(srv, "/api/v1/portfolio", acc)
	if r.StatusCode != http.StatusOK { t.Errorf("want 200, got %d", r.StatusCode) }
	r.Body.Close()
}

func TestAPIHealthz_200(t *testing.T) {
	srv, _ := newSrv(); defer srv.Close()
	r := apiGet(srv, "/healthz", "")
	if r.StatusCode != http.StatusOK { t.Errorf("want 200, got %d", r.StatusCode) }
	body := readAPIBody(r)
	if body["status"] != "ok" { t.Errorf("want status=ok, got %v", body["status"]) }
}

func TestAPIHQUnits_200(t *testing.T) {
	srv, s := newSrv(); defer srv.Close()
	s.reg(srv, "hq@rso.ru", "Password123!")
	acc, _ := s.login(srv, "hq@rso.ru", "Password123!")
	r := apiGet(srv, "/api/v1/me/hq_units", acc)
	if r.StatusCode != http.StatusOK { t.Errorf("want 200, got %d", r.StatusCode) }
	r.Body.Close()
}

func TestAPIPositionChange_200(t *testing.T) {
	srv, s := newSrv(); defer srv.Close()
	s.reg(srv, "pc@rso.ru", "Password123!")
	acc, _ := s.login(srv, "pc@rso.ru", "Password123!")
	r := apiPost(srv, "/api/v1/me/position/change", map[string]any{"new_position_id": 1}, acc)
	if r.StatusCode != http.StatusOK { t.Errorf("want 200, got %d", r.StatusCode) }
	r.Body.Close()
}

func TestAPIHQStaffRequest_200(t *testing.T) {
	srv, s := newSrv(); defer srv.Close()
	s.reg(srv, "hqs@rso.ru", "Password123!")
	acc, _ := s.login(srv, "hqs@rso.ru", "Password123!")
	r := apiPost(srv, "/api/v1/me/hq-staff/request", map[string]any{"hq_id": 1, "hq_position_id": 1}, acc)
	if r.StatusCode != http.StatusOK { t.Errorf("want 200, got %d", r.StatusCode) }
	r.Body.Close()
}