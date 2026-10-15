# Chat Details Figma Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the approved native SwiftUI chat-details, recording, editing, recovery, and adaptive states from APF-61 using the supplied Figma nodes and existing encrypted conversation contracts.

**Architecture:** Extend the existing audio/voice snapshots with content-free live capture disposition, then drive one typed conversation presentation state through feature-local SwiftUI composition and business-free TaisaDesignSystem components. Existing storage, transcript-revision, exactly-once request, and recovery owners remain authoritative.

**Tech Stack:** Swift 6, SwiftUI, Observation, AVFoundation adapters, Swift Testing/XCTest, TaisaFoundation packages, iOS/iPadOS 26+

**Spec:** Linear APF-61 description and approval comment `2f1a01fd-8e6e-415b-91cd-def359e15040`

## Global Constraints

- Preserve encrypted, device-authoritative readable data and the device UUID identity boundary.
- No backend, storage-schema, authentication, AI-contract, or new dependency changes.
- Build from APF-60 `9bc16e7`; do not integrate APF-61 ahead of APF-60.
- Use Figma nodes `1:859`, `1:1000`, `1:887`, `1:1038`, `1:934`, `1:1143`, and `1:1117` as recorded in APF-61.
- The title is one line, fixed at 220pt, center aligned, with tail truncation and a complete accessibility value.
- Every production behavior change follows RED → GREEN; Reduce Motion and reduced-transparency behavior are first-class.
- Do not publish to canonical preview or request device QA until the complete verification and review gates pass.

## Review Focus

- Competing discard, keyboard, pause, send, and chevron actions must serialize without double cleanup or duplicate requests.
- Backgrounding/interruption at the empty/short/sendable boundary must restore the correct state without persisting an empty chat.
- Editing an old user message must revise only its response chain and preserve subsequent messages and provenance.
- Large Dynamic Type, RTL, compact height, and iPad widths must keep the header and active controls reachable.
- Dismissal during durable transcription/coaching must reconcile by request identity without duplicate visible messages.

---

### Task 1: Recorder-owned live capture disposition

**Files:**
- Modify: `apple/Packages/TaisaFoundation/Sources/TaisaAudio/AudioRecorderAdapter.swift`
- Modify: `apple/Packages/TaisaFoundation/Sources/TaisaAudio/AudioCaptureService.swift`
- Modify: `apple/Packages/TaisaFoundation/Sources/TaisaVoice/VoiceSessionCoordinator.swift`
- Test: `apple/Packages/TaisaFoundation/Tests/TaisaAudioTests/AudioCaptureServiceTests.swift`
- Test: `apple/Packages/TaisaFoundation/Tests/TaisaVoiceTests/VoiceSessionCoordinatorTests.swift`

**Interfaces:**
- Produces: `VoiceCaptureDisposition` with `.empty`, `.shortCapture`, `.sendable`, `.durableProcessing`; a redacted live snapshot containing elapsed milliseconds, meter levels, capture activity, and disposition.
- Consumes: existing actor-serialized audio and durable voice-turn state.

- [ ] Write failing tests proving prepared/zero capture is empty, captured-but-below-policy is short, policy-qualified capture is sendable, and a durable request is processing.
- [ ] Run focused TaisaAudio/TaisaVoice tests and confirm failures are caused by missing snapshot/disposition APIs.
- [ ] Add the minimal content-free recorder telemetry and one named sendability policy; do not expose URLs, audio bytes, transcript text, or private content.
- [ ] Prove interruption, pause/resume, finalization, discard, and repeated snapshots retain correct disposition.
- [ ] Run focused package tests and commit `feat(voice): expose redacted capture disposition`.

### Task 2: Shared chat-details design-system foundations

**Files:**
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem/ConversationPageHeader.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem/ConversationActionBar.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem/ConversationActivityIndicator.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem/InlineRecoveryAlert.swift`
- Modify: `apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem/TextComposer.swift`
- Modify: `apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem/CentralIcon.swift`
- Modify: `apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem/SpacingToken.swift`
- Test: `apple/Packages/TaisaFoundation/Tests/TaisaDesignSystemTests/ConversationComponentTests.swift`

**Interfaces:**
- Consumes: APF-60 `PageEdgeFade`, glass controls, semantic tokens, Central icons.
- Produces: business-free typed header, reply/recording/paused/saved/progress action bars, Figma activity visuals, recovery alert, and composer variants.

- [ ] Write failing component-contract tests for 220pt title width, fade reuse, 56pt recording controls, action availability by disposition/phase, empty/paused/saved variants, text composer voice/send/progress substitutions, and recovery actions.
- [ ] Run focused design-system tests and confirm expected missing-component failures.
- [ ] Implement the smallest SwiftUI components using semantic tokens and native Liquid Glass with opaque reduced-transparency fallbacks.
- [ ] Translate the supplied two-second Figma keyframes into native SwiftUI keyframes; render static indicators under Reduce Motion and while paused/interrupted.
- [ ] Verify Dynamic Type action stacking, 44pt minimum targets, VoiceOver labels, RTL ordering, and compact-height scrollability.
- [ ] Run design-system tests and verification; commit `feat(ds): add conversation detail surfaces`.

### Task 3: Conversation timeline and message actions

**Files:**
- Modify: `apple/TaisaApp/Conversation/ConversationTimeline.swift`
- Modify: `apple/TaisaApp/Conversation/TranscriptCorrectionView.swift`
- Modify: `apple/TaisaUnitTests/ConversationViewContractTests.swift`
- Modify: `apple/TaisaUnitTests/ConversationViewModelTests.swift`

**Interfaces:**
- Consumes: existing `MessageRecord`, correction/revision client, Markdown renderer, clipboard environment.
- Produces: user bubble, full-width Taisa response, six-line user preview, Copy/Edit context menu, correction editor, regeneration and recovery presentation.

- [ ] Write failing tests for role-specific alignment, user-only Edit, all-message Copy where approved, complete-text editing, unchanged/empty Save disabled, and response-chain regeneration state.
- [ ] Confirm the focused tests fail for missing presentation and state contracts.
- [ ] Implement the message views and native context menu without changing storage records directly.
- [ ] Wire correction to immediate revised user text plus in-place `Updating response…`, retry, and keep-edited-message outcomes.
- [ ] Add tests for long messages, Markdown blocks, manual scroll suspension, jump-to-latest, subsequent-message preservation, and one-edit-at-a-time behavior.
- [ ] Run focused tests and commit `feat(apple): refine conversation timeline and editing`.

### Task 4: Conversation page state machine and input lifecycle

**Files:**
- Modify: `apple/TaisaApp/Conversation/ConversationViewModel.swift`
- Modify: `apple/TaisaApp/Conversation/ConversationView.swift`
- Modify: `apple/TaisaApp/Conversation/ConversationRuntimeFactory.swift`
- Test: `apple/TaisaUnitTests/ConversationViewModelTests.swift`
- Test: `apple/TaisaUnitTests/ConversationViewContractTests.swift`

**Interfaces:**
- Consumes: Task 1 capture snapshot and Task 2/3 UI contracts.
- Produces: serialized page actions and complete approved state/action matrix.

- [ ] Write failing model tests for preparing, empty, short, sendable, paused, saved draft, text, durable processing, interruption, permission denial, offline, and cleanup failure states.
- [ ] Write failing concurrency tests for double Send, cross+chevron, keyboard+pause, dismissal during save, and relaunch during processing.
- [ ] Confirm failures reflect the missing state/actions rather than test setup.
- [ ] Implement typed confirmation intents and one serialized action gate; keep durable operations idempotent.
- [ ] Compose the Figma header, timeline, centered empty state, shared fades, action bars, text composer, progress, and recovery variants.
- [ ] Implement provisional-chat cleanup versus existing-chat return-to-Reply exactly as recorded in APF-61.
- [ ] Run focused app tests and commit `feat(apple): implement chat detail state machine`.

### Task 5: Lifecycle, restoration, and adaptive verification

**Files:**
- Modify: affected tests under `apple/Packages/TaisaFoundation/Tests/TaisaAudioTests/`, `TaisaVoiceTests/`, and `apple/TaisaUnitTests/`
- Modify: `docs/design-system.md` only for durable shared component/token contracts introduced by Tasks 1–4

**Interfaces:**
- Consumes: completed Platform/Product behavior.
- Produces: end-to-end evidence for interruption, recovery, accessibility, and responsive layouts.

- [ ] Add failing regression coverage for incoming calls, route loss, background checkpoint, termination/relaunch, permission denial, offline queued send, ambiguous completion, storage pressure, and protected-data recovery.
- [ ] Make only the minimal corrections required for those tests and keep the action matrix unchanged.
- [ ] Add UI/contract coverage for Reduce Motion, reduced transparency, increased contrast, accessibility text, VoiceOver focus, hardware keyboard/Switch Control seams, RTL, iPad, landscape, and compact height.
- [ ] Run focused suites, `npm run verify:native-apple:fast`, project generation, and the applicable simulator UI lanes.
- [ ] Commit `test(apple): verify chat detail resilience`.

### Task 6: Whole-branch review and QA candidate

**Files:**
- Review all APF-61 changes against Linear APF-61 and Figma evidence.

**Interfaces:**
- Consumes: Tasks 1–5.
- Produces: reviewed clean candidate and QA evidence; no Ship action.

- [ ] Build the executing-plans review package from merge base `9bc16e7` to HEAD.
- [ ] Run a fresh whole-branch review using `requesting-code-review`; re-grade findings by user impact.
- [ ] Fix Critical/Important findings once with RED → GREEN tests and rerun the suite; ledger any rulings and deferred minors.
- [ ] Run `verification-before-completion`, native design-system verification, package tests, Xcode/simulator builds, accessibility smoke checks, and `git diff --check`.
- [ ] If all non-device gates pass, integrate only after APF-60 is safely in canonical history, publish the exact candidate to canonical preview, confirm the served/installed revision, and run agent smoke checks.
- [ ] Record the stable candidate and exact evidence in APF-61; request one focused iPhone/iPad QA pass. Do not merge without Ship approval.
