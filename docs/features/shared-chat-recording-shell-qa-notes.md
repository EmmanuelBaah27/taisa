# Shared chat and recording shell — QA notes

## 2026-08-20 preview feedback

- Discarding from a chat reveals the Chats destination through a settling reverse morph. The destination must appear stable, without spring or bounce.
- Closing an ordinary conversation with no unfinished input must not show a destructive confirmation.
- Destructive confirmation copy must use the format-neutral term “draft”.
- Returning from Face ID briefly exposes a green frame before the app is ready. The privacy shield must hand off through a stable opaque app background.
- Secondary neutral buttons technically use glass, but their contour disappears on white surfaces. Reduce the milky fill and strengthen the edge and upper sheen without adding more frost.

Canonical reproduction revision: `preview/taisa` at `ff244bc`.
