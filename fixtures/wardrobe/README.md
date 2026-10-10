# Native read-contract fixtures

Synthetic HTTP response shapes shared by iOS and Android tests. These are test resources, never production demo data.
They cover omitted optional attributes, arbitrary garment colours, exact 64-bit versions, several outfits on one
local date and historical names distinct from current inventory. Dates/timestamps stay in their original wire form.
`inventory.json` also carries P4.2 `total_matches` above the single item it returns, so a decoded page is never
mistaken for complete inventory; older responses without it still decode.
Maintain these alongside the wardrobe engine contract when fields change. Tests are authored; execution is deferred.

`media.json` exercises a ready photo's 64-bit version, immutable reservation fields and router-relative derivative
paths. Photo queue tests use fake binary responses to isolate replay/attachment/account fencing, not backend image
validation. Native image preparation and actual camera/HEIC/EXIF/mask behavior require the deferred platform checks.

`suggestions.json`, `analysis.json` and `audit.json` cover eligible/incomplete rule-based choices, factual wear-day/event counts and exact integer audit versions. Recovery tests cover frozen identities, rejected-request replacement and local draft persistence; all remain unrun.

`preferences.json` and `feedback.json` cover P1's exact integer source versions, valid zero-temperature presets,
explicit false/zero settings, optional ratings and feedback tied to an older corrected outfit version. Native P1
tests author frozen queued-feedback replay and explicit-null reset checks; execution is deferred.

`ranked-suggestions.json` adds P2.1 names/versions, source-linked preferences, a meaningful zero score, feedback
coverage and missing-role/warning metadata. Its old timestamp deliberately exercises cached-versus-fresh behavior;
tests create fresh response times for review paths. The legacy `suggestions.json` remains for backward decoding.
Native ranking tests cover exact versions, fingerprint/coverage constraints, locks/swaps and current-eligibility
rechecks before an unsaved plan; all remain unrun.

`daily-automation.json` covers P2.5 settings/run identities, exact 64-bit settings and source versions, sparse Go
suggestion query fields and an uncertain claimed delivery. Native tests refresh only generation/expiry timestamps
for clock-independent validation, retain the source IDs/versions, and author actual wake evidence, paused/absent
proof, frozen queued saves and same-task schedule recovery. Worker and engine replay/window regressions are also
authored; none of these suites has run or sent a notification.

`laundry.json` covers P3.1 a confirmed cold-wash programme, grouped/blocked garment references and a planned load
with retained care snapshots and exact 64-bit source/load versions. Native tests refresh only the preview timestamp
for clock-independent freshness checks and author blocked/duplicate/stale-source rejection, mandatory queued-intent
recovery and frozen replay. Engine tests cover incompatible colour groups, reservations, atomic stale-piece failure,
wash-versus-dry confirmation, professional return, cancel/release and retained snapshots; all suites remain unrun.

P3.2 `WardrobeLaundryAssistanceTests` reuse `preferences.json` rather than duplicate preset sources. Authored tests
cover explicit Celsius evidence/zero, named native aliases, exact 64-bit preset versions, stale/cached/pending or
ambiguous preset rejection, partial/conflicting programmes, acknowledged unsupported conditions and bounded,
account/form-fenced OCR evidence handoff without inferred care or confirmation. No model or OCR execution is claimed.

`laundry-check-in.json` covers P3.3 definite and ambiguous same-day wear totals, a due reminder, exact 64-bit garment/
completed-load source versions and a missing cleaning baseline with unknown counts. Native tests rebase only the
generation/cleaning timestamps for clock-independent freshness while preserving facts/versions. Engine tests author
backdated/void/restored/date/piece corrections, cross-zone same-day ambiguity, distinct dates versus events,
cancelled versus completed cleaning, paused/off reminders and calendar intervals across DST. Frozen native saves
replay the exact reviewed policy/version. All suites, runtime flows and notifications remain unrun.

`pairings.json` and `selected-day.json` cover P2.2 reusable references, current garment facts, selected planned
outfits and exact 64-bit pairing/selection/outfit versions. The old `day.json` still decodes without a selection.
Native tests author choosing-versus-wear separation, explicit null clear, immutable retry/recovery bodies, current
pairing/garment rechecks and new response decoding in the durable queue. Execution remains deferred.

`outfit-context.json` is a synthetic P2.4 gateway envelope with actual-format connection/tool metadata, provider
weather/calendar/travel JSON and a pointer-only projection manifest. It covers explicit Fahrenheit conversion,
source time zones and an exact large integer in the retained provider result. Native tests refresh its timestamps
and IDs, and author forged/stale/unsupported pointer, date/unit/scope, reviewed-refinement, typed recovery and
cancellation checks. These fixtures do not establish deployed connection formats or provider coverage; tests remain unrun.

`laundry-planning.json` covers P3.4 fixed programme/group sources, dark/white/wash-separately pieces, blocked care,
same-zone and other-zone planned outfit sources, an explicitly partial plan page and two proposed batches with an
unresolved duration/capacity condition. Exact garment/outfit versions above JavaScript's safe integer range stay
integers. Native tests rebase date/timestamp fields and fill the deterministic source binding, then author mixed/
blocked/reused/unknown/late scope rejection, DST/midnight, source change, cached data, typed connected task recovery,
late-result fencing and frozen reviewed-load retry cases. No real account/garment/provider data is used; tests remain unrun.

`garment-records.json` covers P4.1 pattern/style/fit and an exact purchase record: a receipt-sourced amount in
integer minor units with its ISO 4217 currency and derived exponent. Native tests author money formatting without
conversion, partial/zero/unknown amounts, client-side field validation, selective purchase patches and explicit
clearing, and confirm the legacy `inventory.json` record still decodes with every new field absent. Tests remain unrun.

P4.2 search fixtures reuse `inventory.json`: the page reports one item, a cursor and a larger `total_matches`.
Native tests author exact wire names for every filter (`wash_method`, `care_confirmed`, `include_archived`),
omitted nils, sort titles, active-filter descriptions and language-draft filters, including rejection of
unsupported or oversized conditions. Engine tests walk pages over tied names, compare every sort order, and
confirm changed filters or sorts invalidate a cursor. All remain unrun.

`usage-review.json` covers P4.3 analytics: ranked most/least worn with per-garment cost per wear in its own
currency, not-worn-in-range versus never-worn lists with their full totals, a colour distribution over the
inventory, one weekly bucket, explicit feedback buckets and separate selection/plan counts. The legacy
`analysis.json` keeps the older shape on purpose: native tests confirm it still decodes and produces the
same unchanged summary. Tests author decoding, money formatting, coverage and subset/sum rules, plus forged
or stale responses (a never-worn entry outside the unworn list, rating buckets that do not add up, a cost per
wear with a smaller denominator, a review for another period). Tests remain unrun.

P4.4 duplicate-scan tests build their candidates and cached thumbnails in code (no photo bytes are stored in the
fixtures): the comparison plan, its fetch budget, over-budget accounting, oversized cached thumbnails, source-photo
and revision binding, and the coverage sentence including an unreadable inventory. Vision feature prints themselves
are not exercised here; they need the deferred device checks.

P4.4 is otherwise tested without fixtures: the comparison plan and its coverage accounting are built in code, and
the broadened capture extraction is checked by asserting that only values present in the supplied text survive,
that unstated values are dropped and reported, and that bounds match the garment record. Vision feature prints and
the on-device language model are not executed here.

P4.5 receipt reading is tested in code against sample receipt text (no image fixture): amount normalization and its
refusals, literal currency and date rules, dropped-value reporting, selective application into `garment-records.json`
and stability when the same receipt is applied twice. Vision text recognition and the on-device model are not run.

P4.6 batch tests build their garments in code and use a file-backed write queue with a stub sender: plan skip
reasons and the queue's item budget, frozen per-item intents, one request per garment, a second run refused per
item, partial acknowledged/refused/retrying outcomes, identity kept across a relaunch, and a signed-out client that
can claim nothing saved. No engine or network behaviour is exercised.
