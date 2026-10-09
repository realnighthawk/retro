CREATE TABLE retro.daily_settings (
 id uuid PRIMARY KEY CHECK(id='8fe141a8-c2af-435c-9e94-166b53fa4b1a'),
 version bigint NOT NULL DEFAULT 1 CHECK(version>0),
 attributes jsonb NOT NULL,
 updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO retro.daily_settings(id,attributes) VALUES (
 '8fe141a8-c2af-435c-9e94-166b53fa4b1a',
 '{"enabled":false,"mode":"morning","hour":7,"minute":0,"time_zone":"UTC","delivery_target":""}'::jsonb
);
CREATE TABLE retro.daily_runs (
 id uuid PRIMARY KEY,
 day date NOT NULL,
 time_zone text NOT NULL,
 settings_version bigint NOT NULL CHECK(settings_version>0),
 expires_at timestamptz NOT NULL,
 data jsonb NOT NULL,
 delivery jsonb,
 UNIQUE(day,time_zone)
);
