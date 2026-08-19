# Chat Card Expansion

**Track:** Product
**Tier:** Standard
**Status:** Review + QA — awaiting device QA
**Design:** [Figma node 409:4635](https://www.figma.com/design/TlIBdEHicoKUR9RhCFuLPi/-Taisa--UI-Design?node-id=409-4635&m=dev)

## What is it?

Make a Chats-list item expand into the canonical conversation view. The resulting screen follows the supplied Figma chat layout, while closing chat or an active recording returns immediately without the existing downward exit motion.

## Acceptance criteria

- [ ] Selecting a Chats item opens that conversation through `/chat`, not the legacy thread screen.
- [ ] The opening surface expands from the selected card bounds into the full viewport.
- [ ] The conversation header, title, message spacing, user bubble, assistant copy, and reply dock match Figma node `409:4635` using Taisa tokens.
- [ ] Closing chat or recording is immediate and has no reverse slide, collapse, or stack transition.
- [ ] Conversation hydration, replies, recording cleanup, safe areas, keyboard behavior, and accessibility remain intact.
- [ ] Reduced-motion users receive an immediate open and close.
- [ ] Mobile tests, typecheck, and design-system verification pass before device QA.

## Design handoff

- The full-screen surface is white with a floating circular chevron at top left and a centered, truncated conversation title.
- User messages are right-aligned neutral bubbles with 32px corners and 16px padding; assistant messages are unboxed 16/24 body copy.
- The bottom Reply control sits inside a white fade and preserves the existing voice/text composer states once activated.
- The opening animation is intentionally asymmetric: expand from the selected Chats card on entry; close instantly on the header action.
- Existing semantic tokens and `Icon`, conversation primitives, and composer behavior are reused. No new dependency or platform capability is introduced.

## Out of scope

- A reverse card-collapse animation
- Changes to coaching, persistence, transcription, or recording ownership
- Redesigning the Chats index or other screens
- Shipping or merging before Baah completes device QA
