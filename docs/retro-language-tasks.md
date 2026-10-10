# Language tasks: one declaration, two executors

Status: implemented in iOS source on 2026-10-10. Three tasks are declared on the seam — request interpretation,
garment extraction and receipt reading — and each offers a connected reading as an opt-in fallback when the device
cannot read the text itself. Runs remain unverified (no Swift suite has run).

## The problem this replaces

Retro asks a language model to turn text into a bounded draft in seven places on device (`WardrobeLanguage`,
`GarmentAssistance`, `WardrobeReceipt`, `WardrobeReviewAssistance`, `WardrobeCandidateAssistance`,
`WardrobeLaundryAssistance`, `WardrobeCareLabelScan`) and delegates three other features to the connected agent
(`WardrobeOutfitContext`, `WardrobeLaundryPlanning`, the daily-automation wake). Each pair is a prompt, an output
shape, a parser, a validator and a fallback. Offering a connected alternative for a task meant writing all five
again, and the rule that matters most — an agent's narrative is never a fact — lived in prose rather than in code.

## The shape

A task is declared once (`WardrobeLanguageTasks`):

- `id`, `schemaVersion`, and a `dataClass`: `typedText`, `reviewedText` or `rawCapture`.
- `instructions` shared by both executors, and a `contract`: the JSON-only answer shape plus its bounds.
- `onDevice(input)`: the on-device path, which may use `@Generable` structured generation.
- `parseAgent(text)`: the connected path's parser for the same shape.
- `validate(draft)`: **the same validator for both**, so a connected answer is structurally no more trusted than a
  local one.
- `policy`: whether the agent may run at all and which executor is preferred.

Two executors implement one protocol: `WardrobeDeviceLanguageExecutor` (Foundation Models) and
`WardrobeAgentLanguageExecutor` (a bounded `ask_agent` delegation, injected as a closure so tests can supply a fake).
`WardrobeLanguageDispatcher.run` picks: preferred first, the other second, then a clear failure that leaves the manual
controls in place.

## What the boundary now enforces

`rawCapture` tasks may never run on the agent, whatever the policy says. That turns "raw camera/label/voice data
stays local by default" from a paragraph in the handoff into a property the dispatcher checks. A connected run also
carries its own provenance: the answer records which executor answered, and the UI labels it.

## What this deliberately does not cover

`WardrobeCandidateAssistance`, `WardrobeLaundryPlanning` and `WardrobeOutfitContext` are not text-to-JSON tasks —
they use tools, snapshots, scopes and provider pointers. Forcing them through this seam would cost more than it
saves, so they keep their own adapters.

## The irreducible duplication

`@Generable` types cannot be derived at runtime, so each output shape keeps a small `@Generable` twin beside its
`Codable` form. Two declarations, one validator, one dispatch — small, and much less than two implementations per
task.

## Wiring

`WardrobeAssistant.delegate(_:connected:)` is the delegation primitive: the existing durable request journal, the
90-second deadline, owner questions and polling, without the text-answer state machine. On the interpreter screen
the connected reading appears as an opt-in toggle beside the on-device reason, so it is offered exactly when the
device cannot read the request itself; the screen reports which executor answered and uses the delegation's own
90-second budget when it does. The query carries the task's instructions, the contract and the owner's typed text
only — no record IDs, no photos, nothing else.

## Open / next

- The remaining on-device-only tasks (review explanation, care-label scan) migrate when a second executor is
  actually wanted; migrating them now would be work without a use.

## Tasks on the seam

| Task | Data class | Connected opt-in | Notes |
|---|---|---|---|
| `interpret.search` / `interpret.outfit` | typedText | Yes | Offered when the device cannot read the request |
| `extract.garment` | reviewedText | Yes | The label photo is never delegated, only the reviewed text |
| `read.receipt` | reviewedText | Yes | The receipt photo is never delegated; a total with no stated currency still cannot be applied |
