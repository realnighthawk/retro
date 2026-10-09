package transport

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"strings"

	"github.com/modelcontextprotocol/go-sdk/mcp"
	"github.com/nighthawklabs/retro/engine/internal/engine"
)

func New(service *engine.Service, health http.Handler, trustedOrigins []string) (http.Handler, error) {
	server := mcp.NewServer(&mcp.Implementation{Name: "retro-engine", Version: "0.1.0"}, nil)
	closed := false
	for _, op := range service.Operations() {
		server.AddTool(&mcp.Tool{
			Name: op.Name, Description: op.Description, InputSchema: op.InputSchema, OutputSchema: op.OutputSchema,
			Annotations: &mcp.ToolAnnotations{ReadOnlyHint: !op.Write, IdempotentHint: op.Write, OpenWorldHint: &closed},
		}, func(ctx context.Context, req *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			data, err := service.Execute(ctx, op.Name, req.Params.Arguments)
			if err != nil {
				public := engine.PublicError(err)
				if public.Code == "internal" {
					slog.Error("retro operation failed", "operation", op.Name)
				}
				body, _ := json.Marshal(map[string]any{"error": public})
				return &mcp.CallToolResult{IsError: true, Content: []mcp.Content{&mcp.TextContent{Text: string(body)}}}, nil
			}
			return &mcp.CallToolResult{StructuredContent: json.RawMessage(data), Content: []mcp.Content{&mcp.TextContent{Text: string(data)}}}, nil
		})
	}
	mcpHandler := mcp.NewStreamableHTTPHandler(func(*http.Request) *mcp.Server { return server }, &mcp.StreamableHTTPOptions{Stateless: true, JSONResponse: true})
	api := http.NewServeMux()
	api.Handle("/mcp", mcpHandler)
	api.HandleFunc("GET /api/v1/capabilities", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, 200, map[string]any{"operations": service.Operations(), "photos_configured": service.PhotosConfigured()})
	})
	api.HandleFunc("GET /api/v1/openapi.json", func(w http.ResponseWriter, r *http.Request) { writeJSON(w, 200, service.OpenAPI()) })
	api.HandleFunc("POST /api/v1/operations/{operation}", func(w http.ResponseWriter, r *http.Request) {
		if ct := r.Header.Get("Content-Type"); ct != "" && !strings.HasPrefix(ct, "application/json") {
			writeError(w, &engine.Error{Code: "invalid_input", Message: "Content-Type must be application/json"})
			return
		}
		raw, err := io.ReadAll(r.Body)
		if err != nil {
			writeJSON(w, 413, map[string]any{"error": &engine.Error{Code: "too_large", Message: "Request body exceeds 1 MiB"}})
			return
		}
		result, err := service.Execute(r.Context(), r.PathValue("operation"), raw)
		if err != nil {
			public := engine.PublicError(err)
			if public.Code == "internal" {
				slog.Error("retro operation failed", "operation", r.PathValue("operation"))
			}
			writeError(w, public)
			return
		}
		writeJSON(w, 200, json.RawMessage(result))
	})
	uploads := make(chan struct{}, 2)
	api.HandleFunc("PUT /api/v1/media/{id}/content", func(w http.ResponseWriter, r *http.Request) {
		select {
		case uploads <- struct{}{}:
			defer func() { <-uploads }()
		default:
			writeError(w, &engine.Error{Code: "busy", Message: "Photo uploads are busy; retry this upload"})
			return
		}
		data, err := io.ReadAll(r.Body)
		if err != nil {
			writeError(w, &engine.Error{Code: "too_large", Message: "Photo exceeds 12 MiB"})
			return
		}
		result, err := service.Upload(r.Context(), r.PathValue("id"), data)
		if err != nil {
			writeError(w, engine.PublicError(err))
			return
		}
		writeJSON(w, 200, result)
	})
	api.HandleFunc("GET /api/v1/media/{id}/content", func(w http.ResponseWriter, r *http.Request) {
		data, err := service.Photo(r.Context(), r.PathValue("id"), r.URL.Query().Get("variant"))
		if err != nil {
			writeError(w, engine.PublicError(err))
			return
		}
		w.Header().Set("Content-Type", "image/jpeg")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Cache-Control", "private, no-store")
		w.WriteHeader(200)
		_, _ = w.Write(data)
	})
	bounded := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		limit := int64(1 << 20)
		if r.Method == "PUT" && strings.HasPrefix(r.URL.Path, "/api/v1/media/") {
			limit = 12 << 20
		}
		r.Body = http.MaxBytesReader(w, r.Body, limit)
		api.ServeHTTP(w, r)
	})
	originGuard, err := newOriginGuard(trustedOrigins)
	if err != nil {
		return nil, err
	}
	root := http.NewServeMux()
	root.Handle("/mcp", originGuard(bounded))
	root.Handle("/api/v1/operations/", originGuard(bounded))
	root.Handle("/api/v1/media/", originGuard(bounded))
	root.Handle("/api/v1/capabilities", bounded)
	root.Handle("/api/v1/openapi.json", bounded)
	root.Handle("/", health)
	return root, nil
}
func writeJSON(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(data)
}
func writeError(w http.ResponseWriter, err *engine.Error) {
	status := 500
	switch err.Code {
	case "invalid_input":
		status = 400
	case "not_found":
		status = 404
	case "too_large":
		status = 413
	case "busy":
		status = 503
	case "conflict", "duplicate":
		status = 409
	}
	writeJSON(w, status, map[string]any{"error": err})
}
