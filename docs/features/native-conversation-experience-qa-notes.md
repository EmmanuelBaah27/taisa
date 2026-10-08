# Native Conversation Experience QA Notes

**Last updated:** 2026-10-08

## Verified revision

- Product revision: `00d5ac2110cfed2749f4717a9795a0972a50643b`
- Branch: `feature/native-conversation-experience`
- Toolchain: Xcode 26.1.1 (`17B100`), iOS/iPadOS Simulator 26.1
- Simulator matrix: iPhone 17 Pro and iPad Pro 13-inch (M5)

## Automated verification

`npm run verify:native-apple:all` passed from the clean verified revision. The matrix included generated-project parity, native contract fixtures, 434 Swift package tests in 59 suites, native design-system enforcement, Development unit and UI tests, Preview unit and UI tests, Personal unit and UI tests, the unsigned generic physical-device build, the Release simulator build, production/Personal isolation inspection, and workflow verification.

Backend verification also passed before the native matrix: 399 tests in 24 suites and the backend TypeScript build.

## Required behavior evidence

| Requirement | Automated evidence | Physical-device status |
|---|---|---|
| Microphone permission denied | Deterministic `conversation.permission-denied` preview and voice coordinator/unit coverage passed | Pending |
| Background and foreground recovery | Recovery, lifecycle, and durable coordinator tests passed | Pending |
| Audio interruption recovery | Recoverable audio capture and voice relaunch suites passed | Pending |
| Force-quit and relaunch recovery | Durable checkpoint/relaunch suites passed | Pending |
| Offline and retry behavior | Retry scheduler, connectivity, reconciliation, transcription, and coaching fixtures passed | Pending |
| Duplicate and overlapping actions | Conversation coordinator, idempotency, and UI interaction tests passed | Pending |
| Successful audio cleanup | Voice audio cleanup and durable-send coverage passed | Pending |
| Dynamic Type | Accessibility XXXL conversation preview passed on iPad simulator | Pending |
| VoiceOver semantics | Contract and UI accessibility identifiers passed; no private live amplitude is announced | Pending human judgment |
| Reduced Motion | Static/reduced-motion preview coverage passed | Pending human judgment |
| iPad layout | All deterministic conversation scenarios passed on iPad Pro 13-inch (M5), iPadOS 26.1 simulator | Pending human judgment |

## Remaining release evidence

- Integrate the exact verified revision into `preview/taisa`, push it, and confirm the canonical preview runtime serves that revision.
- Complete signed physical-device QA on supported iPhone and iPad hardware. No physical-device result is claimed by this document.
- Resolve any device findings, repeat the complete verification and preview-publication loop, then obtain Baah's Ship approval.
