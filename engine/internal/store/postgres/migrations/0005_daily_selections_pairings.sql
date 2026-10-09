CREATE TABLE retro.day_selections (
 id uuid PRIMARY KEY,
 day date NOT NULL UNIQUE,
 outfit_id uuid REFERENCES retro.outfits(id),
 time_zone text NOT NULL DEFAULT '',
 version bigint NOT NULL DEFAULT 1 CHECK(version>0),
 updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE retro.pairings (
 id uuid PRIMARY KEY,
 name text NOT NULL CHECK(length(name) BETWEEN 1 AND 100),
 notes text NOT NULL DEFAULT '',
 version bigint NOT NULL DEFAULT 1 CHECK(version>0),
 archived_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE retro.pairing_items (
 pairing_id uuid NOT NULL REFERENCES retro.pairings(id),
 garment_id uuid NOT NULL REFERENCES retro.garments(id),
 position integer NOT NULL,
 role text NOT NULL CHECK(role IN ('base','mid','bottom','one_piece','outer','feet','accessory','other')),
 PRIMARY KEY(pairing_id,garment_id),
 UNIQUE(pairing_id,position)
);
CREATE INDEX pairing_items_garment ON retro.pairing_items(garment_id,pairing_id);
