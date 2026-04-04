package middleware

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"

	"rso-events/internal/service"
)

type contextKey string

const (
	UserIDKey contextKey = "user_id"
	RoleKey   contextKey = "role"
	TokenKey  contextKey = "access_token"
)

func AuthRequired(s *service.Service) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			authz := r.Header.Get("Authorization")
			if authz == "" || !strings.HasPrefix(authz, "Bearer ") {
				writeUnauth(w, "missing bearer token")
				return
			}
			token := strings.TrimPrefix(authz, "Bearer ")
			claims, err := s.ParseToken(token)
			if err != nil {
				writeUnauth(w, "invalid token")
				return
			}
			ctx := context.WithValue(r.Context(), UserIDKey, claims.UserID)
			ctx = context.WithValue(ctx, RoleKey, claims.Role)
			ctx = context.WithValue(ctx, TokenKey, token)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

func writeUnauth(w http.ResponseWriter, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusUnauthorized)
	_ = json.NewEncoder(w).Encode(map[string]any{"error": "Unauthorized", "message": msg})
}
