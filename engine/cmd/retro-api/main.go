package main

import (
	"context"
	"errors"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/nighthawklabs/retro/engine/internal/config"
	"github.com/nighthawklabs/retro/engine/internal/engine"
	"github.com/nighthawklabs/retro/engine/internal/media"
	"github.com/nighthawklabs/retro/engine/internal/store/postgres"
	"github.com/nighthawklabs/retro/engine/internal/transport"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
	_ "time/tzdata"
)

func main() {
	if err := run(); err != nil {
		// The cause, not just the phase — a swallowed error here made a real
		// failure (unreachable bucket, missing database) indistinguishable
		// from any other startup failure.
		slog.Error("retro-api stopped", "reason", "startup or server failure", "error", err)
		os.Exit(1)
	}
}
func run() error {
	cfg, err := config.Load()
	if err != nil {
		slog.Error("invalid configuration", "reason", err)
		return err
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	pool, err := pgxpool.New(ctx, cfg.DatabaseURL)
	if err != nil {
		return err
	}
	defer pool.Close()
	startup, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	if err = pool.Ping(startup); err != nil {
		return err
	}
	if err = postgres.Migrate(startup, pool); err != nil {
		return err
	}
	var photos *media.Store
	if cfg.MinioEndpoint != "" {
		photos, err = media.New(cfg.MinioEndpoint, cfg.MinioBucket, cfg.MinioAccess, cfg.MinioSecret, cfg.MinioRegion)
		if err != nil {
			return err
		}
		if err = photos.Check(startup); err != nil {
			return err
		}
	}
	service := engine.New(pool, photos)
	health := http.NewServeMux()
	health.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(200); _, _ = w.Write([]byte("ok")) })
	health.HandleFunc("GET /readyz", func(w http.ResponseWriter, r *http.Request) {
		c, cancel := context.WithTimeout(r.Context(), 3*time.Second)
		defer cancel()
		if pool.Ping(c) != nil || service.StorageReady(c) != nil {
			http.Error(w, "unavailable", 503)
			return
		}
		w.WriteHeader(200)
		_, _ = w.Write([]byte("ready"))
	})
	handler, err := transport.New(service, health, cfg.TrustedOrigins)
	if err != nil {
		return err
	}
	workerCtx, cancelWorker := context.WithCancel(ctx)
	workerDone := make(chan struct{})
	go func() { defer close(workerDone); service.RunWorker(workerCtx) }()
	defer func() { cancelWorker(); <-workerDone }()
	srv := &http.Server{Addr: cfg.ListenAddr, Handler: handler, ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 35 * time.Second, WriteTimeout: 35 * time.Second, IdleTimeout: 60 * time.Second, MaxHeaderBytes: 1 << 16}
	errorsCh := make(chan error, 1)
	go func() { errorsCh <- srv.ListenAndServe() }()
	slog.Info("retro-api listening", "address", cfg.ListenAddr)
	select {
	case err := <-errorsCh:
		if errors.Is(err, http.ErrServerClosed) {
			return nil
		}
		return err
	case <-ctx.Done():
		shutdown, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		return srv.Shutdown(shutdown)
	}
}
