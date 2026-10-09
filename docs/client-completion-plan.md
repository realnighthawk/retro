# Native client completion plan

Proposed on 2026-10-08. This is a plan, not completed client implementation.
Finish Retro's wardrobe flow first; then build Sensei's productivity clients against their own backend contract.
The [Retro feature roadmap](retro-feature-roadmap.md) defines the complete first release and its intelligent/product
follow-ups. Retro is the current implementation focus; no Sensei work is required to complete it.
Do not deploy or run verification during this planning step. Runtime validation follows the owner's deployment.

Implementation has begun iteratively: milestone 1 is now implemented in source on both platforms (not built/tested).
The shell reads real inventory/day/history and record details with scoped caches, filters and cursor pagination.
The old productivity demo is preserved. Milestone 2 is also implemented in source on both platforms: manual
versioned garment/outfit forms and atomic durable pending saves with frozen keys/payloads, foreground/reconnect
replay, and basic rejected-request review. M3 private photos and optional iOS OCR/cutout/text capture assistance are also implemented for the installed SDK.
No builds/tests/runtime verification have run; direct model image prompting awaits newer SDK declarations.
M4 source adds suggestions, insights, audit/date/garment history filters, durable form/photo drafts, queued-create
followups and reviewed rejected-request replacement. See the roadmap for remaining device/accessibility validation.

The [on-device intelligence plan](on-device-intelligence-plan.md) adds optional Apple-powered capture and interpretation
before implementation begins. Manual/core behavior remains the baseline; local intelligence does not replace engine rules.

## Starting point

| Area | Current state | Remaining work |
| --- | --- | --- |
| Retro iOS and Android | Real reads/writes, durable pending saves/photos, private capture, optional iOS local assistance, Clerk login and shared idempotent onboarding; M1–M4 source unverified | Device/accessibility validation and later assistance |
| Retro backend | 20 operations, versioned writes, immutable wear snapshots, private photo processing | Native DTOs, stores, operation callers and media transport |
| Router / tenant chart | `/retro` wiring and a MinIO dependency with 10 GB storage implemented in agent-harness | Owner deployment, then integration validation |
| Local persistence | iOS `DiskCache` and Android atomic private read files; caches scope account/endpoint/query | Atomic pending writes/replay implemented; staged photos and frozen attachment recovery implemented; garment/outfit/photo drafts, queued-create followups and selected-field recovery implemented; runtime checks deferred |
| Sensei | Product boundary documented | Repository choice, native apps, registrations, backend contract and `/sensei` route |

Keep `org.nighthawklabs.retro`, the existing icon, theme tokens, Clerk configuration and onboarding behavior.
The private engine delegates authentication to the router; native clients still authenticate and isolate local data
by signed-in account. Completing shared onboarding does not prove the Retro engine is deployed. Show service
unavailability separately, without starting another onboarding request.

Working assumption: Sensei lives in a sibling repository, with proposed identifier `org.nighthawklabs.sensei`.
Repository placement is pending the owner's preference; that choice does not block Retro.

## Product and interaction design

Retro has three destinations, each retaining its own navigation state:

| Destination | First screen | Main actions |
| --- | --- | --- |
| Today | Selected local date, planned and worn outfits, suggestions | Compose outfit, save plan, record wear, edit or void a record |
| Wardrobe | Photo grid, search, category and availability filters | Add garment, inspect/edit details, change laundry state, archive/restore |
| History | Date-grouped outfit timeline and factual usage summary | Inspect historical snapshot, correct/void/restore, view record changes |

Account moves to a toolbar sheet. Add garment is a button opening a focused sheet, rather than a destination tab.
Replace general Capture with wardrobe-specific actions. Preserve productivity source before removing Goals,
journal Review and the old productivity Today from Retro; demo content is never imported as real records.

Use existing SwiftUI/Compose components and Sage & Clay tokens. Garment entry requires name and category;
photo is optional. Availability, warmth, colours and styling details remain editable without a long mandatory form.
The outfit composer supports a top/bottom or one-piece outfit plus optional layers, footwear and accessories.
Allow manual recording without requiring a complete suggested outfit.

Every destination needs explicit loading, empty, cached/offline, pending and failed states. An empty wardrobe offers
“Add your first garment”; it does not silently show sample clothes. Pending wear is visibly pending until the server
acknowledges it. Plans never increment wear statistics. History supports multiple outfits on one date.

Use semantic text styles, Dynamic Type/system font scaling, meaningful VoiceOver/TalkBack names and status text,
44 pt iOS / 48 dp Android touch targets, existing dark/high-contrast colours and reduced-motion behavior.
Keep standard back gestures, keyboard handling, photo-picker behavior and confirmation before discarding edits.

## Delivery order

Build the first complete flow in iOS, then bring Android to the same milestone before starting the next.
Use the same contract examples and acceptance criteria on both; do not introduce a shared UI framework.

### 1. Contract and focused shell

- Preserve reusable productivity source for Sensei; inspect existing persisted edits before removing any old caches.
- Add native wardrobe DTOs from `engine/api/openapi.json` and the engine types, with explicit snake_case mappings.
- Separate demo `Day`/`Garment`/`Outfit` models from production models. The old four slots, eight colours and relative
  wear dates cannot represent seven backend categories, roles, availability, versions, media and historical snapshots.
- Reuse `Engine`, auth, onboarding and API error handling. Add small wardrobe stores bound to the current account.
- Add the three-tab shell with real read calls, cursor pagination and owner-scoped read caching. Reset cursors when
  filters change; discard late responses after an account switch.

Exit: a signed-in owner can see actual inventory, day outfits and history, with honest empty/offline/service states.
Production screens never depend on `DemoData`.

### 2. Garments and the manual outfit flow

- Add/create/edit garments, availability, favourites, archive and restore. Expose optional metadata in garment detail.
- Compose, save and edit a plan; confirm what was worn or record a past outfit directly. Preserve its local date and
  IANA time zone instead of converting a date-only record through UTC.
- Support outfit correction, void and restore. Use historical snapshots for worn outfits; do not reconstruct history
  from today's garment names or photographs. Distinguish wear days from outfit events.
- Give every mutation a client UUID where supported and an idempotency key. Persist its request before delivery;
  versioned edits include `expected_version`. Double taps and response loss must not create duplicate records.
- Begin with one serialized pending-write list per account, including visible retry/conflict states. Milestone 2 includes persisted frozen request recovery on relaunch. Milestone 4
  completes dependent offline editing, richer conflict recovery, unsaved drafts and the broader recovery matrix.

Exit: add a garment → compose an outfit → confirm wear → see it in history → correct or void it → restore it.
The same flow is available on both platforms before moving on.

### 3. Private photographs

Implemented in source on both clients: picker/camera, ordered references, staged immutable JPEG batches, processing
status/retry, guarded attachment and authenticated cached images. iOS adds local OCR/cutouts and reviewed text
suggestions. Garments are saved first, then photos are managed from detail. A source above 24 MP is rejected; final
exports are downsampled to a 2048-pixel edge and at most 12 MiB. A batch's attachment compares current photo references
with the reviewed baseline; conflicts require explicit review with existing ready IDs, not re-uploading the same image.
Derivative caches are capped at 64 MiB. Source files remain until the dependent attachment is acknowledged.

Direct iOS 27 image prompting is not implemented: the installed SDK exposes only the text prompt surface. Tests and
wire fixtures are authored, not run. Unsaved prepared photo-editor drafts are now persisted by M4. Interrupted-staging local sources are pruned on reopen with a readable manifest and one-day grace period.


- Include the optional garment-detail draft, label OCR and cutout preview described in the intelligence plan;
  availability-gate each capability and keep manual entry/save independent of analysis.
- Use PhotosPicker/camera on iOS and the system photo picker/camera on Android; request permission only when needed.
- Normalize orientation and export JPEG/PNG without source metadata; convert HEIC. Enforce the backend's 12 MiB
  and 24-megapixel limits before reservation, and explain unusable input without losing garment edits.
- Save the final bytes durably, calculate lowercase SHA-256, then call `media_prepare`. Upload exactly those bytes
  to `upload_path`, poll `media_get` while the screen/job is active and attach only ready media using a versioned
  garment edit. Resume by checking status after relaunch; offer `media_retry` for failed processing.
- Extend existing transport for binary PUT/downloads and authenticated thumbnail/display loading. Returned paths
  start with `/retro/api/v1`; resolve them against the router root, not the JSON base already ending in `/api/v1`.
  Translate only this known prefix for explicit local-engine development mode.
- Accept only the configured origin and approved media paths; never send Clerk credentials to a returned arbitrary
  URL or directly to MinIO. Account switches cancel work and prevent late images from entering another cache.
- Cache derivatives with a size limit. Delete pending local upload bytes only after the dependent attachment has
  been acknowledged. Photo removal changes the garment's references; it is not permanent object deletion.

Exit: pick/capture → upload → processed thumbnail/detail image → garment attachment survives relaunch.
Processing failure, upload interruption and a full remote volume all produce actionable states.

### 4. Durable offline behavior and conflicts

Implemented in M4 source: owner/endpoint-scoped atomic garment/outfit form drafts with original baselines
and stable entity IDs, Pending resumption and keep/discard, dependent existing-record/queued-create edits kept locally, fresh
selected-field review/reapply and atomic replacement of known rejected writes. One accepted frozen request per entity
remains the queue rule. Uncertain requests retain their original payload/key and cannot be replaced. Automatic retries
respect a durable 10-second cooldown; manual Retry bypasses it. Photo-source orphan cleanup preserves queued bytes and
skips corrupted manifests. Photo drafts keep normalized original/chosen bytes and reference order in a shared
versioned job manifest (20 drafts / 256 MiB of draft sources); acceptance atomically moves draft intent into the
upload queue. Missing/altered bytes block acceptance, and referenced draft files stay outside orphan cleanup.
Create followups preserve the original body/key/entity; they send nothing until explicit rejected-create replacement
or selected-field review after acknowledgement. Removed creates can be reconciled using the original identity.
Outfit followups keep original state/source. These paths have authored tests; hardware/accessibility checks remain.

- Reuse iOS `DiskCache` for reads; make durable writes report failures instead of silently swallowing `try?` errors.
  On Android use private files and atomic writes for the same small queue and photo staging. Add no database unless
  the actual access pattern needs one. Protect local files using platform defaults and avoid cloud backup of queues
  and photo staging to prevent restored stale work from replaying unexpectedly.
- Persist request identity before dispatch. Once dispatched, freeze the payload and key; retry the same request.
  Refresh the entity after acknowledgement because a replayed original success can contain an older version.
- Keep create → edit/attach → confirm dependencies ordered. Prepare a later request against the acknowledged version
  before its first dispatch; never rewrite an uncertain in-flight request. Refresh before dependent confirmation
  so the user can review changed or archived garments.
- Refresh auth once on 401; pause on persistent auth failure. Back off transient failures with the same key.
  On version conflict fetch current data and offer review/reapply with a new key; never overwrite automatically.
- Preserve undelivered work across termination and offline relaunch. Sign-out stops delivery and clears visible reads;
  durable work remains isolated and resumes only for that same account. Show failed persistence instead of claiming
  a change was saved. A dispatched operation with uncertain outcome must be reconciled before discarding it.

Exit: offline edits and wears survive relaunch, retry without duplicates and cannot leak across accounts.
Confirmed totals remain server-derived while pending work is shown separately.

### 5. Suggestions, insights and finishing

Rule-based suggestions, factual insights, all timeline filters and per-record audit pagination are implemented in
source on both clients. New fixtures/tests are authored, not run. Local request interpretation is M5; actual
screen-reader, keyboard, high-contrast and hardware checks remain deferred until the owner deploys.

- Add optional local interpretation of outfit requests using the intelligence plan's constrained draft flow.
- Connect `wardrobe_suggest`: explicit date, optional occasion/warmth, required/excluded garments and combination
  fingerprints for alternatives. Explain reasons and missing roles; let the owner edit and save the selection.
- Refresh before saving stale suggestions. Use the backend's rule-based results without fabricated weather context
  or AI claims. Manual composition remains available when no suggestion is possible.
- Connect `wardrobe_analyze` for date-filtered factual usage and `history_list` for per-record changes.
- Finish keyboard/focus handling, accessibility, responsive layouts, dark/high-contrast states and destructive-action
  wording. Use archive/void terminology and restore actions; avoid promising permanent deletion.

Exit: both clients cover the full existing wardrobe contract, with no productivity/demo dependency in production.

## Operation coverage

| Surface | Existing operations |
| --- | --- |
| Wardrobe list and detail | `garments_list`, `garments_get` |
| Garment entry, metadata, laundry and lifecycle | `garments_create`, `garments_update`, `garments_archive`, `garments_restore` |
| Today and outfit history reads | `wardrobe_day_get`, `outfits_list`, `outfits_get` |
| Outfit planning and wear corrections | `outfits_create`, `outfits_update`, `outfits_confirm`, `outfits_void`, `outfits_restore` |
| Outfit choices and usage | `wardrobe_suggest`, `wardrobe_analyze` |
| Record change details | `history_list` |
| Photo reservation, status and recovery | `media_prepare`, `media_get`, `media_retry`, binary media PUT/GET |

## Sensei follows a separate contract

After Retro's complete flow, establish Sensei's smallest backend contract for agenda/tasks, goals/habit completion
and daily record. Add its private engine and authenticated `/sensei` router route before calling a native shell complete.
Sensei clients can reuse the extracted Today, Goals, Review and productivity Capture, adapted to real DTOs.
Proposed navigation: Today, Goals and Review, with account in a sheet and focused capture actions.

Create iOS/Android applications with the chosen identifier, their own brand assets, native Clerk registrations and
callbacks, and Sensei-specific URLs/cache roots. Reuse the existing Clerk instance and shared idempotent workspace
onboarding; a completed setup must not be repeated when a second app is installed. Backend writes must define
versions, idempotency and audit behavior before native offline writes are implemented.
Neither app requires the other installed. Cross-app projections are deferred.

## Completion evidence, collected after deployment

During implementation add meaningful shared response fixtures and focused tests for DTO decoding, account isolation,
queue replay/version conflicts and the photo workflow. Run builds/tests and runtime checks after the owner permits
verification following deployment; none is being run for this plan.

Both clients are complete only after the following pass:

- Real new-account and returning-account login; shared onboarding reused; unavailable Retro handled separately.
- CRUD/laundry/archive/restore and manual planning/wear/correction across dates, time zones and multiple daily outfits.
- Lost response, duplicate tap, offline termination/relaunch, dependent writes, conflict review and local storage failure.
- Photo conversion, interrupted upload, processing failure/retry, attachment recovery and authenticated cached images.
- Account switch during a request/upload; no old-account response, photograph or pending write enters the new session.
- Historical names/photos remain intact after inventory edits; void/restore changes statistics correctly.
- Empty/loading/offline states, large text, screen readers, dark/high contrast and reduced motion.
- Installed app flow on the owner's iPhone and an Android device, after build/unit/UI and deployed integration checks.

Optional on-device garment suggestions and cutout previews are now planned in the linked intelligence plan.
External AI tagging, actual weather/calendar integration, widgets, notifications, sharing, virtual try-on,
packing lists and cross-app synchronization remain outside this completion scope. No new dependency or configuration
layer is needed just to connect the existing wardrobe operations.
