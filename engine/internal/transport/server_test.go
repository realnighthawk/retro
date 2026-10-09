package transport

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/nighthawklabs/retro/engine/internal/engine"
)

func TestPrivateEngineDoesNotRequireIdentity(t *testing.T) {
	handler, err := New(engine.New(nil, nil), http.NotFoundHandler(), nil)
	if err != nil {
		t.Fatal(err)
	}
	for _, identity := range []string{"", "ignored-router-user"} {
		for _, tc := range []struct {
			method, path string
			status       int
		}{
			{"GET", "/api/v1/capabilities", 200},
			{"GET", "/api/v1/openapi.json", 200},
			{"POST", "/api/v1/operations/unknown", 404},
			{"PUT", "/api/v1/media/unknown/content", 503},
		} {
			req := httptest.NewRequest(tc.method, tc.path, strings.NewReader("{}"))
			req.Header.Set("X-Nighthawk-Verified-User", identity)
			response := httptest.NewRecorder()
			handler.ServeHTTP(response, req)
			if response.Code != tc.status {
				t.Fatalf("%s %s: wanted %d, got %d", tc.method, tc.path, tc.status, response.Code)
			}
		}
	}
}
