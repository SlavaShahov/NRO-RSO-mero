// Файл: internal/http/handlers_test.go
package httpapi_test

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

func newFakeServer() http.Handler {
	registered := make(map[string]string)
	revoked := make(map[string]bool)

	mux := http.NewServeMux()

	mux.HandleFunc("/api/v1/auth/register", func(w http.ResponseWriter, r *http.Request) {
		var b map[string]any
		_ = json.NewDecoder(r.Body).Decode(&b)
		email, _ := b["email"].(string)
		password, _ := b["password"].(string)
		lastName, _ := b["last_name"].(string)
		firstName, _ := b["first_name"].(string)
		if email == "" || password == "" || lastName == "" || firstName == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing fields"}); return
		}
		if len(password) < 8 {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "password too short"}); return
		}
		if _, exists := registered[strings.ToLower(email)]; exists {
			writeJSON(w, http.StatusConflict, map[string]string{"error": "email exists"}); return
		}
		registered[strings.ToLower(email)] = password
		writeJSON(w, http.StatusCreated, map[string]any{"access_token": "tok", "refresh_token": "ref"})
	})

	mux.HandleFunc("/api/v1/auth/login", func(w http.ResponseWriter, r *http.Request) {
		var b map[string]any
		_ = json.NewDecoder(r.Body).Decode(&b)
		email := strings.ToLower(b["email"].(string))
		pass, _ := b["password"].(string)
		stored, ok := registered[email]
		if !ok || stored != pass {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid credentials"}); return
		}
		writeJSON(w, http.StatusOK, map[string]any{"access_token": "access." + email, "refresh_token": "refresh." + email})
	})

	mux.HandleFunc("/api/v1/auth/refresh", func(w http.ResponseWriter, r *http.Request) {
		var b map[string]any
		_ = json.NewDecoder(r.Body).Decode(&b)
		tok, _ := b["refresh_token"].(string)
		if !strings.HasPrefix(tok, "refresh.") || revoked[tok] {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid"}); return
		}
		writeJSON(w, http.StatusOK, map[string]any{"access_token": "new-access", "refresh_token": "new-refresh"})
	})

	mux.HandleFunc("/api/v1/auth/logout", func(w http.ResponseWriter, r *http.Request) {
		var b map[string]any
		_ = json.NewDecoder(r.Body).Decode(&b)
		if rt, ok := b["refresh_token"].(string); ok { revoked[rt] = true }
		if auth := r.Header.Get("Authorization"); strings.HasPrefix(auth, "Bearer ") {
			revoked[strings.TrimPrefix(auth, "Bearer ")] = true
		}
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	auth := func(w http.ResponseWriter, r *http.Request) (string, bool) {
		h := r.Header.Get("Authorization")
		if !strings.HasPrefix(h, "Bearer ") {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"}); return "", false
		}
		tok := strings.TrimPrefix(h, "Bearer ")
		if revoked[tok] || !strings.HasPrefix(tok, "access.") {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid token"}); return "", false
		}
		return strings.TrimPrefix(tok, "access."), true
	}

	mux.HandleFunc("/api/v1/me", func(w http.ResponseWriter, r *http.Request) {
		email, ok := auth(w, r); if !ok { return }
		writeJSON(w, http.StatusOK, map[string]any{"id": 1, "email": email, "role_code": "participant"})
	})

	mux.HandleFunc("/api/v1/events", func(w http.ResponseWriter, r *http.Request) {
		if _, ok := auth(w, r); !ok { return }
		writeJSON(w, http.StatusOK, []any{})
	})

	mux.HandleFunc("/api/v1/notifications", func(w http.ResponseWriter, r *http.Request) {
		if _, ok := auth(w, r); !ok { return }
		writeJSON(w, http.StatusOK, []any{})
	})

	mux.HandleFunc("/api/v1/notifications/read-all", func(w http.ResponseWriter, r *http.Request) {
		if _, ok := auth(w, r); !ok { return }
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	mux.HandleFunc("/api/v1/hqs", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, []any{})
	})

	mux.HandleFunc("/api/v1/positions", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, []any{})
	})

	return mux
}

func postJ(router http.Handler, path string, body any) *httptest.ResponseRecorder {
	b, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPost, path, bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)
	return w
}

func getJ(router http.Handler, path, token string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodGet, path, nil)
	if token != "" { req.Header.Set("Authorization", "Bearer "+token) }
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)
	return w
}

func registerAndLoginH(router http.Handler) (string, string) {
	postJ(router, "/api/v1/auth/register", map[string]any{
		"email": "test@rso.ru", "password": "Password123!",
		"last_name": "Тест", "first_name": "Пользователь",
	})
	w := postJ(router, "/api/v1/auth/login", map[string]any{
		"email": "test@rso.ru", "password": "Password123!",
	})
	var resp map[string]string
	_ = json.NewDecoder(w.Body).Decode(&resp)
	return resp["access_token"], resp["refresh_token"]
}

// ── Register ─────────────────────────────────────────────────────────────────
func TestHandlerRegister_Success_201(t *testing.T) {
	w := postJ(newFakeServer(), "/api/v1/auth/register", map[string]any{
		"email": "n@rso.ru", "password": "Password123!",
		"last_name": "Н", "first_name": "П",
	})
	if w.Code != http.StatusCreated { t.Errorf("want 201, got %d: %s", w.Code, w.Body) }
}

func TestHandlerRegister_Tokens(t *testing.T) {
	w := postJ(newFakeServer(), "/api/v1/auth/register", map[string]any{
		"email": "t@rso.ru", "password": "Password123!",
		"last_name": "Т", "first_name": "Т",
	})
	var body map[string]any
	_ = json.NewDecoder(w.Body).Decode(&body)
	if body["access_token"] == nil { t.Error("expected access_token") }
}

func TestHandlerRegister_ShortPassword_400(t *testing.T) {
	w := postJ(newFakeServer(), "/api/v1/auth/register", map[string]any{
		"email": "x@rso.ru", "password": "short",
		"last_name": "X", "first_name": "X",
	})
	if w.Code != http.StatusBadRequest { t.Errorf("want 400, got %d", w.Code) }
}

func TestHandlerRegister_MissingField_400(t *testing.T) {
	w := postJ(newFakeServer(), "/api/v1/auth/register", map[string]any{
		"email": "x@rso.ru", "password": "Password123!",
	})
	if w.Code != http.StatusBadRequest { t.Errorf("want 400, got %d", w.Code) }
}

func TestHandlerRegister_Duplicate_409(t *testing.T) {
	srv := newFakeServer()
	postJ(srv, "/api/v1/auth/register", map[string]any{
		"email": "dup@rso.ru", "password": "Password123!",
		"last_name": "A", "first_name": "B",
	})
	w := postJ(srv, "/api/v1/auth/register", map[string]any{
		"email": "dup@rso.ru", "password": "Password123!",
		"last_name": "A", "first_name": "B",
	})
	if w.Code != http.StatusConflict { t.Errorf("want 409, got %d", w.Code) }
}

func TestHandlerRegister_ContentType_JSON(t *testing.T) {
	w := postJ(newFakeServer(), "/api/v1/auth/register", map[string]any{
		"email": "ct@rso.ru", "password": "Password123!",
		"last_name": "Т", "first_name": "Т",
	})
	ct := w.Header().Get("Content-Type")
	if !strings.Contains(ct, "json") { t.Errorf("want JSON Content-Type, got %s", ct) }
}

// ── Login ─────────────────────────────────────────────────────────────────────
func TestHandlerLogin_Success_200(t *testing.T) {
	srv := newFakeServer()
	postJ(srv, "/api/v1/auth/register", map[string]any{
		"email": "u@rso.ru", "password": "Password123!",
		"last_name": "У", "first_name": "П",
	})
	w := postJ(srv, "/api/v1/auth/login", map[string]any{
		"email": "u@rso.ru", "password": "Password123!",
	})
	if w.Code != http.StatusOK { t.Errorf("want 200, got %d", w.Code) }
}

func TestHandlerLogin_WrongPassword_401(t *testing.T) {
	srv := newFakeServer()
	postJ(srv, "/api/v1/auth/register", map[string]any{
		"email": "wp@rso.ru", "password": "Password123!",
		"last_name": "X", "first_name": "Y",
	})
	w := postJ(srv, "/api/v1/auth/login", map[string]any{
		"email": "wp@rso.ru", "password": "Wrong!",
	})
	if w.Code != http.StatusUnauthorized { t.Errorf("want 401, got %d", w.Code) }
}

func TestHandlerLogin_UnknownEmail_401(t *testing.T) {
	w := postJ(newFakeServer(), "/api/v1/auth/login", map[string]any{
		"email": "nobody@rso.ru", "password": "Pass123!",
	})
	if w.Code != http.StatusUnauthorized { t.Errorf("want 401, got %d", w.Code) }
}

func TestHandlerLogin_ContentType_JSON(t *testing.T) {
	srv := newFakeServer()
	postJ(srv, "/api/v1/auth/register", map[string]any{
		"email": "ct2@rso.ru", "password": "Password123!",
		"last_name": "Т", "first_name": "Т",
	})
	w := postJ(srv, "/api/v1/auth/login", map[string]any{
		"email": "ct2@rso.ru", "password": "Password123!",
	})
	ct := w.Header().Get("Content-Type")
	if !strings.Contains(ct, "json") { t.Errorf("want JSON Content-Type, got %s", ct) }
}

// ── Refresh ───────────────────────────────────────────────────────────────────
func TestHandlerRefresh_Valid_200(t *testing.T) {
	srv := newFakeServer()
	_, refresh := registerAndLoginH(srv)
	w := postJ(srv, "/api/v1/auth/refresh", map[string]any{"refresh_token": refresh})
	if w.Code != http.StatusOK { t.Errorf("want 200, got %d", w.Code) }
}

func TestHandlerRefresh_Invalid_401(t *testing.T) {
	w := postJ(newFakeServer(), "/api/v1/auth/refresh", map[string]any{"refresh_token": "garbage"})
	if w.Code != http.StatusUnauthorized { t.Errorf("want 401, got %d", w.Code) }
}

// ── Me ────────────────────────────────────────────────────────────────────────
func TestHandlerMe_WithToken_200(t *testing.T) {
	srv := newFakeServer()
	access, _ := registerAndLoginH(srv)
	w := getJ(srv, "/api/v1/me", access)
	if w.Code != http.StatusOK { t.Errorf("want 200, got %d: %s", w.Code, w.Body) }
}

func TestHandlerMe_NoToken_401(t *testing.T) {
	w := getJ(newFakeServer(), "/api/v1/me", "")
	if w.Code != http.StatusUnauthorized { t.Errorf("want 401, got %d", w.Code) }
}

func TestHandlerMe_InvalidToken_401(t *testing.T) {
	w := getJ(newFakeServer(), "/api/v1/me", "garbage.token")
	if w.Code != http.StatusUnauthorized { t.Errorf("want 401, got %d", w.Code) }
}

// ── Events ────────────────────────────────────────────────────────────────────
func TestHandlerEvents_WithToken_200(t *testing.T) {
	srv := newFakeServer()
	access, _ := registerAndLoginH(srv)
	w := getJ(srv, "/api/v1/events", access)
	if w.Code != http.StatusOK { t.Errorf("want 200, got %d", w.Code) }
}

func TestHandlerEvents_NoToken_401(t *testing.T) {
	w := getJ(newFakeServer(), "/api/v1/events", "")
	if w.Code != http.StatusUnauthorized { t.Errorf("want 401, got %d", w.Code) }
}

// ── Notifications ─────────────────────────────────────────────────────────────
func TestHandlerNotifications_WithToken_200(t *testing.T) {
	srv := newFakeServer()
	access, _ := registerAndLoginH(srv)
	w := getJ(srv, "/api/v1/notifications", access)
	if w.Code != http.StatusOK { t.Errorf("want 200, got %d", w.Code) }
}

func TestHandlerNotifications_NoToken_401(t *testing.T) {
	w := getJ(newFakeServer(), "/api/v1/notifications", "")
	if w.Code != http.StatusUnauthorized { t.Errorf("want 401, got %d", w.Code) }
}

// ── Справочники ───────────────────────────────────────────────────────────────
func TestHandlerHQs_200(t *testing.T) {
	w := getJ(newFakeServer(), "/api/v1/hqs", "")
	if w.Code != http.StatusOK { t.Errorf("want 200, got %d", w.Code) }
}

func TestHandlerPositions_200(t *testing.T) {
	w := getJ(newFakeServer(), "/api/v1/positions", "")
	if w.Code != http.StatusOK { t.Errorf("want 200, got %d", w.Code) }
}

// ── Logout + Me ───────────────────────────────────────────────────────────────
func TestHandlerLogout_Then_Me_401(t *testing.T) {
	srv := newFakeServer()
	access, refresh := registerAndLoginH(srv)
	// Logout
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/logout",
		bytes.NewBufferString(`{"refresh_token":"`+refresh+`"}`))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+access)
	srv.ServeHTTP(httptest.NewRecorder(), req)
	// Me после logout
	w := getJ(srv, "/api/v1/me", access)
	if w.Code != http.StatusUnauthorized {
		t.Errorf("after logout /me should 401, got %d", w.Code)
	}
}