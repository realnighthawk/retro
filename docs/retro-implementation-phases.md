# Retro implementation phases

Started on 2026-10-08 from the approved [feature checklist](retro-feature-checklist.md).
As of 2026-10-09, new client implementation is **iOS only**; earlier Android work remains in source.
Keep on-device Apple Intelligence/native processing for suitable work and the existing agent endpoint for
connected context, scheduled execution and heavier/specialist processing. Apple Private Cloud Compute is excluded.
Every feature keeps ordinary engine validation, durable writes and manual fallback. The MinIO budget stays 10 GB;
no deployment is performed as part of these source implementation phases.

## P1 — Shared records and intelligence integration foundations

Outcome: iOS, Android and the agent can use the same durable wardrobe preferences, confirmed care settings and
explicit feedback. Apple helpers can retrieve bounded, source-linked facts instead of inventing context.

- [x] P1.1 — Backend preferences: singleton migration, read/update operations, validation, optimistic versions,
  idempotent execution, audit browsing and generated OpenAPI. Unit/integration tests are authored; not run.
- [x] Inspect the existing agent-harness mobile transport and router forwarding in source; record findings below.
- [x] P1.2 — Confirmed garment care metadata and machine presets needed by laundry planning. Preserve current garment
  edits/snapshots and make unknown instructions explicit.
- [x] P1.3 — Versioned explicit outfit feedback records; correction/reset and history semantics, without inferring
  wears, dirtiness or dislikes from viewing a suggestion.
- [x] P1.4 — Inspect/reuse the actual agent context/task contract. Define bounded context results, stable request/job
  IDs, source/freshness/coverage, capability discovery and cancellation/account fencing before native wiring.
  **Source complete:** `wardrobe_context_get`, Apple read-only context and gateway MCP `ask_agent` are implemented.
  Gateway delegation includes owner/tenant-scoped durable turns, bounded results, stable IDs, retry/poll/cancel and
  reviewed pending-input handling. iOS Today → Ask Retro now has the MCP bridge, bounded native Apple tool loop,
  optional connected delegation, durable recovery/stop intents and native owner questions. Domain-specific connected
  facts and permissions follow in their feature phases. Tests/build/runtime checks remain deferred.
  See [agent contract](retro-agent-contract.md).
- [x] P1.5 — Native preference/care/feedback DTOs, editable settings and durable save/recovery on both clients.
  Extend existing Apple typed helpers and read-only tools over ordinary authenticated stores/API methods.

P1 shared records/native source is implemented on 2026-10-09. The registry now has 25 operations: preferences,
outfit feedback and bounded source-linked context extend the original 20. iOS/Android expose editable wardrobe
settings, machine presets, garment care and outfit feedback through durable frozen saves and selected-field
conflict recovery. iOS adds reviewed Apple typed proposals and authenticated read-only tools. P2.1 adds rule-based ranking;
native MCP/local loop wiring is now in source. N06 remains unchecked until its full editing/ranking behavior is delivered.

Preferences cover preferred/avoided colours, preferred styles, default occasion, temperature unit/sensitivity,
cold/hot thresholds, layering, repeat interval, underused-item preference and variety. Migration 0003 initializes
one record with a stable UUID and version 1 in each engine database. Updates retain omitted settings; null clears
lists/default occasion only. Required scalar settings reject null so explicit zero/false remain meaningful.
Preference audit is available through `history_list` with `entity_type: "preferences"`.

Care records retain unknown instructions and require explicit review before confirmation. Machine presets reuse
the preference record; migration 0003 remains unchanged. Feedback migration 0004 stores one separate record per
outfit, with an initial virtual version zero, ordinary idempotent writes, audit/reset and both feedback/outfit
version checks. Only actual wears accept feedback edits. Voiding preserves feedback and outfit corrections keep
the previously reviewed outfit version. No viewing/rating action creates wears or marks garments dirty.

The native Save action persists a frozen request before dismissing; retry/reconnect uses its original identity.
Rejected preferences/care/feedback saves can be reviewed against fresh fields. Feedback recovery also displays
the current wear before selecting changes. Unsaved settings forms are in-memory; garment/outfit/photo draft
features from M4–M6 remain unchanged.

Existing agent transport findings (source inspection only):

- Router forwarding exists for `/gateway/`; gateway native routes are `/ios/ws` and `/android/ws`, giving external
  paths `/gateway/ios/ws` and `/gateway/android/ws`.
- Native adapters use platform-scoped sessions and an initial authenticated WebSocket frame; router authorization
  also applies before the upstream connection. The current mobile adapter accepts only its default/main session.
- The wire protocol supports conversational messages, streaming turn events, client message identities and
  resume/cancel. This is useful transport, but does not establish a typed wardrobe context/image/rendering API.
- The selectable HTTP gateway also exposes durable structured tool-call results through `/gateway/poll`; these
  can support later integration. Neither session selection nor a prompt supplies task-scoped read-only permissions.
- Reuse these conventions where suitable. Confirm structured results, job isolation and available specialist tools
  rather than embedding unvalidated narrative text into Apple tool results or inventing a new endpoint URL.

Sources: sibling `agent-harness/router/internal/core/proxy.go`,
`agent-harness/gateway/internal/mobile/mobile.go` and `agent-harness/gateway/internal/realtime/frames.go`.
Gateway MCP implementation now adds `/gateway/mcp` over that existing router prefix. See the
[gateway contract](../../agent-harness/docs/components/gateway/mcp.md); no live endpoint was contacted or deployment performed.

## P2 — Daily outfit decisions

Outcome: useful fresh choices every day, with a quick way to change them and record the real wear.
Checklist coverage: N01, N05, N06/N07 ranking and N08 pairings.

- [x] P2.1 — Apply stored preferences and explicit feedback to explainable eligible-candidate ranking; honour locked and
  excluded pieces, availability and configurable repeat rules without silently dropping constraints.
- [x] P2.2 — Add durable daily selections and saved garment pairings; keep a chosen plan stable across refreshes and preserve
  the distinction between generated choices, plans and confirmed wears.
- [x] P2.3 — Use Apple Foundation Models for bounded request/swap interpretation and candidate comparison/explanation;
  shared engine code owns eligibility, counts and scoring. Keep native/manual fallbacks on iOS.
- [x] P2.4 — Retrieve relevant weather/calendar/travel context through available agent connections, carrying sources,
  timezone and freshness. Local tools consume these facts; unavailable context has an explicit fallback.
- [x] P2.5 — Add agent-scheduled generation and optional morning/previous-evening connected delivery, with a stable wake,
  durable snapshots and one authorized send attempt per date/time zone. Provider delivery guarantees still need evaluation.

Start with useful choices when Today opens; scheduled delivery follows without relying on the phone being awake.

P2.1 is implemented in source on 2026-10-09. `wardrobe_suggest` now returns `rules-v2`, preference identity/version,
effective occasion, bounded feedback coverage, names/versions and explainable integer scores. Avoided colours and
repeat intervals are hard filters; locks that conflict fail rather than disappearing. Colours use exact normalized
tags; preferred styles match existing formality tags only. No weather or temperature sensitivity is inferred.
Wear counts use confirmed wears through the requested date. Numeric ratings from the latest 2000 version-matched
worn outfits affect piece and exact-look ranking; comments, plans, views, future wears, voids and older outfit revisions
do not supply rating evidence. Resetting ratings removes their contribution. Variety penalizes overlap between choices.

The bounded search keeps eight garments per role and a 64-choice beam for each outfit shape, with at most 2000
inventory records. Daily tie ordering is stable for the same date and unchanged facts. Empty/incomplete choices
disclose constraints and missing roles rather than claiming exhaustive inventory search or relaxing settings.

iOS Today loads choices on open, foreground, local-day changes and refresh, through existing account/endpoint caches.
It leaves saved plans and actual wears intact. Review rechecks the saved preference version and current engine
eligibility, then refreshes garment versions before opening the ordinary unsaved plan editor. Individual swaps keep
the other pieces fixed, exclude the target and require its replacement role; locked targets must be unlocked first.
The existing on-device request interpreter and manual controls remain available in Suggestions. P2.3 now adds Apple
candidate tools/explanations; P2.4 adds reviewed connected context and P2.5 adds scheduled generation below.

Focused rule/integration/native tests and a ranked-result fixture are authored. Formatting, OpenAPI generation
(which compiled the engine package) and Xcode project generation completed. Tests, native builds, runtime flows
and deployment remain deferred at the owner's request.

P2.2 is implemented in source on 2026-10-09. A daily selection references an existing saved plan rather than copying
its pieces or recording a wear. Save a plan, then choose it from Today after reviewing current selection/outfit
versions and readiness. One shared selection per local date retains the plan's IANA time zone. Refreshing generated
choices never changes this reference. Explicit confirmation keeps the reference and shows the recorded wear.
Moved/voided plans and unavailable pieces remain visible with a review message; clear is a versioned tombstone and
keeps the original outfit/history. Choice saves use the established durable queue and rejected-request review.

Saved pairings persist 2–30 unique garment references with manual roles, name and notes. iOS browses them from
Wardrobe and “What goes with this?” on garment detail, supports named reusable complete looks, and can start a
pairing from an outfit's pieces. Editing/archive/restore use existing idempotency, versions and audit. Planning
refreshes the pairing version and current garments, rejects unavailable/pending pieces and opens a separate unsaved
plan editor. Pairings do not add wear events, change garment availability or copy photo objects.

Migration `0005_daily_selections_pairings.sql` adds the three small tables using the existing database. Seven HTTP/MCP
operations extend the registry to 32. Unset daily selections have version zero and reads never insert them.
Unsaved pairing forms stay in memory with discard confirmation; accepted pairing/choice saves are durable and
account/endpoint scoped. P2.3 compares real engine choices locally; typed connected pairing proposals remain pending.
Rule, integration and native regressions plus pairing/selected-day fixtures are authored. Formatting, 32-operation
OpenAPI generation (compiling the engine package) and Xcode project generation completed. Tests, migration execution,
native builds, runtime flows and deployment remain deferred.

P2.3 is implemented in iOS source on 2026-10-09. Today, Suggestions and refreshed Compare offer **Outfit help**.
The existing Describe an outfit helper still extracts supported occasion/warmth and unresolved garment hints into
native controls; the new Apple tool reads fresh `rules-v2` choices for the fixed request before comparing them or
identifying one unlocked piece to swap. Candidate/piece aliases bind only to that source snapshot. Fresh reads reject
cached fallback, changed option ordering/garment versions/preference identity, pending piece/settings saves and
account/request/date/time-zone/revision changes. Exact integer versions stay in native data and are strings in model context.

Guided proposals reference only supplied choices and the first three engine reasons per choice. Short names/reason
excerpts carry omission flags; full reasons, scores, missing roles, feedback coverage and warnings remain native UI.
Model commentary is labeled separately and never becomes a wardrobe fact. Ambiguous/unsupported requests stay
visible; continuing without unsupported conditions needs a native acknowledgement. A proposal does not write records.
Reviewing a plan refreshes eligibility and garments through the existing editor path. Reviewing a swap refreshes its
source, preserves the date/occasion/warmth, locks all other pieces, retains existing piece/combination exclusions and
requires the same replacement role. Explicit manual edits/generation can begin a new preference review.

The feature reuses the existing 90-second controller, optional query-only MCP delegation, durable remote recovery,
native owner questions and stop/account fences. Connected help defaults off. One fresh choices snapshot is exposed
in at most two tool calls (the second is a short same-source receipt); tool results have a 4000-byte/result and
5500-byte total budget, guided output a 700-token cap. Overflow or unavailable Apple Intelligence uses the existing
manual interpretation/Compare/swap controls. No new engine operation, model provider, endpoint or dependency is added.
Focused alias/evidence/constraint/freshness/cache/pending/cancellation regressions are authored. Xcode project generation
completed; tests, native builds, model/device evaluation, runtime flows and deployment remain deferred. P2.4 adds a
separate typed provider-context adapter below; generic remote narrative does not establish these facts.

P2.4 is implemented in iOS/gateway source on 2026-10-09. Outfit help can retrieve connected context for its fixed
date and captured IANA time zone, with an explicit weather location and no inferred GPS location. The same generic
`ask_agent` discovers available connections; the answer supplies only field pointers into actual completed top-level
`call_tool` results. Native code resolves literal provider values and checks ownership, connection/tool identities,
date/location, temperature units, event overlap and bounded source age. One daily forecast, up to three calendar
events and two agent-selected travel events are supported. Native UI retains full accepted facts, source pointers,
provider zones, available/partial/unavailable coverage and expiry. Empty selections do not prove an empty calendar;
travel classification and semantic field mapping remain agent proposals, and entries do not prove bookings.

The read expires 30 minutes after the oldest accepted source call started; retrieving a saved job does not refresh
that age. A supplied forecast issue time must be within six hours; absent issue time explicitly leaves provider
cache age unknown. Missing connections, unsupported formats, stale or omitted evidence retain manual controls.
The gateway 1.1 profile adds bounded connection identities and expands raw evidence to 4096 bytes/source, with a
32 KiB envelope and 128 KiB native wire cap. No provider SDK, credentials, engine operation, route or chart value is added.

Retrieval and reviewed manual warmth/occasion changes work without Apple Intelligence. On supported devices,
`read_outfit_context` supplies at most 2000 bytes of typed facts with scoped aliases to the existing Apple loop.
Fresh native context is reused without starting another remote task. Guided changes cite supplied fact aliases;
native review refreshes engine choices, preserves locks/exclusions and opens Suggestions with the adjusted warmth
or occasion. No proposal saves a wardrobe record. Matching pending context requests resume their original IDs,
using the existing owner-input and durable stop/recovery flow. Connected help remains opt-in; requests ask for
reads only but use existing agent permissions rather than server-enforced task-specific grants.

Source-pointer/unit/scope/date/freshness/refinement/recovery/cancellation tests and `outfit-context.json` are authored.
Xcode project generation includes the new files. Tests, native/gateway builds, live connection/model/device checks
and deployment remain deferred. Deploy the new gateway and iOS client together. Automatic forecast-driven ranking,
precipitation/garment suitability and temperature-sensitivity rules still require further N05 work.

P2.5 is implemented in engine/iOS/harness worker source on 2026-10-09. Today → **Daily automation** edits a separate
versioned singleton: enabled, morning/previous-evening mode, local hour/minute, fixed IANA time zone and an optional
connected-service recipient. Saves reuse the frozen durable write queue and selected-field conflict recovery.
Saving changes desired settings; **Apply saved schedule**, **Pause agent schedule** and **Check agent schedule**
use the same user-scoped `retro-daily-outfits` Temporal wake through generic `ask_agent`. The existing headless wake
path runs while the phone sleeps. Setup never generates outfits or sends a notification. Native code confirms a
fresh actual `manage_wake` inspect result with the exact owner, workflow, objective/settings version, normalized
daily time/zone and future firing. Disabled settings accept a paused wake or explicit Temporal not-found evidence;
an unavailable service is not absence. Existing owner questions, same-task recovery and cancellation remain.

Migration `0006_daily_automation.sql` adds settings and daily runs in the existing database; six HTTP/MCP operations
extend the registry to **38**. Generation requires the current enabled settings version and a two-hour catch-up
window, and derives its day from server time in the saved zone. Calendar-day arithmetic covers daylight saving;
nonexistent local slots are skipped. Each date/zone has one immutable `rules-v2` snapshot with preference/garment
source versions, expiring at the following local midnight. Earlier settings cannot regenerate that same day.
Today shows this cache separately from fresh on-open choices. Review rechecks current eligibility/preferences and
pieces before opening an unsaved plan; generation does not choose a plan, record a wear or change availability.

An empty delivery target means generation only. Otherwise the agent discovers an unambiguous connected sender,
then reserves one engine-authorized attempt after current settings/window/ranking checks. A replay of the same
claim key or a competing claim returns `send_allowed: false`; this intentionally differs from ordinary result
replay. Lost replies/uncertain outcomes remain visibly claimed and are never automatically resent. Completion
stores an **agent-recorded** provider receipt and actual send tool-call reference. This is not exactly-once external
delivery or an enforced remote tool grant: connector retries need provider idempotency, and the generic agent can
call its tools outside the convention. iPhone push/APNs and provider-specific adapters are not implemented.

Wake tools now support IANA cron zones, decode described SDK Payloads, report normalized daily calendars and use
the SDK's updater callback while preserving existing action/options/policy. No provider SDK, new worker, harness
wake table, endpoint, chart value or additional storage is introduced. Engine/native/worker regressions and the
daily fixture are authored, unrun. Go formatting, 38-operation OpenAPI generation (which compiled the engine
package) and Xcode project generation completed. Tests, migrations, native/worker/gateway builds, live connection
or device checks and deployment remain deferred. Deploy the updated worker, engine/migration and iOS client together;
gateway 1.1 provenance is also required. Broader N05 automatic context-driven ranking remains open.

## P3 — Laundry loads and history

Outcome: “prepare a cold wash” produces compatible, editable load lists and accurate progress/history.
Checklist coverage: N03, using N12 care records and relevant N04 label support.

- [x] P3.1 — Implement manual loads and dated wash/dry confirmations, saved machine presets, care compatibility and availability transitions.
- [x] Separate machine wash, hand wash and dry-clean-only instructions; apply all confirmed temperature/cycle/colour/
  drying restrictions. Unknown care information remains visible and needs review.
- [x] P3.2 — Use local OCR and Foundation Models for reviewed care-label text, evidence-based care drafts and laundry request interpretation.
- [x] P3.4 — Add reviewed local/agent timing and batch proposals using upcoming wardrobe needs; deterministic rules validate each load.
- [x] Add native load selection, adjustments, progress/confirmation and wash history.
- [x] P3.3 — Add wears-since-cleaning and optional in-app wear-day/calendar-interval review reminders.

The first usable slice is manual confirmed care settings plus compatible loads. Label assistance and connected
planning enhance it; they do not block an owner who enters care instructions manually.

P3.1 is implemented in engine/iOS source on 2026-10-09. Wardrobe → **Laundry loads** reviews an explicit machine,
hand-wash or professional-care programme. Existing presets copy into the reviewed programme; an unknown drying
method requires an explicit choice. Preview assesses at most 2000 active garments explicitly marked `needs_wash`,
using confirmed care only. Temperature must not exceed the recorded maximum; machine cycles match exactly rather
than assuming gentler equivalence. Drying must match the recorded instruction, with `do_not_tumble` permitting
line/flat choices. Whites, lights and darks stay in separate groups; `separate` gets a one-garment group. Unknown,
unconfirmed and incompatible care stays visible with a reason and a link to the existing care editor/local helper.
These are recorded-care checks, not a machine capacity assessment or an inference about unrecorded label warnings.

Choose and adjust 1–30 pieces from one group, name/date the load and save a plan. Planned loads remain editable;
save and start are separate. Creation/edit/start recheck garment versions, current confirmed care and eligibility
inside the existing write transaction. Start also reserves garments against concurrent loads and sets availability
to `washing`. Confirm wash finished moves the load to `drying`; garments stay unavailable until **Confirm dry and
ready** restores `ready`. Professional care completes when explicitly returned clean. Actual server timestamps
record these confirmations; a future planned date cannot start early. Cancel retains the record and returns active
pieces to `needs_wash`, never claiming completion. Wearing remains independent and does not automatically mark dirty.

Care/garment snapshots and progress timestamps survive later inventory changes. Active reservations block garment
edits, photo attachment and archive/restore until completion/cancel, preventing another screen from making wet
pieces ready. Native saves use the existing frozen queue and exact integer versions. Pending saves can reopen
rejected create/edit intent against the latest planned load and fresh group sources; uncertain dispatches keep their
original identity. Retained garment edits do not block active load completion/cancel; starting a planned load still
waits for garment saves. Rejected progress is inspected, not automatically advanced again. Garment detail links its
load/wash history, and load detail links the existing audit browser. Unsaved forms stay in memory with discard
confirmation; accepted saves are durable.

Migration `0007_laundry.sql` adds load/item tables and an exclusive active-garment index to the existing database.
Seven shared HTTP/MCP operations extend the registry to **45**. No service, provider/model dependency, gateway/router
change, chart value or photo storage change is added. Focused engine/native tests and `laundry.json` are authored,
unrun. Go formatting, 45-operation OpenAPI generation (compiling the engine package) and Xcode project generation
completed; suites, migrations, native builds, runtime/device checks and deployment remain deferred. Deploy the
engine/migration and iOS together.

P3.2 is implemented in iOS source on 2026-10-09. **Plan a load → Describe a laundry programme** accepts typed text
or an optional reviewed on-device speech transcript. The Apple model drafts only programme settings with literal
request excerpts. Temperatures require an explicit numeric Celsius value; cold/warm/hot and other units are left
for manual review. An explicitly named, unique saved preset maps to a bounded native alias and copies its actual
values, including zero and unresolved drying restrictions. Native source/version/pending checks refresh any used
preset before applying it. Field selection and an explicit acknowledgement keep unsupported dates, garment filters,
timing/actions and other conditions visible. Unchanged controls retain their form values; method changes clear
incompatible settings without inventing missing temperatures/cycles/drying. Applying invalidates compatibility
preview and does not select garments, save or start a load. Ordinary P3.1 review/versions/queue/rules still govern saving.

**Care instructions → Scan a care-label photo** reuses local Vision text recognition and bounded photo normalization.
Review/correct the recognized text before replacing label evidence. The photo is not uploaded; reviewed text becomes
ordinary care evidence only when saved. Applying text marks source Label and clears care confirmation, preserving
other settings. The existing source-linked local care model can then draft explicit text-supported changes; numeric
temperatures now require Celsius units. Symbol-only labels, missing/unclear instructions, other units and text over
the evidence limit need manual entry. Neither OCR nor the language model confirms care or proves a label is complete.

Manual controls and local OCR remain usable without Apple Intelligence; language drafting needs the existing eligible
iOS 26/device/model/locale gate. Requests use no agent or Private Cloud Compute. Both screens cancel on background,
dismissal and source edits, bound work to 20 seconds and prevent late results from changing another account/form.
Focused source/preset/units/partial-method/OCR review tests reuse existing fixtures and are authored, unrun. Xcode
project generation completed; builds, suites, model/OCR/device checks and deployment remain deferred. The backend
registry stays at 45 operations; no migration/config/gateway/chart changes are needed for P3.2.

P3.3 is implemented in engine/iOS source on 2026-10-09. **Wardrobe → Laundry check-in** and garment detail →
**Wears since cleaning and reminders** show the latest completed dry/clean-return source, definitely later wear
days/records and separate same-cleaning-day records with unclear order. Only current `worn` history contributes;
void/restore, date correction and actual-piece correction update the derived totals. Comparison uses the cleaning
instant's calendar date in each outfit's own time zone, so a backdated wear logged after cleaning stays before it.
No completed cleaning means unknown counts, not a claimed zero. Planned, washing, drying and cancelled loads do not
reset the baseline. A newer completed cleaning becomes the baseline without a mutable counter or wear-history rewrite.

Per-garment reminder preferences opt in to a 1–100 distinct-wear-day threshold and/or a 1–365 calendar-day interval.
The first reached threshold prompts care review; same-day ambiguous wears do not advance the wear threshold.
Calendar intervals use displayed IANA time-zone dates, not elapsed 24-hour blocks. Missing baselines wait for cleaning;
washing/archived pieces pause reminders. Turning reminders off clears only this optional preference. Reminders are
in-app check-ins refreshed on open/foreground/day/clock change and after saved changes, with explicit cached snapshot
status; no background notification or delivery is scheduled. A due reminder never means proven dirtiness and never
changes availability, confirms care, starts a load or schedules a wash. Native links open care, actual availability,
reminder preferences and retained load history for ordinary owner review.

`laundry_check_in` is a read-only shared HTTP/MCP operation over a complete active wardrobe capped at 2000 garments,
or one explicit garment (including archived history). It returns coverage, an as-of database timestamp, exact garment/
completed-load versions, nullable baseline statistics and deterministic due reasons. The read transaction derives
facts consistently with the completion clock; it does not send model text or infer wear instants. Reminder preferences
are optional garment attributes saved through existing versioned/idempotent `garments_update`, audit, durable queue
and rejected-field recovery. Unsaved native forms have discard protection and stay in memory. Migration 0008 adds
one lookup index to existing load items; no table, worker, provider dependency, chart value or storage allocation is added.

The registry is now **46 operations**. Focused engine/native threshold/date/time-zone/correction/unknown-baseline/
paused-reminder/frozen-save tests and `laundry-check-in.json` are authored, unrun. Go formatting, contract generation
(compiling the engine package) and Xcode project generation completed. Suites, migrations, native builds, runtime/device
checks and deployment remain deferred. Deploy the updated engine/migrations and iOS together. P3.4 below adds
connected laundry timing/batches; P3.3 does not add notification delivery.

P3.4 is implemented in iOS source on 2026-10-09. **Plan a load → Review compatible groups → Plan batches around
upcoming outfits** fixes the owner's reviewed programme, IANA time zone and need-by date within 14 calendar dates.
Fresh `laundry_preview` and one `outfits_list` page provide compatible Needs wash pieces and saved planned outfits.
The device represents at most eight pieces, prioritizing matches to four earliest same-zone plans in a 20-plan page.
Partial pages, omitted pieces/plans, other-zone plans and blocked care are visible. This is a bounded selection,
not proof of a complete wardrobe schedule; existing planned laundry loads, capacity and wash/dry durations are
not assessed. The complete ordinary programme/group editor stays available.

Apple's on-device model uses `read_laundry_choices` and the existing generic `ask_agent` tool when connected help
is enabled. Native code retains the original request, binds exact source versions to aliases and sends a bounded
schema query over the existing gateway MCP endpoint. The agent can propose up to three batches. Optional local
`read_outfit_context` reuses the provider-pointer adapter for calendar/travel on the need-by day only; generic
agent prose cannot become provider facts. A direct connected planner works without Apple Intelligence. Local
language drafting follows the existing eligible iOS 26/device/model/locale gate, with no Private Cloud Compute.

Both proposal paths validate scope, source binding, real compatible groups, unique pieces, cited outfit needs and
date bounds. No mixed colour/care groups, blocked pieces, repeated pieces or invented provider references can be
applied. A planned date never proves dry readiness. Review one batch, acknowledge unsupported conditions, then
refresh the programme/groups and plans online. Changed source versions, pending writes, cached/stale results,
account/form changes or a local-day change block application. Applying changes the current load form only; ordinary
versioned/idempotent save, care validation, durable queue/rejected-intent recovery and separate progress confirmations
remain authoritative. Other proposed batches are not automatically saved.

Connected tasks retain query/identity/owner response/stop intent in the existing journal. Matching unchanged source
bindings/request text reuse the saved task, including recovery after lost replies. Dismissal/background/source edits
cancel local work and retain best-effort remote stop intent; the existing 90-second/two-delegation/poll/context bounds
apply. Generic remote permissions remain those of the agent, not a newly enforced read-only grant.

`laundry-planning.json` and focused native source/scope/group/alias/date/DST/freshness/recovery/frozen-save regressions
are authored, unrun. P3.4 reuses all **46 operations**, with no engine/gateway/router/migration/provider/chart/storage
change. Xcode project generation includes the new sources; builds, suites, model/agent/device checks and deployment
remain deferred. P3.1–P3.4 are implemented in source. Notification delivery and richer scheduling/provider formats
remain follow-ups; P4 capture/discovery/maintenance is the next implementation phase.

## P4 — Capture, discovery and wardrobe maintenance

Outcome: faster garment entry, complete search, useful reviews and dependable multi-item maintenance.
Checklist coverage: N04, N09, N10, N11 and the remaining N12 purchase/style metadata.

- [ ] Add richer metadata, amount/currency/evidence semantics, full server filters/sort and real ranked usage lists.
- [ ] Prefer local OCR/cutouts/feature prints and guided extraction. Direct Apple image prompting needs compatible
  SDK/OS/model/device support; use available agent image tools only for tasks requiring that remote capability.
- [ ] Add complete-inventory duplicate proposals, source-linked analytics and local explanations of engine aggregates.
- [ ] Reconcile supporting purchase records through agent connections, with uncertain matches reviewed before saving.
- [ ] Add bounded bulk maintenance with explicit selection, per-item progress, stable identities, retry/recovery and
  protection of historical photos. Keep suitable photo operations local and heavier jobs outside engine transactions.

## P5 — Live try-on feasibility

Outcome: measured evidence for a rendering approach that can meet the requested live-camera experience.
Checklist coverage: N02 feasibility; can start alongside P2–P4 without blocking them.

- [ ] Define the required camera setup, asset capture, garment categories and measurable fidelity/latency/battery targets.
- [ ] Prototype native pose/person masks and a purpose-built local renderer/model on the owner's actual device.
  Foundation Models handles language commands, not per-frame clothing simulation.
- [ ] Evaluate agent asset preparation or a specialist renderer only where needed; measure swap response and video
  consistency with the real camera/network rather than assuming agent access provides live rendering.
- [ ] Record the supported approach, category limits, capture requirements and failures before planning delivery.

A still image or static overlay can inform experiments but does not complete N02.

## P6 — Live try-on delivery and integrated client completion

Outcome: stand in the camera, see a suggested outfit, swap individual pieces/live looks and save the chosen plan.
Checklist coverage: N02 delivery and integration across all required N01–N12 features.

- [ ] Implement camera positioning guidance, moving-person preview, layering/occlusion and stable live swaps.
- [ ] Add reachable/hands-free controls, tracking-loss/loading/recovery states and the ordinary reviewed save path.
- [ ] Deliver supported platform behavior with explicit device/camera/category capability limits. Keep Android's
  record/manual contract usable without Apple APIs and evaluate its own rendering capabilities.
- [ ] Complete accessibility, account isolation, pending/offline recovery and bounded preview retention within 10 GB.

Family sharing, browser UI, localization and configurable providers remain optional O01–O04 product choices.

## Delivery and validation discipline

Each iteration completes a small source slice and records its actual status here. Author focused tests for new
rules/contracts and dangerous retry/conflict paths; do not claim a feature complete because its DTO or prototype exists.
At the owner's request, runtime/test-suite validation follows implementation/deployment. Deployment itself needs
a separate request; these phases do not deploy infrastructure or install new phone builds automatically.

P1 evidence: Go formatting, the OpenAPI generator and Xcode project generation completed; the generator compiled
the engine and produced the 25-operation contract. Focused backend/native tests and shared fixtures are authored.
Gateway MCP source, schemas and focused regressions are now authored and dependency metadata is resolved.
Unit/integration suites, migration execution, native/gateway builds, agent flows and deployment remain unrun.
P1.4 now includes the iOS MCP bridge, native Apple tool loop, durable request/owner-response/stop journal and
Today assistant sheet. Its focused transport, recovery and controller tests are authored, unrun. P2.1 ranking/Today
and P2.2 daily selections/pairings, P2.3 local candidate help, P2.4 connected context and P2.5 daily automation are
now implemented in source. P3.1 manual laundry, P3.2 local laundry/label assistance, P3.3 wear/check-in reminders
and P3.4 reviewed local/connected timing/batches are also in source. P4–P6 remain pending, with laundry notification
delivery, broader scheduling and N05 selection rules still open.
No Helm changes or deployment were performed;
MinIO remains budgeted at 10 GB.
