# Retro context and agent boundary — P1–P3

Implemented 2026-10-09. Shared wardrobe facts use the existing engine's authenticated router path and MCP
registration. Remote delegation uses the gateway MCP path described below; no new host or infrastructure deployment is added.
Apple inference stays on the device; ordinary authenticated record reads supply facts. Private Cloud Compute is excluded.

## Implemented factual context

`POST /retro/api/v1/operations/wardrobe_context_get` through the router, or the identically named registered engine MCP tool:

```json
{
  "request_id": "<caller-generated UUID retained for this request>",
  "garment_ids": ["<up to ten explicit garment UUIDs>"],
  "outfit_ids": ["<up to five explicit outfit UUIDs>"]
}
```

The engine normalizes UUIDs and rejects duplicates, invalid IDs and oversized selections before reading records.
Missing requested records fail the request instead of silently shrinking coverage. A read-only repeatable-read
transaction returns one consistent snapshot. The result contains:

| Field | Meaning |
| --- | --- |
| `schema_version` | Contract version 1 |
| `request_id` | Echoed normalized request identity; reads do not create jobs or journal writes |
| `retrieved_at` | UTC time of this snapshot; `sources[].updated_at` is the underlying record freshness |
| `coverage` | Always `explicit_records_only`; this is not a complete inventory or connected-services view |
| `capabilities` | `wardrobe_records`, `preferences`, `care`, `feedback`; no scheduler, weather, calendar or renderer is advertised |
| `preferences` | The current singleton settings and machine presets |
| `garments`, `outfits` | Only requested records; confirmed wears retain their snapshots |
| `feedback` | Feedback for requested outfits, with saved/current outfit versions and state |
| `sources` | Entity type, stable ID, exact integer version and last-update timestamp |

Responses exceeding 128 KiB fail with an instruction to request fewer records. Feedback version zero means
**no saved feedback**, with no update timestamp; it is not a zero rating. Context is factual as of its retrieval,
not a promise that availability stays unchanged. Every eventual mutation still requires ordinary engine versions,
idempotency and explicit review. Cross-type identities are qualified by `entity_type` when comparing sources.

## Native Apple tools and editing

iOS settings assistance scopes reads to its current editor: preferences, one garment or one outfit. The request
UUID is stable for that invocation. Its Foundation Models tool cannot accept another record ID or make a write.
It permits two reads, keeps results in memory rather than a request-UUID read cache, rejects error results and checks schema/request/coverage and source versions against
the reviewed editor, and supplies at most 10,000 bytes of compact facts to the local model. Both Engine and Store
fence account changes. A 20-second UI deadline, explicit cancellation and background dismissal invalidate late results.

Typed proposals accept only supported settings, bounded values and verbatim supporting excerpts from entered
request/label text. Ratings and care temperatures require explicit numeric evidence. The owner reviews proposals
before applying them to the form. Applying care proposals clears confirmation; saving uses the ordinary durable
write queue. Android has the same manual record/edit/save/recovery contract without Apple APIs.

## Existing agent-harness transport

Source inspection found these existing conventions:

- `/gateway/ios/ws` and `/gateway/android/ws` accept an authenticated initial frame, conversational message IDs,
  turn IDs/sequences, resume and cancellation. Mobile adapters allow only their main platform-scoped session.
  A mobile cancel stops that session's active turn, so it cannot safely represent an isolated Retro background job.
- The gateway's HTTP adapter exposes `/gateway/send`, `/gateway/poll` and `/gateway/cancel` with bearer auth and
  selectable `session_id`. Send accepts `content`, `client_message_id`, `session_id`, `parent_session_id`.
  Poll uses `session_id` and `since_turn_seq`, returning completed/failed/cancelled turns and pending user input.
- Poll includes durable `tool_calls` with tool identities, arguments, status and JSON results. Realtime clients
  advertising `tool_calls` also receive these activity frames. Structured tool results can be reused; the agent's
  narrative `content` is not a typed wardrobe result.
- Turn IDs and tool-call IDs are established transport identities. P2.5 separately uses a stable Temporal wake
  identity for daily automation; transport IDs alone are not a specialist-result schema or task-scoped tool
  allowlist. Creating a new session alone does not restrict the agent's available mutation tools.

Sources: sibling `agent-harness/router/internal/core/proxy.go`, `gateway/internal/mobile/mobile.go`,
`gateway/internal/realtime/frames.go`, and `gateway/internal/web/{web,send,poll,cancel}.go`.
These describe the existing chat adapters. The MCP adapter below is now implemented in gateway source; no live endpoint was contacted.

## Gateway MCP delegation

The sibling gateway now serves a Streamable HTTP MCP server at `/mcp`, exposed through the existing router at
`/gateway/mcp` on the configured router base URL. Its single generic tool is `ask_agent`:

```json
{
  "request_id": "<native-controller-generated UUID retained for this task>",
  "query": "<the task or question for the remote agent>"
}
```

Every HTTP request carries the existing Clerk bearer JWT. The gateway reuses its verified owner, tenant slug,
Postgres, Temporal and activity routing. Each task has its own owner/tenant-scoped session and ordinary agent
turn; it does not signal the main chat. Retrying/polling with the same ID and query returns the same execution;
changing the query returns a conflict. Completed results remain readable from Postgres and a recorded execution
is never restarted after Temporal history expiry. Transport sessions are stateless and can move across replicas.

Version-1 envelopes carry request/session/turn IDs, retrieval/completion times and `running`, `needs_input`,
`cancelling`, `completed`, `failed` or `cancelled` status. Each call waits at most ten seconds within a twenty-second
request deadline. Gateway implementation 1.1 caps results at 32 KiB: a bounded answer plus up to six recent direct
tool-call records with raw JSON results of at most 4096 bytes each, execution times and explicit truncation.
Completed `call_tool` evidence can include bounded `server`/`tool` identities taken from its actual arguments;
arbitrary arguments and credentials are not exposed. `coverage: recent_top_level_tool_calls` does not
claim complete wardrobe or connected-service facts; tool timestamps are not underlying fact expiry. Exact
integer versions are preserved. Domain facts still need their own validated schemas and source/freshness/coverage.

Repeat the original request with `cancel: true` to cancel that turn cooperatively. `cancelling` is an acknowledgment,
not proof of completion. Disconnect stops the HTTP wait while the durable task remains resumable. Repeat with
`response: {request_id: <pending_input ID>, selected_option_id: <advertised option>}` or permitted `free_text` for
a reviewed owner answer; pending approvals in subagents are included. Both ownership and response choices are
validated. Oversized approval previews fail instead of being silently truncated. No automatic approval is supplied.

The gateway retains the existing agent tool/trust policy and is not advertised as read-only. MCP supplies transport,
discovery and query delegation; it does not establish a task-specific tool allowlist or typed specialist facts.
Detailed server contract: [gateway MCP](../../agent-harness/docs/components/gateway/mcp.md).

## Implemented iOS model and MCP loop

**Today → Ask Retro** creates a fresh `LanguageModelSession` with the explicitly selected on-device system model.
Apple's [native tool loop](https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling)
performs model → tool → result → model; the app supplies the execution limits and owner controls.
The ordinary settings helpers remain editor-scoped and unchanged.

The assistant registers `read_wardrobe_preferences`, a fresh authenticated read of preferences only, and optionally
`ask_agent`, whose generated arguments contain **only `query`**. Connected help starts disabled. An explicit
**Ask connected agent** action is also available without Apple Intelligence; it bypasses local inference and sends
the owner's request to the same gateway. No failure silently substitutes a remote model for the Apple model.

| Limit | Enforcement |
| --- | --- |
| Owner question | Nonempty, at most 1,200 UTF-8 bytes; selected date validated by the existing date helper |
| Model-generated delegation | Nonempty, at most 1,800 bytes; original owner question, date and timezone also retained |
| Calls | At most two preference reads and two remote tool invocations; remote calls are serialized |
| Local tool context | At most 2,000 bytes per result and 3,500 bytes across tool results; oversized preferences fail without discarding restrictions |
| Remote model context | At most 800 bytes of answer plus two source identities, with explicit excerpt/coverage flags; raw arbitrary tool JSON is kept out of the prompt |
| Generation | `maximumResponseTokens: 600`, a fresh session and a 90-second overall deadline, including owner input |
| Polling | At most 30 calls across an attempt, honoring bounded server retry timing |

Preference facts check request/schema/coverage, exact source versions, known capabilities and retrieval freshness.
Machine presets, inventory and other domain facts are explicitly outside this tool's coverage. Remote envelopes check
the saved request, owner-qualified turn and nested input/source identities, times, byte limits and advertised choices.
Integer versions up to `Int64` remain exact. Remote narrative remains labeled untrusted evidence, rather than becoming
verified weather, care, calendar or wardrobe facts. The full bounded remote answer and evidence identities remain
available in the native request section even when the model receives an excerpt.

The private MCP adapter reuses the configured router host, owner-fenced Clerk token helper and single 401 refresh.
It performs initialize → initialized → tools/list → tools/call, validates JSON-RPC identities and the gateway's
tool/schema discovery, negotiates known protocol versions and caps wire responses at 128 KiB before decoding
(the gateway SDK includes both structured content and JSON text). Decoded envelopes retain the 32 KiB cap.
It reuses the existing ephemeral, cookie-free, redirect-free session. This adapter supports **our stateless JSON
gateway profile**, not arbitrary MCP servers: SSE or assigned transport sessions fail closed. Switch to the official
Swift MCP transport if that server contract expands; no new SDK, URL setting or credentials are added now.

## Durable tasks and native owner input

The controller generates task UUIDs and saves the immutable query **before** transmission. Identical delegated
queries within one model attempt reuse the same UUID; checks/retries/relaunch retain the original ID and query.
Account- and gateway-scoped atomic, protected files retain at most eight nonterminal tasks and three recent terminal
tasks when a new request is accepted. Transport credentials and Apple model transcripts are not journal fields. Unreadable or oversized
journals stay in place and block new connected requests; persistence failure prevents acceptance/transmission.

Polling and owner input happen inside the tool implementation, outside model-generated reasoning steps. The model
cannot produce task IDs, cancellation flags, option selections or free-text approval responses. Native controls show
the complete gateway prompt/options, allow only advertised choices/permitted free text, and persist the owner's
answer before sending it. The gateway's existing permission prompt is used; this does not add task-specific grants.
Closing an input or returning a terminal result clears its saved answer; no automatic approval is supplied.

Stop, deadline, sheet dismissal, backgrounding and account changes invalidate the local generation and store stop
intents for its nonterminal remote tasks. Best-effort cancellation uses only the original owner's credentials;
foreground/reconnect retries **saved stop intents only**, never starts new work or answers owner questions.
`Stop pending` stays pending until a terminal result is confirmed. A `not_found` cancellation retains its identity
and intent because an ambiguous original send may still arrive; it is never converted into a new task.
Network/model errors retain recoverable tasks. **Check saved request** retrieves the same job and displays its remote
answer directly; an interrupted Apple transcript is not replayed. Previous-owner and cancelled-generation results
cannot populate the current assistant answer.

## P2.3 reviewed local outfit choices

Today, Suggestions and refreshed Compare now reuse this controller with `read_outfit_choices` and optional
`ask_agent`. The Apple model stays on-device. The local read uses the ordinary authenticated `wardrobe_suggest`
operation for the fixed request, preserving its date, variant, locks, exclusions and captured preference version.
It rejects cached results, changed preference identity or option ordering, garment version/name/role changes,
pending piece/settings saves and account/request/date/time-zone/revision changes. Only a fresh `rules-v2` response
with validated fingerprints and ranking coverage becomes model context.

Candidate aliases `c1`–`c3` and candidate-scoped piece aliases `g1`, `g2`, etc. bind to the native snapshot; raw UUIDs
and fingerprints are absent from the model's tool result. Versions remain exact native `Int64` values and use
strings in the bounded JSON. The first three reasons per choice and shortened names/reasons carry omission flags.
Native review retains all original reasons, names, scores, missing roles, feedback coverage and engine warnings.
One fresh snapshot is supplied in at most two tool calls; the second returns a short same-source receipt. This
feature caps tool output at 4000 bytes/result and 5500 bytes/attempt and guided generation at 700 response tokens.
The existing 90-second deadline, two-delegation limit, polling, durable jobs and owner-input/stop fences still apply.

Guided proposals may select a supplied option, reference displayed engine reasons or identify one unlocked piece
to swap. Unknown/out-of-range/duplicate references, locked targets and malformed output fail closed. Model commentary
is displayed separately from authoritative engine evidence. Ambiguity/unavailable actions appear as unsupported;
continuing without other unsupported conditions requires native acknowledgement. No proposal queues a write.
Plan review uses the existing fresh eligibility/garment checks and unsaved editor. Swap review refreshes the source,
keeps all other pieces locked, retains original exclusions and requires the target's replacement role before opening
Suggestions. The earlier Describe an outfit helper still reviews occasion/warmth and unresolved garment hints in
native controls. Unavailable models/oversized context use manual Compare, interpretation and per-piece swaps.

Connected help defaults off. Optional delegation remains bounded generic narrative, with the agent's existing tool
permissions and native owner questions; a request to avoid writes does not create a server-enforced read-only grant.
This feature does not turn connected prose into verified weather, calendar, travel, care or pairing facts.

## P2.4 sourced outfit context

Outfit help adds a native **Retrieve connected context** action and, when connected help is enabled, the Apple
tool `read_outfit_context`. The native controller captures the selected date/timezone and the owner's explicit
weather location; an empty location makes weather unavailable. It sends a fixed bounded query through the same
generic MCP `ask_agent`. The agent discovers available connections and requests small relevant provider reads:
one daily forecast, up to three calendar events and two agent-selected travel events overlapping that local day.
There is no separate weather endpoint, provider credential or automatic GPS collection.

The remote answer is a JSON projection manifest, not a prose forecast or inline factual DTO:

```json
{
  "schema_version": 1,
  "day": "2026-10-09",
  "time_zone": "America/Los_Angeles",
  "location": "San Francisco",
  "weather": {
    "status": "available",
    "reason": "",
    "items": [{
      "source_id": "<actual completed call_tool ID>",
      "fields": {
        "day": "/forecast/day",
        "time_zone": "/forecast/time_zone",
        "location": "/forecast/location",
        "temperature_min": "/forecast/low",
        "temperature_max": "/forecast/high",
        "temperature_unit": "/forecast/unit"
      }
    }]
  },
  "calendar": {"status": "unavailable", "reason": "No calendar connection", "items": []},
  "travel": {"status": "unavailable", "reason": "No travel evidence", "items": []}
}
```

Every field must resolve through an RFC6901 pointer into the referenced retained, nontruncated provider result.
The reader supports JSON text nodes returned by MCP tools. It checks the owner envelope and actual `call_tool`
connection/tool identity, field types, explicit C/F temperature units, exact selected weather day/location, IANA
zones and event overlap. Calendar/travel fields require title, start, end and time_zone; location is optional.
Timestamps need ISO8601 offsets; all-day ISO dates have exclusive ends. Unknown formats, missing identities,
fabricated pointers, stale or oversized results fail into explicit unavailable/partial coverage. Other valid
sections remain usable. These checks establish literal provenance, not the semantic correctness of the agent's
field mapping or travel classification. Empty selections are not complete schedule coverage or booking proof.

Accepted facts expire 30 minutes after the oldest accepted source call started. Resuming a completed request does
not refresh its fact age. If a provider issue time is present it must be within six hours; if absent, native UI
explicitly says the forecast's cache age is unknown. Retrieval time, provider issue time, source pointer/identity,
provider timezone, coverage and expiry remain visible in the native review. Version-1 generic envelopes without
the new identities remain valid advice but cannot supply typed outfit context; deploy gateway 1.1 and iOS together.

The local model receives at most 2000 bytes of typed facts, coverage/expiry and scoped aliases (`w1`, `e1`–`e3`,
`t1`–`t2`); raw provider JSON and task IDs stay out of its prompt. Fresh context already retrieved natively is reused
after the model's read tool is called. Generic `ask_agent` prose does not supply these aliases. Candidate/model
tool output retains the existing combined 5500-byte budget and two-delegation limit. Oversized model context leaves
full native evidence and manual controls available.

The model may cite supplied aliases when comparing choices or propose a separate reviewed warmth/occasion change.
Native validation checks aliases, freshness, scope and supported fields. Review refreshes the original engine
choices and preserves locks, piece/combination exclusions and preference constraints, then opens Suggestions with
the reviewed change. Manual context retrieval and manual adjustments remain available without Apple Intelligence.
There is no automatic save, wear, booking or engine weather filter. Unsupported conditions still require review.

Matching nonterminal context requests resume the original saved query/UUID. Typed recovery, owner questions,
cancellation, deadline and account/request/background fences use the existing journal/controller. Connected help
defaults off. The query requests reads only; **the generic gateway still uses its existing agent permissions**,
so this is not a server-enforced read-only grant. Provider data is treated as untrusted data, never instructions.
The current adapter supports explicit provider units and ISO dates; provider-specific formats can be added after
the owner's deployed connections are known.

## P2.5 daily automation and connected delivery

The phone configures background work; Apple Foundation Models remains the local interactive model and is not
expected to run while iOS sleeps. The existing harness headless `WakeSession` path executes the agent's scheduled
turn. The native surface uses the same generic query-only `ask_agent`, existing permissions, owner questions and
durable journal. Applying is explicit authorization for recurring generation and the reviewed delivery destination.
There is no new MCP endpoint, provider SDK, push service or scheduler deployment.

| Operation | Contract |
| --- | --- |
| `wardrobe_daily_settings_get` | `{}` → `settings`, a versioned singleton (`8fe141a8-c2af-435c-9e94-166b53fa4b1a`) |
| `wardrobe_daily_settings_update` | Ordinary `PatchInput` for enabled, mode, hour/minute, IANA zone and optional connected-service recipient |
| `wardrobe_daily_generate` | Current `expected_settings_version` + retained `idempotency_key`; returns one immutable ranked `run` per day/zone |
| `wardrobe_daily_get` | `day`, `time_zone` → nullable `run`, including current delivery state |
| `wardrobe_daily_delivery_claim` | `run_id`, new retained UUID `claim_id`, `idempotency_key` → `run`, `send_allowed` |
| `wardrobe_daily_delivery_complete` | Same run/claim, new retained retry key, bounded provider `receipt` and actual send tool-call `source` → `run` |

Settings are separate from wardrobe preferences and use the existing native frozen save queue and rejected-edit
recovery. Defaults are disabled, morning, 07:00 UTC and generation only. Mode is `morning` or `previous_evening`;
null fields are rejected, hour/minute and IANA zones are validated, and a recipient is bounded to 200 bytes. Saving
settings changes desired state. Applying reads those exact saved values, inspects and creates/revises the one wake
`wake:agent:main:web:user:<owner>:retro-daily-outfits`, then inspects it again. Disabling pauses only an existing
wake. Setup never generates or sends. Saving disabled settings independently blocks new generation/claims; stopping
an apply request cannot undo a wake already changed, so native recovery offers check/pause.

Native confirmation requires a completed, fresh, untruncated actual top-level `manage_wake` inspect result with
the exact scoped wake ID. Enabled proof also requires `WakeWorkflow`, the canonical owner session, recurring daily
hour/minute, saved IANA zone, the exact objective including settings version and a future firing. Temporal normalizes
cron into calendars, so worker inspection reports the actual normalized `daily_time`. SDK Payloads are decoded using
its data converter; revision uses the SDK update callback and preserves unrelated action/options/policy. Disabled
proof accepts paused state or explicit Temporal `NOT_FOUND` → absent; network/unavailable errors stay unknown.
This is a status snapshot, not a promise the wake cannot subsequently change. Narrative is never proof.

Generation reads current enabled settings/version under the existing engine write lock, determines its local date
from server time and allows two hours after the configured slot. Previous-evening targets tomorrow by calendar
date; nonexistent DST slots are skipped. Run UUIDs are deterministic for date/zone, expire at the following local
midnight and capture the exact preference version, effective occasion and ranked garment versions. Updated settings
apply to later runs and cannot replace an already generated day. Scheduled choices are displayed separately from
fresh on-open choices. Native plan review rechecks current ranking and pieces; no generation selects a plan, records
a wear or changes availability. Weather/context ranking is not assessed by this scheduled rules-v2 path.

With a nonempty recipient, the objective discovers an unambiguous connected sender before claiming. Claim validates
current settings/window/day/expiry and ranked sources and grants only one committed attempt. **A replay with the
same idempotency key intentionally returns `send_allowed: false`**, rather than replaying permission to send.
Competing claims also return false. Lost replies and uncertain sends remain `claimed`, visible for manual service
review, and never automatically resend. Completion records `sent` with the matching claim, an **agent-recorded**
provider receipt and tool-call reference, each bounded to 500 bytes; this does not authenticate the receipt.
Provider idempotency should use the run ID when supported. Connector retries still require deployed provider
support, and the generic agent can invoke tools outside this convention: there is no exactly-once external guarantee
or task-specific enforced tool grant. Empty recipient means generation only; APNs/iPhone push remains unimplemented.

Migration 0006 adds two tables and six operations extend the shared registry to 38. Existing engine URL/router/MCP,
database and 10 GB MinIO allocation are reused. Deploy updated worker, engine/migration and iOS together, with gateway
1.1 evidence support. Live schedules/senders, migrations, suites and builds remain deferred at the owner's request.

## P3.1 manual laundry boundary

The first laundry slice uses deterministic engine rules and native owner review. The existing P1 local care/OCR
helper is reachable from blocked preview items; no new inference service, remote job or model tool is required
to plan or finish a load. P3.1 extended the same router-authenticated HTTP/MCP registry to **45 operations**.

| Operation | Contract |
| --- | --- |
| `laundry_preview` | Explicit `program` → generation time, active-needs-wash coverage/count, versioned colour groups and blocked items/reasons |
| `laundry_create` | Optional UUID `id`, retained key, name/day/IANA zone, programme and 1–30 garment IDs/expected versions → planned `load` |
| `laundry_get`, `laundry_list` | Read retained care/garment snapshots and dated progress; list supports ordinary scoped pagination plus state/garment filters |
| `laundry_update` | Versioned `PatchInput` for planned name/day/zone/programme/items; new current garment review is required |
| `laundry_progress` | Load ID/expected version/key confirms the next real state; no state label can bypass the lifecycle |
| `laundry_cancel` | Versioned cancel of an unfinished load; active pieces return to needs wash without a completion claim |

Programme fields are `wash_method`, optional `temperature_c`, `cycle`, `drying`. Machine/hand require explicit
temperature and home drying; hand has no machine cycle. Dry cleaning requires professional care without a wash
temperature/cycle. The engine checks confirmed care, maximum temperature, exact machine cycle, colour separation
and drying. Unknown care stays blocked, and incompatible methods never silently become another programme.
The preview covers at most 2000 active `needs_wash` garments, not the whole wardrobe. It returns compact IDs,
exact integer versions/names and reasons; source details remain in the ordinary care record. Each load uses one
colour group, with wash-separately items alone. Capacity/unrecorded warnings and machine-specific gentler-cycle
equivalence are not assessed. Native manual settings/preset copies are explicit programme review, not new care facts.

Saving creates an editable plan and does not reserve or wash pieces. Start rechecks versions/care/availability,
rejects future planned dates, reserves each garment exclusively and marks it washing. Confirming wash finished
starts drying while pieces remain unavailable; dry/ready confirmation releases them. Professional return completes
the cleaning record directly. Server timestamps capture confirmations, separately from the planned local date.
Cancel retains progress/snapshots and releases active pieces to needs wash. Active garment edits/photo attachment/
archive are blocked; historical care/names/photos remain in snapshots. No wear record or inferred dirtiness is added.

Ordinary frozen native queue keys replay exactly; engine transaction/audit rules prevent duplicate progress.
Rejected create/edit recovery retains requested fields, reads the latest planned load, refreshes programme groups
and requires owner selection of current versions before replacing a definitely rejected request. Missing queued
programme/date/pieces fail recovery rather than becoming defaults. Rejected progress opens current state for
inspection; it never automatically confirms another stage. Unsaved native forms are in memory with discard
confirmation, while accepted requests remain durable. Migration 0007 adds two tables and an active-garment unique
index; no gateway/router/chart/storage changes are required. Deploy engine/migration and iOS together.

Agent-assisted timing remains next P3 work; P3.3 below adds derived wears/in-app reminders. Any future proposal still
needs these deterministic checks and native review; generic MCP delegation is not an enforced read-only or restricted
write grant.

### P3.2 local request and label boundary

The laundry editor's **Describe a laundry programme** uses the existing Apple guided-generation pattern with no
remote tool. Typed text or a reviewed local speech transcript becomes a bounded proposal over `machine_preset`,
`wash_method`, `temperature_c`, `cycle`, `drying` only. Every field cites literal request text. Numeric temperature
drafts require explicit Celsius units; cold/warm/hot and Fahrenheit conversion are not guessed. Native code maps an
explicitly named unique preset alias to its saved values, retains its exact preference source version and refreshes
that source before applying. The model never supplies source IDs/versions, actual preset values or garment selections.

Native review selects fields and acknowledges unsupported conditions. Unchanged form values remain unchanged;
wash-method changes clear incompatible settings and leave missing home temperature/cycle/drying for manual choice.
Contradictory hand/professional settings cannot be applied. Apply changes only the form and invalidates its previous
compatibility preview. Dates, real piece selection, save/progress and care compatibility remain ordinary P3.1 work.
Model output cannot create a load, mark a garment dirty, confirm care, set availability or restore clean/dry readiness.

The care editor now directly scans selected label photos using local Vision OCR and existing photo bounds. It
shows editable recognized text; applying requires the same account/form, marks source Label, clears confirmation
and leaves care settings unchanged. Photos are not uploaded; reviewed text is stored only with an ordinary saved
care record. The existing read-only care-model context then proposes evidence-supported changes. Care numeric
temperature proposals now also require explicit Celsius text. Symbols, missing units/instructions, ambiguous text
and OCR errors remain owner review; neither OCR nor model output proves the label is complete.

On-device language generation uses existing iOS 26/device/model/locale availability gates. Manual controls and
OCR work without Apple Intelligence. Requests have bounded text/context, 20-second work limits, cancellation and
source/account/form checks; no Private Cloud Compute or connected laundry delegation is added. The registry remains
45; P3.2 needs no backend migration, gateway/router/chart setting or provider dependency.

### P3.3 wear facts and review reminder boundary

`laundry_check_in` adds the **46th shared HTTP/MCP operation**. Native input supplies an explicit IANA time zone
and optionally one garment ID. Otherwise the read covers the complete active wardrobe up to 2000 items, failing
rather than returning partial coverage above the cap. Explicit garment reads include archived history. Each compact
item carries exact garment and latest completed-load source versions, nullable cleaning/derived wear facts, optional
owner reminder preferences, availability and deterministic due/reason fields. An as-of database clock and the
read transaction bind the returned history/clock snapshot.

Wear days/events count current `worn` items on dates strictly later than completion's date in the outfit's own
zone. Same-cleaning-day dates/events have uncertain order and are reported separately. Logged-at timestamps cannot
turn a backdated wear into a later wear. Void/restore, date and actual-piece corrections change the next read's
derived counts. A missing completed baseline is unknown; planned/active/cancelled loads never claim a wash reset.

Optional `laundry_reminder` garment preferences store wear-day (1–100) and/or calendar-day (1–365) review thresholds.
Existing `garments_update` versions/idempotency/audit and native queue/rejected-field recovery handle save or null
clear. Care and availability are independent. Either reached threshold prompts review; unknown baselines wait,
ambiguous same-day wears do not advance it, and washing/archived pieces pause it. Calendar age uses the supplied
zone's dates, including DST, not elapsed 24-hour blocks. iOS validates the supplied due reasons against facts,
labels cached assessed snapshots, and offers ordinary care/availability/load/reminder review. No model arithmetic,
dirty inference, care confirmation, automatic clean-ready state, schedule or notification delivery is added.

The first reminder surface is an opt-in in-app check-in refreshed on foreground/day/clock/save changes. P3.4 below
adds the connected timing/batch boundary; later notification delivery remains separate. Generic agent access to this
read operation does not grant a restricted write policy. Migration 0008 is one existing-table lookup index; no
service, provider dependency, deployment value or photo storage change is added.

### P3.4 reviewed laundry planning boundary

The native `read_laundry_choices` tool reads the existing `laundry_preview` plus one fresh `outfits_list` page
(`state=planned`, from today through an explicit need-by date, limit 20). Programme and IANA zone are fixed native
inputs; the window spans at most 14 calendar dates, using date labels across DST. A bounded model sample has eight
compatible Needs wash pieces, prioritized against four earliest same-zone plans in that page. Coverage retains
partial-page/omitted/other-zone/blocked counts; it is not a full schedule. Names/titles are clipped with truncation
flags, while native review retains complete names and exact 64-bit source versions. No photos or wear-count model
arithmetic are added.

`ask_agent` keeps its generic query schema and existing gateway MCP transport. A laundry run wraps the bounded
delegation in a typed planning query, retains the full owner request, and binds programme/scope plus current
garment/plan IDs and integer versions in a deterministic SHA-256 snapshot. Agent output is a version-1 proposal:
`snapshot`, exact `from`/`need_by`/`time_zone`, up to three `batches` and bounded `unhandled` conditions. Each batch
contains an exact native group, supplied piece aliases, a local plan date, explanation, saved-outfit aliases and
`context_evidence`. Native validation rejects scope/binding mismatches, unknown or blocked pieces, mixed groups,
reused pieces, dates after any represented outfit need (even uncited), unrelated cited outfits and unsupported connected references. Agent output remains
untrusted advice, not care facts or proof of readiness. The original programme is never changed by this adapter.

Remote proposals cannot inline external facts or provider evidence. When enabled, Apple's local model can separately
use the existing `read_outfit_context`/pointer adapter for bounded calendar/travel facts on the need-by day. Only
validated fresh e/t aliases from that matching adapter can be cited. No weather location is inferred. Source text
and generic prose remain untrusted; no complete calendar/travel coverage or verified booking is asserted. Direct
native agent planning works without Apple Intelligence and uses the same typed proposal validation, without external
fact references. The eligible iOS 26/device/model/locale gate applies only to local language drafting; no PCC is used.

The existing journal preserves query/task identity, owner questions, replies and cancellation intent. Matching
unchanged snapshot/request text reuse the saved task, including a completed response. Queries stay within 4000
UTF-8 bytes, owner requests 600, model delegation focus 300, proposals 2500; the existing 90-second/two-delegation/
poll/output-budget limits apply. No remote task-specific read-only permission grant is added; prompts are not
authorization enforcement.

An explicit owner action refreshes programme/groups and the same plan page before applying one batch to the existing
load form. Source-version changes, local pending saves, cached/stale reads, account/form changes and midnight block
application. Unhandled conditions require acknowledgement. Ordinary `laundry_create`/`laundry_update` source checks,
reviewed load versions, idempotency, durable save/rejected-intent recovery and progress confirmations remain in charge.
Applying never saves/starts a load or marks dirty/ready. Other proposed batches are not automatically queued. Existing
planned laundry loads, machine capacity, drying/cleaner durations and complete scheduling are not assessed; dates are
plans rather than ready-by promises. P3.4 adds no operation, migration or service; the shared registry remains **46**.

## Feature adapters still to implement

P1.4's generic native loop and gateway wiring are implemented in source. P2.1 adds deterministic preference/explicit-rating
ranking through `wardrobe_suggest` with source versions, bounded feedback coverage and iOS review checks. This is an
ordinary app/engine flow; the generic Ask Retro surface still reads preferences, while P2.3 Outfit help reads real
choices through the adapter above. P2.4 Outfit help adds typed connected facts and reviewed request refinements;
task-specific remote tool grants remain pending.
P2.2 adds registered HTTP/MCP pairing operations and versioned daily-selection updates. Native clients review and
queue these saves; a generic remote answer still cannot automatically become a pairing or selected plan. Typed
connected pairing proposals remain pending.
Automatic forecast-driven ranking, precipitation/garment suitability and temperature-sensitivity rules remain N05
work. Provider-specific delivery guarantees/iPhone push, laundry notification delivery, richer scheduling and rendering remain. A generic delegation prompt does not enforce a remote read-only
policy, and no generic assistant response automatically saves a wardrobe record.

## Validation status

Focused backend/native tests and shared preference/feedback fixtures are authored. Go formatting, contract generation
and Xcode project generation completed. Gateway MCP source and focused tests are also authored; dependencies are resolved.
The iOS MCP transport, journal, loop/controller and native owner-input UI are now authored, with focused tests for
protocol/auth boundaries, exact versions, lost replies, storage failure, account fencing, durable responses/stops,
duplicate delegation, limits and parked-input cancellation. Test suites, migrations, native/gateway builds, agent execution and deployment remain
deferred at the owner's request. P2.3 native alias/evidence/constraints/freshness/cache/pending/cancellation tests are
also authored, unrun; Xcode project generation completed. P2.4 source-pointer, units, scope/date/freshness, refinement,
typed recovery and cancellation regressions plus the synthetic outfit-context fixture are authored, unrun. Gateway
evidence-bound/provenance regressions are authored, unrun. P2.5 timezone/window, concurrent generation, claim replay,
native queue/receipt/recovery and worker Payload/calendar/callback regressions plus the daily fixture are authored,
unrun. Contract generation compiled the engine package; formatting and Xcode project generation completed. Prior
M6 iPhone build evidence does not validate P1–P2 changes.

P3.1 engine/native compatibility, reservations, atomic stale-source failure, dated progress/return/cancel, exact
versions and frozen-intent recovery tests plus the synthetic laundry fixture are authored, unrun. Formatting,
45-operation contract generation (compiling the engine package) and Xcode project generation completed. Suites,
migrations, native builds, live flows/device checks and deployment remain deferred.

P3.2 request evidence/units/zero, selected/partial method changes, exact preset versions and source refresh,
unknown/ambiguous presets and reviewed OCR handoff regressions reuse native fixtures and are authored, unrun.
Xcode project generation includes the new files; native builds, suites, actual model/OCR/device checks and deployment
remain deferred. Prior M6 device evidence does not validate these additions.

P3.3 current-history/date/zone/unknown-baseline/threshold/pause/clear and frozen native retry regressions and the
check-in fixture are authored, unrun. Formatting, 46-operation OpenAPI generation (compiling the engine package)
and Xcode project generation completed. Suites, migration execution, native builds, runtime/device checks and
deployment remain deferred.

P3.4 focused native compatibility/alias/scope/date/DST/freshness/source-change/typed task recovery/cancellation/frozen
load-save tests and `laundry-planning.json` are authored, unrun. Xcode project generation completed. Native builds,
suites, live model/agent/device checks and deployment remain deferred. Existing engine/gateway/router/contracts and
migrations are reused unchanged.
