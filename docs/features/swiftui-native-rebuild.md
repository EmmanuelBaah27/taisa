# SwiftUI Native Rebuild

**Track:** Platform + Product
**Tier:** Full
**Status:** Swift canonical; React Native retained only in Git history and frozen evidence

---

## What is it?

Rebuild Taisa's iPhone and iPad client as a native SwiftUI application targeting iOS and iPadOS 17 or later. The native client uses accepted product decisions, portable behavior contracts, the existing Node/Express gateway, and the current React Native experience as non-blocking reference evidence.

The rebuild proceeds as complete vertical slices. Swift previews, fixtures, tests, and signed device builds are the implementation authority; React Native remains recoverable reference material only through Git history and frozen migration evidence.

## Why now?

Taisa's current Apple experience depends on a large cross-platform runtime for navigation, local persistence, audio, gestures, shaders, glass effects, and device services. A native client can give those Apple-specific behaviors clearer ownership and a more direct preview, testing, accessibility, and release path. Freezing the existing product first prevents the rewrite from becoming a moving target and separates parity work from future redesign.

## Acceptance criteria

- [ ] Accepted behavior is captured in platform-neutral contracts covering required screens, states, flows, copy, accessibility, API revision, fixtures, known defects, and deliberate platform adaptations.
- [ ] The native app runs on iPhone and iPad with a minimum deployment target of iOS/iPadOS 17 and implements those accepted contracts with native platform behavior.
- [ ] The native app continues to use the existing stateless coaching and transcription gateway contracts; the backend is not rewritten in Swift.
- [ ] New installs begin with a fresh native local store. The native app does not import React Native SQLite, Keychain, recording, settings, or history data.
- [ ] Taisa's local-first boundary remains intact: private capture stays on device until deliberate Send, readable user history remains device-authoritative, and the gateway stores no readable coaching content.
- [ ] Onboarding, app/privacy shell, Home, Chats, conversation history, text coaching, governed proposals, voice coaching, Me/settings, notifications, app lock, and export/restore complete end to end in the native app.
- [ ] Voice submission preserves the accepted post-Send streaming behavior for clear, uncertain, and no-speech outcomes, including interruption, retry, cleanup, and offline capture behavior.
- [ ] The native design system has typed semantic tokens and components, SwiftUI previews for meaningful states, and automated enforcement against unapproved raw visual values.
- [ ] Fonts, app artwork, bespoke icons, the Navii avatar, glass treatments, recording glow, and shader-driven effects have verified native resource strategies and approved fallbacks.
- [ ] Every migration slice passes unit/contract tests, deterministic flow tests, visual parity review, accessibility checks, and applicable physical-device QA before it is accepted.
- [ ] Every discovered defect follows the recorded reproduce-test-fix-regress-preview loop; unresolved severity-one or severity-two defects block the slice and cutover.
- [ ] Signed preview builds identify their exact Git revision, environment, and fixture version so device feedback can be traced to the code under review.
- [ ] Native work is delivered as a migration program with a separately reviewable and approvable implementation plan for each major slice; approval of one slice does not authorize later slices.
- [ ] Apple signing, entitlements, App Store Connect/TestFlight access, device registration, CI secrets, and development/production bundle identifiers are proven before Product migration begins.
- [ ] The production cutover passes clean-install, low-storage, permission-denied, offline, background/foreground, audio-interruption, notification, biometric, export/restore, and iPhone/iPad regression scenarios.
- [x] The React Native client is retired from the active tree after Baah's 2026-10-07 Swift-canonical decision; its frozen behavior remains recoverable from Git history and migration evidence.

## Platform dependencies

- [ ] Preserve current React Native worktrees and evidence without requiring further React Native implementation for native progress.
- [ ] Create platform-neutral behavior contracts and native deterministic fixtures alongside each accepted slice.
- [ ] Establish signed native development/TestFlight distribution and exact-build identification for iPhone and iPad QA.
- [ ] Prove the native encrypted SQLite, Keychain, audio, streaming transcription, notification, biometric/privacy, export/restore, shader, glass, and avatar approaches through bounded foundation work before dependent Product slices enter Build.
- [ ] Generate or validate Swift `Codable` contracts against the existing shared TypeScript schemas and backend fixtures.
- [ ] Prove the native preview channel and signing prerequisites before relying on physical-device QA.

## Out of scope

- Android or web replacement clients.
- Rewriting the Node/Express backend, provider adapters, prompts, or gateway in Swift.
- Importing or preserving React Native on-device data, Keychain entries, recordings, preferences, or user history.
- Redesigning screens, changing product information architecture, or adding new user-facing capability during parity migration.
- Localization, dark-mode redesign, macOS, visionOS, widgets, and new background-processing capability.
- Continuing ordinary React Native feature development after the baseline freeze.
- Retiring legacy backend routes unless separately scoped and approved.
- Deleting historical branches, worktrees, or migration evidence before their commits are accounted for.

## Closeout

To be completed during Review with the frozen baseline commit, native release commit, verification evidence, accepted parity differences, device matrix, and final React Native disposition.
