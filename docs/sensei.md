# Sensei product boundary

Product split agreed on 2026-10-08. The service architecture and extraction below are proposals;
no Sensei client, Clerk native registration, engine or router route has been created.

Sensei is the separate productivity app for what the owner intends to do and what actually happened.
Retro becomes the wardrobe app. Shared identity and calendar dates allow optional cross-reads without shared tables.

| Record or behavior | Owner |
| --- | --- |
| Garments, photographs, laundry state, outfit plans and confirmed wears | Retro |
| Wardrobe statistics, styling notes and outfit comfort/style feedback | Retro |
| Goals, habits, tasks, agenda and focus | Sensei |
| General notes, journal, daily record and productivity review | Sensei |
| Authentication and workspace provisioning | Shared Clerk and agent-harness |
| Future outfit card on Sensei's board | Optional read-only projection from Retro, linking to Retro |

An outfit's styling note belongs to Retro; a journal entry about the day belongs to Sensei.
Neither app requires the other installed. Sensei must use Retro operations to change an outfit, rather than keeping
another authoritative copy. Retro must not read a private journal to recommend clothes. Optional context is limited
to deliberately shared occasion, time window and weather. Cross-read failures cannot block either app's core use.

## Proposed identity and services

- Display name: **Sensei**.
- iOS bundle / Android package: `org.nighthawklabs.sensei` (proposed, unregistered).
- HTTP: `/sensei/api/v1/operations/<name>`; MCP: `/sensei/mcp` (proposed, not configured).
- Separate Sensei engine/database using the same Go/PostgreSQL and HTTP/MCP conventions as Retro and Finance.
- Same Clerk instance and shared idempotent workspace onboarding; installing Sensei reuses completed setup.
- Separate native app targets, icon, per-owner cache and pending-write queue.

Initially each app reads its own engine. No cross-app day service, distributed transaction, shared business-rule
library or new authentication system is needed. Sensei's full backend contract and brand design are separate work.

The [on-device intelligence plan](on-device-intelligence-plan.md) proposes reviewed task extraction from typed/voice
capture, then OCR capture, source-linked daily summaries and day-plan drafts. Design the contract to preserve source
text and source record versions before building these helpers. Local models do not commit tasks or completions directly.

## Extraction plan

1. Combined demo source is preserved in `ProductivityDemoShell` on both platforms; Retro now opens its real read shell.
   This first client increment is not built/tested. Retain productivity models/screens until Sensei extraction.
2. Create Sensei's iOS/Android clients in its own repository or another chosen project location.
3. Move/adapt Today, Goals, Review and productivity Capture there. Reuse native auth, networking, onboarding and
   accessibility conventions with Sensei-specific identities, callbacks and service URLs.
4. Separate the combined `Day` model: Retro gets outfits; Sensei gets agenda, goals, focus and record data.
   Remove wardrobe counts from Sensei's account summary unless an optional cross-read is added.
5. Replace Retro's general Capture with garment/photo and outfit capture. Make its Today screen about dressing.
6. Add engine response fixtures and update both apps' UI tests before removing the combined demo surfaces.

Demo content must never be imported as real user data. Before removing old caches, inspect for actual persisted
user edits and migrate them explicitly if needed. Moving source is not a data migration. Retro keeps its existing
identifier, login configuration and installation. Sensei needs its own Clerk native registrations when built.

First Sensei release: daily agenda, simple goals/habit completion and a daily record, with owner isolation,
audited corrections, idempotent writes and offline reading. Coaching personas, team projects, gamification,
notifications and automatic cross-app synchronization are deferred.
