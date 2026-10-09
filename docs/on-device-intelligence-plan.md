# On-device intelligence for Retro and Sensei

Proposed on 2026-10-08, before either client's completion begins. This extends the
[client completion plan](client-completion-plan.md). No client implementation, model evaluation, build,
device upgrade or deployment is part of this change.

The [Retro feature roadmap](retro-feature-roadmap.md) is the current Retro-only release scope, including the full
initial capture assistance and follow-up requests, voice, search, duplicate hints, summaries and system actions.

## Current implementation

M3 now implements local Vision label OCR and foreground cutout previews in source, plus capability-gated Foundation
Models **text** extraction on eligible iOS 26+ devices. The owner supplies a description and/or OCR text, reviews the
suggestion, chooses fields to replace and saves through the ordinary versioned queue. There are no model tools, cloud
fallbacks or brand/material/warmth/fit/care guesses. A changed account, input or form discards late results. Input/output
are bounded and the UI cancels suggestions after 20 seconds. Label photos are not attached or uploaded by this flow.

The installed SDK's Foundation Models Swift interface has no image attachment declarations. R1 direct image prompting
remains pending a suitable SDK and hardware evaluation; current text extraction never claims to inspect garment pixels.
Cutouts preview up to six foreground subjects and retain the original as fallback; colour sampling is still pending.
Both native clients implement manual photo storage/management. Android local inference, speech, intents and R3/R4 remain
later work. These M3 source changes and authored tests have not been built, run or evaluated on hardware.

## Recommendation

Use Apple's on-device models to understand input and produce editable drafts. Ordinary code and engine operations
own dates, counts, eligibility, conflicts and saving. Start with garment entry in Retro and task capture in Sensei;
these remove repetitive work without needing a general chatbot.

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
| SpeechAnalyzer / SpeechTranscriber | Explicit voice capture | iOS 26+; independently check supported hardware, locale and downloaded speech assets |
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
Apple's [SpeechAnalyzer introduction](https://developer.apple.com/videos/play/wwdc2025/277/) describes local transcription
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

An optional model pass may select or explain a supplied candidate, restricted to those fingerprints and validated
in code. Preserve backend reasons; do not invent weather, garments or fabric properties. Saving/confirming uses
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
- Explicitly select the on-device system model. Private Cloud Compute and third-party providers are outside this plan;
  failures do not trigger cloud fallback. System Siri/Writing Tools behavior is outside our local-inference guarantee.
- Start with bounded input snapshots and no model tools. If retrieval later needs [tool calling](https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling),
  expose only read-only cached queries with strict limits. No generic HTTP/MCP or mutation tools.
- OCR/notes/journal text is data, not instructions. Models cannot expand permissions, fetch arbitrary URLs or commit
  records. Keep authentication tokens out of prompts.
- Use short feature-specific sessions, one generation at a time per session. Budget input, schema and output for the
  context limit; use runtime context/token APIs where available. Do not send an entire year's journal or all photos.
- Cancel on dismissal/account switch; reject stale completions. Cached results belong to account, source versions/photo
  checksum and prompt/model version. No global transcript; production logs contain timings/error categories, not content.
- Initially run foreground requests only, with progress, Cancel and manual entry accessible. No full-library scan or
  automatic regeneration on every keystroke. Handle model-not-ready, refusal, context overflow and resource failures.
- Custom voice capture checks local speech support and installs assets with visible progress. Use local recognition
  only, never a silent network fallback; typing remains available. Discard raw audio after transcription unless
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
assistance. Android local OCR, speech and generative-model options need their own evaluation; do not introduce cloud
inference merely to make buttons identical. No cross-platform model abstraction or bundled LLM in this first plan.

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
