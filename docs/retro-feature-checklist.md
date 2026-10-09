# Retro feature checklist and agent responsibilities

Requirements recorded on 2026-10-08. This consolidates the Wardrowbe comparison and the owner's daily suggestions,
live virtual try-on and laundry-planning requirements. It is the next-feature checklist alongside the
[existing roadmap](retro-feature-roadmap.md), not a claim that these features are implemented.

Implementation now follows the [P1–P6 phases](retro-implementation-phases.md). P1 shared settings, presets, care,
feedback, native editors/recovery, Apple context and the bounded iOS Apple/MCP agent loop are in source. Preference
ranking and iOS choices on Today are now in source (P2.1), with stable daily selections and saved garment pairings
(P2.2). P2.3 adds reviewed Apple candidate comparison/explanation and contextual swaps; P2.4 adds bounded source-linked
weather/calendar/travel context and reviewed warmth/occasion changes. P2.5 adds daily settings, a stable agent wake,
cached snapshots and a single connected delivery reservation. Broader weather selection and provider delivery
guarantees remain pending. P3.1 adds manual compatible laundry plans, progress and retained wash history;
P3.2 adds reviewed local laundry interpretation and care-label OCR/text drafts; P3.3 adds derived wear counts and
optional in-app review reminders. P3.4 adds reviewed local/connected timing and batch proposals. Feature boxes below track
complete owner-facing behavior, not partial backend foundations.

## Product and architecture decisions

- Retro remains the wardrobe app; Sensei owns productivity. The agent can read supporting user data and connections
  without requiring a Sensei client or copying all that data into Retro.
- The app will have an agent endpoint with access to the owner's user data and supporting connections. Treat this
  as a product requirement. Existing gateway transport/tool-result source has been inspected; capability and
  task-scoped permissions/runtime integration still need agreement. See the [agent contract](retro-agent-contract.md).
- Prefer Apple's on-device intelligence for suitable local interpretation, extraction and explanation. The shared
  agent supplies connected context, scheduled orchestration and heavier/specialist processing. Apple Private Cloud
  Compute is excluded by the owner; the existing agent endpoint is the remote path. M3–M6 source remains unchanged.
- The native clients own interaction, camera capture, local tracking/rendering, cached reads and durable pending
  work. The engine owns wardrobe facts, eligibility, compatibility rules, versions, transactions and history.
- Agent tool calls reuse the engine's HTTP/MCP operations through the trusted router. Each engine still serves one
  wardrobe without Clerk or multi-tenant storage. Do not add an inference/provider framework inside the engine.
- MinIO remains private, with the existing **10 GB** storage and minimal resources. Heavy compute belongs to the
  existing agent or an available specialist service; it does not imply a GPU deployment in Retro's tenant chart.

M1–M6 already provide wardrobe entry/photos, composition, planning/wear history, rule-based suggestions, durable
native saves/imports, local iOS assistance and system entry points in source. The M6 iPhone build/install/launch
passed; full feature/backend and Android validation remain outstanding. All boxes below describe additional work.

## Apple-first execution policy

Use Apple Intelligence's Foundation Models for bounded language tasks; use Apple's other local frameworks for
OCR, masks, speech, similarity and tracking. Vision, Speech, Core ML and ARKit are separate capabilities, not all
Apple Intelligence features. Ordinary code/engine operations still calculate counts and enforce domain rules.

- [ ] Prefer Foundation Models guided generation for typed search/outfit requests, preference/feedback extraction,
  evidence-based label/receipt drafts and explanations of supplied candidates/aggregates. Validate facts and IDs
  after generation; typed output alone does not establish correctness.
- [ ] Add small read-only Foundation Models tools over existing stores/API methods for inventory, real candidates,
  care settings, usage summaries and bounded agent-supplied context. Tool calls may use the network even when the
  model runs locally. Keep credentials out of model context and saves on the established durable write paths.
- [ ] Use local Vision OCR, cutouts and feature prints first. Evaluate direct Foundation Models image proposals only
  when the compiled SDK, OS, available model and device expose that capability. The current installed source path
  remains text-only; newer image APIs are a follow-up dependency, not an implemented feature.
- [ ] Keep voice capture local using the current SFSpeechRecognizer support checks; evaluate SpeechAnalyzer only
  if it improves measured accuracy/latency or required language support. Interpret reviewed transcripts locally.
- [ ] Evaluate native Vision pose/masks and suitable Core ML/Metal rendering for try-on. ARKit depends on supported
  device/camera configuration. A purpose-built garment renderer is still required; Foundation Models is not a
  per-frame clothing simulator. Keep the camera/tracking loop separate from general agent requests.
- [ ] Reuse App Intents/Siri/Shortcuts entry points for outfit, search and laundry workflows as those records become
  available. System integration does not establish that all Siri processing is on-device or bypass normal auth/saves.
- [ ] Gate each helper by actual model readiness, language, SDK/OS/device support and measured quality/resource
  limits. Bound context, cancel stale requests and retain manual/rule-based controls. Do not run local and remote
  models on the same task by default; route a clear unmet capability to the existing agent when appropriate.
- [ ] Label processing location. Locally scoped audio/camera work stays local; a task that uses the agent follows
  its chosen remote-processing path. Core Android/manual behavior shares engine contracts without Apple dependencies.

For example, the agent can return relevant calendar/travel/forecast facts with sources, then the iPhone's model
can interpret “warmer, but keep these shoes” and explain validated wardrobe candidates. The endpoint need not
redo that language work. Server scheduling generates/delivers background choices; local inference personalizes
interactive changes without relying on the phone being awake for scheduled execution.

Apple documents [on-device guided generation and tool calling](https://developer.apple.com/videos/play/wwdc2025/286/),
[new image-understanding APIs](https://developer.apple.com/videos/play/wwdc2026/237/) and
[pose/person segmentation](https://developer.apple.com/videos/play/wwdc2023/111241/).
These establish platform building blocks; feature quality and installed SDK/device compatibility still need evaluation.

## Required feature checklist

### N01 — Daily outfit suggestions and reminders

P2.1 source adds on-open choices, preference/explicit-rating ranking, native locks and role-preserving swaps.
P2.2 adds server-backed daily selections with reviewed choosing/clear and durable retries. P2.3 adds the read-only
Apple candidate tool and reviewed comparison/swap proposals. P2.4 adds opt-in source-linked context and reviewed
request changes. P2.5 adds saved settings, a stable agent wake, one snapshot per date/zone and a single authorized
connected delivery attempt. Automatic context-driven ranking and provider delivery guarantees remain.

- [ ] Show a fresh set of choices each local day using real available garments, recent wears, preferences,
  occasion and weather/context when available; retain a useful rule-based fallback.
- [x] Support whole-outfit alternatives, individual swaps and locked pieces. Keep the selected plan stable across
  refreshes; saving a plan and confirming an actual wear remain separate actions.
- [x] Generate/cache suggestions through scheduled agent work or on demand. Optional morning/previous-evening
  delivery has fixed IANA zones, freshness checks and one authorized send claim; uncertain attempts never resend.
- [ ] Evaluate deployed senders/provider idempotency and live schedule delivery. Engine claims do not guarantee
  exactly-once external notifications; APNs/iPhone push is not implemented.
- [x] Prefer on-device Foundation Models for interactive requests, swaps and candidate explanations, using read-only
  tools for real wardrobe/context facts. Eligibility and repeat/preference scoring remain validated engine/code work.

### N02 — Live virtual try-on with live swaps

- [ ] Prototype garment asset preparation and a rendering approach using the owner's actual clothes. Determine
  required capture views, supported garment categories and acceptable quality/performance on the owner's device.
- [ ] Open a camera view, guide full-body positioning and preview a suggested outfit on the moving person. Swap
  complete looks or individual tops/bottoms/layers/accessories while maintaining the same preview session.
- [ ] Provide reachable controls and an appropriate hands-free option, tracking-loss/loading states and saving the
  selected combination as a plan. Validate identity/garment fidelity, occlusion, swap latency and thermal behavior.
- [ ] Prefer native pose/masking and local speech for live controls; evaluate on-device specialized rendering before
  a remote renderer. Track models/assets separately from the language model and measure actual device performance.

A generated still image can be an intermediate experiment. N02 is complete only when the requested live-camera
experience works; a still preview or a static sticker does not satisfy this requirement. The general agent can
orchestrate asset/model jobs, but a suitable native or specialist streaming renderer remains a separate dependency.

### N03 — Laundry and care planner

- [x] Capture and confirm garment care instructions: wash method, temperature limit, cycle, colour-separation
  requirements and drying restrictions. Preserve label evidence/manual corrections and configurable machine presets.
- [x] Build editable, compatible load lists such as cold machine wash, delicates, hand wash or dry-clean-only.
  Check all recorded restrictions, not just temperature; unknown care settings need review rather than guessed rules.
- [x] Record reviewed load dates, wash/dry progress and dated wash history. Confirm completion before restoring
  availability; wearing alone does not establish dirtiness.
- [x] Track wears since confirmed cleaning and offer optional in-app wear-day/calendar-interval review reminders.
- [x] Suggest reviewed load timing/batches using bounded upcoming saved outfits and optional need-by-day connected context.
- [x] Use local OCR and Foundation Models to draft care settings from readable label text and interpret requests such
  as “prepare a cold load”. Confirm care facts and let ordinary rules validate every proposed load.

Example: a cold machine-wash preset can group compatible garments, while a cold hand-wash-only item stays separate.
The agent can propose the grouping/timing; engine validation enforces confirmed care constraints.

P3.1 source implements the manual load/progress/history part of N03. The engine separates colour/method/drying
restrictions, checks exact cycles and holds active pieces unavailable through drying. Completion is explicit;
cancelled loads retain history and return active pieces to Needs wash. Existing local care assistance is available
from blocked items. P3.2 adds a direct local care-label scanner and reviewed programme request interpretation: explicit
Celsius evidence or an explicitly named unique preset, with unresolved conditions retained for manual review. Applying
never saves/starts a load or confirms care. P3.3 derives current confirmed wear totals after the latest completed
cleaning, keeps same-day timing uncertain and missing baselines unknown, and adds opted-in in-app care check-ins.
Voided/corrected wears and cancelled loads retain accurate semantics. Reminder preferences never infer dirtiness or
restore availability, and no background notification is scheduled. P3.4 adds local/agent proposals for up to three
compatible batches over eight pieces and four same-zone planned outfits in one 20-plan page, within 14 calendar
dates. Optional provider-backed calendar/travel covers the need-by day. Partial/omitted coverage stays visible;
capacity, existing laundry plans and wash/dry durations are not assessed. Source/version/pending/freshness checks
refresh one reviewed batch before applying it to the load form. No automatic save/start or dry-ready guarantee.

### N04 — Photo-based garment capture

- [ ] Prefer supported on-device Foundation Models image proposals from selected garment photos, with local
  OCR/cutouts and manual entry retained. Use agent image tools when the task needs an available remote capability;
  record photo/record revision and proposal source so late results cannot overwrite newer edits.
- [ ] Review proposed visible attributes and care-label evidence before applying them. Appearance alone cannot
  establish material, fit or washing instructions as facts.
- [ ] Extend duplicate hints beyond the current partial local thumbnail set when an agent/service can search the
  complete inventory; choosing an existing garment never silently merges or deletes records.

### N05 — Weather-aware recommendations

P2.4 source retrieves a daily forecast for an explicitly chosen location, validates literal provider units/date/
provenance and exposes freshness/coverage. The local model can interpret bounded facts and propose reviewed
warmth/occasion changes; native manual adjustments remain available. Full current-conditions coverage, numerical
weather overrides and deterministic precipitation/garment-suitability/temperature-sensitivity rules remain open.

- [ ] Use a supporting weather connection for current conditions and forecasts for planned dates, with location
  selection, source/time/freshness and a manual override.
- [ ] Feed temperature, precipitation and relevant conditions into validated outfit selection and explanation.
  Missing garment properties or unavailable/stale forecasts remain explicit.
- [x] Let the local model consume bounded forecast facts and explain choices; forecasts still come from a network
  connection or cached source, not model-generated weather.

### N06 — Persistent personal preferences

- [ ] Store preferred/avoided colours, styles, layering, temperature sensitivity, repeat intervals and variety
  settings in a structured versioned preference record shared by both clients and agent tools.
- [ ] Use those preferences to rank eligible outfits, with understandable reasons and owner-editable settings.
- [ ] Interpret stated preferences locally into reviewed fields; keep the shared structured record authoritative.

### N07 — Feedback and learning

- [ ] Record explicit overall/style/comfort ratings and warmth feedback against the actual outfit, separately from
  accepting a plan or recording a wear.
- [ ] Use recorded feedback to improve preference and pairing ranking; explain changes and allow corrections/reset.
  Viewing or skipping an outfit is not automatically a dislike.
- [ ] Prefer local interpretation of explicit comments and explanations of computed trends; use the agent for broader
  cross-service analysis when useful. The app does not retrain Apple's system model from ratings.

### N08 — Saved garment pairings

P2.2 source implements persisted combinations, garment-linked browse, manual edits, archive/restore and fresh
review before opening a separate plan. P2.3 interprets reviewed anchors and compares supplied eligible engine choices
locally. Typed connected pairing proposals remain pending.

- [x] Persist and browse “what goes with this?” combinations linked to a garment, alongside reusable complete looks.
- [ ] Allow agent-proposed pairings and manual edits, rechecking current versions/availability before planning a wear.
- [x] Prefer local request interpretation and comparison of supplied eligible combinations; broader contextual or
  specialist styling work can use the agent without inventing garments outside inventory.

### N09 — Richer wardrobe analytics

- [ ] Add most/least/never-worn lists, colour distribution, usage trends and feedback/acceptance summaries with
  explicit date ranges and links to underlying records.
- [ ] Prefer local Foundation Models explanations of authoritative aggregates; use the agent for connected context
  or larger analysis. Counts and money remain computed from engine records; partial pages are not exhaustive evidence.

### N10 — Advanced search and browsing

- [ ] Extend server-backed search/filter/sort for brand, notes, colour, season, favourites and care settings.
- [ ] Translate typed/spoken requests into visible, editable filters on either client. Unsupported predicates and
  incomplete results remain explicit; do not treat one cached page as a complete inventory.
- [ ] Prefer local Foundation Models parsing and inventory tools on eligible iPhones; fetch complete query results
  through the engine and route unsupported connected searches to the agent when available.

### N11 — Bulk maintenance

- [ ] Add explicit multi-selection for appropriate inventory and photo actions, including reanalysis, rotation and
  background processing; reuse resumable imports and existing per-item operations where possible.
- [ ] Preserve intent, per-item progress, versions and idempotency across partial failures/retries. Review destructive
  actions and report the actual outcome instead of claiming an entire batch succeeded.
- [ ] Keep supported rotation/masking/OCR processing local and bounded; offload heavy reanalysis/orchestration to the
  agent. Use ordinary progress/job code rather than language generation for batch success accounting.

### N12 — Richer garment records

- [ ] Add structured pattern/style/owner-supplied fit, purchase date/amount/currency and the care fields required by N03.
- [ ] Reconcile proposed details from labels, receipts or supporting purchase records with garment IDs and evidence;
  review uncertain matches and preserve the owner's corrections.
- [ ] Prefer local OCR and guided field extraction for selected labels/receipts. The agent obtains supporting purchase
  records through its connections; proposed matches preserve source evidence and amount/currency semantics.

## Optional product choices retained from the comparison

- [ ] O01 — Family/shared wardrobes and ratings. This changes the current single-owner product boundary and needs
  membership/access rules before implementation.
- [ ] O02 — Browser client. Reuse the same engine/agent contracts; a native or agent integration does not create a web UI.
- [ ] O03 — Localization. Translate and validate native UI, settings and accessibility text; agent fluency is not UI localization.
- [ ] O04 — Configurable AI providers. Reuse provider capabilities/configuration already owned by the shared agent,
  if present; defer a separate Retro provider manager unless a real need remains.

Calendar/travel context can support N01/N05 through the agent. Separate packing-list records, widgets, export/backup
and storage reclamation remain in the existing roadmap and are not silently added to this consolidated gap list.

## Where Apple and the agent contribute

Apple's local model is the preferred interpreter/explainer for suitable interactive tasks. The agent complements
it with connected data, scheduled execution and capabilities unavailable locally. Neither route is assumed to
have an image model or live renderer merely because it has data access.

| Feature | Preferred Apple/on-device work | Agent contribution | App/engine or specialist work |
| --- | --- | --- | --- |
| N01 Daily suggestions | Interpret requests/swaps; explain supplied candidates with Foundation Models tools | Connected context, scheduled generation/delivery and broader planning | Eligibility/ranking rules, saved daily choices, deduplication and UI |
| N02 Live try-on | Vision pose/masks, local voice commands; evaluate specialized Core ML/Metal rendering | Asset preparation, contextual alternatives and specialist rendering jobs | Camera controls, garment renderer and measured fidelity/latency |
| N03 Laundry | OCR care labels; draft fields and interpret load requests locally | Preset/context lookup, timing and broader load planning | Confirmed care rules, compatible loads, wash history and completion |
| N04 Capture | OCR/cutouts/similarity; direct image proposals when supported | Unavailable local image capabilities or complete-inventory comparison | Media transport, review and revision checks |
| N05 Weather | Interpret forecast facts and explain outfit adjustments | Fetch relevant weather/travel/calendar context | Forecast freshness, location and garment constraints |
| N06 Preferences | Extract stated preferences into reviewed structured fields | Cross-service/contextual preference analysis when useful | Shared versioned record and explainable scoring |
| N07 Learning | Interpret explicit comments; explain computed feedback trends | Larger historical/contextual analysis | Accurate feedback, derived ranking, correction/reset |
| N08 Pairings | Interpret anchors; compare supplied real combinations | Broader contextual/specialist combination proposals | Saved pairings and availability checks |
| N09 Analytics | Summarize bounded factual aggregates | Connected context and larger analysis | Exact counts, rankings, dates and charts |
| N10 Search | Typed/voice request parsing and read-only inventory tools | Connected searches beyond the local task's capabilities | Complete queries, pagination and visible filters |
| N11 Bulk maintenance | Supported image/OCR processing; local intent interpretation | Heavy processing and durable job orchestration | Selection/review, per-item versions/retries and success accounting |
| N12 Metadata | Label/receipt OCR and evidence-based guided extraction | Supporting purchase records and uncertain-match enrichment | Schema, evidence/currency semantics and reviewed writes |

For optional work, the agent can translate copy or coordinate tools; it cannot replace family access controls or
browser/localized interfaces. Centralized provider selection may eliminate most Retro-specific provider work.

## Integration checklist and responsibility boundaries

- [ ] Inspect/reuse the actual agent endpoint contract, authentication, capabilities, available connections and
  image/rendering tools. Separate synchronous requests from supported asynchronous jobs and existing scheduler services.
- [ ] Define each task's local capability/quality gate and agent escalation reason. Return bounded context through
  read-only tools for on-device reasoning when sufficient; do not duplicate local work or introduce another cloud provider.
- [ ] Return structured proposals with actual garment IDs/versions, date/timezone, sources/freshness, unsupported
  constraints and a stable request/job identity. Narrative text is an explanation, not the mutation contract.
- [ ] Keep agent reasoning/rendering outside engine transactions. Reuse the existing HTTP/MCP operations; add small
  domain operations for genuinely missing preferences, feedback, care/load/wash records, pairings and daily selections.
- [ ] Separate proposal acceptance from durable execution. App saves use its established queue; authorized background
  workflows use engine operations with the same version/idempotency rules. Choose one execution owner per accepted
  action, reconcile lost acknowledgements, and never infer a confirmed wear/wash from a recommendation or camera view.
- [ ] Preserve job state, bounded retries, cancellation and account/endpoint isolation. Reject stale proposals against
  changed records; deduplicate daily generation/delivery by owner, local date/timezone and job intent.
- [ ] Support offline use from cached wardrobe/last suggestions and local manual/rule-based flows. Remote-only tasks
  show unavailable/pending states and resume without duplicate records or pretending completion.
- [ ] Use relevant user context available to the agent, retaining only wardrobe decisions and source references in
  Retro. Selected media may go to agent image tools; camera capture does not automatically stream to the general endpoint.
- [ ] Bound generated previews/assets under the existing storage budget. Keep generated try-on media distinct from
  garment evidence and wear snapshots; retained artifacts and cleanup must preserve referenced historical photos.

Data access enables context, not every capability: scheduling needs durable execution, image analysis needs image
tools, and try-on needs a renderer. A language-only endpoint can still contribute to text requests, explanations,
planning and tool orchestration, but cannot inspect garment pixels or render clothing by itself.

The camera preview should use native tracking where practical. Apple's
[Vision overview](https://developer.apple.com/videos/play/wwdc2023/111241/) documents pose and person segmentation.
[Video try-on research](https://arxiv.org/abs/2505.16980) addresses consistency across frames with dedicated modeling.
Our architectural assessment is that agent orchestration can prepare/offload this work, while the requested live
experience still needs a separately measured rendering pipeline; no model/service selection is made here.

## Suggested implementation order

1. Reuse M3–M6 local helpers; define Apple capability gates/read-only tools and inspect the agent context/job contract.
   Add shared N12 care metadata, N06 preferences and N07 feedback records.
2. N01 daily choices on open with local request/explanation helpers, then agent-scheduled generation/delivery;
   N05 supplies connected forecast facts for local interpretation when available.
3. N03 confirmed laundry lists/history with local label/request interpretation, then agent-assisted timing/context.
4. N04 local-first capture, N10 search, N09 summaries and N08 pairing comparison; N11 retains bounded local processing
   and offloads only work requiring heavier/scheduled execution.
5. Start N02 native tracking/rendering feasibility independently, evaluating specialist agent-offloaded work from
   measured asset, quality and live-performance results.

The three owner-requested experiences remain required. This order sequences implementation; it does not downgrade
live try-on to a still-image feature or make agent availability a prerequisite for manual wardrobe use.

## Open implementation decisions

- Actual endpoint/tool availability, async execution and scheduling/notification capabilities.
- Available Apple SDK/device/language/assets and per-task quality/latency gates; direct image understanding and
  specialized local rendering are pending evaluations. Apple Private Cloud Compute remains out of scope.
- Native versus specialist remote try-on rendering, required photos/assets, supported garment categories and measured
  quality/latency/battery/cost targets. Android needs its own capability check and platform implementation.
- Available washer presets/connectors and how the owner confirms care settings and completed loads.
- Delivery channels and automation preferences: background generation is distinct from recording real-world actions.

The original checklist was documentation-only. P1.1 backend source progress and actual validation evidence are
recorded in the phase plan; no live endpoint/deployment/full-feature verification has been performed.
