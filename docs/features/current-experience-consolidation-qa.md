# Current Experience Consolidation — QA

**Status:** Automated verification in progress; Baah device QA pending  
**Branch:** `feature/current-experience`  
**Runtime:** `/Users/emmanuelbaah/Documents/Beats/VibeCoding/Taisa/.worktrees/feature-current-experience/mobile`

## Start the review build

```bash
cd /Users/emmanuelbaah/Documents/Beats/VibeCoding/Taisa/.worktrees/feature-current-experience/mobile
npm install
npm start
```

Use the managed development build for native checks; Expo Go is not valid for SQLCipher, recording, or device-security evidence.

## Baah device checklist

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

## Deferred

The Chats-card-to-thread expansion, reverse transition, and reduced-motion behavior are not part of this baseline. They require the dedicated post-Ship Product plan and thread Figma handoff.
