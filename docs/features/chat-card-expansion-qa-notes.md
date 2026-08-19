# Chat Card Expansion QA Notes

## 2026-08-19 — Reverse morph required

Baah requested that closing a historical chat reverse the opening transition and return the full-screen conversation to its source card. The Chats list must preserve its source scroll position throughout both directions so the destination card remains visually stable.

### Revised acceptance

- Opening captures the selected card frame and current Chats-list scroll offset.
- Closing a chat opened from Chats morphs back to that exact frame before the route pops.
- The underlying Chats list remains mounted and restores its captured offset before it refreshes or reorders.
- Deep links, fresh capture, invalid geometry, orientation mismatch, and reduced motion close immediately rather than targeting stale geometry.
- Recorder cleanup starts when closing begins and remains safe while the reverse animation finishes.

## 2026-08-19 — White-shell reveal and settled chat position

Baah reported that transforming the full conversation made its content look visibly squashed. The card morph must therefore animate only a blank white shell. Header, messages, and composer reveal on a separate layer as the shell approaches full-screen and hide as the reverse morph begins.

Historical chats must also complete their initial non-animated bottom positioning while that content layer is hidden. The first visible conversation frame is already at the latest message; no initial animated scroll is shown.

## 2026-08-19 — Source-card text continuity

Baah reported a pause before the source card text returned after collapse. The opaque shell was covering the real card until route dismissal. During the final quarter of closing, the shell now fades from opaque to transparent so the mounted source card text is already visible before the route is removed.
