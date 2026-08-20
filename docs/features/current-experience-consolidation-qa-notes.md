# Current experience consolidation — device QA notes

## 2026-08-18 — navigation correction

The review build exposed the obsolete five-destination top navigation. Baah approved returning the work to Build and implementing Figma node `409:4497` as the app shell navigation:

- floating 240×60 translucent iOS material at the bottom;
- Home, Chats, and Account destinations only;
- existing Navii profile identity retained for Account;
- 104×56 lime record button centered 12px above the navigation;
- Figma bottom fade, border, fill, radii, typography, and shadow values.

Next gate: managed-device QA of layout, glass rendering, safe-area behavior, navigation, and record entry.

Code verification: 50 Jest suites / 438 tests passed, TypeScript passed, and the design-system catalog verifier passed. Native glass and final optical alignment remain device-QA items.

## 2026-08-19 — native glass registration failure

The rebuilt iPhone binary compiled and linked `ExpoGlassEffect`, but Expo's runtime module registry still reported `Cannot find native module 'ExpoGlassEffect'`. The navigation availability boundary must catch that runtime failure and use the documented material-blur fallback instead of preventing the app shell from loading.

Correction verified in code: the availability boundary now converts a missing native module into the material-blur fallback; 50 Jest suites / 439 tests, TypeScript, and the design-system verifier pass. Baah device retry remains the visual QA gate.

## 2026-08-19 — bottom navigation visual mismatch

Device screenshot showed the 240×60 fallback material without its 32px clipping, producing an opaque rectangular sheet, and the Account label below the icon row. Root causes: critical geometry was passed as `className` to third-party `BlurView`, which does not reliably consume NativeWind styling, and active flex sizing was applied inside the animated item wrapper. Correction uses explicit native geometry on the material surface and a fixed 48/124/48 row model inside the 240px capsule.

Correction loaded on the connected iPhone. Verification: 50 Jest suites / 440 tests, TypeScript, and the design-system verifier pass. Baah visual retry remains the gate.

## 2026-08-19 — Figma navigation component replacement

Figma node `454:738` defines state-dependent navigation geometry: Home and Chats states are 240×60 with 108px active items; Me is 220×60 with an 88px active item; inactive items are 56×48. Baah explicitly changed the active fill to `rgba(15,16,16,0.06)` for every state. The existing Navii avatar remains the Me identity. The updated component was loaded on the connected iPhone; 50 Jest suites / 441 tests, TypeScript, and the design-system verifier pass. Baah visual QA remains the gate.

## 2026-08-19 — persistent navigation motion overlap

Paired-iPhone QA showed duplicate selected content during travel, delayed shell feedback, a mid-transition pause, and an invisible moving surface. The implementation rendered stable, outgoing, and incoming content simultaneously and advanced label, width, and position on independent 180/220/320ms phases. A transparent child inside the outer glass also had no distinct optical surface.

Correction removes the outgoing selected-content layer entirely. One persistent icon-label capsule now starts on touch-down, before routing; X, capsule width, and shell width share one interruptible 280ms spring; the shell reaches the original uniform 1.12 over 90ms without a second capsule scale; and travel uses the Figma 4% white surface and 4% dark border without nesting native glass. Automated verification passes, but this correction remains **device-QA failed / awaiting paired-iPhone recheck** until Baah confirms the visible result.

Follow-up device video showed the fixed inactive icon centers crossing the selected capsule and the incoming label scaling around its own center. Inactive destinations now animate to state-specific safe positions on the capsule spring; both origin and destination stable icons remain hidden until the handoff settles. The incoming label uses an icon-facing left transform origin, scaling and easing outward from the icon over 160ms.

The next device review exposed a remaining sequential pause: the capsule completed before the 320ms shell-size reset began. Shell feedback now peaks at 1.12 in 90ms and immediately returns over 220ms while capsule travel is still running, aligning the two endings instead of chaining them.

Frame-by-frame review of the 13:35 recording showed the deeper failure: capsule-owned content switched identity at touch-down, the origin icon was deliberately hidden, and destination frames moved independently enough to read as tabs exchanging places. The selected capsule is now surface-only. Home, Chats, and Me remain continuously mounted above it; each tab owns its icon, animated frame, and clipped label reveal, so icons shift to make room without vanishing or changing identity.

Final polish replaces the white-on-white sheen with a neutral hairline/shadow clear-glass base, animates the 6% grey as a separate stale-safe overlay, coordinates the 240↔220 shell width with capsule motion, and permits only the old label—not a second icon or selected capsule—to overlap during handoff. Reduced Motion uses one 180ms label/fill crossfade with no spatial or scale movement. Paired-iPhone recheck remains required.

## 2026-08-20 tap versus drag transition

- Tapping any main navigation item must use the existing direct page crossfade, including adjacent destinations.
- Horizontal page travel is reserved exclusively for an active drag, where the scene remains attached to the finger.
- The navigation capsule may continue to settle to the tapped destination while page content crossfades.
- Tap-driven page commits must not play a selection haptic; the tactile pulse makes the otherwise smooth capsule settlement feel like a sharp snap.

Clean-Metro iOS QA then reproduced a Fabric mount crash in Reanimated 4.1.1 while `useAnimatedStyle` mutated a frozen hook ref. `BottomNavBar` no longer imports or mounts Reanimated: React Native Animated owns shell scale/width, capsule X/width, fill opacity, and content handoff, with native-driver use limited to scale/opacity/translation and layout width animations explicitly JS-driven. A source guard blocks the crashing hooks from returning. Paired-iPhone recheck remains required.

## 2026-08-20 shadow clipping, tap motion, and coaching failure

- The conversation morph shell kept `overflow: hidden` after its rounded transition reached the full-screen state, clipping elevation on the header control, recording controls, and keyboard composer. Clipping now applies only while the shell is rounded; settled content permits shadow bleed without changing component geometry.
- Tapped navigation now advances the same continuous progress consumed by the swipe-driven capsule, using an interruptible non-bouncy spring. Page content retains the approved tap crossfade and does not travel through intermediate pages.
- Live diagnostics confirmed voice transcription completed before coaching failed. The configured Anthropic account returned HTTP 400 because its credit balance was too low. The completed transcript now remains visible with a coaching-specific failure state and retry path; restoring provider service still requires Anthropic credits or a separately approved provider change.
