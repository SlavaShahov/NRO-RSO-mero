package main

import (
	"context"
	"log"
	"net/http"
	"time"

	"rso-events/internal/auth"
	"rso-events/internal/config"
	"rso-events/internal/db"
	httpapi "rso-events/internal/http"
	"rso-events/internal/repo"
	"rso-events/internal/service"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
)

func main() {
	cfg := config.Load()
	ctx := context.Background()
	pool, err := db.NewPool(ctx, cfg.PostgresDSN)
	if err != nil {
		log.Fatalf("db pool: %v", err)
	}
	defer pool.Close()
	jwtManager := auth.NewJWTManager(cfg.JWTSecret, cfg.JWTTTL, cfg.RefreshTTL)
	repository := repo.New(pool)
	svc := service.New(repository, jwtManager)
	handler := httpapi.New(svc, cfg)
	r := chi.NewRouter()
	r.Use(middleware.RequestID)
	r.Use(middleware.RealIP)
	r.Use(middleware.Recoverer)
	r.Use(middleware.Timeout(30 * time.Second))
	r.Use(middleware.Logger)
	handler.Register(r)
	log.Printf("api started on %s", cfg.AppAddr)
	if err := http.ListenAndServe(cfg.AppAddr, r); err != nil {
		log.Fatal(err)
	}
}