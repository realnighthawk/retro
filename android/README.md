# Retro for Android

Kotlin + Jetpack Compose client for the `/retro` engine. Same design language as the iOS client, Android's own controls.

Retro now opens a wardrobe-only shell: **Today / Wardrobe / History**, account-bound to the existing login.
The combined demo is preserved in `ProductivityDemoShell` for **Sensei**. This increment has not been built or tested.
See [the engine design](../docs/wardrobe-engine-design.md) and [the extraction plan](../docs/sensei.md).

```sh
# Needs a JDK 17+. Android Studio's bundled one works:
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
./gradlew assembleDebug        # or: ./gradlew installDebug
./gradlew testDebugUnitTest
```

`local.properties` (gitignored) points at the SDK; the router address and Clerk publishable key come from
`build.gradle.kts` and can be overridden with `-PROUTER_BASE_URL=...`.

## What it does

Reads real inventory, dated outfits and paginated history through `Engine`. Detail screens refresh records while
retaining cached presentation on failure. Per-owner files and endpoint/query keys isolate read caches. Android navigation
uses the installed Navigation Compose library with saved tab back stacks. No new dependencies.

## Private photos

Save a garment, then open **Photos** from detail. Use the system picker/camera, review and order several images,
choose a primary image, or detach references without erasing historical snapshots. Camera writes use a narrowly
scoped FileProvider cache path; no blanket photo-library/camera permission is requested by the app.
Accepted immutable JPEG bytes and retry keys persist before reservation/upload. Foreground/reconnect/manual retry
resume processing and versioned attachment; local sources remain until acknowledgement. Changed references require
explicit review using ready media IDs. Authenticated derivatives use a 64 MiB owner/endpoint cache; binary requests
never follow redirects or returned URLs. Android capture remains manual, with no cloud inference or new dependency.
`WardrobePhotoTest` and shared media fixtures are authored, unrun; native pixel/orientation checks still need hardware.

## Layout

```
app/src/main/java/org/nighthawklabs/retro/
  RetroApp · MainActivity · DevMode
  auth/   Auth (Clerk, offline guard, token)
  net/    Api (Api<T>, classify, errorOf, Engine) · UrlTransport
  data/   WardrobeModels · WardrobeDrafts · WardrobeStore · WardrobeWrites · WardrobePhotos · PhotoPreparation · WardrobeReadCache · preserved demo Models/DemoData
  ui/     theme/Theme (palette, shapes) · DayArc · WeekStrip · GoalRow · TodayScreen · AppRoot · RetroMark
```

## Rules that come from the design

- **Health is not a score.** A missed day draws `sand`, never `clay` or `rust`.
- **Reduce Motion** is Android's animator duration scale; when it is zero the arc arrives drawn.
- **Platform controls.** `LazyColumn`, `ModalBottomSheet`, `OutlinedTextField`, Material icons.

## Workspace setup

After sign-in, Retro checks the shared router's `GET /onboard`. Completed setup opens the app; running setup resumes
polling. A new account can create its workspace with platform defaults and securely generated credentials through
`POST /onboard`. Every retry checks status first. If onboarding history has expired, `/gateway/healthz` checks whether
the workspace already exists before offering setup again. Offline checks leave the app usable, and `dev_engine`
skips provisioning. This provisions the shared workspace; enable the new wardrobe engine through a tenant chart upgrade.

## Dev mode

Launch with the intent extras `dev_engine` (use `http://10.0.2.2:18091` from the emulator) and `dev_hour`:

```sh
adb shell am start -n org.nighthawklabs.retro/.MainActivity \
  --es dev_engine "http://10.0.2.2:18091" --es dev_hour "15"
```

`dev_tab` selects `today`, `wardrobe` or `history`; `dev_hour` remains for the preserved demo.
All overrides are ignored in release builds.

`WardrobeReadTest` uses shared `fixtures/wardrobe` responses for wire decoding, cache isolation, pagination,
and late-query/account-switch behavior. These tests are authored, not run. `WardrobeWriteTest` adds persistence, lost-response replay, rejection, cancellation, account-switch and snapshot-preserving patch cases.

Manual garment/outfit forms and Pending saves are implemented in source. Writes retain their frozen payload/key
and 64-bit expected version across relaunch, are serialized, and retry on foreground/reconnect or explicitly.
One write per record is allowed; selected garments must finish pending writes first. Rejected requests show intended
changes and can load current records; uncertain dispatched requests cannot be discarded. Data stays in account/endpoint
scoped private no-backup files. Unchanged outfit pieces are omitted from correction patches to preserve snapshots.

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
No builds, tests or deployment ran.
