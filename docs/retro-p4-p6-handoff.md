# P4–P6 implementation handoff

Prepared on 2026-10-09. This is the starting point for another implementation agent.
The [feature checklist](retro-feature-checklist.md) owns product requirements; the
[phase plan](retro-implementation-phases.md) records delivery status. The slices below refine the existing
P4–P6 scope into a recommended order. They do not choose a try-on model/provider or claim feasibility.

## Instruction to the next agent

> Continue Retro in `/Users/abishekkumar/Documents/retro`, starting with P4.1 below. Read the constraints,
> current status and relevant source before editing. Complete one small end-to-end source slice at a time,
> including native forms/recovery, engine contracts, fixtures and focused tests where affected. Reuse existing
> stores, photo/import queues and Apple/MCP integration. Update the phase plan with changes and remaining limits.
> New client work is iOS only. Do not implement Sensei, add engine authentication, use Apple Private Cloud Compute,
> increase MinIO storage/resources or deploy infrastructure. The owner deferred running suites/live verification
> until after implementation/deployment; author checks and distinguish source completion from verified behavior.
> P5 needs measured hardware evidence before selecting a renderer; a still image or static overlay does not
> complete P5/P6. Preserve unrelated changes and inspect the actual workspace permissions before sibling-repo edits.

## Read first

1. [Feature checklist](retro-feature-checklist.md): N02, N04 and N09–N12, plus execution/privacy policy.
2. [Phase plan](retro-implementation-phases.md): P1–P3.4 status, then P4–P6.
3. [Agent contract](retro-agent-contract.md): bounded local loop, durable tasks, source validation and pending adapters.
4. [iOS README](../ios/README.md): current entry points, accepted saves, import/photo recovery and model fallback.
5. [Engine README](../engine/README.md) and [engine design](wardrobe-engine-design.md): versions, history,
   snapshots, cursor semantics and private media. [On-device plan](on-device-intelligence-plan.md) explains allocation.

The older [M1–M6 roadmap](retro-feature-roadmap.md) is useful background. Its historical validation notes and
Android work do not override the current iOS-only scope or the latest status below.

## Current status and boundaries

- M1–M6 and P1–P3.4 are implemented in source. P4.1 richer garment records (pattern/style/fit and the purchase
  date/amount/currency/evidence semantics above), P4.2 server search (the filter/sort/keyset-cursor and coverage
  behavior above) and P4.3 source-linked reviews (ranked usage, unworn versus never-worn, distributions, trends,
  feedback/selection counts and per-garment cost per wear) and P4.4 complete-inventory duplicate scans (the
  bounded index, disclosed coverage and photo/version binding described above) are also in source as of
  2026-10-09, as are P4.5's local half (receipt/label reading into the open garment form, with figures verified
  against the recognized text before they are offered) and P4.6 (bounded multi-item maintenance through the existing
  durable queue, with per-item outcomes). **P4 is complete in source.** Two P4 items stay open by capability, not by
  omission: P4.5's connected purchase reconciliation was not built because no purchase/order/receipt tool exists in
  the inspected harness contract to build a typed adapter against, and P4.6 has no rotation, background image
  processing or reanalysis because media derivatives are immutable, background execution is a scheduling decision,
  and no feature-print index exists.
  The engine registry still exposes **46 HTTP/MCP operations**; embedded migrations currently end at
  `0008_laundry_check_in.sql`.
- P1 supplies preferences, confirmed care, machine presets, explicit feedback and durable native saves. P2 supplies
  ranked daily choices, stable selections/pairings, local comparison, typed connected context and daily automation.
  P3 supplies compatible laundry plans/progress, local label/request help, wear-based in-app check-ins and reviewed
  timing/batches. Reuse these; do not rebuild them as P4 foundations.
- On 2026-10-09 the signed Debug build through P3.4 passed, installed and launched on the owner's **iPhone 17 Pro**;
  its running process was confirmed. Bundle ID: `org.nighthawklabs.retro`. Build inputs are `ios/project.yml` and
  the XcodeGen-generated project; the deployment target remains iOS 17 with runtime-gated Apple helpers.
- Authored feature suites, migration execution, deployed engine/gateway/provider flows, actual Apple model flows,
  full device behavior and accessibility remain unverified. A successful app launch does not prove these flows.
- Tenant chart source supports the current engine, private MinIO and gateway transport. Cluster state and published
  images were not inspected. `gateway.enabled` defaults to false and requires a tenant override. Engine/gateway/worker
  use `latest` with `IfNotPresent`; later deployment needs current published images and fresh pinned tags.
- Retro owns wardrobe; Sensei owns productivity. Supporting calendar/travel/purchase connections may come from the
  agent without building a Sensei client. Preserve existing Android wire compatibility; add no Android UI work.
- Engine auth belongs to the router. The private engine serves one wardrobe: no Clerk, owner/tenant fields or
  new inference service. The iOS client and gateway retain their existing Clerk/router authentication.
- MinIO stays private, **10G decimal GB**, with existing minimal resources. Do not add GPU workloads or redundant
  chart values. Accepted photos use normal authenticated media operations; raw camera/label/voice data stays local
  by default. Previewing does not automatically upload or retain body images/video.
- Foundation Models handles bounded language/explanation/extraction when actually available; Vision/Speech/Core ML/
  ARKit are separate local capabilities. No Private Cloud Compute or automatic cloud fallback. Since 2026-10-10 a
  task can be declared once and run on either the device or the connected agent ([language
  tasks](../docs/retro-language-tasks.md)); the agent is only ever a visible, owner-enabled fallback that holds the
  same validator, and raw captures may never be delegated. Verify the installed SDK and runtime capabilities before
  adding direct model image input; the current capture helper uses text/OCR.
- Local and remote proposals are untrusted. Validate supported fields, literal evidence, IDs, exact `Int64` versions,
  freshness, coverage and editor/account identity. Applying a proposal edits a reviewed form; it does not save.
- Accepted writes persist a frozen body/key before dismissal. Identical retries reuse that identity; changed intent
  needs review and a new key. Preserve omission/null semantics, pending-item blocking and historical media references.
- The generic remote tool is existing **`ask_agent({request_id, query})` at `/gateway/mcp`**, not a second chat API.
  Reuse stable tasks, polling, owner questions, cancellation and native source-bound adapters. A prompt asking for
  read-only behavior does not enforce task-scoped permissions on the remote agent.
  Queries cap at 4000 UTF-8 bytes; the existing local loop has a 90-second deadline and two-delegation limit.
  Keep feature-specific evidence/output budgets from the agent contract rather than enlarging the loop for P4.

## Source map

| Work | Existing code to extend |
|---|---|
| Garment fields, validation and filters | `engine/internal/engine/{types,validation,garments}.go`; `ios/Retro/Data/{WardrobeModels,WardrobeDrafts}.swift` |
| Forms, frozen saves and conflict recovery | `ios/Retro/UI/{WardrobeWritesView,WardrobeRecoveryView}.swift`; `ios/Retro/Data/{WardrobeWrites,WardrobeSavedDrafts}.swift` |
| Inventory reads and typed search | `ios/Retro/Data/{WardrobeStore,WardrobeLanguage,WardrobeSpeech}.swift`; `ios/Retro/UI/{WardrobeReadsView,WardrobeLanguageView}.swift` |
| Local OCR/cutouts and garment proposals | `ios/Retro/Data/{PhotoPreparation,GarmentAssistance}.swift`; `ios/Retro/UI/{CaptureSheet,GarmentAssistanceView}.swift` |
| Resumable capture/photos and duplicate hints | `ios/Retro/Data/{WardrobeImport,WardrobePhotoDraft,WardrobePhotos,WardrobeDuplicates}.swift`; `ios/Retro/UI/{WardrobeImportView,WardrobePhotosView}.swift` |
| Authoritative analytics and record links | `engine/internal/engine/history.go`; `ios/Retro/Data/WardrobePeriodReview.swift`; `ios/Retro/UI/WardrobePeriodReviewView.swift` |
| Local model loop and connected evidence | `ios/Retro/Data/{WardrobeAssistant,WardrobeAgentRequests,WardrobeOutfitContext,WardrobeLaundryPlanning}.swift`; `ios/Retro/Net/GatewayMCP.swift` |
| Registry, generated schema and migrations | `engine/internal/engine/{operations,contract}.go`; `engine/api/openapi.json`; `engine/internal/store/postgres/migrations/` |
| Media validation/storage | `engine/internal/engine/media.go`; `engine/internal/media/{images,store}.go`; `ios/Retro/Data/WardrobeMedia.swift` |
| Tests and shared synthetic data | `ios/RetroTests/`; engine tests alongside implementations; `fixtures/wardrobe/README.md` |

Sibling integration lives in `/Users/abishekkumar/Documents/agent-harness`: gateway `internal/agentmcp/`,
`docs/components/gateway/mcp.md`, router `internal/core/proxy.go`, `tenant-worker/tenant_worker/` and
`deploy/helm/agent-harness-tenant/`. Change only a real shared-contract/config dependency; P4 does not inherently
need new gateway routes or Helm values. Read existing instructions and preserve that repo's unrelated changes.

## P4 — Recommended source slices

### P4.1 — Richer garment records (N12)

- Add missing pattern/style, owner-supplied fit and purchase date/amount/currency/evidence through the ordinary
  garment record, create/patch validation, audited snapshots, iOS forms/drafts and selected-field recovery.
  Brand, material, colours, seasons, favourites and confirmed care already exist.
- Define exact money representation, currency precision, unknown versus zero, partial purchase records and
  provenance before saving. Never infer a currency, use floating-point totals or silently convert currencies.
  Keep manual correction authoritative; appearance is not evidence of material, fit or care instructions.
- **Acceptance:** old responses/drafts still decode; omission retains values and explicit clearing works; edits
  survive queued retry/conflict recovery; historical outfits keep their confirmed metadata/photo snapshots.
  Author field/money/old-record/replay regressions and update generated schemas/shared fixtures.

### P4.2 — Complete server search and editable requests (N10)

- Extend `garments_list` and native controls for brand, notes, colour, season, favourite and care predicates, with
  defined sort orders and stable tie-breaks. Current search only matches name, category, availability and archive state.
- Bind cursors to the complete filter/sort request. Existing lists default to 50/max 200; they do not pin an immutable
  multi-page snapshot. Keep query/account cancellation fencing and show remaining pages/coverage.
- Extend local typed/spoken interpretation into visible editable filters. Retain unsupported conditions instead of
  silently dropping them. Connected searches reuse the generic agent with a validated feature adapter when needed.
- **Acceptance:** an item outside the first page can be found; filter changes invalidate old cursors/results;
  ties do not repeat/skip unchanged records; manual search works without the model. Author pagination, combined
  predicate, stale-result and unsupported-request cases. A cached page is never presented as complete inventory.

### P4.3 — Source-linked reviews and ranked usage (N09)

- Extend engine aggregates for most/least/never-worn lists, colour distribution, usage trends and explicit
  feedback/selection summaries. Define archive/category/date semantics and separate events, distinct wear days,
  plans, selections and feedback. Existing `wardrobe_analyze` has counts/category usage, not ranked garment lists.
- Compute facts in engine/code and provide underlying-record links. Local explanations consume bounded aggregates
  and disclose coverage; they cannot invent causes. Connected context is optional evidence with its own provenance.
- **Acceptance:** voids/corrections affect counts consistently; never-worn-in-range differs visibly from lifetime
  never-worn; a plan/view is not a wear, selection or rating. Mixed currencies are not summed. If cost-per-wear is
  exposed, define its confirmed-wear denominator and unknown/zero-wear behavior. Author representative corrections,
  date-boundary, archive and missing-price cases.

### P4.4 — Reviewed capture and complete-inventory duplicate proposals (N04)

- Extend existing OCR/cutouts/text-assisted imports; capability-gate any direct model image support. Bind every
  proposal to selected photo bytes/revision, garment version, account and editor. Preserve owner edits and provenance.
- Current duplicate comparison uses at most 40 loaded garments with cached primary thumbnails and returns three
  hints. Extend coverage through bounded complete-inventory enumeration/search or an available connected capability;
  disclose missing photos, partial scans and changed records. Do not claim completeness from one cached page.
- **Acceptance:** late/cancelled/changed-photo results cannot apply; unknown attributes remain unknown; choosing an
  existing item requires fresh version/photo review and never merges/deletes silently. Manual entry and resumable
  import work without Apple/agent availability. Author source-binding, coverage, cancellation and retry regressions.

### P4.5 — Label/receipt and connected purchase reconciliation (N12)

- Use local OCR/guided extraction for selected evidence and an existing agent connection for actual purchase data.
  Inspect available tools/result schemas before building the adapter; provider access is not established by this doc.
- Propose garment matches using real IDs and source evidence; retain ambiguous/unmatched records, exact
  amount/currency/date semantics and owner's corrections. Generic agent narrative is not purchase proof.
- **Acceptance:** owner reviews matches/fields before normal durable saves; stale versions and changed evidence
  block applying; duplicate receipts/retries do not create duplicate accepted changes; missing connections/manual
  purchase entry remain usable. Author forged/missing-source, ambiguous-match and frozen-retry cases.

### P4.6 — Bounded multi-item maintenance (N11)

- Add explicit selection and per-item progress for supported inventory/photo actions, including rotation,
  background processing and reanalysis where a real capability exists. Reuse current single-item/import/photo queues;
  account for their one-pending-write-per-entity and bounded queue budgets rather than bypassing them.
- Freeze each accepted item's intent/key/version; partial failures resume without repeating successes. Keep suitable
  image work local, heavy agent jobs outside engine transactions and destructive actions explicitly reviewed.
- **Acceptance:** relaunch/reconnect/cancel/account switch and partial conflicts report actual item outcomes;
  retries preserve identities; photo replacement creates new media and cannot delete historical derivatives.
  Author partial-success/lost-acknowledgement/corrupt-manifest/reference-preservation cases. No blanket batch success.

For every slice, extend callers, recovery field allowlists, fixtures and OpenAPI when affected. Use new additive
migrations only when necessary; do not rewrite already-deployable migrations. Regenerate from the registry/types,
and update `ios/project.yml`/XcodeGen inputs rather than relying on hand-edited generated project state.

## P5 — Feasibility gate before delivery

No renderer, model, asset format, specialist provider or quantitative acceptance thresholds have been selected.
Start with native/local possibilities, and record an explicit proposed benchmark budget before comparing approaches.
**P5.1 is authored in [the feasibility record](../docs/retro-try-on-feasibility.md)** (camera, positioning, lighting,
motion and category scope; asset requirements and retention; a proposed benchmark budget marked as unapproved).
P5.2–P5.4 still need the owner's device measurements; the record's measurements and decision sections are empty on
purpose.

- **P5.1 capture/benchmark specification:** define front/rear camera, full-body distance/positioning, lighting,
  supported motion and garment categories. Define asset views/masks/scale requirements for the owner's clothes,
  missing-asset behavior and retention. Existing cutout previews are white-backed JPEGs, not proven try-on assets.
- **P5.2 measured local prototype:** combine appropriate pose/person segmentation with a purpose-built renderer/model.
  Foundation Models may interpret a swap command; it is not the per-frame clothing renderer. Record device/OS/model
  versions, setup and failure clips or observations using owner-approved capture/retention.
- **P5.3 compare only needed specialist support:** inspect actual agent asset tools or a real streaming renderer
  when local results need it. Establish schemas, permissions, licensing, cost and network/privacy implications before
  integrating a service. Agent connectivity alone supplies neither clothing reconstruction nor live rendering.
- **P5.4 decision record:** create `docs/retro-try-on-feasibility.md` with approach, assets, supported devices/categories,
  measured limits, unresolved failures and go/no-go rationale. If quality is inadequate, record that honestly and
  continue independent P4 work; do not label a sticker/still-image substitute as N02 delivery.

Measure camera-to-preview latency/frame rate, swap-to-stable-preview p50/p95, tracking-loss recovery, temporal
stability, body/face identity, garment colour/pattern/silhouette fidelity, hand/body/layer occlusion, memory,
battery/thermal behavior over sustained use and network sensitivity where relevant. Record numerical targets and
observed results separately; proposed numbers are not approved product targets. Real device measurements are
required evidence for this decision and remain pending under the owner's implementation-first validation policy.

## P6 — Deliver the measured approach and integrate it

Begin renderer delivery after P5 establishes a supportable approach. Keep unsupported categories/devices explicit
and preserve ordinary outfit browsing/planning when try-on is unavailable.

- **P6.1 live session:** camera positioning/help, permissions, moving-person rendering, occlusion/layering, tracking
  loss, loading/error/thermal recovery and lifecycle stop. Do not upload/persist camera video by default.
- **P6.2 live choices:** open actual suggested/selected inventory looks, swap whole outfits or supported individual
  pieces in the same session, and offer reachable controls plus an opt-in hands-free route. Reuse local speech and
  validated garment resolution; use the language loop outside per-frame work. Reject stale assets/late swaps.
- **P6.3 reviewed planning:** refresh current garment/source versions, availability and pending changes before saving
  the selected combination through existing draft/frozen-write/day-selection paths. Previewing is not wearing;
  confirming a real wear remains separate. Network loss cannot claim an uncommitted save succeeded.
- **P6.4 integration:** accessible controls/VoiceOver/Dynamic Type/Reduce Motion, account isolation, background and
  interruption cleanup, durable accepted-work recovery, bounded local/MinIO asset retention and visible capability
  limits. Asset replacement/reclamation must preserve historical references and the 10 GB storage budget.

**Acceptance:** on a declared supported device/category the owner can stand in a live camera view, see their actual
moving preview with a suggested outfit, swap supported pieces/looks, recover tracking and save a reviewed plan.
Record the P5 quality/performance evidence and P6 functional/device/accessibility checks; source code or a single
successful launch is not evidence of this experience. Author state/retry/source/owner-fencing tests during implementation.

## Remaining work that P4–P6 must not hide

Full client completion requires reconciling every N01–N12 checkbox with actual behavior/evidence. In particular:
N01 deployed scheduling/sender behavior and APNs remain open; N05 is now partly delivered — a stated temperature is
banded against the owner's own thresholds and scored against recorded warmth tags, with a manual °C override and a
"use the reviewed forecast" fill on Suggestions — while automatic forecast-driven ranking, water-resistance
suitability and layering rules remain open; N08 typed connected pairing proposals are open. N06/N07 have substantial
source implementation but their full checklist acceptance still needs reconciliation. Laundry check-ins are in-app;
background notification delivery and broader duration/capacity scheduling remain follow-ups. Allocate required gaps
explicitly in the phase plan; finishing the P4 slices and camera does not automatically close them.

Family sharing, browser UI, localization and configurable providers are optional O01–O04. Packing lists, widgets,
export/backup and storage reclamation remain separate roadmap items. Do not silently add them to this handoff's scope.

## Validation and deployment handoff

Keep source implementation, authored tests, executed checks, phone installation and infrastructure deployment
distinct in status updates. Under the owner's current instruction, do not start suites, live provider/model flows,
migrations or cluster deployment just because this handoff exists. Formatting/schema/project generation may proceed;
record any compile work they perform. Native signed build/install/launch was explicitly requested and completed for
P1–P3.4; that request is not permission for automatic future deployments or provider jobs.

When a later deployment is requested, the existing phone ID is `F679008A-78D5-52D3-B26A-7418CDAF93AC` and the
last derived-data directory was `/private/tmp/retro-iphone-build`. Recheck device availability then. Infrastructure
deployment needs current engine/gateway/worker images and the tenant's actual gateway override; do not infer running
backend versions from chart source. Keep the latest validation paragraph in the phase plan and iOS README accurate.
