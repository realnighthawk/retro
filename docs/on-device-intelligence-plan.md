# On-device intelligence for Retro and Sensei

Proposed on 2026-10-08, before either client's completion begins. This extends the
[client completion plan](client-completion-plan.md). Source implementation progress is recorded below;
model evaluation and device validation remain deferred.

The [Retro feature roadmap](retro-feature-roadmap.md) is the current Retro-only release scope, including the full
initial capture assistance and follow-up requests, voice, search, duplicate hints, summaries and system actions.

The [next-feature checklist and agent responsibilities](retro-feature-checklist.md) records the owner's later
requirement for an agent endpoint with access to user data and supporting connections. On-device processing remains
preferred for suitable local work; the agent can gather context, orchestrate tools and offload heavier reasoning or
image jobs for the next features. The local-only/no-cloud paths below describe M3–M6 implementation, not a restriction
on the expanded requirements. The generic iOS/gateway MCP loop is now in source; specialist agent capabilities
and live try-on rendering integration are still pending.

## Apple-first allocation for the next Retro features

P1 source now implements typed preference/care/feedback proposals and an authenticated read-only Foundation Models
tool over `wardrobe_context_get`. Editor-scoped records, source-version checks, byte/call limits, cancellation,
account fencing and reviewed durable saving are documented in the [agent boundary](retro-agent-contract.md).
Today → Ask Retro additionally uses Apple's native model/tool loop with optional query-only MCP delegation to
the remote agent. A thin controller owns budgets, durable request IDs, polling, cancellation, native owner input
and account fencing. Connected help defaults off; generic remote evidence remains distinct from typed domain facts.
P2.1 now supplies deterministic preference/explicit-rating candidates, on-open Today choices and role-preserving
swaps. P2.2 adds shared daily selections and saved pairings with native reviewed planning and durable saves.
P2.3 adds the read-only `read_outfit_choices` tool and guided candidate comparison/swap proposals to that same native
loop, with bounded source aliases, full engine evidence in review and no automatic writes. Optional MCP delegation
keeps its existing recovery/owner-input rules. P2.4 adds `read_outfit_context`: source-linked provider facts for the
fixed date/timezone and explicit location, with bounded model aliases, freshness/coverage and reviewed warmth/occasion
refinements. Native retrieval/manual controls work without Apple Intelligence; generic agent prose is not factual
context and requests do not create new remote permission grants. P2.5 uses the existing headless Temporal agent
wake for generation while the phone sleeps, with durable engine snapshots and one authorized connected delivery
attempt. Native settings/status/recovery work without Apple Intelligence; its interactive model roles remain local.
Provider-specific delivery guarantees and broader automatic weather rules remain open. The prior M3–M6 helpers
retain their feature scopes. New client work is iOS only.

P3.1 adds deterministic compatible laundry groups and native editable loads/progress/history. The existing local
care text/OCR assistant remains available from blocked items; confirmed facts and programme restrictions are
validated by the engine. Manual programme selection, presets and confirmation work without Apple Intelligence.
P3.2 now adds guided laundry request interpretation and a direct local care-label OCR/review path. Explicit Celsius
values require request/label excerpts; named presets map to native aliases and are refreshed before applying.
Unknown temperatures, symbols, missing instructions and unsupported conditions stay in manual review. Applying
changes only forms; care confirmation, fresh compatible piece selection and durable saves remain ordinary native work.
OCR works without Apple Intelligence, while drafting follows the existing iOS 26/device/model/locale gate. Programme
interpretation needs no remote tool. P3.3 now derives date-based wears since completed cleaning and opt-in in-app
review thresholds in engine code, with distinct same-day ambiguity and unknown baselines. Native care/availability/
load/reminder review, owner/source checks and durable saves need no Apple model. The model never calculates or resets
usage/cleaning counts or infers dirtiness. P3.4 now adds the local Apple tool loop over fresh compatible pieces and
bounded upcoming saved outfits, optional generic `ask_agent` MCP batch proposals and provider-pointer calendar/travel
context for the need-by day. Native aliases bind exact source versions and deterministic group/date checks. A direct
connected planner works without Apple Intelligence; review refreshes sources before changing only the load form.
No model care/duration/capacity/readiness inference, automatic saves/progress, PCC or notification delivery is added.

The owner confirmed that the [feature checklist](retro-feature-checklist.md) should use Apple Intelligence as much
as practical. Apple Private Cloud Compute is excluded. Remote work uses the already planned agent endpoint.

Use Foundation Models for bounded interactive language tasks: interpret outfit/search/swap requests, extract
explicit preferences/feedback and evidence-backed label/receipt fields, compare engine-supplied candidates and
explain authoritative usage summaries. Extend the existing feature-specific helpers and bounded native tool loop;
Foundation Models owns the reasoning loop. Guided generation constrains shape; ordinary validation still checks facts, IDs and dates.

Small read-only Foundation Models tools can expose existing inventory/candidate/summary API methods and relevant
agent-provided forecast/calendar/travel facts. The model stays on-device even when its tools fetch network data.
Select bounded records with source/coverage metadata; do not place credentials or an entire user-data dump into
the prompt. Versioned/idempotent saving remains ordinary app/engine work, including authorized background jobs.

Vision OCR/cutouts/similarity, local speech and native pose/person masks handle their respective local tasks.
These frameworks are distinct from Apple Intelligence. Direct Foundation Models image proposals require suitable
compiled SDK/OS/model/device support; the current M3–M6 SDK path stays text-only. Care facts require readable evidence
or owner input. Laundry compatibility, statistics and financial arithmetic remain deterministic code/engine work.

For live try-on, prefer native tracking and evaluate a purpose-built Core ML/Metal or suitable native renderer;
ARKit requires a compatible device/camera configuration. The language model can interpret swaps and explain options,
but is not a per-frame garment renderer. The agent can prepare assets or invoke specialist processing when local
capabilities are insufficient. A generated still does not complete the required live-camera experience.

Use the agent for connected context, scheduled generation/delivery, heavy analysis and unavailable specialist tools.
Do not run both model routes on every request. Keep capability/readiness/language checks, bounded context, cancellation,
late-result rejection and manual/rule-based fallback. Preserve locally scoped voice/camera processing rather than
silently sending it remotely. App Intents reuse normal auth/UI/save paths. Android shares the domain contract and
can use the existing agent without an Apple API dependency.

The checklist assigns these roles across all N01–N12 features and records outstanding implementation tasks.
Apple's [Foundation Models introduction](https://developer.apple.com/videos/play/wwdc2025/286/) describes on-device
guided generation/tool calling, and its [image-understanding session](https://developer.apple.com/videos/play/wwdc2026/237/)
describes newer image APIs. These are planning inputs, not evidence of compatibility with the currently installed SDK.

## Current implementation

M3 now implements local Vision label OCR and foreground cutout previews in source, plus capability-gated Foundation
Models **text** extraction on eligible iOS 26+ devices. The owner supplies a description and/or OCR text, reviews the
suggestion, chooses fields to replace and saves through the ordinary versioned queue. There are no model tools, cloud
fallbacks or brand/material/warmth/fit/care guesses. A changed account, input or form discards late results. Input/output
are bounded and the UI cancels suggestions after 20 seconds. Label photos are not attached or uploaded by this flow.

The installed SDK's Foundation Models Swift interface has no image attachment declarations. R1 direct image prompting
remains pending a suitable SDK and hardware evaluation; current text extraction never claims to inspect garment pixels.
Cutouts preview up to six foreground subjects and retain the original as fallback; colour sampling is still pending.
Both native clients implement manual photo storage/management. Android local inference/speech remain
later work. The M5 iOS build/install/launch succeeded on 2026-10-08; suites and intelligence evaluation remain unrun.

M5 implements R3-style typed outfit requests and natural-language search with guided text generation, validated editable
fields, real garment selection and explicit unsupported-condition review. Input is capped at 2000 UTF-8 bytes; generation
has a 20-second UI timeout. Applying changes only ordinary controls; candidates and saving remain engine/queue work.
Candidate comparison uses engine reasons and actual supplied pieces deterministically on both platforms, without a
second model explanation or automatic ranking. Past-outfit reuse creates a new reviewed plan and preserves history.

Optional voice uses the existing iOS 17-compatible `SFSpeechRecognizer` API with local-only capability checks and
`requiresOnDeviceRecognition`, rather than requiring a new transcription runtime. Permissions are requested on Record;
unsupported locale/assets or a local recognition error lead to typing, with no remote fallback. Audio is streamed and
never written to a file. Recording is bounded to 30 seconds and transcripts must be reviewed before insertion; input,
owner and foreground checks prevent late application. No speech-asset installer is added. M5 source and focused tests
are authored. The signed M5 iOS app build/install/launch passed; tests, permissions/airplane-mode behavior, inference
quality, accessibility and hardware budgets remain unverified.

M6 source adds explicit on-device Vision revision-2 feature-print comparison of cached primary thumbnails on iOS
(up to forty loaded garments / 16 MiB, three closest photo/name hints, 20-second UI timeout). Missing thumbnails,
other pages and limits are disclosed. Results are ephemeral; no index or feature prints survive revisions. Comparison
does not download or send images to inference. Similarity is an owner-review hint, with no confidence threshold or
auto-merge; choosing an existing item requires fresh active/version/photo checks and confirmation. Android uses manual
existing-item selection. Quality and latency remain hardware validation work.

Both clients provide bounded, private, resumable multi-photo entry through per-item drafts and existing idempotent
garment/photo queues. Normalized bytes and immutable identities persist before upload acceptance; later edits must be
reviewed before completion. Period reviews are deterministic validated server counts linked to paginated confirmed
outfit snapshots, not generated explanations. iOS App Intents require device authentication and open the shared
authenticated/onboarded UI for Add/Search/Today; Android has equivalent launcher shortcuts. No system action saves,
returns wardrobe facts to Siri or bypasses normal review. The signed M6 iOS Debug build/install/launch passed on
2026-10-08 on the iPhone 17 Pro and its running process was confirmed. Suites, Android builds/deployment, full
intelligence/feature/integration flows and system-action/accessibility evaluation remain pending.

## Recommendation

Use Apple's on-device models for suitable input interpretation, editable drafts and explanations of validated
results. Read-only tools can supply engine facts and agent-connected context. Ordinary code and engine operations
own dates, counts, eligibility, conflicts and saving; the existing agent handles scheduled/heavier work. Start with
garment entry in Retro and task capture in Sensei, then the checklist's local-first outfit and laundry flows.

Manual entry and rule-based wardrobe suggestions remain complete features on older iPhones and Android. Accepted
records still sync through the authenticated router, and chosen garment photos still go to private MinIO.
“Processed on device” describes inference, not an entirely local data-storage product.

## Capability map

| Technology | Planned use | Boundary |
| --- | --- | --- |
| Foundation Models, explicitly `SystemLanguageModel` | Extract typed fields, interpret short requests, summarize supplied records | iOS 26+; check hardware, enabled Apple Intelligence, model readiness and supported language |
| Foundation Models multimodal prompts | Draft garment name/category/visible colours from a selected photo | iOS 27 image-capable API/model; the iOS 26 text path cannot inspect pixels |
| Vision OCR | Read labels or photographed task lists | Local image processing; separate from Foundation Models availability |
| Vision foreground instance masks | Optional garment cutout preview | A foreground mask is not garment recognition; owner chooses the subject |
| Core Image / ordinary image processing | Orientation, masked colour sampling, crop and export | No LLM needed; lighting/background can distort observed colours |
| SFSpeechRecognizer (M5); SpeechAnalyzer / SpeechTranscriber later if needed | Explicit voice capture with reviewed transcript | Local-only support/assets gate; current API retains iOS 17 compatibility |
| App Intents / App Shortcuts | Open capture, search inventory, open today's board | System integration; do not promise Siri's entire execution is on-device |
| Vision image feature prints | Later possible-duplicate photo suggestions | Similarity only; no automatic merging |

Apple documents [model updates and the iOS 27 image capabilities](https://developer.apple.com/documentation/updates/foundationmodels),
[the iOS 26 framework floor](https://developer.apple.com/documentation/foundationmodels/updating-prompts-for-new-model-versions),
and [runtime model availability](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models).
[Hardware and settings requirements](https://support.apple.com/en-mide/121115) also apply; do not hardcode a device-name
allowlist or assume an eligible OS means the model is ready.

Vision supplies [on-device OCR](https://developer.apple.com/documentation/vision/recognizing-text-in-images),
[foreground masks](https://developer.apple.com/documentation/vision/vngenerateforegroundinstancemaskrequest), and
[image similarity](https://developer.apple.com/documentation/vision/analyzing-image-similarity-with-feature-print).
Apple's [local-only recognition setting](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition)
and [device-support check](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition)
are both applied before recording. Apple's [SpeechAnalyzer introduction](https://developer.apple.com/videos/play/wwdc2025/277/) describes local transcription
and asset installation; [App Intents](https://developer.apple.com/documentation/appintents/creating-your-first-app-intent)
make app actions available to system experiences.

Keep Retro's iOS 17 deployment floor, compiling optional features with the appropriate SDK and availability guards.
The previously recorded owner-device OS is 26.6.1: direct Foundation Models image assistance needs an eligible iOS 27
installation for evaluation. No OS upgrade is performed here. Check final SDK declarations when implementation starts.
Downloaded assets are required before local models can work offline; language support differs between frameworks.

## Retro priorities

### R1: Assisted garment entry

Select a shirt photo → “Suggest details” → review “Blue shirt / Top / Blue” → edit → Save.

- On the image-capable path generate a small typed draft: name, category from the seven backend categories,
  optional subtype, observed colours and a short description. Unclear fields stay empty.
- On iOS 26 use a typed/spoken description or Vision label OCR as text input. Do not present this as photo
  understanding. Without Foundation Models the ordinary form and recognized label text remain useful.
- Brand/material require readable label evidence or owner input. Do not infer fit, authenticity, laundry state,
  care instructions or warmth as established facts from appearance. Suggested styling attributes need owner input.
- Suggestions fill an editable form, never save by themselves. Bind results to account, photo checksum, draft
  revision and existing garment version. Late results cannot replace intervening manual edits.
- Accepted fields fit existing `garments_create` / `garments_update`. No AI endpoint, backend model credentials,
  tagging worker or schema migration is required for this first feature.

This is the first intelligence feature to ship; analysis is cancellable and never blocks manual saving.

### R2: Photo preparation and label scan

Offer an optional cutout preview, with the original as fallback. Let the owner choose among foreground subjects.
Keep the original locally until the final image is chosen; then normalize/export it before checksum and upload
reservation. Never change bytes after reservation. Initially upload only the chosen image rather than doubling
the 10 GB remote storage with originals, masks and alternate edits. Backend derivatives are opaque JPEG, so composite
cutouts onto the app's neutral background instead of promising transparent downstream thumbnails.

Label scan: OCR → highlighted text → optional field suggestions → review. A label scan remains local unless the
owner deliberately attaches it. Defer care-symbol interpretation rather than fabricating washing instructions.
Colour sampling is a measured visual suggestion, not a guarantee of the garment's true colour.

### R3: Natural-language outfit requests

“Something warm for dinner with the blue shirt” becomes a draft occasion, warmth and garment reference. Resolve
references against actual inventory, showing choices for ambiguity. Send supported constraints to `wardrobe_suggest`;
use its eligible candidate IDs/versions, reasons and missing roles. Show unsupported constraints as unhandled.

P2.3's optional model pass selects or explains supplied candidates using source-bound aliases validated against their
fingerprints/versions in code. It can identify one unlocked piece to swap, preserving every other piece and original
exclusions. Full backend reasons remain separate from model commentary; do not invent weather, garments or fabric properties. Saving/confirming uses
the ordinary reviewed, versioned and idempotent outfit operations. Rule-based suggestions remain the fallback.

### R4: Later history and duplicate assistance

Summarize a selected date range from `wardrobe_analyze` and worn snapshots, with source links. Compute and display
counts/dates deterministically, separately from generated prose. Local feature prints can suggest “possibly already
in your wardrobe”; owner review decides, and nothing is merged or deleted automatically. These do not block capture.

## Sensei priorities

| Feature | Local inference | Code and owner acceptance |
| --- | --- | --- |
| S1: typed/voice quick capture | Split “Call the dentist tomorrow and finish the proposal Friday” into editable task drafts | Resolve dates using capture time/time zone; review ambiguity; save through Sensei operations |
| S2: photographed task list | OCR and extract a bounded set of task drafts | Preview recognized text, select items and save accepted drafts |
| S3: daily record summary | Summarize selected notes/confirmed activities; suggest a title | Preserve source notes, link records and edit/save the summary |
| S4: day-plan proposal | Suggest priorities or break down selected tasks/goals | Code enforces durations, time windows and no overlaps; unknown durations require input; owner accepts |

Start with S1 and one structured extraction task. Keep the journal voice neutral; do not infer diagnoses, score the
owner or persist generated interpretations as moods/completed habits. No hidden collection of messages, mail, health
data, calendar or the other app's private records. Any future calendar integration has separate permissions.

The future Sensei contract should preserve source text separately from accepted tasks and optional derived summaries,
with source record versions for invalidation. The client creates UUIDs/idempotency keys after review; the model cannot
create final request identities, credentials or database mutations. Sensei still needs its own engine and router route.

## Execution and privacy

```mermaid
flowchart LR
    Input[Owner-selected text / photo / voice] --> Local[Local preprocessing and model]
    Local --> Draft[Typed editable draft]
    Draft --> Review[App validation and owner acceptance]
    Review --> Queue[Account-bound durable queue]
    Queue --> Router[Authenticated router]
    Router --> Engine[Versioned engine operations]
```

- Add small feature-specific iOS helpers, not a shared agent runtime or intelligence backend. Keep generative draft
  types separate from authoritative DTOs. Apple's [guided generation](https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation)
  constrains shape, not factual correctness. Validate IDs, enums, references, lengths and dates before applying a draft.
- Explicitly select the on-device system model for local helpers; Private Cloud Compute is excluded. Remote tasks
  use the existing agent as a separate, identified route rather than silently replacing local inference. System
  Siri/Writing Tools behavior is outside our local-inference guarantee.
- M3–M6 uses bounded snapshots without model tools. P1 adds small
  [read-only tools](https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling)
  over ordinary authenticated APIs, with strict limits and coverage/source metadata.
  The assistant also exposes one optional query-only `ask_agent` tool over gateway
  MCP. The model cannot choose HTTP URLs, IDs, polling/cancel controls or owner approval responses. The remote agent
  keeps its configured tool permissions; future feature adapters must validate specialist facts and enforce their
  actual permission scope. The local model cannot directly commit wardrobe records.
- OCR/notes/journal text is data, not instructions. Models cannot expand permissions, fetch arbitrary URLs or commit
  records. Keep authentication tokens out of prompts.
- Use short feature-specific sessions, one generation at a time per session. Budget input, schema and output for the
  context limit; use runtime context/token APIs where available. Do not send an entire year's journal or all photos.
- Cancel on dismissal/account switch; reject stale completions. Cached results belong to account, source versions/photo
  checksum and prompt/model version. No global transcript; production logs contain timings/error categories, not content.
- Initially run foreground requests only, with progress, Cancel and manual entry accessible. No full-library scan or
  automatic regeneration on every keystroke. Handle model-not-ready, refusal, context overflow and resource failures.
- Custom voice capture checks local speech support. M5 uses already available local assets; missing assets keep typing
  available. Any future asset installer must show progress. Use local recognition only, never a silent network fallback. Discard raw audio after transcription unless
  deliberately retained. Request microphone/speech permissions at capture time, not onboarding.
- Only accepted fields and chosen photos follow normal sync. Raw prompts, alternatives, label scans and audio remain
  local by default. Saving AI-assisted drafts has exactly the same offline queue, conflicts and account guards as manual entry.

## System integration and Android

After domain flows work, add a few App Intents: Retro opens Add Garment, searches inventory and opens today's outfits;
Sensei opens Quick Capture and today's board. Reuse stores/auth with sign-in/unlock requirements for private content.
Start mutations by opening the reviewed form; normal saving owns idempotency. Intents must not bypass conflict handling
or claim a pending wear is confirmed. Do not automatically donate private journals to Spotlight. Later indexing needs
an explicit scope, per-account deletion and version handling; declaring an intent is not access to every private record.

Apple Intelligence APIs are not available on Android. Keep record/sync and manual/core parity while permitting iOS
assistance. Android local OCR, speech and generative-model options need their own evaluation; the next checklist can
reuse the existing agent for suitable remote assistance. No separate cloud provider, cross-platform model abstraction
or bundled LLM is needed merely to make buttons identical.

## Delivery changes

1. Before implementation, adopt these boundaries and draft shapes; every design includes a manual fallback.
2. Contract/shell milestone: allow capability-aware form actions and source/version tracking; complete real data flow
   before adding model calls. Do not delay garment → wear for an intelligence abstraction.
3. Photo milestone: R1/R2, using the identical upload/save pipeline.
4. Suggestions milestone: R3; R4 follows only if useful. App Intents follow stable search/save flows.
5. Sensei contract/capture milestone: preserve source text and design reviewed task drafts, then S1; S2–S4 follow.

This replaces the previous blanket deferral of local AI tagging/background removal. External AI, custom model training,
bundled Core ML/Core AI/MLX models, general agents and cross-app intelligence remain deferred until a measured need exists.
No model hosting or new Helm/MinIO values are needed.

## Later evaluation

At the owner's permitted verification stage, evaluate on actual supported devices using synthetic examples and
deliberately selected owner data:

- iOS 17 manual flow, eligible iOS 26 text, eligible iOS 27 images, unsupported locales, disabled/not-ready Intelligence
  and unavailable speech assets. After assets are installed, confirm inference in airplane mode; sync/downloads are separate.
- Photos with poor lighting, busy backgrounds, multiple garments and unreadable/no labels. Measure field accuracy/edit
  rate; unsupported brand/material guesses fail acceptance. Bad masks always have the original fallback.
- Capture with negation, self-corrections, ambiguous dates, several tasks and prompt-injection text. No unknown IDs or
  unreviewed mutations reach the engine. A refusal must never prevent saving ordinary journal text.
- Cancellation/account switches, manual edits during generation, stale sources, overflow and thermal/resource pressure.
  None may lose edits or block ordinary capture.
- First-use/warm latency, memory and energy on hardware. Set feature budgets from those measurements rather than making
  speed claims now. Keep a small versioned evaluation corpus and rerun it after model/OS updates.

Success is less capture/editing effort with factual correctness, local inference and graceful fallback.
Schema validity or a compiling API call alone does not make an intelligence feature ready.
