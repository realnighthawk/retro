CREATE TABLE retro.outfit_feedback (
 id uuid PRIMARY KEY,
 outfit_id uuid NOT NULL UNIQUE REFERENCES retro.outfits(id),
 outfit_version bigint NOT NULL CHECK(outfit_version>0),
 version bigint NOT NULL DEFAULT 1 CHECK(version>0),
 attributes jsonb NOT NULL,
 updated_at timestamptz NOT NULL DEFAULT now()
);
