CREATE TABLE retro.garments (
 owner_id text NOT NULL, id uuid NOT NULL, version bigint NOT NULL DEFAULT 1 CHECK(version>0),
 name text NOT NULL CHECK(length(name) BETWEEN 1 AND 100),
 category text NOT NULL CHECK(category IN ('top','bottom','one_piece','outerwear','footwear','accessory','other')),
 availability text NOT NULL CHECK(availability IN ('ready','needs_wash','washing','unavailable')),
 attributes jsonb NOT NULL DEFAULT '{}' CHECK(jsonb_typeof(attributes)='object'),
 archived_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(owner_id,id)
);
CREATE TABLE retro.media (
 owner_id text NOT NULL, id uuid NOT NULL, version bigint NOT NULL DEFAULT 1 CHECK(version>0),
 checksum text NOT NULL CHECK(checksum ~ '^[0-9a-f]{64}$'),
 size_bytes bigint NOT NULL CHECK(size_bytes BETWEEN 1 AND 12582912),
 mime_type text NOT NULL CHECK(mime_type IN ('image/jpeg','image/png')),
 state text NOT NULL DEFAULT 'awaiting_upload' CHECK(state IN ('awaiting_upload','processing','ready','failed')),
 width integer, height integer, error text,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(owner_id,id)
);
CREATE TABLE retro.garment_media (
 owner_id text NOT NULL, garment_id uuid NOT NULL, media_id uuid NOT NULL, position integer NOT NULL,
 PRIMARY KEY(owner_id,garment_id,media_id), UNIQUE(owner_id,garment_id,position),
 FOREIGN KEY(owner_id,garment_id) REFERENCES retro.garments(owner_id,id),
 FOREIGN KEY(owner_id,media_id) REFERENCES retro.media(owner_id,id)
);
CREATE TABLE retro.outfits (
 owner_id text NOT NULL, id uuid NOT NULL, version bigint NOT NULL DEFAULT 1 CHECK(version>0),
 day date NOT NULL, time_zone text NOT NULL,
 state text NOT NULL CHECK(state IN ('planned','worn','void')),
 previous_state text CHECK(previous_state IN ('planned','worn')),
 label text NOT NULL DEFAULT '', occasion text NOT NULL DEFAULT '', notes text NOT NULL DEFAULT '', source text NOT NULL DEFAULT 'manual',
 confirmed_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(owner_id,id)
);
CREATE INDEX outfits_day ON retro.outfits(owner_id,day,id);
CREATE TABLE retro.outfit_items (
 owner_id text NOT NULL, outfit_id uuid NOT NULL, garment_id uuid NOT NULL, position integer NOT NULL,
 role text NOT NULL CHECK(role IN ('base','mid','bottom','one_piece','outer','feet','accessory','other')),
 snapshot jsonb CHECK(snapshot IS NULL OR jsonb_typeof(snapshot)='object'),
 PRIMARY KEY(owner_id,outfit_id,garment_id), UNIQUE(owner_id,outfit_id,position),
 FOREIGN KEY(owner_id,outfit_id) REFERENCES retro.outfits(owner_id,id),
 FOREIGN KEY(owner_id,garment_id) REFERENCES retro.garments(owner_id,id)
);
CREATE INDEX outfit_items_garment ON retro.outfit_items(owner_id,garment_id,outfit_id);
CREATE TABLE retro.outfit_media (
 owner_id text NOT NULL, outfit_id uuid NOT NULL, media_id uuid NOT NULL,
 PRIMARY KEY(owner_id,outfit_id,media_id),
 FOREIGN KEY(owner_id,outfit_id) REFERENCES retro.outfits(owner_id,id),
 FOREIGN KEY(owner_id,media_id) REFERENCES retro.media(owner_id,id)
);
CREATE TABLE retro.changes (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, owner_id text NOT NULL, actor_id text NOT NULL,
 operation text NOT NULL, entity_type text NOT NULL, entity_id uuid NOT NULL,
 before_data jsonb, after_data jsonb, occurred_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX changes_entity ON retro.changes(owner_id,entity_type,entity_id,id DESC);
CREATE TABLE retro.requests (
 owner_id text NOT NULL, key text NOT NULL CHECK(length(key) BETWEEN 1 AND 128),
 operation text NOT NULL, input_hash text NOT NULL, response jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(owner_id,key)
);
CREATE TABLE retro.media_jobs (
 owner_id text NOT NULL, media_id uuid NOT NULL, attempt integer NOT NULL DEFAULT 0,
 token uuid, lease_until timestamptz, next_attempt timestamptz NOT NULL DEFAULT now(),
 done boolean NOT NULL DEFAULT false, PRIMARY KEY(owner_id,media_id),
 FOREIGN KEY(owner_id,media_id) REFERENCES retro.media(owner_id,id)
);
