# Design Handoff — SwiftUI Functional Home

**Scope doc:** `docs/features/swiftui-functional-home.md`  
**Design source:** Baah's approved native-first direction in conversation  
**Precision:** Directional. Functionality and native interaction fidelity are the sign-off target; final visual design is deferred.

---

## Layout intent

The ordinary app opens into a native SwiftUI shell with Home as the first functional destination. Home is a vertically scrolling content view that presents, in order:

1. a native navigation title and app-level recovery/settings access;
2. recent conversations;
3. active goals;
4. open actions.

Each section renders independently from one immutable Home snapshot. Empty sections explain that no matching local content exists. The whole page has explicit loading and recoverable failure states. No generated insight, coaching summary, recording control, promotional card, or decorative dashboard visualization is introduced in this slice.

The screen uses system spacing, margins, list behavior, navigation, materials, separators, focus, selection, and accessibility behavior. Temporary visual decisions remain deliberately quiet so the page can be redesigned later without changing its state model or query boundary.

## Component inventory

| Element | Verdict | SwiftUI / Taisa owner |
|---|---|---|
| App scene and lifecycle | Reuse | `TaisaApp` |
| Root navigation | Modify | Replace `FoundationRootView` as the production root with a small app-shell composition |
| Home navigation container | Reuse | SwiftUI `NavigationStack` |
| Home scrolling structure | Reuse | SwiftUI `List` or native sectioned scroll container, selected during implementation for best iOS 26 behavior |
| Navigation title and toolbar | Reuse | SwiftUI `.navigationTitle` and `.toolbar` |
| Section headings | Reuse | SwiftUI semantic text styles; do not require a new DS component |
| Conversation, goal, and action rows | New, feature-local | Small Home presentation views with native row semantics; do not promote to `TaisaDesignSystem` in this slice |
| Loading state | Reuse | SwiftUI `ProgressView` and redacted/native placeholder behavior where useful |
| Empty state | Reuse | SwiftUI `ContentUnavailableView` or equivalent native section message |
| Failure state | Reuse | SwiftUI native content-unavailable presentation with Retry and recovery access |
| Recovery access | Reuse | Existing `RecoveryView` and native navigation/presentation |
| Typography and color | Reuse narrowly | System semantic styles and colors by default; existing `TaisaText` only where its current contract improves consistency without fighting native behavior |
| Buttons | Reuse narrowly | Native `Button` by default; existing `TaisaButton` only for a genuinely Taisa-branded action |
| Product state model | New | `HomeModel` using Observation with explicit loading, content, empty, and failure states |
| Product query boundary | New | `HomeQuerying` plus immutable `HomeSnapshot` independent of SwiftUI and GRDB |
| Encrypted-store adapter | New | Storage-backed adapter that performs bounded deterministic reads from the shipped native store |

## Interaction and state contract

- Pull to refresh may rerun the local query if native `List` refresh behavior remains appropriate; refresh never implies network availability.
- Retry reruns only the failed local read and never resets or replaces storage.
- Recovery access opens the existing recovery flow without moving recovery logic into Home.
- Rows expose stable typed intents for future navigation. This slice does not invent incomplete detail screens solely to make rows appear interactive.
- Loading, refresh, and retry are single-flight operations. A superseded result cannot overwrite newer state.
- Section order is fixed, while rows are derived deterministically from local records.

## Temporary visual contract

- Use the iOS 26 system visual language and standard controls.
- Use the system tint plus the minimum existing Taisa semantic accent needed for identity.
- Do not recreate React Native cards, glass surfaces, custom navigation, or motion.
- Do not add a broad component catalog or speculative variants.
- Keep feature-local rows composable so the later page redesign can change hierarchy and placement without replacing the query or state contracts.

## Token gaps

None for this functional pass. System semantic styles, system spacing, and the existing minimal native tokens are sufficient. Any new raw visual value discovered during implementation is deferred unless required for accessibility or layout correctness.

## Platform implications

- Current repositories support entity-by-ID CRUD but not the ordered collection reads Home needs.
- Add bounded read APIs for recent conversations, active goals, and open actions, then compose them behind `HomeQuerying`.
- Reads must remain local, encrypted-store-backed, deterministic, cancellable, and independent of CloudKit availability.
- Product views must not import GRDB or issue SQL.

## Accessibility and adaptability

- Preserve Dynamic Type without truncating essential titles or hiding actions.
- Provide VoiceOver headings, meaningful row labels, predictable traversal, and non-colour state communication.
- Use native focus and keyboard behavior.
- Constrain readable content width where appropriate while allowing the shell to expand in an iPad window.
- Avoid phone-width constants or a bespoke iPad information architecture in this slice.

## Open questions

None blocking. Exact native container choice (`List` versus another system section container) is implementation latitude and is verified on iPhone and iPad before Ship.

## Ready for specification

The functionality-first design is understood. Architecture and verification can be specified without final visual mockups; later visual redesign remains a separate Product stage.
