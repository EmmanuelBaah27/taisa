# Swift-First Native Rebuild Design

**Date:** 2026-10-03
**Status:** Draft for Baah review
**Tier:** Full
**Track:** Platform + Product
**Scope:** `docs/features/swiftui-native-rebuild.md`
**Supersedes when approved:** the React Native baseline-freeze and fixture-harness prerequisites

## Outcome

Taisa's primary Apple implementation will be rebuilt directly in Swift and SwiftUI for iPhone and iPad. Native development starts from the accepted product direction, local-first architecture, API contracts, design language, and useful evidence already present in the repository. It does not wait for a frozen or fully instrumented React Native parity build.

The current React Native application remains available as a reference for product behavior, copy, assets, and interaction intent. It is not the implementation authority, a pixel-perfect oracle, or a blocker for Swift work. Where React Native behavior conflicts with accepted product documentation, native platform conventions, accessibility, privacy, reliability, or an explicit Baah decision, the Swift implementation follows the stronger source and records the difference.

A future React Native client may be built from the finished native product's platform-neutral contracts and design specification. SwiftUI source itself is not expected to translate automatically.

## Approaches considered

### Selected: Swift-first with portable contracts

Build the Apple client natively now, retain React Native as non-blocking reference evidence, and make behavior, schemas, fixtures, copy, and semantic tokens portable. This puts effort into the product Baah prioritizes while preserving a credible path to another client later.

### Rejected: finish the React Native parity harness first

This offers the strongest before-and-after comparison, but spends substantial time improving a client that is no longer the priority. It also makes unfinished React Native behavior the migration gate even when native platform conventions or current product decisions should win.

### Rejected: introduce a cross-platform shared UI or domain runtime now

A new shared runtime could reduce some future duplication, but it would add another language, build system, and abstraction layer before the native product has stabilized. Platform-neutral contracts provide the useful portability now without constraining the Swift architecture around a hypothetical later port.

## Approved priorities

1. Ship an excellent native Apple experience before investing further in React Native parity infrastructure.
2. Support iPhone and iPad on iOS/iPadOS 17 or later.
3. Keep the existing Node/Express gateway and canonical TypeScript runtime schemas.
4. Preserve the local-first privacy boundary and accepted post-Send streaming transcription behavior.
5. Build deterministic Swift previews, fixtures, tests, and signed-device verification from the beginning.
6. Preserve React Native code and evidence without extending it solely to support the migration.
7. Capture product decisions in platform-neutral documents so a later React Native port is practical.

## Authority model

When sources disagree, use this order:

1. Baah's explicit, current product decision.
2. Accepted architecture and decision records.
3. Canonical API contracts and privacy/data rules.
4. Approved native design and accessibility requirements.
5. The current React Native experience as reference evidence.
6. Historical plans, screenshots, and unfinished branches.

Every meaningful divergence from React Native is classified as one of:

- **Intentional native decision** — approved behavior or platform adaptation.
- **Reference defect corrected** — the native app fixes a known React Native defect.
- **Deferred capability** — explicitly scheduled for a later native slice.
- **Regression** — required behavior was accidentally lost and blocks the owning slice.

The migration ledger records the source, decision, owner, and verification evidence. React Native does not need to be modified to mirror a native decision.

## Program decomposition

```text
Swift-First Native Program
├── 0. Native foundation
│   ├── Xcode project, schemes, signing, environments, and exact-build identity
│   ├── Swift package/module boundaries and CI
│   ├── Deterministic preview/fixture host
│   └── Contract, persistence, audio, and resource feasibility
├── 1. Shared native platform
│   ├── Encrypted local persistence, Keychain, export, and restore
│   ├── URLSession transport and TypeScript contract fixtures
│   ├── Privacy, lifecycle, notifications, and biometrics
│   └── Shared coaching-session engine
├── 2. Product vertical slices
│   ├── Onboarding and app shell
│   ├── Home
│   ├── Chats and conversation history
│   ├── Text coaching
│   ├── Voice coaching
│   └── Me, privacy, export, and recovery
├── 3. Native polish and platform adaptation
│   ├── iPad layout and keyboard behavior
│   ├── Motion, materials, Navii, glow, and shaders
│   └── Accessibility and performance closure
└── 4. Release and cutover
```

Each numbered stage receives its own implementation plan and approval. Foundation work must produce a runnable signed shell rather than a collection of disconnected spikes. Later slices may begin only when their concrete dependencies are verified.

## Repository structure

```text
taisa/
├── apple/
│   ├── Taisa.xcodeproj
│   ├── TaisaApp/              App entry, composition, scenes, navigation
│   ├── DesignSystem/          Semantic tokens and business-free components
│   ├── Core/                  Clock, identifiers, errors, diagnostics
│   ├── Domain/                Pure policies and state transitions
│   ├── Networking/            URLSession and Codable contracts
│   ├── Persistence/           Encrypted SQLite, migrations, repositories
│   ├── DeviceServices/        Audio, files, Keychain, biometrics, notifications
│   ├── Features/              Vertical product slices
│   ├── Resources/             Assets, fonts, shaders, localization scaffold
│   ├── PreviewCatalog/        Development-only fixtures and scenario browser
│   └── Tests/                 Unit, contract, snapshot, UI, integration fixtures
├── mobile/                    Existing React Native reference implementation
├── backend/                   Existing Node/Express gateway
├── shared/                    Canonical TypeScript runtime contracts
└── docs/product-contracts/    Platform-neutral behavior and design contracts
```

The native app is a committed Xcode project, not generated by Expo. It has its own development, fixture, and production schemes. Production cannot route to or bundle development fixture controls.

## Architecture

SwiftUI views render explicit state and emit user intents. `@Observable` feature models coordinate use cases. Pure domain policies own state transitions. Repositories own durable data. Protocol-backed adapters own networking and Apple frameworks.

```text
SwiftUI View
  → Feature Model
    → Domain Use Case
      → Repository / Device Service
        → SQLCipher / URLSession / Apple Framework
    ← Typed Result
  ← Explicit Render State
```

Views do not issue SQL or raw network requests. Domain modules do not import SwiftUI. Design-system modules contain no navigation, persistence, networking, or business rules.

## Native preview and fixture system

Swift development uses three complementary lanes:

- **Xcode previews:** focused component and screen states with deterministic clocks, identifiers, text sizes, color schemes, contrast, reduced motion, and reduced transparency.
- **Preview Catalog app/scheme:** full-screen and multi-step scenarios backed by synthetic, in-memory or temporary services. It supports errors, permissions, lifecycle events, slow responses, offline behavior, and iPhone/iPad layouts.
- **Tests and signed builds:** Swift Testing/XCTest, snapshot checks, XCUITest, and exact-build physical-device QA.

Fixtures are native-first and represent required product states whether or not React Native can reproduce them. They cannot use production accounts, storage, credentials, or readable user data. A deny-by-default transport prevents accidental external requests from the catalog.

## Product contracts for future ports

Portable behavior belongs in versioned documents and fixtures, not in SwiftUI implementation details. For every accepted slice, record:

- user intent, visible states, transitions, copy, and recovery behavior;
- accessibility roles, ordering, actions, and scalable-layout expectations;
- platform-neutral design tokens and semantic component roles;
- request/response schemas, streaming frames, identifiers, and error categories;
- deterministic fixture inputs and expected domain outcomes;
- deliberate Apple-only adaptations and the portable fallback expectation.

The canonical runtime API schemas remain TypeScript. Language-neutral JSON fixtures validate both backend handlers and Swift Codable types. A future React Native project consumes the same contracts and recreates the presentation for its runtime; it does not mechanically convert Swift source.

## Local-first data and privacy

The native client starts with a new encrypted store and does not import React Native SQLite, preferences, recordings, or Keychain content. SQLCipher-backed repositories, explicit transactional migrations, integrity checks, export, and staged restore remain foundation requirements.

Readable profile, conversation, transcript, goal, action, evidence, memory, and cached coaching content stay device-authoritative. Only deliberate Send transmits bounded context to the gateway. Logs and diagnostics remain content-free.

The first native production update initializes versioned native storage before touching legacy artifacts. Any legacy cleanup uses an audited allowlist, is idempotent, and is separately tested. Unknown files remain ignored rather than being deleted.

## Networking and coaching

The existing gateway remains responsible for transient provider orchestration, credentials, validation, fallback, and content-free cost accounting. Native networking uses URLSession, async/await, and explicit Codable contracts.

Text and voice submissions share one coaching-session engine that owns request identity, bounded context, cancellation, retry classification, response caching, proposals, receipts, and idempotent reconciliation. No retry may create an unintended second paid request.

Voice remains local before Send. Clear transcription creates the submitted message and coaching request; uncertain transcription becomes an editable private draft; no-speech creates no message and starts no coaching request.

## Design system, assets, and platform adaptation

The Swift design system ports semantic intent, not NativeWind implementation. Typed tokens cover color, typography, spacing, radius, elevation, motion, materials, and accessibility. Product views consume `apple/DesignSystem/`; raw visual values require a narrow documented exception and verification.

- Raster images move into asset catalogs with correct scales.
- Compatible vectors use single-scale PDF assets or Swift paths.
- Standard symbols use SF Symbols; bespoke icons remain owned assets.
- Font files require verified licensing, exact PostScript names, Dynamic Type mapping, and fallbacks.
- Navii requires deterministic seeds and golden reference fixtures.
- Glass and shaders use supported native APIs with accessible fallbacks for older OS versions, reduced motion, and reduced transparency.
- iPad uses adaptive layouts, keyboard navigation, multitasking, rotation where supported, and native popover/sheet conventions rather than a stretched phone layout.

Apple-specific behavior is allowed when it improves platform fit without changing the product's underlying intent. Each adaptation is recorded so a later React Native implementation can choose an equivalent fallback.

## Verification and defect loop

Every slice runs:

1. pure domain and model tests;
2. contract fixtures against canonical schemas;
3. repository or device-service integration tests;
4. deterministic preview and snapshot checks;
5. accessibility checks;
6. applicable XCUITest flows;
7. signed exact-build QA on representative iPhone and iPad hardware.

Every defect follows reproduce → failing test where practical → owning-layer fix → narrow verification → slice verification → signed build → device confirmation. Severity-one privacy/data failures and severity-two primary-flow failures block acceptance. Lower-severity visible differences require an explicit decision.

Signed QA records include Git revision, Xcode build number, bundle identifier, distribution version, backend environment, database schema, contract-fixture revision, and tested device/OS. Simulator and Xcode Preview evidence is useful but never substitutes for device-sensitive checks.

## Performance and release

Native budgets are measured directly rather than inherited from an unfinished React Native reference. Foundation establishes repeatable measurements for launch, memory, database open/migration/query time, list responsiveness, record readiness, transcript latency, coaching start, archive size, and interruption recovery.

Release proceeds through signed development builds, internal distribution, applicable TestFlight groups, and phased App Store rollout. Cutover requires clean-install, low-storage, offline, permission-denied, background/foreground, interruption, notification, biometric, export/restore, and iPhone/iPad regression evidence.

The React Native code remains recoverable from Git through initial native rollout. Removing it is a separate cleanup scope after stable native Ship evidence.

## Deliberate exclusions

- No Android, web, macOS, watchOS, or visionOS client in this program.
- No Swift backend rewrite.
- No automatic Swift-to-React-Native conversion.
- No migration of existing React Native on-device data.
- No requirement to finish or extend the React Native fixture harness.
- No deletion of React Native code, active worktrees, or unaccounted user work.
- No new product capability unless separately scoped and approved.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| Unclear behavior without a frozen RN oracle | Use authority order, platform-neutral contracts, deterministic native fixtures, and explicit decisions. |
| Swift implementation becomes impossible to port | Keep domain outcomes, schemas, tokens, copy, and state contracts platform-neutral. |
| Simulator-only confidence | Establish signed iPhone/iPad installation in Foundation and repeat device gates per slice. |
| Cross-language drift | Validate JSON fixtures against TypeScript schemas, backend handlers, and Swift decoders. |
| Native architecture overbuilt before value appears | Foundation ends in a runnable shell; subsequent work ships vertical slices. |
| Assets or effects do not map cleanly | Resolve fonts, Navii, materials, and shaders through bounded native feasibility work with approved fallbacks. |
| Legacy data is accidentally exposed or deleted | New versioned native store, audited cleanup allowlist, content-free diagnostics, and destructive-action tests. |

## Approval gates

1. **Replacement design:** Baah approves this written specification.
2. **Foundation plan:** exact files, modules, dependencies, tests, signing steps, and runnable-shell acceptance are approved before Swift code begins.
3. **Slice plans:** each later native stage or product slice receives its own approval.
4. **Ship:** automated verification, signed exact-build device QA, accepted differences, and explicit Baah approval.
