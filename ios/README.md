# Retro for iOS

SwiftUI (iOS 17+) client for the `/retro` engine.

P1 source adds Wardrobe settings in the toolbar, editable machine presets, care instructions from garment detail
and feedback from outfit detail. Saves use the existing durable queue and selected-field conflict recovery.
On supported iOS 26 devices, on-device typed proposals and read-only source-linked tools assist these forms;
care proposals always require review/confirmation. Manual editing remains available. P1 builds/tests/deployment
are deferred; see the [phase checklist](../docs/retro-implementation-phases.md) and [agent boundary](../docs/retro-agent-contract.md).

Today → **Ask Retro** now runs Apple's native tool loop with fresh wardrobe preferences and optional `ask_agent`
delegation through `/gateway/mcp`. Connected help defaults off; **Ask connected agent** is an explicit alternative
on any supported iOS device. The app owns UUIDs/auth/polling, full native owner prompts, durable answers/stop intents
and account/generation fences. Attempts have a 90-second deadline and bounded calls/context. Reopening checks the
same remote job instead of regenerating it. Stop remains pending until confirmed. The gateway uses its existing
agent permissions; generic advice is not a wardrobe save or verified specialist fact. This completes P1.4 in source;
P2.1 daily ranking, P2.4 outfit-context retrieval and P2.5 daily automation are now in source. `WardrobeAgentTests` is authored, unrun.

P2.1 adds **Outfit choices** on Today, loaded automatically for the selected local date and refreshed on return,
day changes, saves and pull-to-refresh. Choices use stored preferences and explicit rated wears, with source version,
generation time, reasons, missing coverage and cached/error states. Review rechecks current ranking constraints and
garment versions, then opens the usual unsaved plan editor. Individual swaps replace the same role while keeping
the other pieces fixed; Suggestions adds lock/unlock and clear controls. Refresh never rewrites an existing plan or
records a wear. Rule/contract/review tests and `ranked-suggestions.json` are authored; runtime validation is deferred.

P2.2 adds **Selected for this day**: save a plan, then choose it from Today after fresh selection/outfit review.
Generated choices refresh independently. Selection survives explicit wear confirmation; moved/voided/unavailable
plans show a review message. Clear retains the outfit and its history. Choice requests use the existing durable
queue and have an explicit conflict review in Pending saves.

**Saved pairings and looks** is available from Wardrobe; garment detail offers **What goes with this?**. Save/edit
combinations of 2–30 real pieces, set manual roles, archive/restore, or start from an outfit's pieces. Review as a new
plan refreshes the pairing version and each current garment before opening the ordinary plan editor. Unavailable
pieces require replacement or manual composition. Unsaved pairing forms stay in memory with discard confirmation;
accepted saves are durable. The new engine migration/operations must be deployed for these flows. Focused native
tests and pairing/selected-day fixtures are authored, unrun; no native build or deployment was performed for P2.2.

P2.3 adds **Help me choose or swap on this device** to Today/Suggestions and local help in refreshed Compare.
On supported iOS 26 devices, Apple's model reads fresh engine choices with scoped aliases, versions, locks, scores
and bounded reasons. It can explain/select a real option or propose a specific unlocked piece to swap. Native UI
shows complete engine evidence separately from model commentary and requires review/acknowledgement of unsupported
conditions. Plan review opens the ordinary unsaved editor; swap review preserves constraints and opens Suggestions.
No model response saves a plan, records a wear or alters pairings. Optional connected help reuses the existing MCP
controller/journal and native owner questions; generic prose does not establish weather/calendar facts. Manual Compare,
Describe an outfit and per-piece swaps remain available. `WardrobeCandidateTests` is authored, unrun. XcodeGen was
run; native builds, device/model evaluation and deployment remain deferred.

P2.4 adds **Retrieve connected context** inside Outfit help. Enable connected help, enter a weather location, and
retrieve bounded weather/calendar/travel values for the selected date and captured time zone. The gateway agent
discovers available connections; native code resolves fields from actual provider-result pointers, checking units,
dates, source identities and freshness. Review displays accepted facts, source details/pointers, provider time zones,
coverage and expiry. Missing connections or unsupported/stale evidence leave manual controls available. Travel entries
are agent-selected context and do not establish bookings; empty lists do not establish an empty calendar. Forecast
issue time is optional, with unknown provider cache age disclosed when absent.

Retrieval and manual warmth/occasion adjustments work without Apple Intelligence. On supported devices, Apple's
`read_outfit_context` tool consumes bounded facts and can propose sourced adjustments. Review refreshes engine
choices, retains the existing locks/exclusions and opens Suggestions with the reviewed warmth or occasion. Fresh
native context is reused by the model without another remote task. Saved pending context requests resume their
original IDs; owner input and stop/recovery use the existing journal. Connected requests ask for reads only and use
the gateway's existing permissions, rather than a separate server-enforced read-only grant.

Deploy gateway 1.1 and this client together: context needs its bounded `server`/`tool` provenance, 4096-byte sources
and 32 KiB envelopes. P2.4 adds no provider SDK, new URL setting or engine operation. Broader automatic weather
selection remains open. `WardrobeOutfitContextTests` and `outfit-context.json` are
authored; XcodeGen includes the new files. Tests, native/gateway builds, live connection/model evaluation and
deployment remain deferred.

P2.5 adds Today → **Daily automation**. Save enabled/mode, local hour/minute, fixed IANA time zone and an optional
connected-service recipient using the ordinary durable queue. Then explicitly apply/pause the saved schedule or
check it through the connected agent. Saving alone changes desired settings. Native status uses actual fresh
Temporal inspect evidence for the one user-scoped `retro-daily-outfits` wake; prose is not confirmation. Disabled
settings accept a paused wake or explicit not-found evidence. Interrupted apply attempts can leave a schedule
active; original task recovery, native owner questions, check/pause and Pending saves remain available.

The existing agent can generate while the phone sleeps. The engine caches one ranked snapshot per date/zone in a
two-hour configured window, checks the settings version and expires it at the following local midnight. Today
shows scheduled choices separately from fresh choices. Review refreshes eligibility/preferences and garments
before opening an unsaved plan; it never changes your selected plan or wear history. Time zones stay fixed until
edited, DST uses calendar dates, and a nonexistent scheduled time can skip that day's firing.

Empty recipient means generation only. Optional delivery uses a discovered connected service and one authorized
engine reservation. Replays never grant another attempt; uncertain outcomes remain visible and are never
automatically resent. A stored delivery receipt is agent-recorded, not provider-verified. Provider-specific retries
still need idempotency support; iPhone push/APNs is not configured. This surface works without Apple Intelligence;
interactive interpretation/explanation continues to use the local Apple model where available.

Deploy the updated harness worker, engine/migration 0006 and this client together, with gateway 1.1 provenance.
`WardrobeDailyAutomationTests` and `daily-automation.json` are authored; XcodeGen includes the new files. Tests,
native builds, live schedules/senders, migrations and deployment remain deferred.

P3.1 adds Wardrobe → **Laundry loads** and garment detail → **Wash history and loads**. Choose an explicit machine,
hand-wash or dry-clean programme, or copy an existing machine preset, then **Review compatible groups**. The engine
checks confirmed care and separates colour groups/Wash separately items. Unknown or incompatible items retain a
reason and access to the existing care editor/local helper. Select 1–30 current pieces from one group and save an
editable dated plan; saving does not start washing. Presets with Unknown drying need an explicit choice.

Load detail confirms start, wash finished/begin drying and dry/ready separately. Garments stay unavailable through
drying; professional care completes on returned-clean confirmation. Active garment edits/photo attachment/archive
are blocked until completion/cancel. Cancel keeps history and returns active pieces to Needs wash. Actual server
timestamps and retained garment/care snapshots are separate from wear history. No automatic dirtiness or machine
capacity assumption is added. Pending saves replays original keys/bodies and reviews rejected plans against current
load/group sources; rejected progress opens current state for inspection. Unsaved forms stay in memory with discard
confirmation; accepted saves are durable. Manual behaviour works without Apple Intelligence.

Deploy the engine/migration 0007 and this client together. `WardrobeLaundryTests` and the synthetic `laundry.json`
are authored; XcodeGen includes the new files. Suites, native builds, migration execution, device/runtime checks
and deployment remain deferred.

P3.2 adds **Plan a load → Describe a laundry programme** with typed requests or the existing reviewed on-device speech
input. Apple guided generation proposes explicit programme changes and short request excerpts. Numeric temperatures
need Celsius units; vague cold/warm/hot and other units need manual choices. Explicitly named unique presets copy
their actual native values; used presets are refreshed/version-checked before applying. Select fields and acknowledge
unsupported conditions. Applying updates the form, invalidates groups and never chooses pieces, saves or starts a load.
Incomplete settings remain visible until manually completed. Existing compatibility/version/queue rules still apply.

**Care instructions → Scan a care-label photo** uses local Vision OCR without Apple Intelligence. Review/correct text
before replacing label evidence; the photo is not uploaded. Applying sets source Label and clears care confirmation,
leaving other facts unchanged. Existing local care drafting then extracts text-supported changes; numeric temperature
drafts require explicit Celsius units. Symbols, uncertain instructions and other units require manual review.
Language drafts use the existing eligible iOS 26/device/model/locale gate; manual controls and OCR still work without it.
Requests use no agent or Private Cloud Compute. Cancellation/timeouts and account/form/source checks prevent late applies.
`WardrobeLaundryAssistanceTests` reuse the preferences fixture and cover evidence, preset sources, partial programmes
and reviewed OCR handoff. Tests, native builds, real model/OCR/device checks and deployment are unrun. The backend
P3.2 adds no operation, migration or configuration.

P3.3 adds **Wardrobe → Laundry check-in**, also linked from laundry loads and garment detail → **Wears since cleaning
and reminders**. The complete active-wardrobe read supports up to 2000 pieces; a garment-specific read retains
archived history. It shows the latest completed dry/clean return, definite later wear days/records, separate
same-day timing-unclear records and calendar age in the displayed IANA time zone. Missing cleaning baselines remain
unknown. Corrected/void/restored wear history updates the derived count; cancelled/unfinished loads never reset it.

**Review reminder thresholds** opts a garment in to distinct wear-day and/or calendar-day care review. The first
threshold reached prompts an in-app review. Same-day uncertain wears do not advance wear thresholds; washing or
archived pieces pause reminders. Turning reminders off clears only the optional preference. Check-ins refresh on
foreground/day/clock changes and acknowledgements; cached reads retain their assessed timestamp. No background
notification is scheduled and no reminder changes availability or means proven dirtiness. Links open care, actual
availability and retained load history. Saving thresholds reuses the ordinary frozen garment queue, versions/audit
and rejected-field recovery; unsaved forms stay in memory with discard protection.

`WardrobeLaundryCheckInTests` and `laundry-check-in.json` cover nullable baselines, exact 64-bit sources, due/paused
invariants, calendar age, opt-in/clear and lost-acknowledgement replay. Tests, native builds, real runtime/device
checks and deployment remain deferred. The backend now has 46 operations and migration 0008 adds one existing-table
lookup index; deploy engine/migrations and iOS together. P3.4 below adds reviewed timing/batches.

P3.4 adds **Plan a load → Review compatible groups → Plan batches around upcoming outfits**. Choose a need-by date
within 14 local calendar dates. The programme/time zone remain those reviewed in the form. Fresh existing preview/
outfit reads feed eight compatible pieces and four earliest same-zone plans from one 20-plan page. Coverage shows
partial pages, omitted pieces/plans, other-zone plans and blocked care. Existing laundry plans, machine capacity
and wash/dry durations are not assessed; the ordinary complete manual group editor remains available.

**Plan on this device** uses Apple's model with a native read tool, optional generic MCP `ask_agent` delegation and
the existing source-pointer connected context adapter for the need-by day. **Ask connected planner** works without
Apple Intelligence and returns schema-bound proposals through the same durable agent journal. Both use exact native
source bindings/aliases, preserve the owner request, bound queries and reject mixed groups, unsupported pieces,
repeated pieces, scope changes and missing provider evidence. Same unchanged sources/request text reuse saved agent
tasks; generic remote permissions remain those configured on the agent. No Private Cloud Compute is used.

Review a single proposed batch, acknowledge unresolved conditions and refresh its sources before applying it to the
load form. Application does not save, start or claim garments will be dry by a need. Changed sources, pending writes,
cached/stale data, account/form edits or midnight block application. Existing queue, frozen request identity and
rejected-load recovery handle the subsequent save. Other batches are not saved automatically. Background/dismissal/
edits cancel local work and retain remote stop intent. The existing bounded loop and owner-question UI are reused.

`WardrobeLaundryPlanningTests` and `laundry-planning.json` are authored, unrun. Xcode project generation includes the
new files. On 2026-10-09, the owner's device deployment request built the signed Debug app with P1–P3.4, installed
it on the connected iPhone 17 Pro and launched `org.nighthawklabs.retro`; the running Retro process was confirmed.
Build fixes renamed the settings assistance view file to avoid a duplicate filename, renamed the empty-state view
to distinguish it from the API input, split an outfit row expression and added the laundry timestamp view return type.
Suites, backend integration, actual model/agent flows and full device/accessibility checks remain unrun. No new engine
operation, migration, gateway/router/chart value or storage allocation is needed; the registry remains 46.

P4.1 is implemented in engine/iOS source on 2026-10-09. Garment records carry optional pattern, style, owner-supplied
fit and one purchase record: an ISO-date, a source (`manual`, `receipt` or `connected`) with required bounded evidence
for the latter two, an optional ISO 4217 currency and an exact integer amount in that currency's minor units. The
engine derives the currency exponent from a small table (default two decimals), parses the typed major-unit amount
without floating point and rejects precision the currency does not have; it never converts, totals or infers a
currency. A missing amount stays unknown and a recorded zero stays zero. `Edit garment` adds the three description
fields and a purchase section; leaving every purchase field empty records no purchase. Amounts are typed with the
currency the record already has, so Android and agent callers keep their existing wire compatibility.

Money appears only where a record states it. `WardrobeGarment.purchase` decodes as nil for every older response, and
pattern/style/fit/purchase are optional in saved drafts so drafts written before P4.1 still open. Patches omit
unchanged values and `null` clears the whole purchase record; selected-field recovery can reapply or clear it
individually. Historical outfit snapshots keep the metadata and purchase facts confirmed at the time. `garments_create`
and `garments_update` remain the only operations; the registry stays 46 with no migration (attributes are JSONB),
gateway/router change or storage allocation. `WardrobeGarmentRecordTests` and `garment-records.json` are authored.
Go formatting and the focused engine unit tests ran; OpenAPI and Xcode project generation completed and the simulator
app and test targets compiled. Swift suite runs, integration/migration execution, device builds and live flows remain
deferred, so these checks are authored rather than verified.

P4.2 is implemented in engine/iOS source on 2026-10-09. `Wardrobe` filters inventory by name, brand and notes
substrings, colour and season (whole recorded values), category, availability, favourite, confirmed wash method,
care reviewed/unreviewed and archive state, and sorts by default order, name, recently updated or newest first. The
list is paged by a keyset cursor carrying the last record's sort key and ID, so equal sort values neither repeat nor
skip, and the cursor is bound to the exact filter and sort request: changing either is rejected instead of returning
a mixed page. The response adds `total_matches`, counted in the same read as the page, and the screen shows how many
of how many are displayed — never "all garments" for a cached page.

`Describe a search` interprets the same filters on device and shows them as editable controls; anything the engine
cannot search stays listed as not applied. Colours and seasons are matched only as complete recorded values, and the
model is told to copy them verbatim instead of translating them. Manual search, filters and sorting work without the
model, and no connected search adapter was added. `WardrobeSearchTests` and the engine search/paging integration test
are authored; focused engine unit tests ran and both simulator targets compiled, with suite runs, integration
execution and device flows still deferred.

P4.3 is implemented in engine/iOS source on 2026-10-09. **History → Wardrobe review** now shows the most and least
worn garments for the period, the garments with no confirmed wear in it, the ones that have never been worn at all,
the recorded colour distribution, recent weekly buckets and the explicit feedback and saved-selection counts, each
linked to the ordinary garment record it came from. Only a confirmed wear counts as a wear; plans, saved choices,
opened records and ratings are counted separately and never as wears. Cost per wear is shown per garment from its
own recorded amount and confirmed-wear count, with no cross-currency total and no figure at all when the price or
the wears are unknown.

The summary states the figures and discloses every cap ("only the 50 longest-owned of 71 are listed"), and refuses
a response whose totals disagree — category, unworn, ranked, rating-bucket and cost-per-wear denominators are all
cross-checked before anything is explained. **Explain this review on device** sends only that validated sentence to
the on-device model, which is told to add no causes, garments or coverage; it is labelled as commentary and the
figures remain readable without it. `WardrobeUsageReviewTests`, the engine analytics integration test and
`usage-review.json` are authored; focused engine unit tests ran and both simulator targets compiled, while suite
runs, integration execution, device builds and live model/agent flows remain deferred.

P4.4 is implemented in iOS source on 2026-10-09. **Add from photos → Review photo → Check the whole wardrobe for
similar items** now indexes the complete active inventory (paged through `garments_list` up to 2000 garments, using
the engine's match count to know whether the walk was complete) instead of checking one cached page. It compares
cached thumbnails first and then up to 120 fetched ones, and it says exactly what it covered: how many photos were
compared, how many garments have no photo, how many were not checked, and when the index itself was cut short.

Each hint is bound to the selected photo's exact bytes by checksum and to the pinned Vision revision; applying one
re-reads the garment and requires the same version and primary photo before offering the ordinary "use this
existing garment" confirmation, which only replaces unsaved new-garment details. A cancelled scan, an account
switch, a finished draft or changed photo bytes cannot apply a stale hint. Nothing is merged or deleted, and no
direct model image path is added.

**Capture assistance** now extracts brand, material, pattern, style, fit and seasons as well as name, category,
subtype, colours and notes, but only from the owner's own description or a scanned label. Each value the text does
not actually contain is dropped and listed as "not proposed", so an invented brand or material cannot reach the
form; multi-word values must appear in the supplied words. Warmth, price, care, authenticity and laundry state are
still never proposed. Applying a suggestion replaces only the fields the owner selects. `WardrobeDuplicateTests`
and the extended assistance tests are authored; Xcode project generation and the simulator app/test compiles ran,
while Swift suite runs, device checks and live flows remain deferred.

P4.5 (local half) is implemented in iOS source on 2026-10-09. The garment form's purchase section adds **Read a
receipt or price label**: a scanned receipt (local Vision text recognition, nothing uploaded) or typed text is read
on device for the date, final total, currency and merchant only. Every figure is then checked against that text —
`1,234.56` normalizes to `1234.56` while `1,50` and a bare `12,345` are refused, a currency must be stated as a code
or an unambiguous name (`$` alone is reported as "choose it yourself"), and an all-numeric `03/02/2026` is never
converted. Dropped values are listed. Applying fills only the purchase record — with `receipt` as the source and the
reviewed text as its evidence — and never saves; the ordinary garment save still owns persistence, and re-applying
the same receipt changes nothing. Manual purchase entry is unchanged.

The connected half (reading real purchase records through an agent connection) is **not** built: the harness was
inspected for a purchase/order/receipt tool and none exists, so an adapter would have to invent its result schema.
That stays open until a real connection exposes purchase records. `WardrobeReceiptTests` is authored; Xcode project
generation and the simulator app/test compiles ran, while Swift suite runs, device/model checks and live flows
remain deferred.

P4.6 is implemented in iOS source on 2026-10-09. Wardrobe → **Maintain several garments** selects garments
explicitly (paged, filterable, each row showing either its state or why the chosen action cannot apply) and offers
mark available, mark needs wash, add/remove favourite, archive and restore. Review shows every garment with its
exact version before anything is queued, archiving is confirmed, and items that are already in that state, archived,
or already pending are excluded with a reason instead of written as no-ops. The batch writes nothing itself: it
hands one frozen request per garment to the existing durable queue, so one-pending-write-per-entity, its 100-item
budget, retry/rejection rules and account fence all still apply. Outcomes are per garment — waiting, sending,
retrying, refused with the engine's message, saved, or no longer pending — and a queued item is never shown as
saved. Re-running the same selection is refused per item rather than duplicating intents, and relaunching keeps
refused items with their original identities. Rotation, background image processing and reanalysis are not included
because the capabilities do not exist yet (immutable derivatives, background scheduling, no feature-print index).
`WardrobeBatchTests` is authored; Xcode project generation and the simulator app/test compiles ran, while Swift
suite runs, device checks and live flows remain deferred.

Language tasks are declared once and can run on either reader (2026-10-10). `WardrobeLanguageTasks` holds each
task's instructions, answer contract, on-device reader, connected parser and a single shared validator;
`WardrobeLanguageDispatcher` picks between them. Raw captures can never be delegated — the dispatcher refuses that
by data class, so the local-only rule is enforced in code. **Describe a search / outfit** now offers an opt-in
connected reading whenever the device itself cannot read the request: only the owner's typed text is sent, the
reply is held to the same validator, the existing journal/90-second/two-delegation bounds apply, and the screen says
which reader answered. Garment extraction runs through the same seam on device; its connected opt-in is not wired
yet. See [language tasks](../docs/retro-language-tasks.md). `WardrobeLanguageTaskTests` is authored and unrun.

N05 temperature is implemented in engine/iOS source on 2026-10-10. Suggestions accept an optional temperature in
Celsius: it is banded against your saved cold/hot thresholds, and each garment's **recorded** warmth is scored
against that band at the sensitivity you saved (low/normal/high). A garment with no warmth tag stays neutral and is
never treated as the wrong layer — the response says how many such garments there are — and the reason on a scored
garment names both the value and the band. No temperature means no temperature term and an explicit warning, so a
reading is never implied. Rain or snow can be reported: it is disclosed as unassessable rather than filtered,
because no garment records water resistance.

On screen: a °C field beside the warmth picker with a **Use the reviewed forecast** button that fills the midpoint
of the forecast you already retrieved, a rain toggle, and a note explaining what a temperature does and does not
affect. Nothing is fetched or applied on its own. `WardrobeRankingTests` and the engine tests are authored; every
check remains unrun and the temperature integration test is unrun without a disposable database.

Retro now opens a wardrobe-only shell: **Today / Wardrobe / History**, account-bound to the existing login.
The combined demo is preserved in `ProductivityDemoShell` for **Sensei**. The signed M6 app build/install/launch succeeded on the connected iPhone 17 Pro on 2026-10-08 and its running process was confirmed; new tests remain unrun.
See [the engine design](../docs/wardrobe-engine-design.md) and [the extraction plan](../docs/sensei.md).

```sh
brew install xcodegen          # once
cd ios && xcodegen generate    # the .xcodeproj is generated, not committed
open Retro.xcodeproj           # or: xcodebuild -scheme Retro -destination 'id=<device>' test
```

Router address and Clerk publishable key live in `project.yml` (the publishable key is public by design). The
`.xcodeproj` and the generated `Info.plist` are gitignored; `project.yml` is the project.

## What it does

Reads real inventory, dated outfits and paginated history through the existing `Engine`; garment/outfit details refresh
from get operations. Name/category/availability and archive filters use the backend contract. Query-scoped caches are
isolated by account and engine endpoint; failed refreshes preserve previously loaded data. Empty responses stay empty.
The second increment adds manual garment creation/edits/availability/archive/restore, outfit planning/direct wears,
confirmation, correction/void/restore, and Pending saves. Requests are saved atomically with UUID retry keys and
64-bit expected versions before delivery. Delivery is serialized and resumed on foreground/reconnect/retry.
Rejected writes can be compared with the current record; uncertain dispatched writes cannot be discarded.
One pending write per entity is allowed; an unconfirmed garment cannot be used in another queued outfit.
Unchanged worn-outfit pieces are omitted from correction patches so label edits preserve their snapshots.

## Photos and capture assistance

Save a garment, then open **Manage photos** from detail. Pick/capture, review originals or local foreground cutouts,
reorder, choose a primary photo and save. Accepted bytes/keys persist before reservation/upload; processing/attachment
resume after relaunch, foreground/reconnect or retry. Pending saves shows photo jobs and processing retry. Changed
references require attachment review; ready media is reused. Local bytes remain until attachment acknowledgement.
Images load through authenticated, redirect-free `/retro` requests; account/endpoint caches are capped at 64 MiB.

**Capture assistance** in the garment form scans a label locally or extracts reviewed fields from typed/OCR text with
Apple's available on-device model. It has explicit acceptance, cancellation, stale-result checks and manual fallback.
Label scans never upload automatically. The current SDK has no Foundation Models image prompting; direct model photo
understanding and measured colour hints remain pending. `WardrobePhotoTests` and media fixtures are authored, unrun.

## Layout

```
Retro/
  App/       RetroApp, Config (Info.plist reader, -dev-engine / -demo-hour)
  Auth/      AuthService (Clerk, 8s offline guard, token)
  Net/       RetroAPI (Api<T>, classify, errorOf) · Engine (per-user, 401 retry) · Reachability
  Data/      WardrobeModels · WardrobeDrafts · WardrobeStore · WardrobeWrites · WardrobePhotos · PhotoPreparation · GarmentAssistance · DiskCache (per owner) · preserved demo Models/DemoData
  UI/        Theme (palette, motion, Panel) · DayArc · WeekStrip · GoalRow · TodayView · RootView · RetroMark
```

House style, matching the rest of the family: `@MainActor @Observable` models, constructor injection with closures, one
`Api<T>` result enum for every engine call, models with explicit snake_case `CodingKeys`, and a single `Theme.swift`
carrying the tokens.

## Rules that come from the design

- **Health is not a score.** A missed day draws `raised`, never `clay` or `rust`. `rust` is only a day marked void.
- **No eyebrows.** No small tracked label above a heading; the heading carries its own weight.
- **Native controls.** `List`, `NavigationStack`, sheets, `TextField`, SF Symbols. No reinvented navigation.
- **Dynamic Type.** System text styles, so the layout follows the reader's size.
- **Reduce Motion.** Every non-essential movement has a real alternative; the arc arrives drawn.
- **Contrast in the token.** Four variants each, so the system Contrast setting needs no per-view work.

## Workspace setup

After sign-in, Retro checks the shared router's `GET /onboard`. Completed setup opens the app; running setup resumes
polling. A new account can create its workspace with platform defaults and securely generated credentials through
`POST /onboard`. Every retry checks status first. If onboarding history has expired, `/gateway/healthz` checks whether
the workspace already exists before offering setup again. Offline checks leave the app usable, and `-dev-engine`
skips provisioning. This provisions the shared workspace; enable the new wardrobe engine through a tenant chart upgrade.

## Dev mode

`-dev-engine <url>` skips Clerk entirely and points the app at an engine on this Mac, which is how the UI tests drive
the real screens. `-demo-tab <today|wardrobe|history>` selects the opening tab. `-demo-hour` remains only for preserved demo previews.
All dev overrides are `#if DEBUG`.

```sh
xcodebuild -scheme Retro -destination 'id=<simulator>' test
```

`RetroTests` covers status classification, both error shapes, the two-tier file store, and account isolation.
`WardrobeReadTests` uses shared `fixtures/wardrobe` responses and covers stale-query/account-switch reads.
`RetroUITests` checks the three-tab shell and account sheet; it does not seed production demo records.

`WardrobeWriteTests` covers persistence failure, frozen replay, rejected/uncertain discard rules,
account-switch/cancellation, acknowledgement persistence failure and snapshot-preserving patches; authored, not run.

## Not built yet

Direct model image prompting, later optional features and Sensei extraction remain. M1–M6 source is implemented;
P1–P3.4 is also in source, and its signed iPhone build/install/launch passed on 2026-10-09. Suites/full runtime and
device/accessibility checks remain pending. P4–P6 starts from the [implementation handoff](../docs/retro-p4-p6-handoff.md).

## Suggestions, insights and recovery (M4 source)

Today opens rule-based suggestions for its selected date, with occasion/warmth, required/excluded pieces and
Shuffle alternatives. Fresh piece/version checks lead into the normal reviewed composer; no wear is recorded by
choosing a suggestion. History offers date/garment filters, factual Insights and per-record change history from details.

Garment/outfit forms store private atomic drafts with original baselines and stable create IDs; resume them from
Pending saves, keep them while existing-record saves are pending, or discard explicitly. Review against a fresh record
and select fields to reapply. Known rejected edits can be replaced atomically with a new key; uncertain requests stay
frozen. Automatic write retry cooldown persists for 10 seconds; explicit Retry can bypass it. Corrupt durable files are
preserved with visible errors. Readable photo manifests allow pruning only unqueued JPEG staging leftovers older than a day.

Photo drafts persist normalized originals, chosen images and reference order in the same versioned manifest as
upload jobs (20 drafts / 256 MiB of draft sources). Save moves a draft into an upload batch in one atomic write;
unchosen originals are released after that commit. Reopening never allocates a second upload for an accepted draft.
Missing or altered bytes block loading/acceptance and preserve the draft. Cutout previews can be regenerated on iOS;
raw camera/picker work and OCR/model input remain transient until preparation or field review completes.

Use Continue editing locally on a queued create to keep later garment/outfit edits without changing its frozen body
or key. Keep draft leaves those edits unsent; after acknowledgement, Review against latest record requires selected
fields and a fresh version. Outfit followups keep the create's planned/worn state and source. A known rejected
create can be replaced explicitly with corrected fields and a new key. Retry original create restores the same body,
entity and key if its queue row was removed, and conservatively protects it as dispatched until reconciled.

Tests and shared review fixtures are authored but unrun. Actual device/accessibility validation remains M4 work.
On 2026-10-08, the signed wardrobe Debug build succeeded and was installed and launched on the connected
iPhone 17 Pro; its running process was confirmed. Unit/UI suites, backend flows and accessibility checks were not run.

## Requests, comparison and reuse (M5 source)

Both clients compare two or three refreshed engine options, showing shared/different garments, roles, reasons and
missing coverage. Selecting an option checks current garments/versions again before opening the normal composer.
Reuse from outfit detail refreshes the original and its current garments. Missing, archived, unavailable or pending
pieces need explicit replacement/removal. Review plan refreshes chosen replacements and starts a new manual plan for
the selected date/current time zone. Historical notes, wear state and snapshots are not copied into the new record.
Saving uses the existing draft/queue path with a new entity UUID and retry key; the original outfit stays intact.

Describe an outfit/search interprets up to 2000 UTF-8 bytes with the available on-device Foundation Models text model.
Generated fields are validated and editable. Garment phrases are hints: choose real IDs from inventory, or explicitly
ignore and acknowledge them. Unsupported conditions remain visible after applying. Search supports literal name,
category, availability and include-archived only; richer metadata/weather/date conditions do not become hidden filters.
Requests time out after 20 seconds and cancel on input change/dismissal/background; owner/query checks reject late results.

Record a description is also available in garment Capture assistance. It uses `SFSpeechRecognizer` only when
`supportsOnDeviceRecognition` is true, with `requiresOnDeviceRecognition` enabled. Record requests microphone/speech
permission, streams audio without storing it, and stops after 30 seconds, interruption or leaving the foreground.
Review/edit the captured transcript and explicitly Use reviewed transcript; this replaces text only, without interpreting
or saving automatically. Unavailable language/assets/permissions leave typing accessible; no network fallback or asset
installer is added. The iOS 17 deployment floor is retained.

`WardrobeAssistanceTests` adds bounded/mixed-mode interpretation, transcript source/account checks, real candidate
comparison, new-plan identity/snapshot preservation, unavailable/service distinction and late-owner rejection.
Tests are authored, unrun. On 2026-10-08, the signed M5 Debug app build succeeded, installation and launch succeeded
on the connected iPhone 17 Pro, and its running process was confirmed. Speech/model accuracy, permission UX, offline
recognition, accessibility and energy/latency still require hardware verification; backend flows were not exercised.

## Photo entry, review and system actions (M6 source)

Wardrobe → Add from photos stores up to 20 normalized source photos in the private account/endpoint draft scope
(10 per picker selection, 12 MiB each, 256 MiB folder budget). Review a garment per photo or confirm an existing item;
save the garment, accept its photo, and finish only after attachment acknowledgement. Pause/relaunch resumes in this
screen or Pending saves. Imports preserve original create payloads/keys and chosen media IDs before acceptance;
ordinary draft/photo queues handle rejection, conflict and upload retry. Later edits require fresh selected-field
recovery. Explicit removal leaves accepted work running and an unaccepted photo draft available in Pending saves.
Changed bytes or corrupt manifests are preserved with a recovery error. Old unreferenced import sources have a one-day
grace period and are pruned only with readable intent.

Check for similar items uses Vision feature-print revision 2, on demand, against up to 40 loaded garments with cached
primary thumbnails / 16 MiB. Missing photos and other inventory pages are disclosed. No comparison downloads, feature
index, cloud fallback, confidence score or auto-merge is added. The three closest photo/name hints need owner review;
fresh version/photo checks precede Use existing. Cancellation/dismissal and a 20-second timeout fence results.

History → Wardrobe review validates selected-period server counts/category totals and opens paginated source outfits,
using saved snapshot names. Counts and record pages show separate cached/error states. No causal explanation is generated.
Siri/Shortcuts Add garment, Search wardrobe and Today's outfits use App Intents with device authentication and the shared
entry point behind Clerk/onboarding. They only open the normal UI; search text is bounded to 100 UTF-8 bytes. iOS 17
support is retained. `WardrobeM6Tests` covers entry gating/parsing, factual counts, private import recovery, corruption,
stable photo handoff and cache-only comparison input. These tests are authored, unrun. On 2026-10-08, the signed
M6 Debug build succeeded, was installed over Retro and launched on the iPhone 17 Pro; the running process was
confirmed (PID 11774). Feature flows, duplicate quality, Siri, backend integration and accessibility remain unverified.
