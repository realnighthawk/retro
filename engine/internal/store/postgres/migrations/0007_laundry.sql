CREATE TABLE retro.laundry_loads (
 id uuid PRIMARY KEY,
 version bigint NOT NULL DEFAULT 1 CHECK(version>0),
 name text NOT NULL,
 day date NOT NULL,
 time_zone text NOT NULL,
 state text NOT NULL DEFAULT 'planned' CHECK(state IN ('planned','washing','drying','completed','cancelled')),
 program jsonb NOT NULL,
 started_at timestamptz,
 washed_at timestamptz,
 completed_at timestamptz,
 cancelled_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE retro.laundry_items (
 load_id uuid NOT NULL REFERENCES retro.laundry_loads(id),
 garment_id uuid NOT NULL REFERENCES retro.garments(id),
 position integer NOT NULL CHECK(position>=0),
 expected_version bigint NOT NULL CHECK(expected_version>0),
 snapshot jsonb NOT NULL,
 active boolean NOT NULL DEFAULT false,
 PRIMARY KEY(load_id,garment_id),
 UNIQUE(load_id,position)
);
CREATE UNIQUE INDEX laundry_active_garment ON retro.laundry_items(garment_id) WHERE active;
