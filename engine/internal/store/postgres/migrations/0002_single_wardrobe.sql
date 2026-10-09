-- Refuse to merge distinct wardrobes. The migration runner applies this transactionally.
DO $$
BEGIN
 IF (SELECT count(*) FROM (
  SELECT owner_id FROM retro.garments UNION SELECT owner_id FROM retro.outfits
  UNION SELECT owner_id FROM retro.media UNION SELECT owner_id FROM retro.requests
  UNION SELECT owner_id FROM retro.changes
 ) identities) > 1 THEN
  RAISE EXCEPTION 'Retro requires one wardrobe per database; split existing datasets before upgrading';
 END IF;
END $$;

ALTER TABLE retro.garment_media DROP COLUMN owner_id CASCADE;
ALTER TABLE retro.outfit_items DROP COLUMN owner_id CASCADE;
ALTER TABLE retro.outfit_media DROP COLUMN owner_id CASCADE;
ALTER TABLE retro.media_jobs DROP COLUMN owner_id CASCADE;
ALTER TABLE retro.garments DROP COLUMN owner_id CASCADE;
ALTER TABLE retro.outfits DROP COLUMN owner_id CASCADE;
ALTER TABLE retro.changes DROP COLUMN owner_id CASCADE;
ALTER TABLE retro.requests DROP COLUMN owner_id CASCADE;
ALTER TABLE retro.media DROP CONSTRAINT media_pkey CASCADE;
-- Preserve the opaque legacy namespace so existing MinIO objects need no rename/copy.
ALTER TABLE retro.media RENAME COLUMN owner_id TO storage_namespace;
ALTER TABLE retro.media ALTER COLUMN storage_namespace SET DEFAULT '';

ALTER TABLE retro.garments ADD PRIMARY KEY(id);
ALTER TABLE retro.outfits ADD PRIMARY KEY(id);
ALTER TABLE retro.media ADD PRIMARY KEY(id);
ALTER TABLE retro.requests ADD PRIMARY KEY(key);
ALTER TABLE retro.garment_media ADD PRIMARY KEY(garment_id,media_id),
 ADD UNIQUE(garment_id,position),
 ADD FOREIGN KEY(garment_id) REFERENCES retro.garments(id),
 ADD FOREIGN KEY(media_id) REFERENCES retro.media(id);
ALTER TABLE retro.outfit_items ADD PRIMARY KEY(outfit_id,garment_id),
 ADD UNIQUE(outfit_id,position),
 ADD FOREIGN KEY(outfit_id) REFERENCES retro.outfits(id),
 ADD FOREIGN KEY(garment_id) REFERENCES retro.garments(id);
ALTER TABLE retro.outfit_media ADD PRIMARY KEY(outfit_id,media_id),
 ADD FOREIGN KEY(outfit_id) REFERENCES retro.outfits(id),
 ADD FOREIGN KEY(media_id) REFERENCES retro.media(id);
ALTER TABLE retro.media_jobs ADD PRIMARY KEY(media_id),
 ADD FOREIGN KEY(media_id) REFERENCES retro.media(id);
CREATE INDEX outfits_day ON retro.outfits(day,id);
CREATE INDEX outfit_items_garment ON retro.outfit_items(garment_id,outfit_id);
CREATE INDEX changes_entity ON retro.changes(entity_type,entity_id,id DESC);
