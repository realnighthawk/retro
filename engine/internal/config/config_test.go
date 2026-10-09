package config

import "testing"

func TestConfigNeedsOnlyDatabaseAndCompleteStorage(t *testing.T) {
	for _, key := range []string{"DATABASE_URL", "LISTEN_ADDR", "MINIO_ENDPOINT", "MINIO_BUCKET", "MINIO_ACCESS_KEY", "MINIO_SECRET_KEY", "MINIO_REGION", "TRUSTED_ORIGINS"} {
		t.Setenv(key, "")
	}
	t.Setenv("DATABASE_URL", "postgres://example")
	t.Setenv("LISTEN_ADDR", "0.0.0.0:8092")
	if _, e := Load(); e != nil {
		t.Fatal(e)
	}
	t.Setenv("MINIO_ENDPOINT", "http://minio:9000")
	if _, e := Load(); e == nil {
		t.Fatal("partial MinIO configuration accepted")
	}
}
