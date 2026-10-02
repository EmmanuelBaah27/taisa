# SwiftUI Native Rebuild

**Track:** Platform + Product
**Tier:** Full
**Status:** Scope agreed; design awaiting written-spec review

---

## What is it?

Rebuild Taisa's iPhone and iPad client as a native SwiftUI application targeting iOS and iPadOS 17 or later. The native client will preserve the behavior and visual language of one verified, frozen React Native preview baseline while continuing to use Taisa's existing Node/Express gateway and API contracts.

The rebuild will proceed as complete vertical slices beside the React Native client. React Native remains the parity oracle and rollback reference until the native application passes the full cutover gate.

## Why now?

Taisa's current Apple experience depends on a large cross-platform runtime for navigation, local persistence, audio, gestures, shaders, glass effects, and device services. A native client can give those Apple-specific behaviors clearer ownership and a more direct preview, testing, accessibility, and release path. Freezing the existing product first prevents the rewrite from becoming a moving target and separates parity work from future redesign.

## Acceptance criteria

- [ ] A verified React Native commit is named and frozen as the parity baseline only after all approved active work and unique preview changes are accounted for.
- [ ] The frozen baseline includes a versioned parity catalog covering required screens, states, flows, copy, accessibility behavior, API revision, fixture data, reference media, known defects, and explicit exclusions.
- [ ] The native app runs on iPhone and iPad with a minimum deployment target of iOS/iPadOS 17 and reproduces the frozen baseline's required screens, copy, states, navigation, accessibility, and interaction behavior without redesign.
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
- [ ] The React Native client is not retired or removed until the native Ship gate passes and its frozen behavior remains recoverable from Git.

## Platform dependencies

- [ ] Reconcile current active worktrees, unique commits, and the served `preview/taisa` revision into one verified parity baseline.
- [ ] Create and approve the parity catalog before writing Product-slice plans.
- [ ] Freeze React Native feature development after baseline selection; allow only critical fixes recorded in a parity ledger and mirrored in SwiftUI.
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
- Deleting current branches, worktrees, or the React Native implementation before all work is accounted for and native Ship is approved.

## Closeout

To be completed during Review with the frozen baseline commit, native release commit, verification evidence, accepted parity differences, device matrix, and final React Native disposition.
