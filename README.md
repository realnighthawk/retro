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
The table describes the earlier native demo. On 2026-10-08, the current wardrobe iOS Debug build also succeeded,
was installed and launched on the connected iPhone 17 Pro, and its running process was confirmed. New client
tests/fixtures have not been run; full-flow, Android, backend/router/Helm and accessibility validation remain deferred.

## Backend deployment

The backend implements 20 operations for garments, outfits, history, availability, suggestions and photo jobs.
Router and tenant Helm wiring live in the sibling `agent-harness` repository. Supply the container image;
the tenant chart deploys MinIO with a 10 GB PVC and wires Retro automatically. See the [deployment guide](engine/README.md#deploy)
and [values example](engine/deploy/tenant-values.example.yaml). No infrastructure has been deployed by this change.

## Not built yet

- M4 device validation: actual keyboard, screen-reader, high-contrast and hardware checks.
  Recovery source is implemented; builds/tests/runtime verification remain deferred.
- Direct Apple model image prompting, voice/follow-up assistance and Sensei app extraction.
- Notifications, weather, external AI tagging and remote object reclamation. Old unqueued local staging files
  are pruned only after a readable manifest and a one-day grace period.
