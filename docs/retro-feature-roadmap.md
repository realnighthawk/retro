# Retro feature roadmap

Proposed on 2026-10-08. Retro is the active product focus; Sensei implementation follows separately.
This defines first-release and follow-up scope; implementation progress is recorded below. No deployment is performed.
Use this as the product scope, the [client completion plan](client-completion-plan.md) as the implementation sequence,
and the [on-device intelligence plan](on-device-intelligence-plan.md) as the technical/privacy boundary.

## Current implementation

M1 is implemented in source on iOS/Android: real read DTOs, account-bound stores, query/endpoint-scoped caches,
Today/Wardrobe/History navigation, inventory search/filters, paginated inventory/history, date selection and refreshed
garment/outfit details. Existing login/shared onboarding remains. The old combined demo is preserved for Sensei.
Shared wire fixtures and focused tests are authored; no builds/tests/runtime verification or deployment has run for M1.
M2 is also implemented in source on both platforms: garment creation/metadata edits/availability/archive/restore,
outfit composition/planning/direct wears/confirmation/correction/void/restore, and a persistent Pending saves sheet.
Atomic account/endpoint-scoped queues persist payload/UUID keys before sending, serialize delivery and resume on
foreground/reconnect/manual retry. Existing edits freeze their reviewed expected version; successful retries refetch
current reads rather than applying an old cached idempotency response. Label-only worn corrections omit unchanged
items to retain historical snapshots. Rejected requests show intent/current-record comparison; uncertain dispatches
cannot be discarded. Storage failures surface and unreadable files are preserved rather than overwritten.
M2 tests are authored, not run; no build/runtime verification or deployment has occurred.

Current limits: one pending write per record, up to 100 small requests; outfits wait for selected garment writes.
Conflict resolution is explicit comparison/removal of a definitely rejected request followed by a fresh edit, without
auto-merge. Unsaved form drafts, dependent offline composition, richer recovery/conflict UX, history date/garment
filters/audit browsing and full accessibility validation remain M4.

M3 is implemented in source for the installed SDK: both clients select/capture multiple garment photos, normalize
orientation, strip source metadata, export bounded JPEGs, display authenticated cached derivatives, reorder the primary
photo and detach references. Save a garment before managing its photos. Accepted photo batches persist immutable bytes,
reservation IDs/keys, processing retry intent and the eventual frozen attachment. Delivery resumes on foreground,
reconnect or explicit retry; active photo/pending sheets poll in bounded passes. Local bytes are removed only after
attachment acknowledgement. A lost attachment acknowledgement is replayed with the original body/key; changed photo
references pause attachment for explicit review, reusing ready media rather than uploading another copy.

All media paths are built from validated UUIDs under the configured API origin; returned URLs are never used for
authenticated requests. Binary transport rejects redirects and HTTP caches; derivative file caches are account/endpoint
scoped and capped at 64 MiB. Disk/decoding errors preserve jobs instead of silently replacing them.

iOS provides local Vision label OCR and up to six foreground cutout previews, with the normalized original retained
until the owner chooses. Capability-gated Foundation Models text extraction returns reviewed garment fields; selected
suggestions replace only explicitly reviewed fields and never save. No brand/material/warmth/fit/care inference,
cloud fallback or backend AI service is added. Account/source/form checks reject late completions; requests have bounded
input/output and a 20-second UI timeout. OCR remains available without Apple Intelligence.

The installed Foundation Models SDK has no image attachment/prompt declarations. Direct iOS 27 model photo
understanding remains pending a suitable SDK; this implementation never labels text extraction as pixel understanding.
Android has manual core photo parity; Android inference is still a separate later capability decision.
M3 tests/fixtures are authored, the generated iOS project is updated, and no build/test/runtime verification or deployment
has run. M3 initially kept unsubmitted photo-editor inputs ephemeral; M4 now persists prepared originals and selected images. Raw assistant inputs remain ephemeral.
M4 now prunes old interrupted-staging sources only with a readable manifest. Current staging limit is 20 batches, each with up to 10 total garment photos. Source images above 24 MP are
rejected with a manual error rather than decoded at full size. M4 below adds suggestions/insights and broader recovery.

M4 source is implemented; device/accessibility validation is outstanding. It implements A09/A11 and the remaining A10 read surfaces on both clients:
`wardrobe_suggest` preferences, required/excluded pieces, genuine Shuffle fingerprints, incomplete coverage and
fresh garment/version review into the existing composer; date-range `wardrobe_analyze` counts and category usage;
state/date/garment timeline filters and paginated `history_list` change details. Suggestions do not mutate records,
fabricate weather or mark a wear. Analyses distinguish wear days from outfit events, include archived inventory and
explain current-category semantics. Reads retain account/endpoint/query isolation.

A12 now includes atomic private garment/outfit draft files (up to 100 drafts / 4 MiB), original versions, stable create
entity IDs, explicit keep/discard, resumption from Pending saves and visible persistence errors. Existing records and
new queued creates can be edited into local drafts while an accepted save is unresolved. Create followups preserve
the original full body/key and entity without inventing a server version. Keep draft sends nothing; acknowledged
creates use fresh selected-field review. A known rejected create can be explicitly replaced with corrected fields
and a new key. Outfit state/source stay fixed. If a create was removed, Retry original create restores its identical
body/key as conservatively dispatched work; it cannot be removed again until reconciled. After acknowledgement, review/reapply compares the
latest record and requires explicit field selection. Definitively rejected field edits can be replaced in one durable
queue commit using a new key/version; uncertain requests cannot be replaced. Lifecycle/confirm/photo-attachment
requests keep their dedicated review paths. Automatic write replay has a persisted 10-second transient cooldown;
explicit Retry may bypass it while preserving the frozen body/key. Old unqueued JPEG staging files have a one-day
grace period and are pruned on reopen only when the manifest is readable; queued, draft and remote historical media stay intact.

Photo forms persist normalized original/chosen bytes and reference order in a versioned manifest shared with upload
batches (20 drafts / 256 MiB of draft sources). Legacy job arrays still load. Immutable files precede intent commits;
Save moves a draft to its accepted batch in one atomic manifest write. Only then are unchosen originals released;
chosen sources stay until acknowledgement. Relaunch preserves selected file IDs and reservation keys. Damaged or
missing bytes block draft load/acceptance without overwriting intent. Cutout alternatives are regenerated locally;
interrupted raw camera/picker preparation remains transient.

New controls use native semantic text, labelled checkbox rows and minimum touch targets. Shared fixtures and tests
cover exact versions, wire filters/counts, stale suggestions, draft recovery/account guards, corrupt data, atomic
rejected replacement, durable retry cooldown, photo draft/queue handoff, legacy manifests, frozen create followups
and orphan safety. They are authored and **not run**. Remaining M4 work is actual keyboard, screen-reader,
high-contrast and device validation. Raw OCR/model inputs remain transient by design;
accepted garment fields are preserved in the form draft. No builds/tests/deployment were run for this iteration.

## Product shape

Retro helps answer three questions: what do I own, what should I wear, and what did I actually wear?
The first release should let the owner add real clothes, choose an outfit, record it and depend on its history.
On-device assistance makes those actions easier; neither Apple Intelligence nor connectivity is required to read
cached records or compose a draft. Server acknowledgement is required before a pending wear becomes confirmed.

Navigation remains **Today / Wardrobe / History**. Account, assistance availability and pending work live in a toolbar
sheet/settings. Insights live inside History initially; laundry is a Wardrobe filter, not another tab. Add opens a
garment sheet. Outfit composition is a focused flow from Today or a garment detail. Retain Retro's identifier,
icon and Sage & Clay theme. Preserve the productivity source for Sensei, then remove demo content from production.

## Release A: a complete wardrobe with assisted capture

| ID | Feature | Behavior | Existing backend support |
| --- | --- | --- | --- |
| A01 | Account and setup | Clerk login, shared idempotent onboarding, existing-workspace reuse, sign-out/account isolation | Router/onboarding already wired; distinguish engine unavailable from workspace missing |
| A02 | Inventory browsing | Real photo grid, literal name search, category/availability filters, pagination and archive view | `garments_list`, `garments_get` |
| A03 | Garment entry and edits | Name/category required; optional subtype, colours, warmth, season, formality, material, brand, notes and favourite | `garments_create`, `garments_update` |
| A04 | Private photos | Camera/picker, several photos per garment, primary-photo ordering, replacement/detachment, processing status/retry | Up to 10 ordered media IDs; `media_prepare`, `media_get`, `media_retry`, authenticated binary PUT/GET |
| A05 | Assisted capture | Editable photo/text-derived details, label OCR, optional subject cutout/colour hints | Native preprocessing; accepted fields use A03/A04; no new inference endpoint |
| A06 | Availability and archive | Explicit ready/needs wash/washing/unavailable, archive/restore, visible exclusion from suggestions | `garments_update`, `garments_archive`, `garments_restore` |
| A07 | Outfit composition | Multiple layers/accessories, one-piece or top/bottom, garment roles, label/occasion/notes | `outfits_create`, `outfits_update`; 1–30 unique garment IDs |
| A08 | Date planning and wear | Save a plan for a date; review and confirm actual pieces; direct historical wear; several outfits per day | `wardrobe_day_get`, `outfits_confirm`, `outfits_create`; saved local date/IANA time zone |
| A09 | Outfit suggestions | Up to three eligible choices, optional occasion/warmth, anchor/exclude pieces, real alternatives and incomplete-coverage reasons | `wardrobe_suggest`; no fabricated weather |
| A10 | History and correction | Date-grouped timeline, date/state/garment filters, snapshot detail, audited corrections, void/restore | `outfits_list`, `outfits_get`, `outfits_update`, `outfits_void`, `outfits_restore`, `history_list` |
| A11 | Factual insights | Days worn, outfit events, last worn, date-range usage, unworn pieces and category totals | Garment wear statistics and `wardrobe_analyze` |
| A12 | Durable native behavior | Cached reads, persistent drafts/writes/photos, retries, conflict review, pending status, accessible states | Existing idempotency/version contract; native queue/cache work remains |

These features cover all 20 current operations. Full first-release behavior is planned on iOS and Android;
Apple-specific capture assistance is optional on supported iPhones. No extra business engine is needed for Release A.

### Capture flow

1. Choose a photo or start a manual garment. Name/category are the only required inventory facts.
2. Optionally suggest visible details, scan a label or preview a cutout. Unclear fields stay empty; user edits win.
3. Review/save the garment independently of analysis. A garment can exist while its optional photo is pending.
4. Export the chosen image, remove source metadata and enforce the existing size/pixel limits; compute its checksum
   after final editing. Reserve/upload immutable bytes and attach only ready media through a versioned edit.

Photo understanding suggests name/category/subtype/observed colours and a short description. Brand/material require
readable label evidence or owner input; warmth, fit, authenticity and care rules are not established by appearance.
Label scans stay local unless deliberately attached. Cutout previews retain the original locally until selection;
upload the chosen image only, composited for the backend's opaque JPEG derivatives. Avoid doubling the 10 GB budget.
Removing a photo reference does not erase old outfit snapshots or promise permanent storage deletion.

### Daily use and correction

Today shows the selected date's plans and wears. Suggestions remain unsaved until accepted; accepting one does not
record wear. An owner can change pieces before confirmation, record another outfit later, or record a past incomplete
outfit. Future dates can be planned, never recorded worn. Show current availability warnings without rewriting history.

Garment detail shows current facts and usage. Worn-outfit detail renders saved names/photos, even after inventory
rename, photo replacement or archive. Correction is explicit and audited. Void removes a wear from statistics;
restore reinstates its previous state. Plans and queued writes never inflate confirmed counters.

### First-release states and controls

- Explicit loading, no records, no search matches, cached/offline, unsent, processing, failed, conflict and unavailable-service
  states. Show the useful action for each; never substitute demo clothes for missing data.
- Pending work view supports retry and conflict review. Uncertain dispatched writes must be reconciled before discard;
  removing a local pending card is not proof the server never received it.
- Refresh, filters and pagination must not overwrite edits or mix queries. Account switch cancels jobs and rejects late
  network/model/image completions. Queues, drafts and photos remain account-bound across relaunch.
- Dynamic Type/font scaling, VoiceOver/TalkBack, 44 pt / 48 dp targets, dark/high contrast and reduced motion are release
  requirements. Accessible garment names/status remain useful without a photograph.

## Release B: the full initial set of intelligent follow-ups

This release includes the follow-ups previously discussed, rather than leaving them as an unspecified backlog.

| ID | Feature | Owner experience | Dependency / limit |
| --- | --- | --- | --- |
| B01 | Natural-language outfit requests | “Warm dinner outfit with the blue shirt” becomes reviewed constraints and real candidate outfits | Resolve garment ambiguity; `wardrobe_suggest` accepts occasion/warmth/required/excluded IDs |
| B02 | Voice wardrobe capture | Speak a garment description or outfit request, review transcript and fields | Local speech availability/assets; normal typed fallback and save queue |
| B03 | Natural-language wardrobe search | “Show ready jackets” becomes visible filter chips; richer requests explain supported/unsupported predicates | Current server search is name-only plus category/availability/archive; metadata search needs a later contract extension or a clearly complete local inventory |
| B04 | Candidate comparison and explanation | Ask why a supplied outfit fits the stated occasion, or choose among actual returned options | Restrict output to supplied IDs/fingerprints and facts; do not claim image-derived styling truth on text-only models |
| B05 | Possible duplicate warning | When adding a photo, see visually similar existing items and choose “Use existing” or “Create another” | On-device image similarity; refresh current garment before attaching; never auto-merge |
| B06 | Source-linked wardrobe review | Short selected-period summary of what was worn and unused, linking to underlying records | `wardrobe_analyze` + snapshots; deterministic counts; no invented causal explanations |
| B07 | Reuse a past outfit | Open a historical outfit, create a new reviewed plan for another date, replace archived/unavailable pieces | Existing create/list/get operations; preserve the original record, assign a new UUID/key |
| B08 | Guided multi-item entry | Select several garment photos, review one garment at a time, pause/resume import | Per-item draft/queue and existing operations; no all-or-nothing bulk API or automatic split of one crowded photo |
| B09 | Siri/Shortcuts entry points | Open Add Garment, search wardrobe or open today's outfits; reviewed wear action later | App Intents reuse auth/stores; sign-in/unlock and explicit confirmation; no duplicate mutation path |

B01/B04 interpret and explain engine-supplied candidates; the engine continues eligibility and rule-based selection.
The assistant must show unhandled conditions such as waterproofing when the contract has no such attribute.
No open-ended chat transcript, vector service or cloud model fallback is needed.

B05 compares available local thumbnails; missing photos reduce coverage and must not be presented as exhaustive checking.
Model/feature-print revisions invalidate derived local results. B06 describes correlation and inventory facts without
claims about personality, body shape or why an item went unworn.

B08 uses bounded local work and normal per-item idempotency. Partial completion and failed uploads stay visible.
Repeated analysis may change a draft, but retrying a dispatched save must reuse its frozen payload/key.

## Release C: optional context and preference features

These are planned follow-ups with named dependencies, not hidden requirements for finishing A/B.

| ID | Feature | Proposed behavior | Contract/service change needed |
| --- | --- | --- | --- |
| C01 | Comfort/style feedback | Explicit “too warm”, “comfortable”, “liked this combination” on an outfit | Versioned feedback record/operation; notes suffice until a structured feedback contract is designed |
| C02 | Personal preference ranking | Use explicit preferences and feedback to rank eligible outfits | Small preference schema and explainable scoring; no learning from merely skipping or viewing |
| C03 | Weather-aware requests | Chosen location + fresh forecast informs warmth/context, with manual override | Optional weather service and context provenance; no forecast invented by the model |
| C04 | Calendar occasion hints | Owner chooses an event to prefill date/occasion | Narrow calendar permission; no bulk private calendar/journal ingestion or Sensei dependency |
| C05 | Detailed laundry history | Record wash events and inspect them separately from current availability | Dated wash record and idempotent operations; wearing never automatically marks dirty |
| C06 | Packing lists | Dates/occasions and available clothes yield a reviewed checklist with missing coverage | Durable packing-list records if syncing is wanted; packing does not create confirmed wears |
| C07 | Widgets and optional reminders | Today's selected outfit and explicit recording/laundry reminders | Platform surfaces, notification permission, privacy display choices and clear pending states |

For C03, [WeatherKit](https://developer.apple.com/weatherkit/) is an Apple-service option, not on-device weather generation.
Its network/setup/attribution requirements need their own decision; Android needs an appropriate access path too.
Store source, forecast time/freshness and chosen location precision if context becomes authoritative.
For C04, keep event-derived context limited to what the owner selected; Retro stays independently usable.

C02 starts with deterministic feedback/preferences, optionally explained locally. A model's self-reported confidence
is not evidence that feedback is accurate or that a recommendation will be comfortable.

## Longer-term product choices

| Feature | Why it is separate | Minimum prerequisite |
| --- | --- | --- |
| Export/import and recovery | Current paginated reads are not a consistent export or backup contract | Versioned export/import, media/audit references and safe repeat import; coordinated DB/object backup |
| Storage usage and reclaim | Unreferenced upload sources are retained today; no quota/cleanup API exists | Actual usage reporting, lease/reference-aware cleanup and retention policy; preserve historical photo references |
| Purchase price / cost per wear | No currency/purchase record is currently modeled | Explicit amount/currency semantics and factual confirmed-wear denominator |
| Outfit sharing | Current photos are private/authenticated | Owner-triggered export with chosen content; public links need separate expiry/access design |
| Virtual try-on / generated styling images | Distinct model-quality, privacy and compute problem | Explicit feasibility evaluation; never substitute generated images for wardrobe/history facts |

No storage increase is planned: MinIO remains **10 GB** with the existing minimal-resource setup. Do not silently
expand the PVC, retain every alternate photo edit remotely or enable cleanup that can destroy historical images.
Custom models/fine-tuning, automated garment recognition across an entire photo library and autonomous wardrobe mutations
are outside A/B. Evaluate them only if the local platform features demonstrably cannot meet a real task.

## Platform and intelligence boundaries

Keep iOS 17 manual support and full core Android behavior. Gate Apple assistance by actual capability:

- Vision supports local OCR/masking independently of Apple Intelligence availability.
- Foundation Models text helpers use an eligible iOS 26+ device with Apple Intelligence enabled and model/language ready.
- Direct Foundation Models photo understanding uses the iOS 27 image-capable API/model. Apple's
  [framework updates](https://developer.apple.com/documentation/updates/foundationmodels) describe this addition.
- Local speech has separate device/locale/asset checks; never silently switch to server recognition.
- App Intents integrate system actions; [Apple's guide](https://developer.apple.com/documentation/appintents/getting-started-with-the-app-intents-framework)
  describes their role. Siri's processing is outside our app-local inference guarantee.

Raw prompts, discarded alternatives, label scans and voice audio stay local by default. Accepted garment facts/photos
follow the existing router/MinIO sync. Explicitly use the on-device system model; no Private Cloud Compute/third-party
fallback. Models return typed drafts, never credentials, final write identities, arbitrary tool calls or saved truth.
Generation is foreground, bounded and cancellable; refusal or not-ready state never blocks manual capture.

Android assistance is a later local-capability decision. No Apple-only backend dependency, new universal inference
interface or cloud service is introduced solely to make assistance identical across devices.

## Implementation sequence and exit criteria

| Milestone | Scope | Exit condition |
| --- | --- | --- |
| M1 | A01/A02, real DTOs/stores, three-tab shell and read cache | Real account sees real inventory/day/history; no production demo dependency |
| M2 | A03/A06/A07/A08/A10 plus minimal reliable A12 queue | Add garment → plan → record wear → history → correct/void/restore, durable request identity |
| M3 | A04/A05 | Photo capture/processing/attachment resumes safely; optional local suggestions never replace user edits |
| M4 | Complete A09/A11/A12 and accessibility | All existing operations covered; offline restart, conflicts and account switching preserve data |
| M5 | B01–B04/B07 | Typed/voice interpretation/search and outfit reuse produce valid reviewed operations |
| M6 | B05/B06/B08/B09 | Duplicate hints, review summaries, resumable entry and system actions respect source/privacy rules |
| M7+ | C features individually, after explicit scope selection | Add required contracts and native flows together; no placeholder feature claimed complete |

Build iOS first per milestone, then Android core parity before the next. Apple helpers remain optional platform work;
Android is not blocked on matching the same inference. Reliability is required from the first saved write, not postponed
until an end-of-project polish stage. No speculative schedule estimates until real integration effort is known.

Later verification, following the owner's deployment/permission, covers real login/shared onboarding, manual flows,
multiple outfits/local dates, snapshots after archive/photo replacement, idempotent lost-response retries, offline
termination/relaunch, account-switch late results, media failure/retry, conflict review and accessible UI.
Intelligence checks cover model absence, poor/ambiguous images, unsupported requests, injection text, stale drafts,
cancel/refusal/overflow and actual hardware latency/energy. Airplane-mode inference needs assets already installed;
network sync remains separately pending.

Release A is complete only when the first garment → outfit → confirmed history loop is dependable on both clients.
Release B is complete only when every helper has manual fallback and uses the same guarded data path.
