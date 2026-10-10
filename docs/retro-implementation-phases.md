# Retro implementation phases

Started on 2026-10-08 from the approved [feature checklist](retro-feature-checklist.md).
As of 2026-10-09, new client implementation is **iOS only**; earlier Android work remains in source.
Keep on-device Apple Intelligence/native processing for suitable work and the existing agent endpoint for
connected context, scheduled execution and heavier/specialist processing. Apple Private Cloud Compute is excluded.
Since 2026-10-10 a language task can also run on the connected agent as a **visible, opt-in fallback** when the
device cannot read a request itself, holding the same validator and provenance rules as the on-device path; see
[language tasks](retro-language-tasks.md). That is not an automatic cloud fallback and not a change to what runs
where by default.
Every feature keeps ordinary engine validation, durable writes and manual fallback. The MinIO budget stays 10 GB;
infrastructure deployment is outside these source implementation phases. The separately requested signed iPhone
build/install/launch through P3.4 passed on 2026-10-09; feature suites and live backend/model flows remain unverified.
For the next implementation agent, start with the [P4–P6 handoff](retro-p4-p6-handoff.md).

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
and deployment remain deferred. Deploy the new gateway and iOS client together. Temperature sensitivity is now
implemented (see the N05 section below); automatic forecast-driven ranking, precipitation/water-resistance
suitability and layering rules still require further N05 work.

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
change. Xcode project generation includes the new sources. On the owner's subsequent 2026-10-09 deployment request,
the signed Debug build containing P1–P3.4 passed, installed and launched on the iPhone 17 Pro; its running process
was confirmed. Suites, migrations, backend integration, actual model/agent flows and full device/accessibility checks
remain unrun. P3.1–P3.4 are implemented in source. Notification delivery and richer scheduling/provider formats
remain follow-ups; P4 capture/discovery/maintenance is the next implementation phase.

## P4 — Capture, discovery and wardrobe maintenance

Outcome: faster garment entry, complete search, useful reviews and dependable multi-item maintenance.
Checklist coverage: N04, N09, N10, N11 and the remaining N12 purchase/style metadata.

The [handoff](retro-p4-p6-handoff.md#p4--recommended-source-slices) defines the recommended P4.1–P4.6 sequence,
existing source entry points and acceptance criteria. Start with P4.1 records, then search, analytics, capture,
purchase reconciliation and bulk maintenance.

P4.1 is implemented in engine/iOS source on 2026-10-09. The ordinary garment record gained optional pattern, style,
owner-supplied fit and one purchase record. Brand, material, colours, seasons, favourites and confirmed care were
already present. Pattern, style and fit are bounded free text like subtype/material/brand: the owner's own
description, not a claim that appearance proves anything, and absent means unknown. No migration was needed because
garment attributes are stored as JSONB; both existing operations, `garments_create` and `garments_update`, carry the
new fields, so the registry stays at **46**.

The purchase record defines money before saving. It holds an ISO date, a source (`manual`, `receipt`, `connected`),
bounded evidence text (required for the non-manual sources, mirroring care labels), an optional ISO 4217 currency and
an exact integer `amount_minor` in that currency's minor units. Callers may supply the owner-typed amount as a plain
decimal (`"199.9"`); the engine parses it with `strconv` — never floating point — against the currency exponent, and
rejects precision the currency does not have rather than rounding. Exponents come from a short table of the
non-two-decimal ISO currencies with a documented two-decimal default; the derived `currency_exponent` is recomputed
on every write, ignored if supplied, and returned so clients format without duplicating the table. An amount requires
its currency, a currency may stand alone as a partial record, and currencies are never converted, summed or inferred.
Absent means unknown; an explicitly recorded zero stays zero and is never treated as missing.

Omission retains values and `null` clears the purchase record; an all-empty record normalizes to absent so the
ordinary patch clears it. Audit snapshots carry the new fields automatically, and historical outfit snapshots keep
the metadata and purchase facts confirmed at the time. On iOS, pattern/style/fit are editable text fields and the
purchase section covers date, amount, currency, source and evidence. Every new stored field is optional, so responses
and saved drafts written before P4.1 still decode, and unchanged values are omitted from patches; selected-field
recovery can reapply or clear each field, including the purchase record as a whole. Android wire compatibility is
unchanged and no Android work was added. `WardrobeGarmentRecordTests`, the engine unit/money cases, a queued-record
integration test and `garment-records.json` are authored. Go formatting, the focused engine unit tests, 46-operation
OpenAPI regeneration and Xcode project generation ran; the simulator app and test targets compiled. Integration and
migration execution, device builds, suite runs and live flows remain deferred.

P4.2 is implemented in engine/iOS source on 2026-10-09. `garments_list` filters on name, brand and notes substrings;
colour and season as whole recorded values (case-insensitive, matched element-wise against the stored lists);
category; availability; favourite; confirmed wash method; whether care has been reviewed; and archive state. Every
predicate is optional, and an absent filter is never a wildcard value. Four sort orders are defined with a stable
tie-break: `id` (default), `name`, `recent` (updated) and `added` (created), the latter three breaking ties by ID in
the same direction as the order.

Cursors are keyset positions, not offsets. The cursor carries the sort key of the last returned record plus its ID,
so ties neither repeat nor skip, and its scope hash covers the complete filter *and sort* request: changing any
predicate or the sort rejects the old cursor as `invalid_input` rather than returning a mixed result. Timestamp
cursors are parsed as instants and compared as `timestamptz`, so paging stays exact below one second. The list also
reports `total_matches` — counted in the same repeatable-read transaction as the page — so clients can disclose
coverage; it is documented as one read of the current records, not an immutable multi-page snapshot, and the
default/maximum page size remains 50/200.

iOS adds brand, notes, colour, season, favourite, wash-method and care-state controls, a sort menu, an active-filter
summary and a coverage line that never claims completeness for a cached page. Text filters debounce like the name
search. The on-device interpretation now returns the same editable filters — including brand, colour, season, notes,
favourite, wash method and care state — validated before use, with unsupported conditions still listed as "Not
applied" instead of being dropped; the model is instructed to copy colours and seasons verbatim and to keep material,
warmth, subtype, similarity and wear dates in that unsupported list. Manual controls and manual search are unchanged
and need no model. No connected search adapter was added: the local filters cover the documented predicates, and the
existing generic agent remains available if a future predicate genuinely needs external data. Existing account,
revision and cancellation fencing is unchanged, and the second increment's cursor/limit semantics are untouched.

`WardrobeSearchTests`, the engine search/paging integration test and the `inventory.json` coverage field are
authored. Focused engine unit tests, formatting, 46-operation OpenAPI regeneration and Xcode project generation ran;
the simulator app and test targets compiled. Integration/migration execution, Swift suite runs, device builds and
live flows remain deferred.

P4.3 is implemented in engine/iOS source on 2026-10-09. `wardrobe_analyze` now returns ranked usage, unworn
lists, colour distribution, weekly trends, an explicit-feedback summary and separate selection/plan counts
alongside the existing counts and category usage; no new operation or migration was needed, so the registry
stays at **46**. Only outfits whose *current* state is `worn` count as wears, which is what makes voiding,
restoring and correcting a record move every figure together. Plans, saved selections, viewed records and
ratings never become wear events or ratings; plans and selections are counted in their own summary.

Ranked usage returns the most and least worn garments with in-range wear events and distinct wear days, each
capped at 20 with `ranked_limit` disclosed. Garments with no in-range wear are excluded from the ranked lists
entirely so an unworn piece can never occupy a "most worn" row. Cost per wear is per garment and per currency:
it divides the recorded `amount_minor` by that garment's confirmed wears on or before the review end date,
rounds to the nearest minor unit, discloses its own denominator, and is absent when either the price or a
confirmed wear is missing — never zero, and never summed across currencies.

The unworn lists are ordered oldest-first and capped at 50 with their full totals; a garment not worn in the
range reports its last wear on or before the end date, while `never_worn` (a strict subset) covers garments
with no confirmed wear at all, so a piece worn last month is visibly different from one never worn. Colours
distribute recorded tags case-insensitively over the inventory and its in-range wears, note that a multi-colour
garment counts under each tag, and cap at 100 entries with a truncation flag. Weekly buckets start on Monday
and keep the most recent 104 weeks with an explicit truncation flag; an unbounded review starts from the
earliest confirmed wear. Feedback summaries count records, rated/comfort/style coverage, comments and rating
buckets for worn outfits in range only.

iOS shows the ranked lists, both unworn lists, the colour distribution, recent weekly buckets and the
feedback/selection split, and each entry links to the ordinary garment detail (which reads the current record
before showing it). The deterministic summary states the facts and discloses every cap, and it refuses a
response whose category totals, unworn totals, ranked counts, cost-per-wear denominator, rating buckets or
period do not agree. An optional **Explain this review on device** button sends only the already-validated
summary sentence to the on-device model, which is instructed to add no causes, garments or coverage; the model
path is labelled as commentary and the deterministic figures stand alone without it. `WardrobeUsageReviewTests`,
the analytics integration test and `usage-review.json` are authored. Focused engine unit tests, formatting,
46-operation OpenAPI regeneration and Xcode project generation ran; the simulator app and test targets compiled.
Integration/migration execution, Swift suite runs, device builds and live flows remain deferred, so the new
analytics SQL and the new native checks are authored rather than verified.
P4.4 is implemented in iOS source on 2026-10-09. Similar-item checks now walk the **complete active inventory**
instead of one cached page: the client pages `garments_list` (200 per request, the existing keyset cursor) up to a
2000-garment index limit and uses the engine's `total_matches` to decide whether the walk was complete, so
completeness is never claimed from a single page. Each candidate carries its garment ID, name, exact version and
primary media ID.

Comparison is planned locally: cached thumbnails are used first under a 16 MiB byte budget, then up to 120
thumbnails are fetched within the scan, and every candidate that is not compared is counted — garments without a
photo and candidates skipped by the budget or a failed fetch. The returned scan states the numbers it actually
covered, discloses a truncated index, and repeats that the closest matches are photos to review, never a duplicate
verdict. Nothing is merged, deleted or written by a scan.

Every hint is bound to the source photo bytes by SHA-256 checksum and to the pinned Vision feature-print revision,
and applying one still re-reads the garment and requires its exact version and the same primary photo before the
ordinary "use this existing garment" confirmation, which only replaces the *unsaved* new-garment details. A
cancelled scan, an account change, a finished draft or replaced photo bytes cannot apply a stale hint, and the
whole scan is cancelled on dismissal or background.

Text and label extraction was broadened to match what the screen already claimed: it now proposes brand, material,
pattern, style, fit, colours and seasons in addition to name, category, subtype and notes, each copied from the
owner's own words or the label. A deterministic literal check then drops every proposed value the supplied text does
not actually contain and reports it as "not proposed" instead of offering it, so a plausible-looking brand or
material can never enter the form unstated; case differences are ignored and multi-word values must appear as the
stated phrase. Warmth, price and purchase details, authenticity, laundry state and care instructions are still never
proposed, nothing is guessed from a garment photo, and no direct model image path is added — feature prints stay on
Vision with a pinned revision. Applying a suggestion still replaces only the fields the owner selects, and unknown
attributes remain unknown. Manual entry and the resumable import flow are unchanged and need neither Apple
Intelligence nor the agent. `WardrobeDuplicateTests` and the extended assistance tests are authored. No engine,
contract, migration, gateway or storage change is needed; the registry stays at **46** and the generated contract
is byte-identical. Xcode project generation and the simulator app/test compiles ran; Swift suite runs,
integration/device checks and live flows remain deferred.
P4.5 is implemented in iOS source on 2026-10-09 for the **local** half. The garment form's purchase section gains
**Read a receipt or price label**: the owner scans a receipt (local Vision text recognition, no upload) or types
what it says, and the on-device model reads only the purchase date, the final total, the currency and the merchant
from that text. A deterministic gate then verifies every figure against the text before offering it. Totals are
normalized only when they read one way — `1,234.56` becomes `1234.56`, while `1,50` and a bare `12,345` are refused
because they mean different numbers in different countries. A currency is proposed only when the receipt states a
three-letter code or spells out an unambiguous name such as "US dollars"; `$` or a bare "dollar" is reported as
"choose the currency yourself" instead of being guessed. A date is accepted as an ISO date or a date spelled with a
month name (normalized for the record), and an all-numeric `03/02/2026` is never converted. A merchant the text does
not name is dropped. Everything dropped is listed, and a total with no currency cannot be applied.

Applying fills only the open form's purchase record — date, amount, currency, `source: "receipt"` and the reviewed
recognized text as the bounded evidence the record keeps — and never saves: the ordinary garment save with its
frozen request, version check and rejected-field recovery still owns persistence, so the owner reviews the fields
and the record together. Reading is account-, form- and cancellation-fenced with the existing 20-second bound, so a
late or changed result cannot apply. Retries cannot duplicate a purchase: the purchase is one attribute of one
garment and the save is versioned and idempotent, so re-applying the same receipt produces no change. Manual entry
of every purchase field is unchanged and needs no model.

**Connected purchase reconciliation is deferred, deliberately.** The handoff requires inspecting real tools/result
schemas before building that adapter, and provider access is not established. Source inspection of the sibling
harness found no purchase, order or receipt capability: the only "receipt" in the gateway MCP contract is P2.5's
notification-delivery receipt, and the generic `ask_agent` remains the sole path with no typed purchase result
schema. Writing an adapter now would mean inventing that schema, so the local path stands alone and the connected
one stays open until a real connection exposes actual purchase records. Consequently, matching one receipt's line
items to several garments is also not implemented: each reading applies to the garment already being edited.

`WardrobeReceiptTests` is authored (amount normalization, currency and date literalness, dropped-value reporting,
selective application, repeat-application stability and the evidence requirement). No engine, contract, migration,
gateway or chart change is needed; the registry stays at **46** and the generated contract is byte-identical. Xcode
project generation and the simulator app/test compiles ran; Swift suite runs, device/model checks and live flows
remain deferred.
P4.6 is implemented in iOS source on 2026-10-09. Wardrobe → **Maintain several garments** lists garments with
explicit checkboxes (paged, filterable, with per-item reasons shown for anything that cannot take the chosen
action) and offers six real maintenance actions: mark available, mark needs wash, add to favourites, remove from
favourites, archive and restore. Restore lists archived garments; every other action lists active ones. An item that
is already in the requested state, is archived when an edit would be refused, or already has a pending save is left
out with its reason rather than written as a no-op, and the plan stops at the queue's own 100-item budget, reporting
every garment it could not include.

Review happens before anything is queued: the plan shows each garment, its current state, its exact version and the
action, and archiving is confirmed explicitly because it hides the garment until restored. A batch writes nothing
itself — it builds one frozen request per item (`id`, `expected_version`, and the patch for edits) and hands each to
the existing durable queue, so one-pending-write-per-entity, the frozen payload, the per-item retry/rejection rules
and the account fence are all the queue's, not the batch's. Photos, laundry, imports and pairings keep their own
single-item queues and are not batched.

Outcomes are reported per garment from the queue's own state — waiting, sending, waiting to retry, refused with the
engine's message, saved, or no longer pending — and a queued item is never presented as saved; if the session never
saw the acknowledgement, the copy says to open the record instead of claiming success. Re-running the same selection
is refused per item rather than duplicating intents, relaunching keeps refused and retrying items with their original
identities, and a signed-out client sends nothing.

Rotation, background image processing and reanalysis are **not** included, and the three are not blocked equally.
Normalization already applies the photo's EXIF orientation, so imported photos arrive upright; what remains is rare
manual correction, which is achievable today by uploading a rotated copy as new media (no new engine operation), and
was left out because it is a single-photo edit that duplicates stored bytes under the 10 GB budget rather than a
missing capability. Background image processing needs an iOS background-scheduling/entitlement decision, and the
on-device model cannot run while the app is not running; the existing queues already resume on foreground and
reconnect. Reanalysis specifically means there is no stored feature-print index: prints are computed per scan and
valid only within the pinned Vision revision, so making whole-wardrobe duplicate checks instant is a persistence
question, not a model one. None of the three was faked with a local re-render. Photo replacement already creates new
media and leaves historical derivatives referenced, which the existing MinIO lifecycle integration test asserts.

`WardrobeBatchTests` is authored (plan skip reasons and capacity, frozen per-item intents, one request per item with
no duplicates on a second run, partial acknowledged/refused/retrying outcomes, relaunch identity, and a signed-out
client that can report nothing saved). No engine, contract, migration, gateway or chart change is needed; the
registry stays at **46** and the generated contract is byte-identical. Xcode project generation and the simulator
app/test compiles ran; Swift suite runs, device checks and live flows remain deferred.

- [x] Add richer metadata, amount/currency/evidence semantics, full server filters/sort and real ranked usage lists.
  **P4.1 supplies the metadata and money semantics, P4.2 the server filters/sort/coverage and P4.3 the ranked
  usage, unworn, distribution, trend and feedback aggregates above.**
- [ ] Prefer local OCR/cutouts/feature prints and guided extraction. Direct Apple image prompting needs compatible
  SDK/OS/model/device support; use available agent image tools only for tasks requiring that remote capability.
  **P4.4 keeps every comparison on-device with a pinned Vision revision and adds no model image path;** it does not
  settle whether a future capture feature needs one.
- [x] Add complete-inventory duplicate proposals, source-linked analytics and local explanations of engine aggregates.
  **P4.3 supplies the source-linked analytics and the bounded local explanation, and P4.4 the complete-inventory
  duplicate scan above with its disclosed coverage and source binding.**
- [ ] Reconcile supporting purchase records through agent connections, with uncertain matches reviewed before saving.
  **P4.5 delivers the local receipt/label reading, literal figure checks and reviewed application above.** The
  connected half stays open: it needs a real connection that exposes purchase records before a typed adapter can be
  written, and no such tool exists in the inspected gateway contract.
- [x] Add bounded bulk maintenance with explicit selection, per-item progress, stable identities, retry/recovery and
  protection of historical photos. Keep suitable photo operations local and heavier jobs outside engine transactions.
  **P4.6 delivers the explicit selection, frozen per-item requests, per-item outcomes and queue-reusing recovery
  above.** Rotation, background image processing and reanalysis need capabilities that do not exist yet (immutable
  derivatives, background scheduling, a feature-print index) and stay open.

## N05 weather and temperature (2026-10-10)

The temperature settings P1 stored (`temperature_unit`, `temperature_sensitivity`, `cold_threshold_c`,
`hot_threshold_c`) were validated and never read by ranking. They now drive a real term: `wardrobe_suggest` takes
an optional `temperature_c`, bands it against the owner's own cold/hot thresholds, and scores each garment's
**recorded** warmth against that band by the saved sensitivity (low/normal/high → weight 2/4/7). A garment whose
warmth tag is absent or `unknown` scores nothing and is never treated as the wrong layer; how many such garments
exist is reported in the response warnings. The reason on a scored garment names the value and the band
("its warm warmth suits a cold day. 4°C is a cold day for your thresholds."). No temperature means no temperature
term and an explicit "no temperature was supplied" warning, so a reading is never implied.

`precipitation` is accepted and **disclosed as unassessable**: no garment records water resistance, so nothing is
filtered or scored for it, and inventing suitability from material would be exactly the inference the product
forbids. Adding a water-resistance attribute is a product decision that has not been taken.

iOS adds the manual override the checklist asks for: a °C field on Suggestions with a **Use the reviewed forecast**
button that fills the midpoint (or the single end) of the forecast the owner already retrieved through P2.4, a
rain-or-snow toggle, and a note saying what a temperature does and does not affect. Nothing is fetched or applied on
its own: the value must be stated, and clearing the field removes it rather than sending a zero. Ranked reasons
already surface in the UI, so the temperature reason appears with the others.

Authored: `TestTemperatureUsesOwnerThresholdsAndRecordedWarmth` (banding at both thresholds, sensitivity scaling,
per-warmth scores including unknown, the reason text, the beam preferring the light layer on a hot day and the warm
layer on a cold day), an integration case for the warning lines and the `-60..60` bound, and the native
`temperature_c`/`precipitation` encoding including omission. **Still open:** automatic forecast-driven ranking
(nothing fetches a temperature; the owner supplies or accepts one), layering as a rule rather than the existing
disclosure, and water-resistance suitability. Every check remains unrun.

## Language tasks across executors (2026-10-10)

A language task is now declared once and can run on either the on-device model or the connected agent:
`WardrobeLanguageTasks` holds the instructions, the answer contract, the on-device reader, the connected parser
and **one shared validator**; `WardrobeLanguageDispatcher` chooses between them. `rawCapture` tasks are refused on
the agent by the dispatcher itself, so the local-only rule for raw camera, label and voice data is enforced in code
rather than by convention, and each answer records which executor produced it. See
[language tasks](retro-language-tasks.md).

Wired: **request interpretation** (search and outfit). When the device cannot read the request, the screen offers an
opt-in connected reading, sends only the owner's typed text plus the task's instructions and contract through the
existing `ask_agent` delegation, and holds the reply to the same `WardrobeLanguageDraft` validator and the same
90-second/two-delegation journal as the other connected features. **Garment extraction** runs through the same seam
on device, with the connected parser and the literal-evidence gate already in place, but has no UI opt-in yet. The
tool-using adapters (candidate help, laundry planning, outfit context) deliberately keep their own shapes.

Authored: `WardrobeLanguageTaskTests` covers routing and provenance, the raw-capture refusal, fallback when a
preferred executor fails or returns an invalid draft, the shared validator rejecting the same bad draft on either
route, the literal gate dropping a brand the owner's text does not contain, and the delegation's query budget.
Everything remains **unrun**. No engine, contract, gateway or storage change; the registry stays at **46**.

## P5 — Live try-on feasibility

Outcome: measured evidence for a rendering approach that can meet the requested live-camera experience.
Checklist coverage: N02 feasibility; can start alongside P2–P4 without blocking them.

- [x] Define the required camera setup, asset capture, garment categories and measurable fidelity/latency/battery targets.
  **P5.1 is authored in [the feasibility record](retro-try-on-feasibility.md):** camera, distance/positioning,
  lighting, motion and category scope, the asset requirements (views, mask, scale, colour, format-undecided,
  missing-asset behaviour, retention under 10 GB) and a proposed benchmark budget whose numbers are explicitly not
  approved targets, with observed results kept separate.
- [ ] Prototype native pose/person masks and a purpose-built local renderer/model on the owner's actual device.
  Foundation Models handles language commands, not per-frame clothing simulation.
- [ ] Evaluate agent asset preparation or a specialist renderer only where needed; measure swap response and video
  consistency with the real camera/network rather than assuming agent access provides live rendering.
- [ ] Record the supported approach, category limits, capture requirements and failures before planning delivery.

A still image or static overlay can inform experiments but does not complete N02.
No renderer, asset format or quantitative acceptance thresholds have been selected. Record measured evidence and
the go/no-go decision in [the feasibility record](retro-try-on-feasibility.md) before P6 renderer delivery; see the
[handoff's feasibility gate](retro-p4-p6-handoff.md#p5--feasibility-gate-before-delivery). **P5.1 (specification and
proposed benchmark budget) is authored there; P5.2–P5.4 wait on the owner's device measurements**, which the
current validation policy defers.

## P6 — Live try-on delivery and integrated client completion

Outcome: stand in the camera, see a suggested outfit, swap individual pieces/live looks and save the chosen plan.
Checklist coverage: N02 delivery and integration across all required N01–N12 features.

- [ ] Implement camera positioning guidance, moving-person preview, layering/occlusion and stable live swaps.
- [ ] Add reachable/hands-free controls, tracking-loss/loading/recovery states and the ordinary reviewed save path.
- [ ] Deliver supported iOS behavior with explicit device/camera/category capability limits. Preserve Android wire
  compatibility; new Android implementation/rendering is outside the current scope.
- [ ] Complete accessibility, account isolation, pending/offline recovery and bounded preview retention within 10 GB.

Family sharing, browser UI, localization and configurable providers remain optional O01–O04 product choices.
P6 integration must explicitly reconcile remaining N01–N12 gaps, including broader weather rules, delivery and
connected pairings; completing the camera alone does not close them. See the [handoff](retro-p4-p6-handoff.md).

## Delivery and validation discipline

Each iteration completes a small source slice and records its actual status here. Author focused tests for new
rules/contracts and dangerous retry/conflict paths; do not claim a feature complete because its DTO or prototype exists.
At the owner's request, runtime/test-suite validation follows implementation/deployment. Deployment itself needs
a separate request; these phases do not deploy infrastructure or install new phone builds automatically.

Historical P1 evidence: Go formatting, the OpenAPI generator and Xcode project generation completed; the generator compiled
the engine and produced the 25-operation contract. Focused backend/native tests and shared fixtures are authored.
Gateway MCP source, schemas and focused regressions are now authored and dependency metadata is resolved.
Unit/integration suites, migration execution, native/gateway builds, agent flows and deployment remain unrun.
P1.4 now includes the iOS MCP bridge, native Apple tool loop, durable request/owner-response/stop journal and
Today assistant sheet. Its focused transport, recovery and controller tests are authored, unrun. P2.1 ranking/Today
and P2.2 daily selections/pairings, P2.3 local candidate help, P2.4 connected context and P2.5 daily automation are
now implemented in source. P3.1 manual laundry, P3.2 local laundry/label assistance, P3.3 wear/check-in reminders
and P3.4 reviewed local/connected timing/batches are also in source. P4.1 richer garment records, P4.2 complete
server search, P4.3 source-linked reviews/ranked usage, P4.4 complete-inventory duplicate scans, P4.5 local
receipt/label purchase reading (its connected half stays open) and P4.6 bounded multi-item maintenance are in
source, so **P4 is complete in source**. P5–P6 remain pending, with laundry notification delivery, broader
scheduling and the remaining N05 rules (automatic forecast-driven ranking, water-resistance suitability) still open,
plus the capabilities P4.6 could not use.
Latest native evidence (2026-10-09): the signed Debug build through P3.4 passed, installed and launched on the
iPhone 17 Pro, with its running process confirmed. Earlier phase notes about deferred native builds describe their
original iteration status. Suites, migration execution, actual Apple/agent/provider flows and full device/accessibility
checks remain unrun. No infrastructure deployment was performed in these iterations; current chart source supports
Retro/MinIO/gateway wiring but running images and tenant overrides were not checked. MinIO remains budgeted at 10 GB.
