# Current Experience Consolidation — QA

**Status:** Review + QA — awaiting Baah paired-iPhone device QA<br>
**Branch:** `feature/current-experience`<br>
**Runtime:** `/Users/emmanuelbaah/Documents/Beats/VibeCoding/Taisa/.worktrees/feature-current-experience/mobile`

## Start the review build

```bash
cd /Users/emmanuelbaah/Documents/Beats/VibeCoding/Taisa/.worktrees/feature-current-experience/mobile
npm install
npm start
```

Use the managed development build for native checks; Expo Go is not valid for SQLCipher, recording, or device-security evidence.

## Baah device checklist

- [ ] Active navigation content keeps its icon and label on one horizontal row (failed 2026-08-19: Chats stacked vertically on device).

### Persistent navigation capsule motion — 2026-08-19

- [ ] On touch-down, the entire glass pill scales uniformly to 1.12; the selected capsule does not compound that scale, and neither stretches or squashes.
- [ ] Pill-size restoration overlaps capsule travel so both settle together without a midpoint pause.
- [ ] Capsule is plain glass during travel and restores 6% grey only after settlement.
- [ ] Capsule visibly moves Home ↔ Chats ↔ Me while route content changes immediately.
- [ ] Destination label emerges from its icon with no duplicate outgoing icon or label.
- [ ] Inactive icons move to their state-specific positions and remain clear of the selected capsule throughout travel.
- [ ] Rapid retargeting redirects smoothly without grey flashes or scale reset.
- [ ] Reduced Motion removes spatial/scale motion and preserves short crossfades.

- [ ] Cold launch shows the current Chats experience after the existing onboarding/startup gates.
- [ ] Navigation says **Chats** (never **Logs**) and Inter typography matches the current design system.
- [ ] Chats groups conversations and opens the selected local conversation.
- [ ] Back and Reply preserve the same durable conversation identity.
- [ ] Text, voice, pause, resume, discard, transcription, retry, and submit states work.
- [ ] Offline/private local capture remains local until deliberate submission.
- [ ] Loading, empty, error, long-text, safe-area, keyboard, and accessibility-text cases remain usable.
- [ ] Native-only recording glow/refraction behavior works in its real app screen.

## Browser catalog

Run `npm run storybook:web`, open the printed local URL, and confirm the component catalog and controls render. Ordinary Taisa navigation must expose no design-system gallery route. Browser verification on 2026-08-16 rendered all 19 catalog modules with no console errors.

## Automated evidence — 2026-08-16

- `npm run verify:workflow` — passed.
- Backend Jest — 20 suites, 242 tests passed.
- Backend TypeScript build — passed.
- Mobile Jest — 49 suites, 435 tests passed.
- Mobile TypeScript — passed.
- Design-system verifier — passed, 19 modules.
- Browser Storybook — story tree and controls rendered with no console errors.
- Reconciliation audit, destructive-diff review, and whitespace check — passed; no files deleted.

The dependency audit has 37 open findings (2 low, 17 moderate, 17 high, 1 critical). They are recorded for deliberate dependency hygiene; no broad automatic upgrade was applied during this UI consolidation.

## Navigation correction — 2026-08-19

Device QA showed the active Chats icon and label stacked vertically. The active item now owns an explicit horizontal content row rather than relying on the pressable's dynamic layout style. The approved 6% black active fill and Figma state widths remain unchanged.

- Mobile Jest — 50 suites, 441 tests passed.
- Mobile TypeScript — passed.
- Design-system verifier — passed, 19 modules.
- Taisa relaunched on the paired iPhone against the running LAN bundle; visual re-QA remains pending.

> **BTS:** The selected icon and label are one visual unit. Giving that unit its own row container makes the Figma relationship structural, so pressed-state styling cannot accidentally change its axis on iOS.

## Persistent navigation capsule motion — automated evidence — 2026-08-19

- Mobile Jest — 52 suites, 456 tests passed.
- Mobile TypeScript — passed.
- Design-system verifier — passed, 22 catalog modules.
- Workflow verifier, current-experience audit, and whitespace check — passed.
- Metro was listening on port 8081 (`http://192.168.8.169:8081`, packager status running).
- Taisa (`com.taisa.app`) launched successfully on the paired iPhone 15 Pro (`CB2D8D19-B858-55E5-A24E-3BC7AD31441D`) at 11:50:52 Africa/Accra time.

The process launch confirms the review build was handed to the paired device; it is not visual QA evidence. Complete the checklist above before Ship approval.

### Device failure and correction — 2026-08-19

The first motion build failed paired-iPhone QA: duplicate selected content overlapped during travel, the scale response felt delayed, capsule motion paused between independently timed phases, and the transparent travelling surface visually disappeared inside the outer glass. The corrected build now uses one selected content layer, synchronous pre-route startup, one coordinated capsule/shell/inactive-icon spring, 90ms shell feedback, a label reveal anchored to the icon-facing edge, and a tested clear-glass sheen/border. Automated checks pass; every motion checklist item above remains unchecked pending device re-QA.

## Deferred

The Chats-card-to-thread expansion, reverse transition, and reduced-motion behavior are not part of this baseline. They require the dedicated post-Ship Product plan and thread Figma handoff.
