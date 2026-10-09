package media

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"golang.org/x/image/draw"
	"image"
	"image/color"
	"image/jpeg"
	_ "image/png"
)

func Validate(data []byte, mime, checksum string) error {
	if len(data) == 0 || int64(len(data)) > MaxBytes {
		return errors.New("photo must be 1-12 MiB")
	}
	hash := sha256.Sum256(data)
	if hex.EncodeToString(hash[:]) != checksum {
		return errors.New("photo checksum does not match")
	}
	config, format, e := image.DecodeConfig(bytes.NewReader(data))
	if e != nil {
		return errors.New("photo must be a valid JPEG or PNG")
	}
	if (format != "jpeg" && format != "png") || mime != "image/"+format {
		return errors.New("photo format does not match its MIME type")
	}
	if config.Width < 1 || config.Height < 1 || int64(config.Width)*int64(config.Height) > 24_000_000 {
		return errors.New("photo exceeds 24 megapixels")
	}
	return nil
}
func Variants(data []byte) (display, thumbnail []byte, width, height int, err error) {
	cfg, _, e := image.DecodeConfig(bytes.NewReader(data))
	if e != nil || cfg.Width < 1 || cfg.Height < 1 || int64(cfg.Width)*int64(cfg.Height) > 24_000_000 {
		return nil, nil, 0, 0, errors.New("photo dimensions are invalid")
	}
	src, format, e := image.Decode(bytes.NewReader(data))
	if e != nil || !((format == "png") || (format == "jpeg")) {
		return nil, nil, 0, 0, errors.New("photo cannot be decoded")
	}
	display, e = resize(src, 1600)
	if e != nil {
		return nil, nil, 0, 0, e
	}
	thumbnail, e = resize(src, 320)
	return display, thumbnail, cfg.Width, cfg.Height, e
}
func resize(src image.Image, edge int) ([]byte, error) {
	b := src.Bounds()
	w, h := b.Dx(), b.Dy()
	if w > edge || h > edge {
		if w >= h {
			h = max(1, h*edge/w)
			w = edge
		} else {
			w = max(1, w*edge/h)
			h = edge
		}
	}
	dst := image.NewRGBA(image.Rect(0, 0, w, h))
	draw.Draw(dst, dst.Bounds(), image.NewUniform(color.White), image.Point{}, draw.Src)
	draw.CatmullRom.Scale(dst, dst.Bounds(), src, b, draw.Over, nil)
	var output bytes.Buffer
	if e := jpeg.Encode(&output, dst, &jpeg.Options{Quality: 85}); e != nil {
		return nil, e
	}
	return output.Bytes(), nil
}
