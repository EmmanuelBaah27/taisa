# SwiftUI Native Rebuild Design

**Date:** 2026-10-02
**Status:** Draft for Baah review
**Tier:** Full
**Track:** Platform + Product
**Scope:** `docs/features/swiftui-native-rebuild.md`

## Outcome

Taisa ships a native SwiftUI client for iPhone and iPad, targeting iOS/iPadOS 17 or later, while retaining the existing stateless Node/Express gateway. The native client reaches behavioral and visual parity with one reconciled and frozen React Native preview baseline before any redesign begins.

The React Native app remains intact beside the native target as the comparison oracle and recovery reference. Native work advances in independently verifiable vertical slices; a slice is complete only after automated checks, side-by-side parity review, and applicable physical-device QA pass.

## Approved boundaries

- Rebuild the Apple client only; retain the existing backend.
- Support iPhone and iPad on iOS/iPadOS 17 or later.
- Match the canonical preview before redesigning or adding features.
- Freeze React Native product work after selecting the baseline; mirror only critical fixes.
- Start the native client with a new local store; do not migrate React Native device data.
- Preserve the local-first privacy model and accepted post-Send voice behavior.
- Do not remove the React Native implementation until native Ship approval.

## Baseline selection and freeze

The preview revision observed during scoping was `719180012de745e3b507ed93eadbe7d8a951331c`, but it is not automatically the permanent parity baseline. `preview/taisa` is ahead of `main`, several active worktrees contain approved or unmerged behavior, and the documentation checkout has unrelated uncommitted work.

Before native implementation begins:

1. Inventory every active mobile worktree: branch, HEAD, upstream, cleanliness, unique commits, and user-owned uncommitted files.
2. Classify each difference as approved baseline behavior, critical correction, unfinished work, or excluded future work.
3. Reconcile approved behavior into the canonical preview architecture without deleting source branches.
4. Run the existing backend, shared, mobile, design-system, workflow, and device checks.
5. Record the exact verified React Native commit, fixture seed/version, backend contract revision, and signed reference build.
6. Freeze ordinary React Native feature development.

After the freeze, every critical React Native correction receives a parity-ledger entry containing the defect, baseline impact, React Native commit, SwiftUI owner/slice, regression evidence, and resolution. New product ideas wait until parity Ship.

## Repository and target structure

Keep the current monorepo and backend/shared packages. Add a native Apple application as a sibling of `mobile/`, with one Xcode project/workspace and focused target groups or Swift packages for independently testable responsibilities.

```text
taisa/
├── apple/                    Native iOS/iPadOS application
│   ├── TaisaApp/             App entry, composition root, scenes, routing
│   ├── DesignSystem/         Tokens, typography, icons, surfaces, previews
│   ├── Core/                 Clock, IDs, logging, feature flags, errors
│   ├── Networking/           URLSession transport and Codable contracts
│   ├── Persistence/          Encrypted SQLite, migrations, repositories
│   ├── Domain/               Pure policies and state transitions
│   ├── Features/             Onboarding, Home, Chats, Coaching, Me
│   ├── DeviceServices/       Audio, notifications, Keychain, biometrics, files
│   ├── Resources/            Asset catalogs, fonts, shaders, localization
│   ├── ComponentCatalog/     Development-only preview/catalog host
│   └── Tests/                Unit, contract, snapshot, UI, integration fixtures
├── mobile/                   Frozen React Native parity oracle
├── backend/                  Existing Node/Express gateway
└── shared/                   Existing TypeScript source contracts
```

Feature views do not issue SQL or raw network calls. Design-system components contain no business logic. Domain policies do not import SwiftUI.

## Application architecture

The application composition root constructs protocol-backed services and injects them into feature models. SwiftUI views render state and emit user intents. `@Observable` feature models coordinate use cases; domain policies remain pure value transformations; repositories own durable reads/writes; device-service adapters own Apple frameworks.

```text
SwiftUI view
  → feature model intent
    → domain/use-case policy
      → repository or device-service protocol
        → encrypted SQLite / URLSession / Apple framework
    ← typed result or domain error
  ← explicit render state
```

Navigation uses explicit typed routes with `NavigationStack`, tabs, sheets, and full-screen presentation. Route state, not animation state, is authoritative. Custom transitions may decorate a route change but cannot own data loading or leave a blocking overlay after cancellation.

## Data ownership and persistence

The SwiftUI client starts clean and does not read the React Native database or Keychain. This removes legacy data conversion from the release gate, but it does not weaken native recovery requirements.

Use an encrypted SQLite store behind typed repositories rather than SwiftData. The domain needs explicit schema migrations, SQLCipher behavior, foreign-key and integrity checks, full-text search, transactional mutation receipts, deterministic export/restore, and precise failure recovery. The new schema may simplify legacy compatibility details, but it must represent every frozen-baseline behavior and preserve the canonical local-first entities and governance rules.

Store initialization is fail-closed: obtain or create the device-only Keychain key, open the encrypted store, apply ordered transactional migrations, verify cipher/schema/foreign keys/integrity, and publish repositories only after success. Validation failure presents a recoverable startup error without destructive recreation.

Export and restore remain native-client capabilities. Restores stage and validate a candidate before promotion, retain rollback state through successful reopen, and never allow archive-owned schema to replace trusted app migrations.

The production target retains `com.taisa.app`. Parallel development/parity targets use distinct bundle identifiers and containers. Cutover documentation states that preview/test history does not carry forward. Obsolete React Native app-container cleanup must be bounded, proven safe, and must never delete the new native store.

## Backend contracts and networking

The backend remains the authority for transient coaching/transcription orchestration, credentials, validation, provider fallback, and content-free cost accounting. The native client remains the readable-data authority.

Networking uses `URLSession`, `async/await`, and explicit `Codable` types. Contract fixtures are generated from or checked against the existing TypeScript runtime schemas. Date, identifier, enum, optional-field, unknown-field, payload-limit, streaming-frame, error-envelope, and cancellation behavior receive cross-language tests.

The client preserves installation identity in `x-user-id`, bounded coaching context, explicit Send, typed NDJSON post-Send transcription streaming, clear/uncertain/no-speech outcomes, governed proposals, content-free errors/receipts, cancellation, and idempotent local reconciliation. No provider key or prompt logic enters the app. No client retry may accidentally create a second paid coaching request.

## Native platform mapping

| React Native capability | Native owner |
|---|---|
| Expo Router | Typed SwiftUI navigation and presentation routes |
| Zustand | `@Observable` feature models and injected use cases |
| Expo SQLite / SQLCipher | Native encrypted SQLite adapter and typed repositories |
| Expo SecureStore | Keychain service |
| Expo Local Authentication | `LocalAuthentication` plus root privacy shielding |
| Axios | `URLSession` transport |
| Expo AV / file system | `AVAudioSession`, recorder/audio engine, and scoped file service |
| Expo Notifications | `UNUserNotificationCenter` |
| Reanimated / Gesture Handler | SwiftUI gestures and transactions; Core Animation where justified |
| NativeWind | Generated semantic Swift tokens and Asset Catalog values |
| Storybook | SwiftUI previews plus a development-only component catalog |
| Jest | Swift Testing/XCTest, snapshot tests, contract fixtures, and XCUITest |

## Voice and audio lifecycle

Voice is a dedicated foundation slice because simulator success cannot prove device behavior. The recorder owns permission, audio-session category/mode, metering, interruption, route change, backgrounding, cancellation, file lifecycle, and recovery as one state machine.

Audio remains local before Send. Send begins streamed transcription. Provisional deltas are transient. A clear terminal result atomically creates the submitted message and begins coaching; an uncertain result becomes an editable private draft; no-speech creates no user message and starts no coaching request.

The implementation covers denied/revoked permission, recorder acquisition races, calls/Siri, Bluetooth and headphone route changes, silence/noise, short/long recordings, deactivation, network loss after Send, retry, abandonment, and cleanup. Close, keyboard, and cancel remain available during recoverable acquisition states.

## Design system and resources

Port semantic intent, not React Native implementation details. Transform canonical tokens into typed Swift color, typography, spacing, radius, elevation, motion, and accessibility roles. Product views consume the native design-system layer; raw values require a narrow documented exception and automated verification.

- Raster app and splash artwork moves to asset catalogs with required scale and appearance variants.
- Bundled fonts are registered by exact family/PostScript name, licensing is verified, and typography supports Dynamic Type.
- Equivalent standard icons use SF Symbols by name; bespoke marks use vector PDF assets or Swift paths.
- Navii seed-to-avatar output requires a compatibility spike and golden fixtures. It may port the algorithm, package deterministic generated assets, or use another approved local representation, but may not silently change identity.
- Skia shaders require a Metal/native rendering spike with screenshot/performance evidence and reduced-motion/reduced-transparency fallbacks.
- Glass surfaces use native material APIs where supported and the existing semantic fallback otherwise. Interaction ownership, nesting, hit targets, disabled state, and accessibility remain explicit.
- Android and web-only resources stay with React Native.

SwiftUI previews cover meaningful component states, long copy, accessibility sizes, reduced motion, increased contrast, and reduced transparency. Native-only behaviors are verified in real screens on device.

## Migration slices

1. **Foundation:** Xcode project, CI, configuration, tokens, fonts, component catalog, contract harness, test utilities, and signed development distribution.
2. **Local platform:** encrypted SQLite, migrations, repositories, Keychain, file lifecycle, export/restore, installation identity, and privacy guard.
3. **Onboarding and shell:** clean-start initialization, onboarding, typed navigation, root app lock/privacy shield, and iPhone/iPad shell.
4. **Home:** local selectors, readiness/attention policies, work/governance operations, notifications, and presentation.
5. **Chats:** history repositories, list states, conversation resume, search/presentation utilities, and thread navigation.
6. **Text coaching:** composer, context, gateway lifecycle, caching, feedback, proposals, conflicts, and recovery.
7. **Voice coaching:** recording, post-Send streaming, uncertain/no-speech handling, haptics, cleanup, and keyboard transitions.
8. **Me and recovery:** profile/settings, notifications, app lock, privacy, export, restore, and confirmations.
9. **Motion and identity parity:** coordinated tabs, chat card transitions, glass, Navii, recording glow, and shaders.
10. **Cutover:** regression, performance/accessibility, clean-install rehearsal, signed TestFlight/device matrix, backend compatibility, and rollback.

Each slice produces runnable software and has one acceptance gate. A foundation spike that disproves an approach revises the design/plan before dependent slices start.

## Preview and verification lanes

**Component:** SwiftUI `#Preview` scenarios and a development catalog use deterministic non-production data.

**Flow:** Unit, repository, integration, snapshot, and XCUITest fixtures inject clocks, IDs, network frames, permissions, and databases to exercise failure paths.

**Parity:** Frozen React Native and SwiftUI builds use equivalent fixture data. Named states compare layout, copy, navigation, accessibility tree, gestures, animation intent, and recovery. Pixel snapshots inform review but do not replace interaction evidence.

**Device:** Signed builds run on representative iPhone and iPad hardware. Device QA is mandatory for audio, keyboard, haptics, notifications, biometrics, privacy, files, materials/shaders, performance, memory pressure, and lifecycle behavior.

Every build exposes Git revision, configuration, backend environment, database schema, and fixture version in development diagnostics. Baah is not asked to verify a build until that exact revision is signed, distributed, and confirmed on the device.

## Defect loop and severity gates

Every defect records exact build/device/OS/environment/fixture, reproduction and expectation, classification, owning slice/layer, regression test where practical, fix revision, verification evidence, and signed closure build.

The loop is reproduce → failing test where practical → owning-layer fix → narrow checks → full slice gate → signed exact build → device verification. A repeated symptom is not patched in several screens when one shared owner can fix it.

Severity one (data/privacy loss, unusable primary flow, security boundary failure) and severity two (major flow failure without acceptable workaround, repeated crash, incorrect coaching submission, broken recovery) block slice acceptance and cutover. Lesser parity differences require an explicit accepted-difference record.

## Error handling and observability

Feature models expose typed recoverable states rather than raw transport or SQLite errors. Retriable operations preserve private local work and use idempotent identities. Destructive recovery requires explicit confirmation and never runs automatically after unknown integrity failure.

Diagnostics remain content-free. They may include request IDs, state transitions, durations, sizes, schema versions, provider identifiers from receipts, and error categories. They must not include transcripts, prompts, messages, profile fields, keys, recordings, or decrypted exports.

## Accessibility and iPad behavior

Every action has an accessible label, role, state, and target. Critical flows verify Dynamic Type, VoiceOver order, Reduce Motion, Reduce Transparency, Increase Contrast, Bold Text, keyboard focus, and switch-control reachability.

iPad respects size class, safe areas, hardware keyboard, multitasking, rotation where allowed, and native popover/sheet conventions. It does not introduce a separate product information architecture.

## Cutover and rollback

Cutover requires all slices, backend contracts, the production-candidate iPhone/iPad matrix, blocking-defect closure, accepted-difference review, and explicit Ship approval.

The production bundle begins with a new native store; prior preview/test data is not migrated. A backend-compatible React Native release remains reproducible from the frozen commit during initial rollout. Rollback ships that verified compatible client or pauses distribution; it never rewrites shared Git history or deletes native data without explicit action.

Only after stable native release evidence may a separate cleanup scope remove React Native tooling, dependencies, CI, resources, branches, or worktrees.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| Moving parity target | Freeze an accounted, signed reference revision and ledger critical fixes. |
| Cross-language contract drift | TypeScript/Swift fixtures and backend integration tests. |
| Local-first regression | Encrypted-store, privacy, recovery, and content-free logging gates. |
| Simulator-only confidence | Early and repeated physical-device voice/device matrix. |
| Behavior loss hidden by visuals | Vertical slices, named parity states, interaction review, explicit differences. |
| Shader/glass/avatar mismatch | Early bounded spikes, golden references, approved accessible fallbacks. |
| Stretched-phone iPad UI | Size-class, keyboard, multitasking, and representative-device gates. |
| Premature cleanup | Separate post-Ship cleanup scope only. |

## Deliberate exclusions

No Android/web clients, backend rewrite, old-device-data import, redesign, new product capability, legacy-route retirement, or premature React Native deletion.

## Approval gates

1. **Scope:** this design and `docs/features/swiftui-native-rebuild.md`.
2. **Plan:** a later plan names exact files, interfaces, tests, commands, slice gates, and commits.
3. **Ship:** review, automated verification, exact-build device QA, accepted differences, and Baah's explicit approval.
