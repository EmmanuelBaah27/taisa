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
