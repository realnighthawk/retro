package media

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
	"io"
	"net/url"
	"strings"
)

const MaxBytes int64 = 12 << 20

type Store struct {
	client *minio.Client
	bucket string
}

func New(endpoint, bucket, access, secret, region string) (*Store, error) {
	parsed, e := url.Parse(endpoint)
	if e != nil || !oneScheme(parsed) || parsed.User != nil || parsed.Host == "" || (parsed.Path != "" && parsed.Path != "/") || parsed.RawQuery != "" || parsed.Fragment != "" {
		return nil, errors.New("MINIO_ENDPOINT must be an http(s) origin without credentials or a path")
	}
	if bucket == "" || access == "" || secret == "" {
		return nil, errors.New("MinIO bucket and credentials are required")
	}
	client, e := minio.New(parsed.Host, &minio.Options{Creds: credentials.NewStaticV4(access, secret, ""), Secure: parsed.Scheme == "https", Region: region, BucketLookup: minio.BucketLookupPath})
	if e != nil {
		return nil, errors.New("invalid MinIO configuration")
	}
	return &Store{client, bucket}, nil
}
func oneScheme(u *url.URL) bool { return u != nil && (u.Scheme == "http" || u.Scheme == "https") }
func Key(namespace, mediaID, checksum, variant string) string {
	if namespace == "" {
		return fmt.Sprintf("media/%s/%s/%s", mediaID, checksum, variant)
	}
	// Existing objects keep their original storage path after the single-wardrobe migration.
	hash := sha256.Sum256([]byte(namespace))
	return fmt.Sprintf("owners/%s/media/%s/%s/%s", hex.EncodeToString(hash[:]), mediaID, checksum, variant)
}
func (s *Store) Check(ctx context.Context) error {
	exists, e := s.client.BucketExists(ctx, s.bucket)
	if e != nil {
		return errors.New("MinIO bucket is unreachable")
	}
	if !exists {
		return errors.New("MinIO bucket does not exist")
	}
	return nil
}
func (s *Store) Put(ctx context.Context, key, mime string, data []byte) error {
	hash := sha256.Sum256(data)
	checksum := hex.EncodeToString(hash[:])
	opts := minio.PutObjectOptions{ContentType: mime, DisableMultipart: true, UserMetadata: map[string]string{"sha256": checksum}}
	opts.SetMatchETagExcept("*")
	_, e := s.client.PutObject(ctx, s.bucket, key, bytes.NewReader(data), int64(len(data)), opts)
	if e == nil {
		return nil
	}
	if minio.ToErrorResponse(e).Code != "PreconditionFailed" {
		return errors.New("MinIO write failed")
	}
	info, e := s.client.StatObject(ctx, s.bucket, key, minio.StatObjectOptions{})
	if e != nil {
		return errors.New("MinIO verification failed")
	}
	var existing string
	for k, v := range info.Metadata {
		if strings.EqualFold(k, "X-Amz-Meta-Sha256") && len(v) > 0 {
			existing = v[0]
		}
	}
	if info.Size != int64(len(data)) || existing != checksum {
		return errors.New("immutable photo object has different content")
	}
	return nil
}
func (s *Store) Get(ctx context.Context, key string) ([]byte, error) {
	object, e := s.client.GetObject(ctx, s.bucket, key, minio.GetObjectOptions{})
	if e != nil {
		return nil, errors.New("MinIO read failed")
	}
	defer object.Close()
	data, e := io.ReadAll(io.LimitReader(object, MaxBytes+1))
	if e != nil || int64(len(data)) > MaxBytes {
		return nil, errors.New("MinIO object is unreadable or too large")
	}
	return data, nil
}
