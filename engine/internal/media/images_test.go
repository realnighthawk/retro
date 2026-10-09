package media

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"image"
	"image/color"
	"image/jpeg"
	"image/png"
	"testing"
)

func TestPhotoValidationAndVariants(t *testing.T) {
	src := image.NewRGBA(image.Rect(0, 0, 2000, 1000))
	src.Set(0, 0, color.RGBA{R: 100, A: 255})
	var buf bytes.Buffer
	if e := png.Encode(&buf, src); e != nil {
		t.Fatal(e)
	}
	raw := buf.Bytes()
	sum := sha256.Sum256(raw)
	checksum := hex.EncodeToString(sum[:])
	if e := Validate(raw, "image/png", checksum); e != nil {
		t.Fatal(e)
	}
	if e := Validate(raw, "image/jpeg", checksum); e == nil {
		t.Fatal("MIME mismatch accepted")
	}
	if e := Validate(raw, "image/png", string(make([]byte, 64))); e == nil {
		t.Fatal("checksum mismatch accepted")
	}
	d, thumb, w, h, e := Variants(raw)
	if e != nil {
		t.Fatal(e)
	}
	if w != 2000 || h != 1000 {
		t.Fatal("source dimensions lost")
	}
	for _, tc := range []struct {
		raw  []byte
		w, h int
	}{{d, 1600, 800}, {thumb, 320, 160}} {
		cfg, e := jpeg.DecodeConfig(bytes.NewReader(tc.raw))
		if e != nil || cfg.Width != tc.w || cfg.Height != tc.h {
			t.Fatalf("variant dimensions: %+v %v", cfg, e)
		}
	}
	if _, _, _, _, e = Variants([]byte("not an image")); e == nil {
		t.Fatal("malformed image accepted")
	}
	huge := image.NewGray(image.Rect(0, 0, 5000, 5000))
	buf.Reset()
	if e := png.Encode(&buf, huge); e != nil {
		t.Fatal(e)
	}
	sum = sha256.Sum256(buf.Bytes())
	if e := Validate(buf.Bytes(), "image/png", hex.EncodeToString(sum[:])); e == nil {
		t.Fatal("oversized decode accepted")
	}
}
func TestMinioConfigurationAndStorageKeys(t *testing.T) {
	for _, endpoint := range []string{"https://user:pass@host", "http://host/path", "file:///tmp", "https://host?token=x"} {
		if _, e := New(endpoint, "bucket", "access", "secret", "us-east-1"); e == nil {
			t.Fatalf("accepted endpoint %q", endpoint)
		}
	}
	if Key("", "id", "checksum", "display") != "media/id/checksum/display" {
		t.Fatal("new photo path needs identity")
	}
	if Key("a", "id", "checksum", "display") == Key("b", "id", "checksum", "display") {
		t.Fatal("legacy object paths collided")
	}
}
