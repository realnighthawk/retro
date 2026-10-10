# Live try-on: feasibility record

Status: **P5.1 authored 2026-10-10.** No renderer, model, asset format or specialist provider has been selected, and
no approach has been chosen. P5.2–P5.4 need measurements on the owner's actual device; those runs are deferred with
the rest of the runtime validation, so the results and decision sections below are deliberately empty rather than
guessed. A still image or a static overlay does not complete this work and is not N02 delivery.

The [implementation phases](retro-implementation-phases.md) own delivery status; the [P4–P6 handoff](retro-p4-p6-handoff.md)
owns the constraints. This file owns the capture specification, the benchmark budget, the measurements and the
eventual go/no-go record.

## What exists today, and what it is not

- `PhotoPreparation.cutouts` produces foreground-subject cutouts via `VNGenerateForegroundInstanceMaskRequest`, and
  `jpeg(_:)` writes them on a white background. These are **preview images for owner review, not try-on assets**:
  they have no garment mask, no depth, no material or drape information, and no scale reference.
- Garment photos are ordinary authenticated media (`display`/`thumbnail` JPEG derivatives, immutable once
  processed). They are photos of clothes, often flat or on a hanger, at unknown distances and angles.
- Nothing in the current app tracks a person, estimates pose, or renders anything over a camera feed.

## P5.1 Capture specification

**Camera.** Rear camera is the only supported capture path for the live view: it gives a true-scale, unmirrored view
of the wearer as others see them. The front camera may be offered only as a self-check with an explicit mirrored
preview label, because a mirrored feed changes which shoulder a bag or a lapel appears on. Depth-capable devices may
use depth when the framework that provides it is already available; nothing may require a LiDAR device.

**Distance and positioning.** Full-body framing: the owner stands so that the whole silhouette from crown to feet is
inside the frame with margin above the head and below the feet. Guidance is a framing overlay plus plain text, not a
distance in metres, because a phone cannot measure distance reliably without depth. Half-body framing (waist up) is
the fallback when the room cannot fit a full body, and it must be an explicit choice, because a half-body capture
cannot evaluate a dress, a coat length or footwear.

**Lighting.** Even, front-facing room light; no direct backlight (a window behind the wearer). The specification must
not promise measurements under bad light: if the scene is too dark or too blown-out for the tracker, the session says
so and stops rather than rendering from a degraded feed.

**Motion.** Standing still, turning slowly on the spot, and taking one step. Running, jumping, sitting and lying down
are explicitly out of scope for the first measured prototype. Hands crossing the torso are in scope because they are
the most common occlusion people actually produce; a carried bag or an open coat is in scope as a known-difficult
case, recorded as a limitation rather than solved.

**Garment categories** (first measured prototype): upper body (t-shirt, shirt, sweater), outerwear (jacket, coat),
lower body (trousers, jeans, skirt). Explicitly out: footwear, hats and accessories, swimwear/underwear, and dresses
with complex trains. A category excluded from the prototype must say so in the app rather than render something wrong.

## P5.1 Asset requirements

For each garment the owner wants to try on, the prototype needs an asset built from the photos already in the
wardrobe where possible:

| Requirement | Definition |
|---|---|
| Views | One frontal view minimum; a back view for garments with a distinct back (coats, printed tops) |
| Garment mask | A per-garment foreground mask tight to the silhouette, not the white-backed preview cutout |
| Scale reference | A known physical measurement (chest width or garment length) recorded by the owner, or an accepted relative fit only |
| Colour handling | Recorded under a known light temperature; the asset must carry its own colour profile rather than assuming sRGB |
| Format | To be decided by the renderer comparison; no format is chosen yet |
| Missing asset | The garment is not offered for try-on, and the reason is shown. Never substitute a stand-in garment |
| Retention | Assets are derived media; they count against the existing 10 GB MinIO budget and are deleted with the garment photo they derive from. Historical references are preserved: replacing a photo creates new media and never deletes a derivative another record points at |

Existing cutouts may seed masks, but a preview cutout is not accepted as an asset until the mask requirement above is
verified against a real garment.

## Proposed benchmark budget (not approved targets)

These numbers are **proposals to be measured against**, not approved product targets. They exist so that P5.2 has a
fixed yardstick before any approach is compared; the owner may replace any of them. Observed results go in the table
below this one, never mixed into it.

| Metric | Proposed measurement | Proposed budget |
|---|---|---|
| Preview frame rate | Sustained live preview on the target device | ≥ 30 fps p50, ≥ 24 fps p95 |
| Camera-to-preview latency | Frame captured to frame shown | ≤ 33 ms p50, ≤ 66 ms p95 |
| Swap-to-stable-preview | Garment change to a settled, non-flickering result | ≤ 250 ms p50, ≤ 600 ms p95 |
| Tracking-loss recovery | Person leaves frame and returns | Re-acquire ≤ 1 s, always with a visible state |
| Temporal stability | Garment edge movement on a still wearer | No visible flicker; edge movement ≤ 2 px frame to frame |
| Colour fidelity | Rendered garment vs asset under the same light | ΔE ≤ 5 (CIEDE2000) |
| Pattern and silhouette | Pattern scale and outline vs asset | Pattern within ±10% scale; silhouette IoU ≥ 0.9 against a hand mask |
| Body and face identity | Owner review against reference photos | Pass/fail rubric per category; no distortion accepted |
| Occlusion | Hands crossing torso, open coat, bag strap | Pass/fail rubric per case, recorded as limitation if failed |
| Memory | Peak and 10-minute growth | Peak ≤ 1.5 GB, no growth under sustained use |
| Battery and thermal | 10-minute continuous session | ≤ 8% battery, no thermal throttling below the frame-rate floor |
| Network | Rendering without network; any remote dependency | Local rendering must not require network. Any remote renderer records its p95 and its offline behaviour separately |

**Recording budget.** At most 30 minutes of owner-approved capture is retained locally for measurement, on the
device only, deleted after the results are written here. Raw camera video is never uploaded to MinIO or sent to the
agent; the same rule that keeps label and voice captures local applies here.

## Measurements (pending)

No device measurement has been taken. P5.2 records, per run: device model, OS version, framework and model versions,
build, lighting, distance band, category, and the observed value for each metric above, plus failure clips or notes
where a metric fails.

## Decision (pending)

P5.4 records the approach, supported devices and categories, measured limits, unresolved failures and the go/no-go
rationale. Until that exists, the honest statement is: no approach has been selected, and P5 is not complete.
