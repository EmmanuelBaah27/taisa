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

Correction removes the outgoing selected-content layer entirely. One persistent icon-label capsule starts synchronously before routing; X and width share one 280ms spring; the shell reaches a uniform 1.12 over 90ms; and travel uses a clear sheen/highlight border without nesting native glass. Automated verification passes, but this correction remains **device-QA failed / awaiting paired-iPhone recheck** until Baah confirms the visible result.
