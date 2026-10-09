# Retro wardrobe engine

Single-wardrobe Go/PostgreSQL backend for Retro, with private MinIO photographs. Productivity belongs to Sensei.
Authentication and workspace routing belong entirely to the shared router. The engine has no Clerk SDK, token
validation, identity-header requirement or tenant selector. Each instance uses its own database and private bucket.
HTTP and MCP execute the same **46 operations**, validation, transactions and audit rules.
Implementation is complete for the backend slice below; deployment and final verification are deferred to the owner.

## Implemented

- Garments, searchable inventory, optional attributes/photos, availability and archive/restore.
- Dated planned/worn/void outfits, multiple outfits per date, audited corrections and explicit confirmation.
- Stable daily plan selections and reusable garment pairings, with versioned edits/clear/archive and audit.
- Separate daily automation settings, immutable ranked snapshots per date/time zone, one delivery reservation and agent-recorded receipts.
- Compatible manual laundry plans, exclusive active-garment reservations, confirmed wash/dry progress and retained care snapshots/history.
- Confirmed snapshots preserve names/photos after inventory edits. Wear days/events derive from actual history.
- Preference/feedback-ranked suggestions with required/excluded pieces, role-preserving swaps, Shuffle alternatives and incomplete-coverage disclosure.
- Wear-history summaries, category usage and append-only record history.
- Database-scoped write idempotency, optimistic versions and client-generated UUID support.
- Shared wardrobe preferences and machine presets with versioned partial edits, idempotent retries and audited history.
- Reviewed garment care instructions and explicit versioned outfit feedback with reset/correction and audit.
- Bounded, source-linked context reads for the agent and on-device read-only tools.
- Reserved binary uploads, checksum/type/size/decode validation, immutable MinIO objects and authenticated derivatives.
- Durable PostgreSQL photo jobs with leases, fenced completion, retries and manual retry after failure.
- Generated OpenAPI, MCP Streamable HTTP, capabilities and health/readiness endpoints.

AI tagging, automatic weather ranking, iPhone push/provider-specific delivery guarantees, sharing,
automatic image cleanup/purge and Sensei client extraction are deferred. Raw upload sources and retry/audit records
are retained until a deliberate cleanup policy is implemented; account for them in storage/backups.

The native wardrobe source is now integrated through M6; its iPhone build/install/launch passed, while full flows
remain unverified. [P1 source](../docs/retro-implementation-phases.md) now includes native settings, care and feedback
editing/recovery plus Apple typed proposals/read-only context and the bounded iOS/gateway MCP loop. P2.1 preference/
feedback ranking and iOS choices on Today, plus P2.2 daily selections/pairings, P2.3 Apple candidate help, P2.4
source-linked connected context, P2.5 daily automation and P3.1/P3.3 laundry loads/wear check-ins, are now in source. Remaining specialist work and
permission/provider limits are described in [agent integration](../docs/retro-agent-contract.md).

### Preferences and machine presets (P1)

`preferences_get` accepts `{}` and returns `{"preferences":{...}}`, including the stable `id`, current `version`
and editable settings. `preferences_update` uses the same partial-patch shape as garment updates:

```json
{
  "id": "971d5190-0ce2-4aaf-aa0a-753c3dde8fc9",
  "expected_version": 1,
  "idempotency_key": "preferences-blue-001",
  "patch": {"preferred_colours": ["blue"], "avoid_repeat_days": 7}
}
```

Omitted fields retain their values. Null clears lists/default occasion only; required scalar settings reject null.
Colours cannot be both preferred and avoided. Lists are bounded and reject duplicate values without regard to case;
temperature thresholds must be ordered and within their supported ranges. `history_list` accepts the preference
ID with `entity_type: "preferences"`. Migration 0003 creates one default record per engine database.
The `rules-v2` suggestion algorithm now applies colours, tag-based style/occasion matches, layering, repeat,
underused and variety settings. Temperature sensitivity/thresholds remain stored facts until verified weather
context is implemented; they do not invent a temperature or laundry instruction.

`machine_presets` is a bounded list in the same preferences record: up to ten presets with stable UUID `id`,
`name`, `temperature_c` (0–95), `cycle` (`normal`, `gentle`, `delicate`) and `drying`. A temperature of zero is valid.
Null clears the list. Migration 0003 is unchanged; older preference JSON reads with an empty preset list.

### Care and outfit feedback (P1)

Garment create/update accepts optional `care`; `patch: {"care": null}` clears it. Care records contain
`wash_method`, optional `max_temp_c`, `cycle`, `colour_group`, `drying`, `source` (`manual` or `label`), optional
`evidence` and `confirmed`. Unknown instructions remain `unknown`; label sources require readable evidence.
Confirmation requires a known method, temperature for machine/hand washing and a known machine cycle.
Dry-clean/do-not-wash records reject wash temperature/cycle. Other unknown restrictions still need review before
future load planning. Nested unknown properties are rejected. Confirmed wear snapshots retain the care record.

`outfits_feedback_get` accepts an **outfit** `id`. Its wrapper returns `feedback`, `current_outfit_version`
and `outfit_state`. Before any save, feedback has its own stable UUID and version **0**; reading creates no row.
Migration 0004 stores one feedback record per outfit. To create or correct feedback:

```json
{
  "id": "<feedback UUID from the read>",
  "outfit_id": "<outfit UUID>",
  "expected_version": 0,
  "expected_outfit_version": 2,
  "idempotency_key": "feedback-review-001",
  "patch": {"comfort_rating": 4, "warmth": "too_cold"}
}
```

Send this to `outfits_feedback_update`. Ratings (`rating`, `comfort_rating`, `style_rating`) are optional 1–5;
warmth is `unknown`, `too_cold`, `comfortable` or `too_warm`; comments are bounded. Null resets ratings/comment
and resets warmth to unknown. Both record versions are checked. Only actual `worn` outfits accept changes;
voiding preserves feedback and restoring permits an explicit review. Outfit corrections do not relabel older
feedback's `outfit_version`. Saving feedback never changes outfit state, wear counts or availability. Browse its
stable ID with `history_list`, `entity_type: "feedback"`, after the first save.

`wardrobe_context_get` exposes current preferences and explicit bounded records with source versions and freshness.
Its [contract and capability limits](../docs/retro-agent-contract.md) distinguish wardrobe facts from connected
services and asynchronous jobs; HTTP/MCP use the same operation.

### Ranked choices and swaps (P2.1)

`wardrobe_suggest` remains read-only. It accepts the existing day/occasion/warmth, required/excluded IDs,
excluded fingerprints and variant. Empty occasion uses the saved default. `expected_preferences_version` is an
optional optimistic check for review; a changed preference version fails with conflict. `swap_role` optionally
requires a replacement in one automatic role (`base`, `bottom`, `one_piece`, `mid`, `outer`, `feet`, `accessory`).
To swap one piece, require the other pieces, exclude the target and set its role. An unavailable replacement
returns no choices rather than changing shape or dropping that role. A locked swap role fails validation.

Only active ready pieces qualify. Avoided colours match case-insensitive trimmed tags, and an interval of seven
requires seven elapsed calendar days since the last confirmed wear through the requested day; zero disables this
filter. Conflicting required pieces fail. Numeric scoring adds requested warmth (8), occasion (6), preferred colour
(4), preferred style via formality (3), favourite (1), and optional underused bonuses (5/3/1 for 0/1–3/4–10 wear days).
Rated-wear contributions average numeric ratings around neutral 3, scaled by two; exact-look ratings add twice
that contribution. This is a bounded association heuristic, not proof a piece caused comfort or a trained model.
Only current-version worn outfits through the requested day contribute; unrated comments, voids, plans, future wears
and corrected-but-unreviewed feedback are excluded. Rating resets are reflected on the next read.

The result includes `algorithm: rules-v2`, source-linked preference version/update time, `effective_occasion`,
`feedback_samples`, `feedback_coverage`, warnings, each piece's name/version, integer `score`, reasons and missing roles.
Completeness sorts before score; date-based ties are deterministic. Variety reduces overlap among alternatives.
The inventory cap is 2000; feedback covers the latest 2000 version-matched rated wears through the requested day.
Search uses eight pieces per role and a 64-choice beam per shape, so no-result is not a claim of exhaustive search.
Warmth and styles use recorded tags; weather, calendar, care compatibility and temperature sensitivity are not assessed.
The operation does not choose/save a plan, record a wear, change availability or create a scheduled job.

Rule and integration regressions are authored, not run. No new operation, migration, deployment value or service is added.

### Daily selections and reusable pairings (P2.2)

`wardrobe_day_get` also returns `selection`: a stable UUID for that local date, `version`, nullable `outfit_id`,
captured `time_zone`, `updated_at`, current `outfit` and an optional `problem`. An unset selection has version zero;
the read does not insert a record. `wardrobe_day_selection_update` takes the selection's `id`, `day`,
`expected_version`, `idempotency_key`, and either a saved plan's `outfit_id` plus `expected_outfit_version`, or
explicit `outfit_id: null` to clear it. The plan must belong to this date and contain active ready garments.
Selection never creates an outfit or records wear. Subsequent confirmation retains the reference. Date/timezone
changes, voids and unavailable planned pieces are disclosed on read, not silently substituted. Clear retains a
versioned row and leaves outfit history intact. One selection is shared per calendar date; the stored plan's zone
is retained instead of moving the choice when a device changes time zone.

`pairings_create` takes optional `id`, required `name`, `items` (2–30 unique garment IDs with manual roles), optional
`notes` and `idempotency_key`. `pairings_get` returns `{"pairing":{...}}` with identity/version, lifecycle timestamps
and ordered pieces containing current garment facts. `pairings_list` accepts `garment_id`, literal name `search`,
`include_archived`, limit and query-scoped cursor. `pairings_update` uses the existing versioned partial-patch shape
for name/notes/items; changed pieces require active garments. Archive/restore use ordinary `EditInput`. Archived or
not-ready pieces remain visible in saved combinations and must be reviewed before planning. Pairings themselves
do not establish eligibility, create wear history or retain extra photo objects. History supports `pairing` and
`day_selection` entity types.

Migration 0005 creates `day_selections`, `pairings` and `pairing_items` in the existing PostgreSQL database; no new
deployment values or service are required. Focused validation/replay/rollback/history regressions are authored,
not run. Migration execution is deferred with deployment.

### Daily automation (P2.5)

`wardrobe_daily_settings_get` accepts `{}` and returns `{"settings":{...}}`. The singleton ID is
`8fe141a8-c2af-435c-9e94-166b53fa4b1a`. `wardrobe_daily_settings_update` uses `PatchInput` (`id`,
`expected_version`, `idempotency_key`, `patch`) for `enabled`, `mode` (`morning` or `previous_evening`),
`hour` (0–23), `minute` (0–59), `time_zone` (IANA) and `delivery_target` (at most 200 bytes; empty means generation
only). Null is rejected. Changes are versioned/audited; saving never creates a Temporal schedule.

`wardrobe_daily_generate` takes `expected_settings_version` and `idempotency_key`. It requires enabled current
settings, uses the server clock in that zone and accepts only the configured slot's two-hour catch-up window.
Morning targets the scheduled date; previous-evening targets the next calendar date, including DST and catch-up
across midnight. Nonexistent local slots or already-expired target days fail rather than moving silently.
The run has a stable UUID, day/zone, settings version, expiry at the next
local midnight, captured suggestion query/source versions and immutable ranked suggestions. Generation creates
no plans/wears. Repeated generation for the same date/zone returns its snapshot; changed settings cannot replace
an existing day's snapshot. `wardrobe_daily_get` takes `day` and `time_zone`, returning `{"run": null}` if absent.

`wardrobe_daily_delivery_claim` takes `run_id`, `claim_id` and `idempotency_key` (UUIDs for the run/claim). It
rechecks enabled/current settings, delivery target, day/window/expiry and ranked piece/preference sources. Only
the first committed reservation returns `send_allowed: true`. **Replaying that same key returns false**, as do
competing claims; a lost grant therefore stays reserved. This exception to ordinary result replay prevents a
second authorized attempt. `wardrobe_daily_delivery_complete` adds bounded nonempty `receipt` and `source`
(actual send tool-call reference, at most 500 bytes each) using the same claim and a new retained retry key.
It records `sent`; matching receipt completion can replay and a changed receipt conflicts. Late completion can
record a send that already happened. History supports `daily_settings` and `daily_run`.

The agent uses the harness's existing Temporal wake and connected sender, with one stable user-scoped name.
These records authorize one send attempt; they cannot guarantee exactly-once provider delivery or authenticate
an agent-supplied receipt. Uncertain outcomes are visible and never automatically resent. There is no APNs
service or in-engine scheduler/notifier. Provider-specific idempotency requires evaluation of deployed senders.
Migration 0006 adds two tables in the existing database; Go embeds IANA tzdata for the engine image. No chart
values or storage change. Deploy the worker, engine/migration and iOS source together; focused tests are authored,
unrun, and migration execution remains deferred.

### Manual laundry loads (P3.1)

`laundry_preview` takes `{"program":{"wash_method":"machine","temperature_c":20,"cycle":"gentle","drying":"line"}}`.
Methods are `machine`, `hand` and `dry_clean`. Machine/hand require an explicit 0–95 °C temperature and concrete
drying (`line`, `flat`, `tumble_low`, `tumble_normal`); hand uses `cycle: unknown`. Dry cleaning uses no temperature,
`cycle: unknown`, `drying: professional`. Presets copy into this explicit programme in native review, so later
preset changes do not alter an existing load. The read returns generation time, `active_needs_wash_only` coverage,
inventory count, compact versioned garment groups and blocked items/reasons, capped at 2000 dirty active records.

Only confirmed care qualifies. The chosen temperature must not exceed the recorded limit. Machine cycles match
exactly; drying matches, except `do_not_tumble` allows line/flat. Unknown colour/drying stays blocked. Colour groups
white/light/dark remain separate, and wash-separately garments each get their own group. Capacity and unrecorded
label restrictions are not assessed. Nothing infers dirtiness from wearing or substitutes another wash method.

`laundry_create` takes optional `id`, retained `idempotency_key`, `name`, `day`, IANA `time_zone`, `program` and
1–30 `items: [{"garment_id":"...","expected_version":1}]` from one compatible group. It returns `{"load":{...}}`.
`laundry_get` uses the load `id`. `laundry_list` supports the ordinary limit/cursor, optional `state` or `garment_id`.
`laundry_update` uses `PatchInput` for name/day/time_zone/program/items, only while planned; null is rejected.
Current garment versions/care are checked again, and new snapshots are captured on planned edits.

`laundry_progress` uses `EditInput` (load ID/version/key) to confirm exactly the next state: planned → washing →
drying → completed. Start checks date, versions, care and availability, reserves each garment and sets it to
`washing`. Wash completion keeps garments `washing`; final dry confirmation sets `ready`. Professional care
goes from sent-to-cleaner to returned clean/completed. Server timestamps record actual confirmations independently
of the planned date. Active reservations block garment edit/attachment/archive operations. Two plans may reference
a garment, but only one can start; subsequent stale/competing starts conflict atomically.

`laundry_cancel` also uses `EditInput`. It cancels only unfinished loads, returns active garments to `needs_wash`,
releases reservations and never records completion. Load snapshots and timestamps remain; ordinary replay does
not advance twice or repeat availability/audit changes. `history_list` supports `laundry_load`; garment history
also records availability transitions. Migration 0007 adds two tables and an exclusive active-garment index.
P3.2 adds reviewed local Apple request/label assistance on iOS. P3.4 reuses existing preview/outfit/load operations
for reviewed native Apple/agent timing and batch proposals; it adds no engine operation or migration.
No new deployment values/services/storage are required; deploy the engine/migration and iOS together. Tests are
authored but unrun, and migration execution is deferred.

### Wear history and care check-ins (P3.3)

`laundry_check_in` takes `{"time_zone":"America/Los_Angeles"}` for a complete active wardrobe (maximum 2000), or
also `garment_id` for one explicit garment, including archived history. It returns `generated_at`, `time_zone`,
`coverage`, `inventory_count`, and compact `items` with current garment identity/version, availability, optional
reminder, latest completed cleaning ID/version/instant, nullable wears/calendar age, `due` and `due_reasons`.
The as-of database clock and existing repeatable-read transaction keep completion/history consistent.

Wear counts derive from current `worn` outfit items: distinct dates and events whose local wear date is strictly
after the cleaning instant's date in that outfit's own time zone. Same-day dates/events are separate uncertain
totals; before-cleaning, planned and void records do not count. Logging a historical wear later does not change its
wear date. Correct/void/restore or actual-piece corrections are reflected on the next read. No completed cleaning
means unknown statistics; cancellation/unfinished loads never reset them. Only the latest completed load is a baseline.

Optional garment `laundry_reminder` attributes use `wear_days` (1–100) and/or `interval_days` (1–365), with at least
one threshold. Save them through ordinary `garments_update`/`patch`; `null` removes the preference, preserving
availability, care and history. These are owner preferences, not care facts. Review is due at either threshold;
ambiguous same-day wears do not satisfy the wear threshold. Calendar age compares dates in the request's time zone,
including DST, and requires a known cleaning baseline. Washing or archived pieces suppress reminders. No dirty-state
inference, automatic wash, notification or delivery is performed. iOS displays these as opt-in in-app check-ins.

Migration 0008 adds an index over existing laundry item garment references. There is no new table/service/config,
photo-storage allocation or chart setting. Engine/native tests and the check-in fixture are authored, unrun;
formatting, 46-operation contract generation and Xcode project generation completed. Migrations, suites, native
builds, runtime/device checks and deployment remain deferred. Deploy updated engine/migrations and iOS together.

## Run and configure

Requires Go 1.26.1+, plain PostgreSQL and an existing private MinIO bucket. No TimescaleDB, Redis or vector extension.
The engine applies numbered embedded migrations under a database advisory lock. Its DB role owns its database/schema.
Migration 0002 removes owner columns and restores ordinary UUID foreign keys. It refuses a database containing
multiple prior owner datasets. Existing photo paths and historical audit records are preserved; fresh photos use
identity-free paths. Do not run the older engine image against the migrated schema.

Copy `.env.example` to `.env` and export it before `make run`; the process does not load dotenv files.

| Variable | Meaning |
| --- | --- |
| `DATABASE_URL` | Private Retro PostgreSQL connection; never use Finance/Sensei's database |
| `LISTEN_ADDR` | Default `127.0.0.1:8092`; container defaults to `0.0.0.0:8092` |
| `TRUSTED_ORIGINS` | Comma-separated browser origins; native clients require no entry |
| `MINIO_ENDPOINT` | S3 API origin such as `https://minio.example.org`; no path or console URL |
| `MINIO_BUCKET` | Existing private bucket; use a dedicated bucket/service account per engine instance |
| `MINIO_ACCESS_KEY`, `MINIO_SECRET_KEY` | Application credentials, supplied through environment or a Kubernetes Secret |
| `MINIO_REGION` | Default `us-east-1`; match the MinIO deployment |

Use HTTPS for an external endpoint; HTTP is explicit for a trusted private/local connection. The SDK verifies TLS
certificates normally. Do not expose bucket access publicly or give the engine MinIO root credentials. Grant its service
account bucket location/list permission plus object Get/Put for its bucket; no Delete permission is needed in this slice.
The engine neither creates a production bucket nor changes its policy. Omitting all four MinIO endpoint/bucket/credential
values enables manual catalog use without photos; partial configuration fails startup. Configured storage must be reachable
at startup/readiness. The bucket and its permissions remain deployment responsibilities.

## Contract

Through the identity router: `POST /retro/api/v1/operations/<name>`, `/retro/mcp`,
`GET /retro/api/v1/capabilities`, `GET /retro/api/v1/openapi.json`.
The private engine paths omit `/retro`. [Generated schemas](api/openapi.json) define the full JSON contract.

Create a garment:

```json
{"idempotency_key":"tee-001","name":"Linen tee","category":"top","warmth":"light","colours":["cream"]}
```

Patch an existing record with `id`, `expected_version`, a new `idempotency_key` and `patch`.
Omitted patch fields retain values; null clears optional attributes. Required scalars cannot be null.
Lifecycle/state changes use dedicated operations. Reuse an idempotency key only for the identical request;
object key order/JSON whitespace do not affect identity. Array order does. Successful retries return the original
saved response even if a later write changed the entity; refresh afterward. Conflicts require reconciliation and a new key.

All error responses are `{"error":{"code":"...","message":"..."}}`. Codes map to invalid input 400,
unauthorized 401, not found 404, conflict/duplicate 409, too large 413, busy 503 and internal 500.
Bearer verification and user authorization belong to the router. The private engine ignores identity headers and
serves its one wardrobe. Production NetworkPolicy restricts ingress to the router and the trusted local MCP hub;
do not publish direct engine ingress. Audit actors identify router writes or the photo worker, not end users.

Lists use stable ID keyset pagination, default 50/max 200. Cursors bind filters and sort but do not pin a
multi-request snapshot. `wardrobe_day_get` is atomic and refuses days with over 200 outfits instead of truncating.
Garment stats are lifetime counts; analysis includes archived garments, uses current inventory categories and applies
its optional date range to wears. `unworn_garments` means unworn in that range, or never worn when no range is supplied.
Category wear events count garment appearances and overlap across outfits; they are not the distinct outfit total.
Suggestions examine at most 2,000 garments, retain eight ranked candidates per role and search up to 128 combinations;
manual outfit composition has no such ranking restriction. v1 accepts explicit warmth/occasion, not fetched weather.

## Photo flow

1. Convert HEIC to JPEG/PNG on the client, normalize orientation, strip location metadata and compute SHA-256.
2. Call `media_prepare` with `idempotency_key`, optional `id`, lowercase `checksum`, `size_bytes`, `mime_type`.
3. PUT those exact bytes to the returned `upload_path` using the router's bearer authentication. Retry the same bytes.
4. Poll `media_get` until `ready` or `failed`. The worker generates JPEG display (≤1600px) and thumbnail (≤320px).
5. Attach ready IDs through `garments_update.patch.media_ids`, using the garment's latest version.
6. Load returned `display_path`/`thumbnail_path` with authenticated networking, and cache per signed-in owner.

JSON bodies cap at 1 MiB, photos at 12 MiB and 24 decoded megapixels. Uploads are limited to two concurrent requests
per replica; one worker per replica uses a 90-second work deadline/2-minute lease and three attempts with backoff.
Original bytes are never served. Re-encoded derivatives omit EXIF. New MinIO keys contain only the media ID, checksum and variant. Repeated same-content writes use conditional creation and checksum metadata verification.
Photo replacement creates a new media ID; old derivatives remain available to historical snapshots.

## Deploy

Build from this repository's root, publish to your registry, then pin the resulting tag:

```sh
docker build -t YOUR_REGISTRY/retro-engine:YOUR_TAG engine
docker push YOUR_REGISTRY/retro-engine:YOUR_TAG
```

The `agent-harness` router now forwards `/retro/` to `retro-engine.<tenant-namespace>.svc.cluster.local:8092`.
Its tenant chart has an off-by-default `retroEngine` block, database-role hook, Secret, Service, Deployment and
mandatory NetworkPolicy. Enabling Retro also enables the pinned upstream MinIO 5.4.0 dependency. Supply only the
Retro image repository/tag in your existing tenant values; see [the values example](deploy/tenant-values.example.yaml).

MinIO runs standalone with one persistent **10G PVC (decimal 10 GB)**, CPU/memory requests of **50m / 128Mi** and a
**512Mi memory limit**. Its S3 API and console remain cluster-private. The chart provisions the first `minio.buckets`
entry as a private bucket without purging existing objects; Retro reads that same declaration. Endpoint/port come
from the subchart's Service. Separate root/application credentials derive from the existing Postgres admin password
with distinct salts, matching the other engines' stable-secret convention. A post-upgrade hook creates the application's
bucket-scoped Get/Put user; Retro never receives root credentials. No extra endpoint, bucket or credential values live
under `retroEngine`. Shared origins, registry pull secrets and router namespace reuse `financeEngine` settings.

Deploy the updated shared router as well as the tenant chart. Use the normal chart upgrade for an existing workspace;
never restart completed onboarding. The Postgres role/database is `retroengine`, with no extension requirements.
Role/bucket/user hooks are post-install/post-upgrade: for first enablement, omit `--wait` so the hooks can run before
waiting for the new engine rollout. Existing DB-role passwords are not rotated. Merge the explicit `retroEngine`
block into tenant values rather than using `--reuse-values` with outdated chart defaults.

`/healthz` reports process health; `/readyz` checks PostgreSQL and MinIO. This change does not add public storage
or engine ingress, register Sensei or deploy infrastructure. Back up the database and MinIO volume together.
Single-node MinIO provides no storage redundancy; objects and retained originals share the 10 GB volume.
Optional trusted tenant MCP-hub registration can use `http://retro-engine:8092/mcp` without identity headers;
external authenticated agents use the router's `/retro/mcp` endpoint.

## Verification after deployment

Per the owner's instruction, final verification is deferred. Unit tests are included; commands below are for later:

```sh
make check
TEST_DATABASE_URL='postgres://...disposable database...' make integration
```

The photo integration test also requires `TEST_MINIO_ENDPOINT`, `TEST_MINIO_BUCKET`, `TEST_MINIO_ACCESS_KEY` and
`TEST_MINIO_SECRET_KEY`, pointing to an existing private test bucket. Without these it skips photo integration.
The Compose file is only an optional disposable test setup. It uses a cached MinIO image by default;
`RETRO_TEST_MINIO_IMAGE` can select a maintained/self-built image. Production uses the chosen existing endpoint.
After deployment, verify router authentication, write retry/version behavior, upload → ready → authenticated image
loading, historical photo preservation and database/bucket restore before treating the release as verified.
