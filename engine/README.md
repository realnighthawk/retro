# Retro wardrobe engine

Single-wardrobe Go/PostgreSQL backend for Retro, with private MinIO photographs. Productivity belongs to Sensei.
Authentication and workspace routing belong entirely to the shared router. The engine has no Clerk SDK, token
validation, identity-header requirement or tenant selector. Each instance uses its own database and private bucket.
HTTP and MCP execute the same **20 operations**, validation, transactions and audit rules.
Implementation is complete for the backend slice below; deployment and final verification are deferred to the owner.

## Implemented

- Garments, searchable inventory, optional attributes/photos, availability and archive/restore.
- Dated planned/worn/void outfits, multiple outfits per date, audited corrections and explicit confirmation.
- Confirmed snapshots preserve names/photos after inventory edits. Wear days/events derive from actual history.
- Rule-based suggestions with required/excluded pieces, real Shuffle alternatives and incomplete-coverage disclosure.
- Wear-history summaries, category usage and append-only record history.
- Database-scoped write idempotency, optimistic versions and client-generated UUID support.
- Reserved binary uploads, checksum/type/size/decode validation, immutable MinIO objects and authenticated derivatives.
- Durable PostgreSQL photo jobs with leases, fenced completion, retries and manual retry after failure.
- Generated OpenAPI, MCP Streamable HTTP, capabilities and health/readiness endpoints.

No client has been switched from demo data to this engine yet. AI tagging, weather lookup, notifications, sharing,
automatic image cleanup/purge and Sensei client extraction are deferred. Raw upload sources and retry/audit records
are retained until a deliberate cleanup policy is implemented; account for them in storage/backups.

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
