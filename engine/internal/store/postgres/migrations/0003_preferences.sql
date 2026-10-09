CREATE TABLE retro.preferences (
 id uuid PRIMARY KEY CHECK(id='971d5190-0ce2-4aaf-aa0a-753c3dde8fc9'),
 version bigint NOT NULL DEFAULT 1 CHECK(version>0),
 attributes jsonb NOT NULL,
 updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO retro.preferences(id,attributes) VALUES (
 '971d5190-0ce2-4aaf-aa0a-753c3dde8fc9',
 '{"preferred_colours":[],"avoided_colours":[],"preferred_styles":[],"default_occasion":"",
   "temperature_unit":"celsius","temperature_sensitivity":"normal","cold_threshold_c":10,
   "hot_threshold_c":25,"layering_preference":"moderate","avoid_repeat_days":7,
   "prefer_underused_items":true,"variety":"moderate"}'::jsonb
);
