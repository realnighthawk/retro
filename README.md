# Retro

Your wardrobe, today's outfit, and a dependable history of what you wore.

Retro owns wardrobe. **Sensei** is the separate app for planning, goals, habits and the daily record.
The native clients now open Today, Wardrobe and History with real, account-bound wardrobe reads.
M1–M3 and M4 recovery are implemented in source: real reads/writes, private photos, rule-based outfit
suggestions, factual insights, record history and resumable local garment/outfit/photo drafts.
Queued creates support later local edits and explicit review against fresh records after acknowledgement.
iOS adds optional local label OCR, cutout previews and reviewed Apple Intelligence text suggestions. These changes
are unverified; direct model-based photo understanding awaits a newer Apple SDK.
The earlier combined demo is preserved in `ProductivityDemoShell` for Sensei extraction.

Two native clients, one design language, one engine:

- [`ios/`](ios/README.md) — SwiftUI, iOS 17+, XcodeGen
- [`android/`](android/README.md) — Kotlin, Jetpack Compose
- [`engine/`](engine/README.md) — Go/PostgreSQL wardrobe backend, private MinIO photos, HTTP/MCP behind `/retro`

## Why it exists

Retro helps you choose from the clothes you own and remember what you actually wore. Garments have stable identities;
outfits belong to dates, and confirmed wears drive history. Plans and suggestions stay distinct from wears.

See the [product definition](PRODUCT.md), [wardrobe engine design](docs/wardrobe-engine-design.md), and
[Retro feature roadmap](docs/retro-feature-roadmap.md). Implementation is organized by the
[native client completion plan](docs/client-completion-plan.md), alongside the
[on-device intelligence plan](docs/on-device-intelligence-plan.md) and
[Sensei ownership and extraction plan](docs/sensei.md). Retro keeps `/retro` and `org.nighthawklabs.retro`;
Sensei's proposed namespace and package are `/sensei` and `org.nighthawklabs.sensei`.

The [next-feature checklist and agent responsibilities](docs/retro-feature-checklist.md) records the expanded
requirements: daily suggestions, live camera try-on and compatible laundry loads, with the shared agent endpoint
providing supporting user context, tool orchestration and optional remote processing.
Its execution policy prioritizes on-device Apple Intelligence and native vision/speech/tracking for suitable work;
the existing agent handles connected context, scheduling and heavier tasks. Apple Private Cloud Compute is excluded.
Implementation follows the [P1–P6 phase plan](docs/retro-implementation-phases.md). P1 shared preferences, care,
machine presets, outfit feedback and native save/recovery are in source, with Apple typed proposals/read-only
context. iOS Today → Ask Retro adds the bounded Apple model loop, optional gateway MCP delegation, native owner
questions and durable task recovery. P2.1 now adds preference/feedback ranking, choices on Today and role-preserving
swaps. P2.2 adds stable daily plan selections and saved garment pairings with native review and durable saves.
P2.3 adds reviewed on-device comparison/explanation and contextual swap proposals over fresh engine choices,
reusing the Apple/MCP loop. P2.4 adds source-linked connected weather/calendar/travel context and reviewed
warmth/occasion adjustments. P2.5 adds saved daily automation settings, a stable agent wake, server-cached daily
choices and optional connected-service delivery with a single send reservation. P3.1 adds compatible manual laundry
plans, confirmed wash/dry progress and retained history. P3.2 adds reviewed on-device laundry interpretation and
care-label OCR/text drafts. P3.3 adds derived wears since confirmed cleaning and opt-in in-app care check-ins.
P3.4 adds reviewed Apple/agent timing and compatible batch proposals around bounded upcoming outfit needs.
Broader automatic weather ranking and laundry notification delivery remain open. New client work is iOS only.
See the [agent contract](docs/retro-agent-contract.md).

## Design

**Tranquil Earth — Sage & Clay.** Linen ground, unglazed pottery, and a garden. Neutrals do all the structure.
Three colours carry meaning and nothing else is coloured:

| Token | Light | Dark | Means |
|---|---|---|---|
| `clay` | `#A2543A` | `#D9926F` | Where you act |
| `sage` | `#4F6B3A` | `#93BB74` | What you kept |
| `rust` | `#8E2F22` | `#E08A72` | A day marked void |

A day that was missed is never drawn in a warning colour. The app describes what happened and is not allowed to be
disappointed about it. Contrast is measured, not assumed: 13.8–16.3:1 for text, and at least 4.6:1 for every other
token, in both appearances and both increased-contrast variants.

The earlier productivity day arc is preserved with the demo source for Sensei; Retro now centers its Today view on outfits.

## Verification

| | Result |
|---|---|
| iOS build | `xcodebuild -scheme Retro build` — succeeded |
| iOS tests | 7 unit + 2 UI, 0 failures |
| iOS on hardware | installed and launched on an iPhone 17 Pro (iOS 26.6.1) |
| Android build | `./gradlew assembleDebug` — succeeded |
| Android tests | 5 unit, 0 failures |
| Android visuals | captured from an API 36.1 emulator |
| Screenshots | `.impeccable/review/` — light and dark, both clients |

Captures come from the simulator and emulator; the iPhone run proves it installs and launches on hardware.
The table describes the earlier native demo. On 2026-10-08, the current M6 signed iOS Debug build succeeded,
was installed and launched on the connected iPhone 17 Pro, and its running process was confirmed. New client
tests/fixtures have not been run; full-flow, Android, backend/router/Helm and accessibility validation remain deferred.

## Backend deployment

The backend implements 46 operations for garments, outfits, daily selections, pairings, daily automation, laundry,
history, availability, suggestions, preferences, feedback, context and photo jobs.
Router and tenant Helm wiring live in the sibling `agent-harness` repository. Supply the container image;
the tenant chart deploys MinIO with a 10 GB PVC and wires Retro automatically. See the [deployment guide](engine/README.md#deploy)
and [values example](engine/deploy/tenant-values.example.yaml). No infrastructure has been deployed by this change.

## Requests, comparison and reuse (M5 source)

iOS can interpret a short typed outfit or search request with the available on-device Apple model. Review its fields,
resolve garment descriptions to real inventory selections, and acknowledge unsupported conditions before applying.
Optional local speech captures descriptions for transcript review; permission is requested only on Record, and typing
remains available when local recognition cannot run. Search retains the engine's name/category/availability/archive limits.
Both clients compare actual outfit candidates using engine reasons and shared/different pieces, then refresh the selected
candidate before opening the composer. Reuse a past outfit as a new dated plan, explicitly replacing or removing blocked
pieces. The ordinary durable create path assigns a new outfit identity/key; the original record and snapshots stay intact.

## Photo entry, review and shortcuts (M6 source)

Wardrobe → Add from photos keeps a bounded, private list of photos for one-at-a-time garment review. Resume it after
relaunch from Wardrobe or Pending saves. Save or explicitly choose the garment, accept its photo, then finish after
acknowledgement. Stable create/media identities reuse the existing save and photo queues; partial completion stays visible.
iOS can optionally compare cached local thumbnails for the three closest photos, with explicit partial-coverage disclosure
and a fresh existing-item check. Android uses manual existing-item selection. Nothing merges automatically.

History → Wardrobe review links validated selected-period server counts to paginated confirmed outfit records and saved
garment facts. iOS Siri/Shortcuts and Android launcher shortcuts open Add, Search or Today through login/onboarding.
No shortcut saves or records wear. M6 source/tests are authored; the signed M6 build was installed/launched on the iPhone 17 Pro on 2026-10-08 and its running process was confirmed.

## Remaining work

- M4–M6 validation: builds/suites, actual keyboard, screen-reader, high-contrast, speech/model, duplicate-hint
  quality and system-action hardware checks. M6 iPhone build/install/launch passed; full runtime verification remains pending.
- Direct Apple model image prompting and Sensei app extraction.
- Provider-specific delivery guarantees/iPhone push, automatic weather ranking, external AI tagging and remote object reclamation. Old unqueued local staging files
  are pruned only after a readable manifest and a one-day grace period.
