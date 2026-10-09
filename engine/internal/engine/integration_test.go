package engine_test

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/nighthawklabs/retro/engine/internal/engine"
	"github.com/nighthawklabs/retro/engine/internal/media"
	"github.com/nighthawklabs/retro/engine/internal/store/postgres"
	"image"
	"image/png"
	"os"
	"sync"
	"testing"
	"time"
)

func integrationService(t *testing.T, photos *media.Store) *engine.Service {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL is not set")
	}
	pool, e := pgxpool.New(context.Background(), url)
	if e != nil {
		t.Fatal(e)
	}
	t.Cleanup(pool.Close)
	if e = postgres.Migrate(context.Background(), pool); e != nil {
		t.Fatal(e)
	}
	return engine.New(pool, photos)
}
func execute[T any](t *testing.T, s *engine.Service, name string, body any) T {
	t.Helper()
	raw, e := json.Marshal(body)
	if e != nil {
		t.Fatal(e)
	}
	response, e := s.Execute(context.Background(), name, raw)
	if e != nil {
		t.Fatalf("%s: %v", name, engine.PublicError(e))
	}
	var value T
	if e = json.Unmarshal(response, &value); e != nil {
		t.Fatal(e)
	}
	return value
}
func errorCode(t *testing.T, s *engine.Service, name string, body any, code string) {
	t.Helper()
	raw, _ := json.Marshal(body)
	_, e := s.Execute(context.Background(), name, raw)
	if e == nil || engine.PublicError(e).Code != code {
		t.Fatalf("%s: wanted %s, got %v", name, code, e)
	}
}
func edit(id string, version int64) map[string]any {
	return map[string]any{"id": id, "expected_version": version, "idempotency_key": uuid.NewString()}
}
func TestIntegrationTransactionsAndHistory(t *testing.T) {
	s := integrationService(t, nil)
	key := uuid.NewString()
	originalName, renamedName := "Original tee "+key, "Renamed tee "+key
	day := time.Now().UTC().Format("2006-01-02")
	baseline := execute[engine.Analysis](t, s, "wardrobe_analyze", map[string]any{"from": day, "to": day})
	body := map[string]any{"idempotency_key": key, "id": uuid.NewString(), "name": originalName, "category": "top"}
	raw, _ := json.Marshal(body)
	var wg sync.WaitGroup
	results := make(chan engine.GarmentResult, 8)
	errs := make(chan error, 8)
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			response, e := s.Execute(context.Background(), "garments_create", raw)
			if e != nil {
				errs <- e
				return
			}
			var g engine.GarmentResult
			e = json.Unmarshal(response, &g)
			if e != nil {
				errs <- e
				return
			}
			results <- g
		}()
	}
	wg.Wait()
	close(results)
	close(errs)
	for e := range errs {
		t.Fatal(e)
	}
	var garment engine.Garment
	for r := range results {
		if garment.ID != "" && garment.ID != r.Garment.ID {
			t.Fatal("duplicate create from concurrent retries")
		}
		garment = r.Garment
	}
	page := execute[engine.Page[engine.Garment]](t, s, "garments_list", map[string]any{"search": originalName})
	if len(page.Items) != 1 {
		t.Fatal("duplicate inventory rows")
	}
	items := []engine.Selection{{GarmentID: garment.ID, Role: "base"}}
	plan := execute[engine.OutfitResult](t, s, "outfits_create", map[string]any{"idempotency_key": uuid.NewString(), "day": day, "time_zone": "UTC", "state": "planned", "items": items}).Outfit
	g := execute[engine.GarmentResult](t, s, "garments_get", map[string]any{"id": garment.ID}).Garment
	if g.WearEvents != 0 {
		t.Fatal("plan counted as wear")
	}
	first := execute[engine.OutfitResult](t, s, "outfits_confirm", edit(plan.ID, plan.Version)).Outfit
	_ = execute[engine.OutfitResult](t, s, "outfits_create", map[string]any{"idempotency_key": uuid.NewString(), "day": day, "time_zone": "UTC", "state": "worn", "items": items})
	patch := edit(garment.ID, garment.Version)
	patch["patch"] = map[string]any{"name": renamedName, "notes": "temporary"}
	g = execute[engine.GarmentResult](t, s, "garments_update", patch).Garment
	if g.WearDays != 1 || g.WearEvents != 2 {
		t.Fatalf("wear totals: %+v", g.WearStats)
	}
	historical := execute[engine.OutfitResult](t, s, "outfits_get", map[string]any{"id": first.ID}).Outfit
	if historical.Items[0].Snapshot.Name != originalName {
		t.Fatal("renaming rewrote history")
	}
	retried := execute[engine.GarmentResult](t, s, "garments_update", patch).Garment
	if retried.Version != g.Version || retried.Name != g.Name {
		t.Fatal("identical update retry did not return saved response")
	}
	original := execute[engine.GarmentResult](t, s, "garments_create", body).Garment
	if original.Name != originalName || original.Version != 1 {
		t.Fatal("retry did not return original response")
	}
	patch["idempotency_key"] = uuid.NewString()
	errorCode(t, s, "garments_update", patch, "conflict")
	patch = edit(g.ID, g.Version)
	patch["patch"] = map[string]any{"notes": nil}
	g = execute[engine.GarmentResult](t, s, "garments_update", patch).Garment
	if g.Notes != "" {
		t.Fatal("null did not clear notes")
	}
	void := execute[engine.OutfitResult](t, s, "outfits_void", edit(first.ID, first.Version)).Outfit
	g = execute[engine.GarmentResult](t, s, "garments_get", map[string]any{"id": g.ID}).Garment
	if g.WearDays != 1 || g.WearEvents != 1 {
		t.Fatal("void did not correct counts")
	}
	_ = execute[engine.OutfitResult](t, s, "outfits_restore", edit(void.ID, void.Version))
	archived := execute[engine.GarmentResult](t, s, "garments_archive", edit(g.ID, g.Version)).Garment
	page = execute[engine.Page[engine.Garment]](t, s, "garments_list", map[string]any{"search": renamedName})
	if len(page.Items) != 0 {
		t.Fatal("archive remained visible")
	}
	historical = execute[engine.OutfitResult](t, s, "outfits_get", map[string]any{"id": first.ID}).Outfit
	if historical.Items[0].Snapshot.Name != originalName {
		t.Fatal("archive rewrote history")
	}
	_ = execute[engine.GarmentResult](t, s, "garments_restore", edit(archived.ID, archived.Version))
	history := execute[engine.Page[engine.Change]](t, s, "history_list", map[string]any{"entity_type": "garment", "id": g.ID})
	if len(history.Items) < 5 {
		t.Fatal("missing audit")
	}
	analysis := execute[engine.Analysis](t, s, "wardrobe_analyze", map[string]any{"from": day, "to": day})
	if analysis.OutfitEvents != baseline.OutfitEvents+2 || analysis.WearDays != 1 {
		t.Fatalf("analysis: %+v", analysis)
	}
	errorCode(t, s, "outfits_confirm", edit(first.ID, historical.Version), "conflict")
	body["name"] = "changed input"
	errorCode(t, s, "garments_create", body, "conflict")
}
func TestIntegrationMinioPhotoLifecycle(t *testing.T) {
	endpoint := os.Getenv("TEST_MINIO_ENDPOINT")
	if endpoint == "" {
		t.Skip("TEST_MINIO_ENDPOINT is not set")
	}
	storage, e := media.New(endpoint, os.Getenv("TEST_MINIO_BUCKET"), os.Getenv("TEST_MINIO_ACCESS_KEY"), os.Getenv("TEST_MINIO_SECRET_KEY"), "us-east-1")
	if e != nil {
		t.Fatal(e)
	}
	s := integrationService(t, storage)
	var buffer bytes.Buffer
	if e = png.Encode(&buffer, image.NewRGBA(image.Rect(0, 0, 24, 12))); e != nil {
		t.Fatal(e)
	}
	data := buffer.Bytes()
	sum := sha256.Sum256(data)
	reservation := execute[engine.MediaResult](t, s, "media_prepare", map[string]any{"idempotency_key": uuid.NewString(), "checksum": hex.EncodeToString(sum[:]), "size_bytes": len(data), "mime_type": "image/png"}).Media
	uploaded, e := s.Upload(context.Background(), reservation.ID, data)
	if e != nil {
		t.Fatal(e)
	}
	if uploaded.Media.State != "processing" {
		t.Fatal("upload did not enqueue processing")
	}
	if _, e = s.Upload(context.Background(), reservation.ID, data); e != nil {
		t.Fatal(e)
	}
	done, e := s.ProcessPhoto(context.Background())
	if e != nil || !done {
		t.Fatalf("worker: %v", e)
	}
	ready := execute[engine.MediaResult](t, s, "media_get", map[string]any{"id": reservation.ID}).Media
	if ready.State != "ready" {
		t.Fatalf("photo state: %s", ready.State)
	}
	display, e := s.Photo(context.Background(), ready.ID, "display")
	if e != nil || len(display) == 0 {
		t.Fatal("missing derivative")
	}
	garment := execute[engine.GarmentResult](t, s, "garments_create", map[string]any{"idempotency_key": uuid.NewString(), "name": "Photo tee", "category": "top", "media_ids": []string{ready.ID}}).Garment
	outfit := execute[engine.OutfitResult](t, s, "outfits_create", map[string]any{"idempotency_key": uuid.NewString(), "day": time.Now().UTC().Format("2006-01-02"), "time_zone": "UTC", "state": "worn", "items": []engine.Selection{{GarmentID: garment.ID, Role: "base"}}}).Outfit
	patch := edit(garment.ID, garment.Version)
	patch["patch"] = map[string]any{"media_ids": []string{}}
	_ = execute[engine.GarmentResult](t, s, "garments_update", patch)
	outfit = execute[engine.OutfitResult](t, s, "outfits_get", map[string]any{"id": outfit.ID}).Outfit
	if len(outfit.Items[0].Snapshot.MediaIDs) != 1 || outfit.Items[0].Snapshot.MediaIDs[0] != ready.ID {
		t.Fatal("photo replacement erased historical reference")
	}
	if _, e = s.Photo(context.Background(), ready.ID, "thumbnail"); e != nil {
		t.Fatal(e)
	}
	if _, e = s.Upload(context.Background(), ready.ID, []byte("different bytes")); e == nil {
		t.Fatal("immutable media was overwritten")
	}
}
