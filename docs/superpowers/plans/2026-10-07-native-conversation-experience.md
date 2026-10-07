# Native Conversation Experience Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status:** Approved by Baah — Build active
**Last updated:** 2026-10-07

**Goal:** Deliver Taisa's complete native voice-first conversation loop with global entry, deliberate Send, multiple recoverable drafts, conversation history, transcript correction, and safe failure recovery.

**Architecture:** Extend the existing encrypted native store and `VoiceSessionCoordinator`; do not create a second recorder or conversation database. Product views consume typed `TaisaConversations` models and clients, while the app shell owns navigation and global entry presentation. The stateless gateway receives readable content only after Send, and every paid request retains its durable request identity through retry and reconciliation.

**Tech Stack:** Swift 6, SwiftUI, Observation, GRDB/SQLCipher, `TaisaStorage`, `TaisaVoice`, `TaisaAudio`, `TaisaNetworking`, XCTest/Swift Testing, Xcode 26, Node/Express TypeScript gateway.

**Spec:** `docs/features/native-conversation-experience.md`
**Design handoff:** `docs/features/native-conversation-experience-design-handoff.md`
**Work Map:** `docs/features/native-conversation-experience-work-map.md`

## Dependency and branch gate

The documentation branch starts from `codex/swiftui-home-scope` (`44b5a08`) and therefore does not contain `TaisaVoice`. The canonical preview `110845e` contains both the Home revision and the native voice lineage ending at `01063fa`. Before Task 1, create the implementation worktree from a verified revision in which the accepted successors of both lineages are accounted for. Stop on conflicts, dirty worktrees, missing commits, or an unverifiable preview base. Do not merge `preview/taisa` into `main`; it remains an integration-only branch.

## Global constraints

- Target iOS/iPadOS 26 or later and preserve Swift 6 strict concurrency.
- Readable conversations, drafts, messages, and draft audio remain device-authoritative and encrypted/local.
- No transcription or coaching request occurs before deliberate Send.
- Reuse `VoiceSessionCoordinator` as the only voice lifecycle owner.
- Opening Home, Conversations, a draft, or history performs no AI request.
- Voice and text are mutually exclusive for one unsent turn.
- Completed voice audio is deleted after durable transcript/message persistence; required draft/retry audio remains local.
- Native screens use typed design-system tokens and standard SwiftUI behavior; no raw visual constants in Product views.
- Build follows DS foundation → Product screens → live integration.
- Mobile QA uses the exact committed revision integrated into and served by canonical `preview/taisa`.

## Review focus

- Force termination during recording, transcription, or coaching restores one exact draft/request without duplicate paid work.
- Switching to keyboard from recording or paused voice cannot leak, preserve accidentally, or double-delete audio.
- Rapid taps on Send, Reply, Save, Retry, and destructive actions remain single-flight.
- Manual titles survive delayed first-response title suggestions and relaunch.
- Conversation A state never appears while Conversation B is hydrating, resuming, correcting, or deleting.

## File structure

| Area | Files | Responsibility |
|---|---|---|
| Storage schema | `TaisaSchema.swift`, `TaisaMigrator.swift`, `DomainRecords.swift`, new conversation snapshot/query files | Durable lifecycle, drafts, title authority, revisions, ordered reads |
| Storage API | `ConversationRepository.swift`, new `ConversationQuery.swift` | Atomic save/resume/rename/delete/correction operations |
| Turn orchestration | `TaisaVoice/*`, new `TaisaConversations/*` | Voice adapter, text turns, shared state, retry/reconciliation, title refinement |
| Gateway contract | `CoachingStreamEvent.swift`, backend streaming coaching contract/tests | Optional first-response title suggestion without another request |
| Design system | `TaisaDesignSystem/*`, `docs/design-system.md` | Tokens, global dock, primary navigation, voice/text composer surfaces |
| Product | `AppRootView.swift`, new `AppShell/*`, `Conversations/*`, `Conversation/*` | Navigation, list, drafts, full-screen conversation, correction |
| Preview and QA | `TaisaPreview/*`, package/UI tests, `docs/features/*-qa-notes.md` | Deterministic states and canonical device verification |

---

### Task 1: Reconcile the implementation base and freeze contracts

**Files:**
- Verify: `apple/Packages/TaisaFoundation/Package.swift`
- Verify: `apple/TaisaApp/App/AppRootView.swift`
- Verify: `apple/Packages/TaisaFoundation/Sources/TaisaVoice/VoiceSessionCoordinator.swift`
- Modify: `docs/features/native-conversation-experience-work-map.md`

**Interfaces:**
- Consumes: accepted Home revision and accepted native voice/audio/networking revision.
- Produces: one clean typed implementation branch containing both dependency lineages.

- [ ] **Step 1: Verify both dependency lineages exist**

```bash
git merge-base --is-ancestor 44b5a08 HEAD
git merge-base --is-ancestor 01063fa HEAD
git status --short --branch
```

Expected: both ancestry checks return `0`, and the implementation worktree is clean. If a successor replaced either commit, document the verified replacement SHA and equivalence before continuing.

- [ ] **Step 2: Verify the compiled target graph exposes Home and voice**

```bash
rg -n 'TaisaHome|TaisaVoice|TaisaAudio|TaisaNetworking' apple/Packages/TaisaFoundation/Package.swift
swift test --package-path apple/Packages/TaisaFoundation
```

Expected: all four targets are present and package tests pass.

- [ ] **Step 3: Record the exact dependency SHAs in the Work Map**

Add a `Build baseline` line naming the verified commit and the Home/voice ancestor SHAs. Do not change feature behavior.

- [ ] **Step 4: Commit the baseline record**

```bash
git add docs/features/native-conversation-experience-work-map.md
git commit -m "docs: freeze native conversation build baseline"
```

### Task 2: Migrate durable conversation, draft, and revision records

**Files:**
- Modify: `apple/Packages/TaisaFoundation/Sources/TaisaStorage/TaisaSchema.swift`
- Modify: `apple/Packages/TaisaFoundation/Sources/TaisaStorage/TaisaMigrator.swift`
- Modify: `apple/Packages/TaisaFoundation/Sources/TaisaStorage/Models/DomainRecords.swift`
- Modify: `apple/Packages/TaisaFoundation/Sources/TaisaSync/SyncProjection.swift`
- Test: `apple/Packages/TaisaFoundation/Tests/TaisaStorageTests/TaisaMigratorTests.swift`
- Test: `apple/Packages/TaisaFoundation/Tests/TaisaStorageTests/ConversationTurnRepositoryTests.swift`
- Test: `apple/Packages/TaisaFoundation/Tests/TaisaSyncTests/VoiceTurnSyncProjectionTests.swift`

**Interfaces:**
- Consumes: existing `ConversationRecord`, `MessageRecord`, and `VoiceTurnRecord`.
- Produces: `ConversationLifecycle`, `ConversationInputMode`, `TitleAuthority`, `ConversationDraftRecord`, and `MessageRevisionRecord` persisted under schema version 2.

- [ ] **Step 1: Write failing migration and round-trip tests**

```swift
@Test func versionOneMigratesWithoutInventingDrafts() async throws {
    let store = try await fixtureStore(schemaVersion: 1)
    try await store.migrate()
    #expect(try await ConversationRepository(store: store).listDrafts().isEmpty)
}

@Test func voiceDraftRoundTripsItsTurnIdentityWithoutReadableAudioInExport() async throws {
    let draft = ConversationDraftRecord(id: UUID().uuidString, conversationID: UUID().uuidString,
        inputMode: .voice, text: nil, voiceTurnID: UUID().uuidString, recoveryKind: .saved,
        createdAtMS: 1, updatedAtMS: 1)
    try await repository.saveDraft(draft, context: context)
    #expect(try await repository.draft(id: draft.id) == draft)
    #expect(try await exportArchive().containsAudioPath == false)
}
```

- [ ] **Step 2: Run focused tests and confirm failure**

Run: `swift test --package-path apple/Packages/TaisaFoundation --filter 'TaisaMigratorTests|ConversationTurnRepositoryTests|VoiceTurnSyncProjectionTests'`
Expected: FAIL because schema v2 and draft/revision types do not exist.

- [ ] **Step 3: Add schema v2 and explicit domain types**

```swift
public enum ConversationLifecycle: String, Codable, Sendable { case draft, active, completed }
public enum ConversationInputMode: String, Codable, Sendable { case voice, text }
public enum TitleAuthority: String, Codable, Sendable { case localFallback, assistantSuggested, user }
public enum DraftRecoveryKind: String, Codable, Sendable { case saved, recovered, retryableTranscription, retryableCoaching }
```

Add constrained columns for conversation lifecycle/title authority and tables for drafts and message revisions. Store only app-owned audio file IDs already governed by the voice cleanup queue; exclude them from readable archive payloads and sync projection.

- [ ] **Step 4: Run storage and sync tests**

Run: `swift test --package-path apple/Packages/TaisaFoundation --filter 'TaisaMigratorTests|ConversationTurnRepositoryTests|VoiceTurnSyncProjectionTests'`
Expected: PASS, including v1 migration, FK deletion, title authority, multiple drafts, and audio-path exclusion.

- [ ] **Step 5: Commit**

```bash
git add apple/Packages/TaisaFoundation/Sources/TaisaStorage apple/Packages/TaisaFoundation/Sources/TaisaSync apple/Packages/TaisaFoundation/Tests
git commit -m "feat: persist native conversation drafts and revisions"
```

### Task 3: Build atomic conversation queries and mutations

**Files:**
- Modify: `apple/Packages/TaisaFoundation/Sources/TaisaStorage/Repositories/ConversationRepository.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaStorage/Conversations/ConversationQuery.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaStorage/Conversations/ConversationSnapshot.swift`
- Test: `apple/Packages/TaisaFoundation/Tests/TaisaStorageTests/ConversationQueryTests.swift`

**Interfaces:**
- Consumes: Task 2 records.
- Produces: `ConversationQuerying.loadIndex()`, `loadConversation(id:)`, `saveDraft(_:)`, `discardDraft(id:)`, `rename(id:title:)`, `delete(id:)`, and `applyCorrection(_:)`.

- [ ] **Step 1: Write failing query and atomicity tests**

```swift
@Test func indexSeparatesDraftsFromNewestCompletedConversations() async throws {
    let snapshot = try await query.loadIndex()
    #expect(snapshot.drafts.map(\.id) == [newestDraftID, olderDraftID])
    #expect(snapshot.conversations.map(\.id) == [newestConversationID, olderConversationID])
}

@Test func correctionSupersedesVisibleExchangeAtomically() async throws {
    try await repository.applyCorrection(correction, context: context)
    let snapshot = try await query.loadConversation(id: conversationID)
    #expect(snapshot.visibleMessages.map(\.body) == ["corrected", "regenerated"])
    #expect(snapshot.revisions.count == 1)
}
```

- [ ] **Step 2: Verify tests fail**

Run: `swift test --package-path apple/Packages/TaisaFoundation --filter ConversationQueryTests`
Expected: FAIL because the query and mutations are absent.

- [ ] **Step 3: Implement bounded snapshots and transactions**

```swift
public protocol ConversationQuerying: Sendable {
    func loadIndex() async throws -> ConversationIndexSnapshot
    func loadConversation(id: String) async throws -> ConversationSnapshot
}
```

Use GRDB reads inside `TaisaStorage`; Product never imports GRDB. Make delete/discard clean referenced draft audio through the existing cleanup contract and make correction persist revision, new visible response, and supersession in one transaction.

- [ ] **Step 4: Run focused and package tests**

Run: `swift test --package-path apple/Packages/TaisaFoundation --filter ConversationQueryTests && swift test --package-path apple/Packages/TaisaFoundation`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apple/Packages/TaisaFoundation/Sources/TaisaStorage apple/Packages/TaisaFoundation/Tests/TaisaStorageTests
git commit -m "feat: add native conversation query boundary"
```

### Task 4: Extend the coaching contract with one title suggestion

**Files:**
- Modify: `apple/Packages/TaisaFoundation/Sources/TaisaContracts/CoachingStreamEvent.swift`
- Modify: `shared/types/coaching.ts`
- Modify: `shared/coachingLimits.ts`
- Modify: `backend/src/schemas/coaching.ts`
- Modify: `backend/src/services/coaching/coachingGateway.ts`
- Modify: `backend/src/services/coaching/anthropicProvider.ts`
- Modify: `backend/src/services/coaching/openaiProvider.ts`
- Test: `apple/Packages/TaisaFoundation/Tests/TaisaContractsTests/CoachingStreamEventTests.swift`
- Test: `backend/src/__tests__/coaching.schema.test.ts`
- Test: `backend/src/__tests__/coachingGateway.test.ts`

**Interfaces:**
- Consumes: first-turn indicator and current title authority.
- Produces: `CoachingResponse.titleSuggestion: String?`, limited to the first successful response and ignored after manual rename.

- [ ] **Step 1: Write failing strict-contract tests**

```swift
@Test func completionDecodesOptionalTitleSuggestion() throws {
    let response = try decodeCompletedResponse(
        reply: "Reply",
        titleSuggestion: "Design review preparation"
    )
    #expect(response.titleSuggestion == "Design review preparation")
}
```

Add a backend test asserting the first-turn response can contain a trimmed short title while later turns omit it.

- [ ] **Step 2: Run tests and confirm failure**

Run: `swift test --package-path apple/Packages/TaisaFoundation --filter CoachingStreamEventTests && npm test --workspace=backend -- coachingGateway --runInBand`
Expected: FAIL on the missing contract field/schema.

- [ ] **Step 3: Implement optional title suggestion in the existing response**

```swift
public struct CoachingResponse: Equatable, Sendable, Decodable {
    public let requestId: UUID
    public let reply: String
    public let mode: CoachingResponseMode
    public let relevance: CoachingRelevance
    public let contextSufficiency: ContextSufficiency
    public let stance: CoachingStance?
    public let proposals: [JSONValue]
    public let usage: UsageReceipt
    public let titleSuggestion: String?
}
```

Update both provider strict-output schemas and the shared response type in lockstep with the backend Zod schema. Do not add a second provider call. Bound and normalize the title server-side, and keep absence valid for retries, fallback providers, and non-first turns.

- [ ] **Step 4: Run contract and backend tests**

Run: `swift test --package-path apple/Packages/TaisaFoundation --filter CoachingStreamEventTests && npm test --workspace=backend -- coachingGateway --runInBand && npm run build --workspace=backend`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apple/Packages/TaisaFoundation/Sources/TaisaContracts apple/Packages/TaisaFoundation/Tests/TaisaContractsTests shared backend/src
git commit -m "feat: return first-turn conversation title suggestions"
```

### Task 5: Unify voice and text conversation orchestration

**Files:**
- Modify: `apple/Packages/TaisaFoundation/Package.swift`
- Modify: `apple/Packages/TaisaFoundation/Sources/TaisaVoice/VoiceSessionCoordinator.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaConversations/ConversationCoordinator.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaConversations/ConversationState.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaConversations/ConversationClient.swift`
- Test: `apple/Packages/TaisaFoundation/Tests/TaisaVoiceTests/VoiceSessionCoordinatorTests.swift`
- Test: `apple/Packages/TaisaFoundation/Tests/TaisaConversationsTests/ConversationCoordinatorTests.swift`

**Interfaces:**
- Consumes: Task 3 snapshots/mutations, `VoiceSessionCoordinator`, and Task 4 coaching response.
- Produces: `ConversationCoordinator.send(_:)`, `saveDraft()`, `discardDraft()`, `beginReply(mode:)`, `switchToText()`, `retry()`, and `correctTranscript(messageID:text:)`.

- [ ] **Step 1: Write failing state and single-flight tests**

```swift
@Test func replyWaitsForExplicitIntent() async throws {
    let coordinator = makeCompletedConversationCoordinator()
    #expect(await coordinator.snapshot().composer == .waitingForReply)
    #expect(recorder.startCount == 0)
    try await coordinator.beginReply(mode: .voice)
    #expect(recorder.startCount == 1)
}

@Test func textSendUsesOneDurableRequestAcrossRetry() async throws {
    try await coordinator.send(.text("Prepare my review"))
    try await coordinator.retry()
    #expect(gateway.requestIDs.count == 2)
    #expect(Set(gateway.requestIDs).count == 1)
}
```

- [ ] **Step 2: Run and confirm failure**

Run: `swift test --package-path apple/Packages/TaisaFoundation --filter 'TaisaVoiceTests|TaisaConversationsTests'`
Expected: FAIL because `TaisaConversations` and explicit Reply orchestration do not exist.

- [ ] **Step 3: Implement the conversation-facing coordinator**

```swift
public enum ConversationInput: Sendable, Equatable { case voice, text(String) }
public enum ComposerState: Sendable, Equatable {
    case preparingVoice, recording, paused, typing(String), transcribing
    case coaching, waitingForReply, failure(ConversationFailure)
}
```

Delegate every voice state transition to `VoiceSessionCoordinator`. Text uses the same durable request/checkpoint semantics. Save/discard and correction call Task 3 atomic mutations. Apply title suggestion only when authority is not `.user`.

- [ ] **Step 4: Run orchestration and package tests**

Run: `swift test --package-path apple/Packages/TaisaFoundation --filter 'TaisaVoiceTests|TaisaConversationsTests' && swift test --package-path apple/Packages/TaisaFoundation`
Expected: PASS, including force-quit restore, ambiguous completion, rapid Send, conversation isolation, and audio cleanup.

- [ ] **Step 5: Commit**

```bash
git add apple/Packages/TaisaFoundation
git commit -m "feat: coordinate durable native conversations"
```

### Task 6: Build the native design-system foundation

**Files:**
- Modify: `apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem/ColorToken.swift`
- Modify: `apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem/SpacingToken.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem/ConversationEntryDock.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem/PrimaryNavigation.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem/VoiceComposerControls.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem/TextComposer.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem/ConversationStatusViews.swift`
- Modify: `docs/design-system.md`
- Test: `apple/Packages/TaisaFoundation/Tests/TaisaDesignSystemTests/ConversationComponentTests.swift`

**Interfaces:**
- Consumes: approved handoff component states.
- Produces: business-free typed SwiftUI components and semantic tokens used by Tasks 7–9.

- [ ] **Step 1: Write failing component-contract and token tests**

```swift
@Test func dockExposesDistinctVoiceAndKeyboardActions() {
    let contract = ConversationEntryDock.Contract.preview
    #expect(contract.voiceAccessibilityLabel == "Talk to Taisa, starts recording")
    #expect(contract.keyboardAccessibilityLabel == "Talk to Taisa with keyboard")
}
```

Add token tests for destructive/warning colors, raised surface, composer radius, and reduced-transparency fallback.

- [ ] **Step 2: Run and confirm failure**

Run: `swift test --package-path apple/Packages/TaisaFoundation --filter TaisaDesignSystemTests`
Expected: FAIL because the components/tokens are absent.

- [ ] **Step 3: Implement presentational components and previews**

Components accept values and callbacks only; they contain no repository, recorder, navigation, or gateway logic. Use native `Button`, `TextEditor`, focus, materials, and accessibility APIs under typed Taisa tokens.

- [ ] **Step 4: Verify design-system tests and documentation**

Run: `swift test --package-path apple/Packages/TaisaFoundation --filter TaisaDesignSystemTests && npm run verify:native-design-system`
Expected: PASS with no unapproved raw visual values.

- [ ] **Step 5: Commit**

```bash
git add apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem apple/Packages/TaisaFoundation/Tests/TaisaDesignSystemTests docs/design-system.md
git commit -m "feat(ds): add native conversation surfaces"
```

### Task 7: Add the primary app shell and global conversation entry

**Files:**
- Modify: `apple/TaisaApp/App/AppRootView.swift`
- Modify: `apple/TaisaApp/App/AppRuntime.swift`
- Create: `apple/TaisaApp/AppShell/PrimaryAppShell.swift`
- Create: `apple/TaisaApp/AppShell/PrimaryDestination.swift`
- Modify: `apple/TaisaApp/Home/HomeView.swift`
- Test: `apple/TaisaUnitTests/PrimaryAppShellTests.swift`
- Test: `apple/TaisaUITests/TaisaLaunchTests.swift`

**Interfaces:**
- Consumes: Task 6 dock/navigation and Task 5 conversation client factory.
- Produces: Home/Conversations/You routing plus new voice/text presentation intents.

- [ ] **Step 1: Write failing shell tests**

```swift
@Test func globalDockAppearsOnEveryPrimaryDestinationButNotInsideConversation() {
    let model = PrimaryAppShellModel.preview
    for destination in PrimaryDestination.allCases {
        model.select(destination)
        #expect(model.showsConversationDock)
    }
    model.presentNewConversation(.voice)
    #expect(!model.showsConversationDock)
}
```

- [ ] **Step 2: Run and confirm failure**

Run: `xcodebuild test -quiet -project apple/Taisa.xcodeproj -scheme Taisa-Dev -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TaisaUnitTests/PrimaryAppShellTests`
Expected: FAIL because the shell does not exist.

- [ ] **Step 3: Implement route-authoritative shell**

Use one selected destination, one optional conversation route, and one entry intent (`voice` or `text`). Consume the automatic voice-start intent once; subsequent renders cannot reopen the microphone.

- [ ] **Step 4: Run shell and launch tests**

Run: `npm run generate:native-apple && xcodebuild test -quiet -project apple/Taisa.xcodeproj -scheme Taisa-Dev -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TaisaUnitTests/PrimaryAppShellTests -only-testing:TaisaUITests/TaisaLaunchTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apple/TaisaApp apple/TaisaUnitTests apple/TaisaUITests apple/project.yml
git commit -m "feat: add native primary navigation and conversation entry"
```

### Task 8: Build Conversations history and draft management

**Files:**
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaConversations/ConversationsModel.swift`
- Create: `apple/TaisaApp/Conversations/ConversationsView.swift`
- Create: `apple/TaisaApp/Conversations/DraftRow.swift`
- Create: `apple/TaisaApp/Conversations/ConversationHistoryRow.swift`
- Test: `apple/Packages/TaisaFoundation/Tests/TaisaConversationsTests/ConversationsModelTests.swift`
- Test: `apple/TaisaUnitTests/ConversationsViewContractTests.swift`

**Interfaces:**
- Consumes: Task 3 index query/mutations and Task 7 routes.
- Produces: Drafts-first list with resume, discard, open, rename, and delete intents.

- [ ] **Step 1: Write failing model and view-contract tests**

```swift
@Test func draftsRemainSeparateAndNewestFirst() async {
    let model = ConversationsModel(client: fixtureClient)
    await model.load()
    #expect(model.snapshot.drafts.map(\.id) == fixtureClient.newestFirstDraftIDs)
    #expect(model.snapshot.conversations.map(\.id) == fixtureClient.newestFirstConversationIDs)
}
```

Assert identifiers for root, drafts, history, empty, retry, recovery, resume, rename, and delete confirmation.

- [ ] **Step 2: Run and confirm failure**

Run: `swift test --package-path apple/Packages/TaisaFoundation --filter ConversationsModelTests && xcodebuild test -quiet -project apple/Taisa.xcodeproj -scheme Taisa-Dev -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TaisaUnitTests/ConversationsViewContractTests`
Expected: FAIL.

- [ ] **Step 3: Implement deterministic list states and native actions**

Use `List`, `Section`, `swipeActions`, `Menu`, and `confirmationDialog`. Keep the global dock as the only new-conversation action. Refresh local state only; never call AI from load/open.

- [ ] **Step 4: Run model and view tests**

Run: `swift test --package-path apple/Packages/TaisaFoundation --filter ConversationsModelTests && xcodebuild test -quiet -project apple/Taisa.xcodeproj -scheme Taisa-Dev -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TaisaUnitTests/ConversationsViewContractTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apple/Packages/TaisaFoundation/Sources/TaisaConversations apple/Packages/TaisaFoundation/Tests/TaisaConversationsTests apple/TaisaApp/Conversations apple/TaisaUnitTests
git commit -m "feat: add native conversation history and drafts"
```

### Task 9: Build the production conversation screen

**Files:**
- Create: `apple/TaisaApp/Conversation/ConversationView.swift`
- Create: `apple/TaisaApp/Conversation/ConversationViewModel.swift`
- Create: `apple/TaisaApp/Conversation/ConversationTimeline.swift`
- Create: `apple/TaisaApp/Conversation/TranscriptCorrectionView.swift`
- Test: `apple/TaisaUnitTests/ConversationViewModelTests.swift`
- Test: `apple/TaisaUnitTests/ConversationViewContractTests.swift`
- Test: `apple/TaisaUITests/ConversationFlowTests.swift`

**Interfaces:**
- Consumes: Task 5 coordinator, Task 6 components, Task 7 route intent.
- Produces: new, draft, and historical conversation UI with exact dismissal and correction behavior.

- [ ] **Step 1: Write failing interaction tests**

```swift
@Test func keyboardReplacementRequiresDiscardAndCancelRestoresPause() async {
    let model = makeModel(state: .paused)
    model.requestKeyboard()
    #expect(model.confirmation == .discardVoiceForKeyboard(returnTo: .paused))
    model.cancelConfirmation()
    #expect(model.composer == .paused)
}

@Test func closeWithInputOffersSaveDiscardCancel() {
    let model = makeModel(state: .typing("keep this"))
    model.requestClose()
    #expect(model.confirmation == .saveDiscardOrCancel)
}
```

Cover rapid Send, waiting-for-Reply, empty close, saved/recovered draft resume, permission denial, retry/save/discard failures, title authority, conversation isolation, and correction regeneration.

- [ ] **Step 2: Run and confirm failure**

Run: `xcodebuild test -quiet -project apple/Taisa.xcodeproj -scheme Taisa-Dev -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TaisaUnitTests/ConversationViewModelTests -only-testing:TaisaUnitTests/ConversationViewContractTests`
Expected: FAIL.

- [ ] **Step 3: Implement the view model and SwiftUI composition**

Keep the view declarative. `ConversationViewModel` serializes intents into Task 5, owns confirmation presentation, and publishes snapshots. Use native dismissal interception so close button and supported interactive dismissal share the same save/discard decision.

- [ ] **Step 4: Run unit and UI flows**

Run: `npm run generate:native-apple && xcodebuild test -quiet -project apple/Taisa.xcodeproj -scheme Taisa-Dev -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TaisaUnitTests/ConversationViewModelTests -only-testing:TaisaUnitTests/ConversationViewContractTests -only-testing:TaisaUITests/ConversationFlowTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apple/TaisaApp/Conversation apple/TaisaUnitTests apple/TaisaUITests apple/project.yml
git commit -m "feat: build native conversation experience"
```

### Task 10: Add deterministic previews and end-to-end recovery verification

**Files:**
- Create: `apple/TaisaPreview/ConversationScenarios.swift`
- Modify: `apple/TaisaPreview/PreviewRootView.swift`
- Create: `apple/TaisaPreviewUITests/ConversationPreviewTests.swift`
- Modify: `docs/design-system.md`
- Create: `docs/features/native-conversation-experience-qa-notes.md`
- Modify: `docs/features/native-conversation-experience-work-map.md`

**Interfaces:**
- Consumes: all completed Platform and Product slices.
- Produces: inspectable fixtures, integration evidence, QA checklist, and review-ready progress state.

- [ ] **Step 1: Add failing preview coverage for every required state**

Define fixtures for empty list, multiple drafts, recovered draft, completed history, recording, paused, typing, transcribing, coaching, waiting for Reply, permission denied, retryable transcription, retryable coaching, correction, Accessibility XXXL, and iPad width. Preview transport remains network-denied.

- [ ] **Step 2: Run preview and package tests**

Run: `npm run generate:native-apple && swift test --package-path apple/Packages/TaisaFoundation && xcodebuild test -quiet -project apple/Taisa.xcodeproj -scheme Taisa-Preview -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -only-testing:TaisaPreviewUITests/ConversationPreviewTests`
Expected before fixtures: FAIL. Expected after implementation: PASS with zero network access.

- [ ] **Step 3: Run the complete native and backend verification matrix**

```bash
npm test --workspace=backend -- --runInBand
npm run build --workspace=backend
npm run verify:native-apple:all
bash scripts/verify-workflow.sh
bash scripts/verify-doc-freshness.sh docs/features/native-conversation-experience-work-map.md docs/features/native-conversation-experience.md docs/features/native-conversation-experience-design-handoff.md docs/superpowers/plans/2026-10-07-native-conversation-experience.md
```

Expected: all checks pass. Missing signed-device infrastructure is recorded as an unresolved QA requirement, never as a pass.

- [ ] **Step 4: Record QA evidence and update progress**

The QA notes must name the exact commit, simulator/device OS versions, permission-denied result, background/foreground result, interruption result, force-quit recovery result, offline retry result, duplicate-action result, cleanup evidence, Dynamic Type, VoiceOver, reduced motion, and iPad result.

- [ ] **Step 5: Commit**

```bash
git add apple/TaisaPreview apple/TaisaPreviewUITests docs/design-system.md docs/features/native-conversation-experience-qa-notes.md docs/features/native-conversation-experience-work-map.md
git commit -m "test: verify native conversation experience"
```

## Review and Ship handoff

After Task 10, invoke `superpowers:requesting-code-review` and `superpowers:verification-before-completion`. Resolve every blocking finding. For device QA, commit the exact verified revision, integrate that commit into `preview/taisa`, push `origin/preview/taisa`, and confirm the preview runtime serves it before asking Baah to test. Ship remains a separate Baah approval gate.
