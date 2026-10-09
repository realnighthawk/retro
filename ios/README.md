# Retro for iOS

SwiftUI (iOS 17+) client for the `/retro` engine.

Retro now opens a wardrobe-only shell: **Today / Wardrobe / History**, account-bound to the existing login.
The combined demo is preserved in `ProductivityDemoShell` for **Sensei**. This increment has not been built or tested.
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

Direct model image prompting, voice/follow-up assistance and Sensei extraction remain.
Core recovery is implemented in source; builds/tests/runtime and device/accessibility checks are deferred at the owner's request.

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
