package config

import (
	"os"
	"strings"
	"time"
)

type Config struct {
	AppAddr     string
	PostgresDSN string
	JWTSecret   string
	JWTTTL      time.Duration
	RefreshTTL  time.Duration
}

func Load() Config {
	return Config{
		AppAddr:     env("APP_ADDR", ":8080"),
		PostgresDSN: env("POSTGRES_DSN", "postgres://postgres:postgres@localhost:5432/rso_events?sslmode=disable"),
		JWTSecret:   env("JWT_SECRET", "change-me-in-production"),
		JWTTTL:      envDuration("JWT_TTL", 15*time.Minute),
		RefreshTTL:  envDuration("JWT_REFRESH_TTL", 7*24*time.Hour),
	}
}

func env(key, fallback string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return fallback
}

func envDuration(key string, fallback time.Duration) time.Duration {
	v := strings.TrimSpace(os.Getenv(key))
	if v == "" {
		return fallback
	}
	d, err := time.ParseDuration(v)
	if err != nil {
		return fallback
	}
	return d
}
