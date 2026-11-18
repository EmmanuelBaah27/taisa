# Native DS Control Enforcement Design

**Status:** Approved
**Last updated:** 2026-11-18
**Linear:** APF-88

## Intent

Close the native design-system loophole that allowed feature-specific or composite UI to use
raw SwiftUI interactive controls merely because the source lived inside the
`TaisaDesignSystem` module. When a shared Taisa component exists, Product code and composite
design-system code must consume it. A missing variant is a blocking design-system gap, not
permission to bypass the shared contract.

## Goals

- Make shared component adoption mandatory across Product and composite design-system code.
- Permit raw SwiftUI interactive controls only in explicitly designated primitive wrappers.
- Make every existing non-primitive occurrence visible as bounded migration debt owned by
  APF-75, without permitting new debt.
- Fail verification when an unclassified raw control is added or an existing debt occurrence
  changes without reclassification and approval.
- Require component-gap evidence at Build entry and at pre-merge audit.

## Non-goals

- Migrate all existing native surfaces; APF-75 owns that full-app outcome.
- Repair the Tasks composer; APF-69 consumes this rule after APF-88 is established.
- Ban SwiftUI controls inside approved design-system primitive implementations.
- Replace genuine system-owned controls without an approved semantic DS treatment.

## Invariant

If a shared design-system component covers an interaction, its use is mandatory. Raw platform
interactive controls may appear only inside explicitly designated primitive implementation
files. A required interaction that no existing component or coherent variant covers terminates
Product work as a design-system gap until Baah approves reuse, extension, addition, or a narrow
system-owned exception.

## Approaches considered

1. **Keep the design-system directory exempt.** Rejected because a composite or feature can be
   moved into that directory and silently gain permission to bypass shared components.
2. **Reject every current raw control immediately.** This is the desired end state but would
   absorb the 83-occurrence full-app APF-75 migration into a workflow repair and leave main
   unverifiable until that unrelated migration completed.
3. **Explicit primitive registry plus exact legacy baseline.** Chosen. Primitive wrappers are
   named individually. Every other current raw occurrence is fingerprinted as APF-75 debt.
   New, moved, or changed occurrences fail closed. APF-75 removes baseline entries as it
   migrates consumers; it cannot add new entries without Baah-approved exception evidence.

## Enforcement design

`scripts/native-apple/design-system-control-policy.json` is the only mechanical classification
source. It contains:

- `primitiveFiles`: exact repository-relative Swift files permitted to wrap raw platform
  interactive controls;
- `legacyOccurrences`: exact fingerprints of current non-primitive raw controls, each owned by
  APF-75 with a semantic reason;
- no directory wildcards and no general Product or design-system exemption.

The native design-system verifier scans both `apple/TaisaApp` and
`apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem`. It reports an error when a raw
interactive-control occurrence is outside a primitive file and does not exactly match the
approved legacy baseline. It also reports stale baseline entries so migrations must remove
their exceptions.

The policy is an enforcement ledger, not an approval surface. Adding a primitive, legacy
occurrence, or system-owned exception still requires the workflow's prior Linear evidence.

## Primitive creation criteria

A new primitive is appropriate only when no existing component can represent the interaction
through a coherent variant, the behavior and accessibility contract are reusable, and adding
the behavior to an existing component would make that component contradictory. Copy,
callbacks, one-screen styling, width, or size differences alone do not justify a new primitive.
Extension of an existing component remains preferred when its semantic contract stays coherent.

## Accessibility and safety

Primitive wrappers retain native activation, focus, keyboard, VoiceOver, disabled, and touch
target behavior. Enforcement does not replace platform behavior with custom gestures. Source
classification must ignore comments and string literals so documentation or test fixtures do
not create false Product violations.

## Acceptance

- Workflow authorities state the invariant and the primitive-creation boundary consistently.
- The bounded Goal template requires exact primitive/legacy/exception evidence.
- Product and composite DS raw-control fixtures fail verification.
- Designated primitive-wrapper fixtures pass.
- Exact legacy occurrences pass, new or changed occurrences fail, and stale entries fail.
- Native DS verification, workflow verification, governed-document freshness, and diff checks
  pass on the exact candidate.
