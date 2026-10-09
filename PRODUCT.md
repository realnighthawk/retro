# Product

<!-- impeccable:product-schema 1 -->

## Product Boundary

Decision recorded on 2026-10-08: **Retro is the wardrobe app. Sensei is a separate productivity app.**

| App | Owns |
| --- | --- |
| Retro | Garments, photographs, outfit plans, confirmed wears, availability/laundry state, wardrobe history and insights |
| Sensei | Daily planning, goals, habits, tasks, focus, general notes, the daily record and productivity review |

An outfit's styling note belongs to Retro; a journal entry about the day belongs to Sensei. Both share Clerk identity
and workspace onboarding. Neither requires the other installed. Optional calendar context can inform wardrobe choices
without copying productivity records into Retro.

The native clients now open a wardrobe-only shell with manual garment/outfit writes and durable pending saves; the earlier combined demo is preserved for Sensei.
Private photos, capture assistance, M5 requests/search/comparison/reuse and M6 photo entry/reviews/system actions are implemented in source. The M6 iOS
build/install/launch succeeded; authored suites and full flows remain unverified. Retro is the current focus; see [the Retro feature roadmap](docs/retro-feature-roadmap.md),
[the on-device intelligence plan](docs/on-device-intelligence-plan.md),
[the wardrobe engine design](docs/wardrobe-engine-design.md) and
[the Sensei boundary and extraction plan](docs/sensei.md).

The [next-feature checklist](docs/retro-feature-checklist.md) adds daily personalized suggestions, live camera
try-on with outfit/piece swaps and laundry load planning from confirmed care settings. A shared agent endpoint will
have access to user data and supporting connections for context, reasoning and optional remote processing; native
clients retain local interaction/offline behavior and the engine remains authoritative for wardrobe records.
The owner's execution preference is Apple-first: on-device interpretation/explanation and native image/speech/tracking
where suitable, complemented by the existing agent for connected and heavier work. Apple Private Cloud Compute is excluded.

## Platform

adaptive

Two native clients in this repository (`ios/`, `android/`), each following its own platform's
conventions rather than one shared skin. The design language is shared; the controls are not.

## Stack

Recorded because this project is new and the choice was made deliberately, not inherited:
SwiftUI (iOS 17+, XcodeGen-generated project) and Kotlin + Jetpack Compose (Android, AGP 8.13).
Both clients talk to the same engine through the shared identity router. No third-party UI
frameworks beyond Clerk for identity; system frameworks otherwise.
The backend uses Go, PostgreSQL and a private MinIO object-storage endpoint, with one operation registry for HTTP/MCP.
Each engine serves one wardrobe, with a dedicated database and bucket. Authentication and tenant routing belong
to the shared router; the engine has no Clerk configuration or user-based data partitioning.

## Users

Primary: the owner, using it on their own phone, for themselves. A personal instrument, not a
multi-user product. Secondary (deliberate, not yet designed for): other people, if it ships. The
owner chose "me first, shippable later", so nothing may be built in a way that would have to be
undone for strangers — but nothing may be built *for* strangers either.

## Product Purpose

Retro helps the owner know what they have, choose what to wear and remember what they actually wore.
The morning decision should take less effort than browsing the whole wardrobe. Recording a wear takes one action.

Success: useful suggestions from the owner's real, available clothes, with a quick way to change the choice.
Second success: a year of outfit history accumulates through use and survives renaming, archiving or giving away clothes.

## Positioning

The wardrobe is personal inventory; **the day anchors its use**. Garments have stable IDs, while outfits and wear
history hang off a local calendar date. Suggestions, plans and confirmed wears are distinct facts. Wear counts come
from confirmed history, not from viewing or accepting a suggestion. Productivity's day board belongs to Sensei.

Second: the engine is reachable over MCP as well as HTTP, like the rest of the family, so an agent
can read and write the owner's wardrobe through the same operations the app uses. The app is a
client of the same contract, never a privileged one.

## Operating Context

- Used in the morning to decide, when adding clothes and when looking back over outfits, often one-handed.
- The owner already runs a family of personal services behind one identity router
  (`harness-router.nighthawklabs.org`), each with its own path (`/finance`, `/maps`). Retro is
  `/retro`.
- Records matter over years. Archiving a garment must preserve its past outfits.
- The owner also uses AutoTelemetry (driving) and Treasure (spending). Cross-reads between them
  and Retro are possible and desirable, but not part of the first build.

## Capabilities and Constraints

Confirmed for the first build:

- Retro owns the wardrobe use case; Sensei owns the remaining productivity use cases.
- Data lives in a `/retro` engine behind the router, reached as
  `POST <router>/retro/api/v1/operations/<name>`, the same shape as the rest of the family. The
  client is thin; it owns presentation and offline tolerance, not domain rules.
- Native identity is the shared Clerk instance, verified by the router. The private engine requires no identity
  configuration. No guest mode in the clients: with no account there is nothing to show.

The backend implements photo-backed manual inventory, dated outfit planning/confirmation, explicit availability,
explainable rule-based suggestions, wear history, factual usage summaries and audited past-outfit corrections.
Photos use a private MinIO endpoint, selected by the owner. Deployment-specific endpoint, bucket and credentials
remain configuration. Native reads, manual writes, private photos and local iOS OCR/cutout/text assistance are implemented in source;
suggestions, insights and durable form/photo/create recovery are also implemented. M5 adds optional reviewed iOS
text/voice requests and search, plus real outfit comparison and history reuse on both clients. M6 adds private per-item
photo imports, optional iOS cached-thumbnail similarity hints, source-linked period reviews and authenticated system
entry points. Direct image prompting remains pending. Client/backend verification follows the owner's deployment. Optional garment text
drafts, OCR, cutout previews, request interpretation and local speech use capability-gated Apple frameworks; Sensei
starts with reviewed task extraction. Manual flows remain
complete, and accepted records/photos still sync. External AI processing and notifications remain deferred.

Constraint: the client must stay usable with no network — the engine is the source of truth, not a
prerequisite for reading cached inventory and outfit history.

## Brand Commitments

- Name: **Retro**. It retains the existing brand icon and wardrobe identity. **Sensei** is the separate productivity app;
  its icon and visual treatment have not been designed.
- Bundle / package identity `org.nighthawklabs.retro`, alongside `…telemetry` and `…treasure`.
- The family voice: restrained, specific, no exclamation marks, no gamification language, and no
  shaming. "You missed four days" is not written anywhere; "last kept 4 days ago" is.
- Colour commitment: a restrained palette — neutrals plus one accent. The owner asked for
  "minimal palette of colours" in explicit words.
- Motion commitment: rich but disciplined; authored rather than scattered.

## Evidence on Hand

Sibling implementations in the same family, used as the standing reference for craft level and
conventions: `finance-engine/clients/ios` (Treasure, ~10.8k lines, SwiftUI) and
`finance-engine/clients/android`; `maps-web/ios` (AutoTelemetry). Their published privacy
posture — on-device OCR, on-device speech, no third-party analytics or crash SDKs — is the
family's standard and Retro inherits it.

Absent and not to be fabricated: no user research, no usage metrics, no
testimonials, no pricing or App Store listing. Screenshots and example content in the
build are authored demonstration material and must be labelled as such wherever a reader could
mistake it for the owner's real data.

Feature/design research includes [Wardrowbe](https://github.com/Anyesh/wardrowbe), reviewed at commit
`1f6f6f49150dc2cc4fe6d0b28460213e9d461e52`. Specific sources and our design choices are recorded in the engine design.
This is not user research or a complete competitor audit. Photographs stay private; external AI processing requires
a deliberate choice and cannot be required for manual capture.

## Product Principles

1. **Inventory supports the decision.** The morning choice leads; the full rail remains available. Outfits belong to dates.
2. **Recording costs less than deciding.** Confirming an outfit is one explicit action; history describes actual wears.
3. **The engine owns the truth; the client owns the moment.** Domain rules live in `/retro`, and
   the client never invents state it cannot reconcile.
4. **Never shame.** Usage and gaps are described, never scored. The app is allowed to be
   interested in what happened; it is not allowed to be disappointed.
5. **One accent, spent carefully.** The single colour means "act here". When everything is
   important, nothing is.

## Accessibility & Inclusion

No product-specific requirement was established by the owner, so the family and platform floor
applies and is the commitment: Dynamic Type through the system text styles, both light and dark
appearance designed and tested rather than inferred, increased-contrast variants in the tokens,
Reduce Motion honoured with a real alternative for every non-essential movement, 44×44pt minimum
touch targets, and contrast ≥4.5:1 for body text in both appearances.

Garment names and metadata make photo tiles usable without seeing the photograph.

M4 source connects rule-based suggestions, factual insights, filtered timeline and append-only record history on
both clients. Garment/outfit/photo drafts survive relaunch; later edits to existing records and queued creates stay
local until reviewed against fresh data. Known rejected creates can be corrected explicitly, and rejected field edits
support selected-field reapplication. Photo draft acceptance and upload queuing share one atomic manifest.
M5 source adds reviewed local request/search interpretation and voice on iOS, deterministic engine-candidate comparison
and new-plan history reuse on both clients. The M5 iOS build/install/launch passed; tests, Android builds, full runtime
flows, intelligence behavior and accessibility validation remain deferred.
M6 source adds resumable per-photo garment review and attachment through existing queues, optional revision-pinned
cache-only Vision similarity hints on iOS, validated selected-period review counts linked to saved outfit facts, and
Add/Search/Today entry points behind normal auth/onboarding (Siri/Shortcuts on iOS, launcher shortcuts on Android).
No action automatically saves or merges. The signed M6 iOS Debug build/install/launch passed on the iPhone 17 Pro
on 2026-10-08, with its running process confirmed. Authored suites, Android builds and full feature/integration
validation remain unrun. Later optional features require individual scope selection.
