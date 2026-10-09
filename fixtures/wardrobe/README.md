# Native read-contract fixtures

Synthetic HTTP response shapes shared by iOS and Android tests. These are test resources, never production demo data.
They cover omitted optional attributes, arbitrary garment colours, exact 64-bit versions, several outfits on one
local date and historical names distinct from current inventory. Dates/timestamps stay in their original wire form.
Maintain these alongside the wardrobe engine contract when fields change. Tests are authored; execution is deferred.

`media.json` exercises a ready photo's 64-bit version, immutable reservation fields and router-relative derivative
paths. Photo queue tests use fake binary responses to isolate replay/attachment/account fencing, not backend image
validation. Native image preparation and actual camera/HEIC/EXIF/mask behavior require the deferred platform checks.

`suggestions.json`, `analysis.json` and `audit.json` cover eligible/incomplete rule-based choices, factual wear-day/event counts and exact integer audit versions. Recovery tests cover frozen identities, rejected-request replacement and local draft persistence; all remain unrun.
