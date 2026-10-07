# Native Foundation Product Contract

**Contract revision:** `native-foundation-v1`  
**Fixture revision:** `transcription-fixtures-v1`  
**Status:** implemented; physical-device QA accepted 2026-10-04

This contract describes the portable behavior of Taisa's first native shell. It is the source for a future React Native implementation; SwiftUI types and Apple framework choices are implementation details unless called out as Apple-only below.

## Foundation shell

The development shell presents:

- the product name, **Taisa**, as the primary heading;
- the status copy, **Native foundation ready**;
- an environment badge in non-production builds;
- a **Build diagnostics** action in non-production builds.

The content remains readable at accessibility text sizes and is constrained to a maximum readable width of 560 points on wide layouts. On iPad, the column is centered rather than stretched. The root is scrollable so enlarged text is never clipped.

The title is a heading. The diagnostics control is a button. Environment and diagnostic rows expose combined, descriptive accessibility labels. Interactive controls retain a minimum 44-point target.

## Build identity

Diagnostics display the immutable evidence needed to identify a tested build:

- full Git commit, branch, and clean/dirty state;
- app build number;
- bundle identifier;
- backend environment;
- portable-contract/fixture revision.

A signed-build record additionally captures Xcode version and build, device name and identifier, device OS, installation, launch, and Baah's confirmation. A dirty worktree, commit mismatch, wrong environment bundle, failed install, or failed launch invalidates the record.

## Environment isolation

| Environment | Bundle identifier | Fixtures | Preview catalog |
|---|---|---:|---:|
| Development | `com.taisa.app.dev` | No | No |
| Preview | `com.taisa.app.preview` | Yes | Yes |
| Production | `com.taisa.app` | No | No |

Preview code is compiled only into the preview target. Preview networking is denied, and scenario content is synthetic. Release verification scans the production app so preview symbols and labels cannot leak into it.

## Preview catalog

The preview app lists searchable, named scenarios and can open a scenario directly for automated tests. The foundation catalog includes default, accessibility text, narrow iPad, reduced motion, increased contrast, and build-diagnostics states. Each scenario declares its intended device family and accessibility settings and uses stable accessibility identifiers.

## Adaptive requirements

- Support iPhone and iPad from iOS 17 onward.
- Support portrait and landscape on iPad.
- Keep the content column at or below 560 points and allow vertical scrolling.
- Respect Dynamic Type; the accessibility-text scenario uses an accessibility category.
- Use semantic design-system tokens/components rather than raw visual values in product views.
- Represent reduced-motion and increased-contrast requirements in scenario metadata. Behavior-specific adaptations are added with the features that use motion or contrast-sensitive surfaces.

## Deliberate Apple-only behavior

SwiftUI navigation, `Bundle` metadata, Xcode build settings, Apple provisioning profiles, XCUITest launch arguments, and iOS orientation declarations are Apple-only. A future React Native shell must reproduce the visible states, accessibility semantics, adaptive constraints, identity fields, environment isolation, and fixture revision—not these mechanisms.

## Voice platform retention and diagnostics

The native voice platform owns finalized audio until the durable conversation turn no longer needs it. In-progress, interrupted, offline, and recoverable turns retain their audio. Completed, no-speech, terminal-failure, and explicitly discarded turns delete owned audio idempotently and durably checkpoint cleanup completion. A failed deletion remains pending for retry.

At startup, files with a known recoverable owner are retained, files with a terminal owner are reconciled, and unknown files enter a bounded quarantine before orphan deletion. Reconciliation works only with opaque file identities; local paths never enter diagnostic or evidence output.

Voice preview fixtures are deterministic, synthetic, and network-denied. They cover clear, uncertain, no-speech, offline, reconnecting, interrupted, ambiguous paid-work, failed, completed, and second-turn states. Their portable evidence is limited to state, stage, counts, sizes, durations, sequences, synthetic fingerprints, and timestamps. Transcript text, coaching responses, private context, audio bytes, and local paths are forbidden from fixtures and diagnostics.

## Out of scope

The original shell remains deliberately separate from final product navigation and Conversation UI. Authentication and migration from the existing React Native application remain outside this contract. Persistence, audio capture, and streaming are governed by their separately approved platform contracts and plans.
