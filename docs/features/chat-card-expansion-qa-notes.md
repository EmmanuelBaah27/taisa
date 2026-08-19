# Chat Card Expansion QA Notes

## 2026-08-19 — Reverse morph required

Baah requested that closing a historical chat reverse the opening transition and return the full-screen conversation to its source card. The Chats list must preserve its source scroll position throughout both directions so the destination card remains visually stable.

### Revised acceptance

- Opening captures the selected card frame and current Chats-list scroll offset.
- Closing a chat opened from Chats morphs back to that exact frame before the route pops.
- The underlying Chats list remains mounted and restores its captured offset before it refreshes or reorders.
- Deep links, fresh capture, invalid geometry, orientation mismatch, and reduced motion close immediately rather than targeting stale geometry.
- Recorder cleanup starts when closing begins and remains safe while the reverse animation finishes.
