# SwiftUI Functional Home

**Track:** Platform + Product  
**Tier:** Full  
**Status:** Design Approved — Plan

---

## What is it?

Deliver Taisa's first functional Product vertical slice in the native SwiftUI client: the production app shell and a Home destination backed by the encrypted native store. The slice replaces the foundation diagnostic screen as the ordinary app entry point and proves that shipped native infrastructure can support real Product UI.

This is a functionality-first build. It uses standard SwiftUI navigation, controls, lists, loading behavior, and accessibility with only minimal Taisa identity. The page is deliberately structured for later redesign without requiring its data flow, navigation contract, or state ownership to be rebuilt.

## Why now?

The native app foundation and encrypted local storage/recovery are already merged into `origin/main`. Product work can now begin, but the current repositories expose entity-by-ID CRUD rather than the ordered collection and summary reads Home requires. Completing one real vertical slice will close that platform gap, establish the native Product composition pattern, and let later pages move faster without prematurely designing a broad component library.

## Acceptance criteria

- [ ] Launching the ordinary native Taisa app opens a functional Home destination rather than the foundation diagnostics screen.
- [ ] Home reads its content from the encrypted native store through a Product-facing query boundary; production UI does not depend on fixtures or hard-coded sample content.
- [ ] A new empty store presents a clear native empty state with an available next action and no error-looking placeholders.
- [ ] When local data exists, Home presents recent conversations, active goals, and open actions in deterministic order and exposes stable navigation boundaries for their later full destinations.
- [ ] Loading, empty, populated, and recoverable failure states are distinguishable and testable without exposing private content in logs or diagnostics.
- [ ] A failed store read preserves the local database and offers a safe retry or recovery route; the app does not replace, reset, or silently ignore the store.
- [ ] The shell and Home remain usable on supported iPhone sizes, in an iPad window, with Dynamic Type, VoiceOver, increased contrast, Reduce Motion, and reduced transparency.
- [ ] Standard SwiftUI navigation and interactions supply the platform behavior. Temporary Product styling does not recreate the React Native UI or introduce custom interaction machinery.
- [ ] Page composition owns layout and placement; shared views remain small enough to be moved or replaced during the later page redesign.
- [ ] Only patterns proven reusable by this slice enter `TaisaDesignSystem`; implemented component contracts, previews, and tests are documented in the same change.
- [ ] The native target and package baseline are iOS/iPadOS 26 or later, built with the latest stable supported SDK.
- [ ] The current React Native client remains intact and usable; this slice does not trigger production cutover or import React Native on-device data.
- [ ] Automated tests cover the Home query contract and every visible state, and the exact signed candidate passes applicable iPhone and iPad device QA before Ship.

## Platform dependencies

- [x] Shipped Swift native app foundation, deterministic project generation, build identity, preview isolation, and signed-build evidence.
- [x] Merged encrypted native store, recovery-key flow, repositories, and atomic export/restore.
- [ ] Add the ordered collection and summary query contracts required by Home without exposing GRDB details to Product views.
- [ ] Reconcile the native rebuild documents with the approved iOS 26+, native-first, functionality-before-redesign direction before implementation planning.
- [ ] Keep voice-specific UI outside this slice until the native audio and conversation-streaming foundation completes its Ship gate.

## Out of scope

- Final Home visual design, bespoke motion, custom glass effects, or pixel parity with React Native.
- Building a comprehensive design-system component catalog before Product needs prove it.
- Voice recording, transcription, coaching-response streaming, or the final Conversation experience.
- Full Chats, Goals, Account, Settings, or onboarding journeys beyond navigation boundaries needed to keep Home actions honest.
- Activating CloudKit, completing automatic cross-device synchronization, or requiring paid Apple Developer capabilities.
- Importing React Native SQLite, Keychain, settings, recordings, or history into the native store.
- Retiring or deleting the React Native client, its worktrees, or its recoverable Git history.
- Bespoke iPad information architecture; the slice must remain adaptable and usable in an iPad window.

## Closeout

To be completed during Review with the accepted Home information contract, exact implementation revision, automated verification, signed-device evidence, documented temporary styling decisions, and the next Product-slice gate.
