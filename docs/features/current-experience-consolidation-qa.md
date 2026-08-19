# Current Experience Consolidation — QA

**Status:** Navigation correction verified automatically; Baah device re-QA pending<br>
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

## Deferred

The Chats-card-to-thread expansion, reverse transition, and reduced-motion behavior are not part of this baseline. They require the dedicated post-Ship Product plan and thread Figma handoff.
