package engine

import (
	"context"
	"encoding/hex"
	"errors"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/nighthawklabs/retro/engine/internal/media"
	"log/slog"
	"time"
)

type Media struct {
	StorageNamespace string  `json:"-"`
	ID               string  `json:"id"`
	Version          int64   `json:"version"`
	Checksum         string  `json:"checksum"`
	SizeBytes        int64   `json:"size_bytes"`
	MimeType         string  `json:"mime_type"`
	State            string  `json:"state"`
	Width            *int    `json:"width"`
	Height           *int    `json:"height"`
	Error            *string `json:"error"`
	UploadPath       string  `json:"upload_path"`
	DisplayPath      *string `json:"display_path"`
	ThumbnailPath    *string `json:"thumbnail_path"`
}
type MediaInput struct {
	Meta
	ID        string `json:"id,omitempty"`
	Checksum  string `json:"checksum"`
	SizeBytes int64  `json:"size_bytes"`
	MimeType  string `json:"mime_type"`
}
type MediaResult struct {
	Media Media `json:"media"`
}

func (u *unit) getMedia(ctx context.Context, value string) (Media, error) {
	var m Media
	key, e := id(value)
	if e != nil {
		return m, e
	}
	e = u.tx.QueryRow(ctx, `SELECT id::text,version,checksum,size_bytes,mime_type,state,width,height,error,storage_namespace FROM retro.media WHERE id=$1`, key).Scan(&m.ID, &m.Version, &m.Checksum, &m.SizeBytes, &m.MimeType, &m.State, &m.Width, &m.Height, &m.Error, &m.StorageNamespace)
	if e != nil {
		return m, e
	}
	m.UploadPath = "/retro/api/v1/media/" + m.ID + "/content"
	if m.State == "ready" {
		d, t := m.UploadPath+"?variant=display", m.UploadPath+"?variant=thumbnail"
		m.DisplayPath = &d
		m.ThumbnailPath = &t
	}
	return m, nil
}
func prepareMedia(ctx context.Context, u *unit, in MediaInput) (MediaResult, error) {
	var result MediaResult
	key, e := createID(in.ID)
	if e != nil {
		return result, e
	}
	hash, e := hex.DecodeString(in.Checksum)
	if e != nil || len(hash) != 32 || hex.EncodeToString(hash) != in.Checksum {
		return result, invalid("checksum must be lowercase SHA-256")
	}
	if in.SizeBytes < 1 || in.SizeBytes > media.MaxBytes {
		return result, &Error{"too_large", "photo must be 1-12 MiB"}
	}
	if !oneOf(in.MimeType, "image/jpeg", "image/png") {
		return result, invalid("photo must be JPEG or PNG")
	}
	_, e = u.tx.Exec(ctx, `INSERT INTO retro.media(id,checksum,size_bytes,mime_type) VALUES($1,$2,$3,$4)`, key, in.Checksum, in.SizeBytes, in.MimeType)
	if e != nil {
		return result, e
	}
	m, e := u.getMedia(ctx, key)
	if e != nil {
		return result, e
	}
	result.Media = m
	return result, u.audit(ctx, "media", key, nil, m)
}
func retryMedia(ctx context.Context, u *unit, in EditInput) (MediaResult, error) {
	var result MediaResult
	before, e := u.getMedia(ctx, in.ID)
	if e != nil {
		return result, e
	}
	if e = version(in.ExpectedVersion, before.Version); e != nil {
		return result, e
	}
	if before.State != "failed" {
		return result, conflict("only failed processing can be retried")
	}
	_, e = u.tx.Exec(ctx, `UPDATE retro.media SET state='processing',error=NULL,version=version+1,updated_at=now() WHERE id=$1`, before.ID)
	if e != nil {
		return result, e
	}
	_, e = u.tx.Exec(ctx, `UPDATE retro.media_jobs SET attempt=0,token=NULL,lease_until=NULL,next_attempt=now(),done=false WHERE media_id=$1`, before.ID)
	if e != nil {
		return result, e
	}
	m, e := u.getMedia(ctx, before.ID)
	if e != nil {
		return result, e
	}
	result.Media = m
	return result, u.audit(ctx, "media", m.ID, before, m)
}
func (s *Service) mediaUnit(ctx context.Context, write bool) (*unit, error) {
	if s.photos == nil {
		return nil, &Error{"busy", "Photo storage is not configured"}
	}
	opts := pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly}
	if write {
		opts = pgx.TxOptions{IsoLevel: pgx.ReadCommitted}
	}
	tx, e := s.pool.BeginTx(ctx, opts)
	if e != nil {
		return nil, e
	}
	u := &unit{tx: tx, actor: "router", operation: "media_upload"}
	if write {
		if _, e = tx.Exec(ctx, `SELECT pg_advisory_xact_lock(91437)`); e != nil {
			tx.Rollback(ctx)
			return nil, e
		}
	}
	return u, nil
}
func (s *Service) Upload(ctx context.Context, value string, data []byte) (MediaResult, error) {
	var result MediaResult
	u, e := s.mediaUnit(ctx, false)
	if e != nil {
		return result, e
	}
	before, e := u.getMedia(ctx, value)
	u.tx.Rollback(ctx)
	if e != nil {
		return result, e
	}
	if int64(len(data)) != before.SizeBytes {
		return result, invalid("photo size does not match its reservation")
	}
	if e = media.Validate(data, before.MimeType, before.Checksum); e != nil {
		return result, invalid(e.Error())
	}
	if e = s.photos.Put(ctx, media.Key(before.StorageNamespace, before.ID, before.Checksum, "source"), before.MimeType, data); e != nil {
		return result, &Error{"busy", "Photo storage is unavailable; retry this upload"}
	}
	u, e = s.mediaUnit(ctx, true)
	if e != nil {
		return result, e
	}
	defer u.tx.Rollback(context.Background())
	current, e := u.getMedia(ctx, before.ID)
	if e != nil {
		return result, e
	}
	if current.State == "awaiting_upload" {
		_, e = u.tx.Exec(ctx, `UPDATE retro.media SET state='processing',version=version+1,updated_at=now() WHERE id=$1`, before.ID)
		if e != nil {
			return result, e
		}
		_, e = u.tx.Exec(ctx, `INSERT INTO retro.media_jobs(media_id) VALUES($1)`, before.ID)
		if e != nil {
			return result, e
		}
		current, e = u.getMedia(ctx, before.ID)
		if e != nil {
			return result, e
		}
		if e = u.audit(ctx, "media", before.ID, before, current); e != nil {
			return result, e
		}
	}
	result.Media = current
	return result, u.tx.Commit(ctx)
}
func (s *Service) Photo(ctx context.Context, value, variant string) ([]byte, error) {
	if !oneOf(variant, "display", "thumbnail") {
		return nil, invalid("variant must be display or thumbnail")
	}
	u, e := s.mediaUnit(ctx, false)
	if e != nil {
		return nil, e
	}
	m, e := u.getMedia(ctx, value)
	u.tx.Rollback(ctx)
	if e != nil {
		return nil, e
	}
	if m.State != "ready" {
		return nil, conflict("photo is not ready")
	}
	data, e := s.photos.Get(ctx, media.Key(m.StorageNamespace, m.ID, m.Checksum, variant))
	if e != nil {
		return nil, &Error{"busy", "Photo storage is unavailable"}
	}
	return data, nil
}
func (s *Service) StorageReady(ctx context.Context) error {
	if s.photos == nil {
		return nil
	}
	return s.photos.Check(ctx)
}
func (s *Service) PhotosConfigured() bool { return s.photos != nil }

// A lease token fences completion after a worker is replaced; objects are immutable and deterministic.
func (s *Service) ProcessPhoto(ctx context.Context) (bool, error) {
	if s.photos == nil {
		return false, nil
	}
	var namespace, key, checksum, token, mimeType string
	var attempt int
	e := s.pool.QueryRow(ctx, `WITH candidate AS (
 SELECT j.media_id FROM retro.media_jobs j JOIN retro.media m ON m.id=j.media_id
 WHERE NOT j.done AND m.state='processing' AND j.next_attempt<=now() AND (j.lease_until IS NULL OR j.lease_until<now())
 ORDER BY j.next_attempt,j.media_id FOR UPDATE OF j SKIP LOCKED LIMIT 1)
 UPDATE retro.media_jobs j SET attempt=j.attempt+1,token=$1,lease_until=now()+interval '2 minutes'
 FROM candidate c,retro.media m WHERE j.media_id=c.media_id AND m.id=j.media_id
	 RETURNING m.storage_namespace,j.media_id::text,m.checksum,j.token::text,j.attempt,m.mime_type`, uuid.NewString()).Scan(&namespace, &key, &checksum, &token, &attempt, &mimeType)
	if errors.Is(e, pgx.ErrNoRows) {
		return false, nil
	}
	if e != nil {
		return false, e
	}
	work, cancel := context.WithTimeout(ctx, 90*time.Second)
	defer cancel()
	source, workErr := s.photos.Get(work, media.Key(namespace, key, checksum, "source"))
	if workErr == nil {
		workErr = media.Validate(source, mimeType, checksum)
	}
	var display, thumb []byte
	var width, height int
	if workErr == nil {
		display, thumb, width, height, workErr = media.Variants(source)
	}
	if workErr == nil {
		workErr = s.photos.Put(work, media.Key(namespace, key, checksum, "display"), "image/jpeg", display)
	}
	if workErr == nil {
		workErr = s.photos.Put(work, media.Key(namespace, key, checksum, "thumbnail"), "image/jpeg", thumb)
	}
	finish, cancelFinish := context.WithTimeout(context.WithoutCancel(ctx), 10*time.Second)
	defer cancelFinish()
	tx, e := s.pool.Begin(finish)
	if e != nil {
		return true, e
	}
	defer tx.Rollback(context.Background())
	if _, e = tx.Exec(finish, `SELECT pg_advisory_xact_lock(91437)`); e != nil {
		return true, e
	}
	tag, e := tx.Exec(finish, `UPDATE retro.media_jobs SET done=$3,lease_until=NULL,token=NULL,next_attempt=now()+interval '10 seconds' WHERE media_id=$1 AND token=$2 AND lease_until>now()`, key, token, workErr == nil || attempt >= 3)
	if e != nil {
		return true, e
	}
	if tag.RowsAffected() == 0 {
		return true, nil
	}
	u := &unit{tx: tx, actor: "retro-media-worker", operation: "media_process"}
	before, e := u.getMedia(finish, key)
	if e != nil {
		return true, e
	}
	state, message := "ready", ""
	if workErr != nil {
		state = "processing"
		message = "Photo processing failed; retry scheduled"
		if attempt >= 3 {
			state = "failed"
			message = "Photo processing failed; retry processing or upload a new photo"
		}
	}
	_, e = tx.Exec(finish, `UPDATE retro.media SET state=$2,width=CASE WHEN $2='ready' THEN $3 ELSE NULL END,height=CASE WHEN $2='ready' THEN $4 ELSE NULL END,error=NULLIF($5,''),version=version+1,updated_at=now() WHERE id=$1`, key, state, width, height, message)
	if e != nil {
		return true, e
	}
	after, e := u.getMedia(finish, key)
	if e != nil {
		return true, e
	}
	if e = u.audit(finish, "media", key, before, after); e != nil {
		return true, e
	}
	return true, tx.Commit(finish)
}
func (s *Service) RunWorker(ctx context.Context) {
	timer := time.NewTicker(time.Second)
	defer timer.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-timer.C:
			if _, err := s.ProcessPhoto(ctx); err != nil {
				slog.Error("media worker transaction failed")
			}
		}
	}
}
