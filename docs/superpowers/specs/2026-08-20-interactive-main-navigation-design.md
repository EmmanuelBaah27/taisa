# Interactive Main Navigation Design

**Date:** 2026-08-20
**Status:** Proposed — awaiting Baah review
**Work tier:** Full
**Current stage:** Scope
**Target branch:** `refactor/shared-chat-recording-shell`

## Objective

Make horizontal navigation between Taisa's main destinations feel directly manipulated: the adjacent page must be visible while the user swipes, with no black intermediate frame or delayed destination mount. Preserve standard route semantics, scale beyond the current three destinations, and avoid making a native pager the application's foundational navigator.

The current destination order is:

1. Chats
2. Home — initial destination
3. You

The retired Logs, Insights, and Goals routes are not part of this architecture.

## Decision

Build a focused Expo Router custom layout navigator on React Navigation's `TabRouter`. The navigator will remain the authority for route state, URLs, deep links, browser history, and accessibility. Its custom view will render an interactive horizontal scene track for the active destination and its immediate neighbors.

This follows React Navigation's supported custom-navigator boundary instead of introducing a separate pager state machine. No native pager dependency is required.

## Why Not a Permanent Pager

A permanent pager is attractive for three screens but becomes progressively less efficient as navigation grows. It also creates a second navigation authority that must be synchronized with Expo Router.

The proposed navigator instead uses route state directly and limits interactive rendering to the scenes needed for the current gesture. It retains the familiar route model while delivering the visual continuity of paging.

## Architecture

### Route model

The tab router owns an ordered destination registry. Each destination defines its route name, public path, label, icon, and availability. The initial route is Home even though Home is the middle item.

Adding a future destination changes the registry and its route file. It does not require changes to gesture math or a new synchronization layer.

### Scene window

At rest, the active scene is visible. The immediate previous and next scenes are eligible for preparation. During a horizontal gesture, the custom view renders:

- the active scene;
- the adjacent scene in the gesture direction;
- no unrelated distant scenes.

Previously visited scenes may remain frozen in React Navigation's descriptor cache, subject to memory policy, but they do not run active animations or foreground effects.

The scene track is clipped to the viewport. Translation is driven directly by the gesture, so the neighboring page enters continuously with the finger. There is never an empty or dark frame between scenes.

### Gesture arbitration

The horizontal recognizer activates only after clear horizontal intent. Vertical motion fails the horizontal recognizer early, preserving page scrolling. The full-screen chat's downward dismiss gesture remains in a separate modal route above the tab navigator and is unaffected.

At the first and last destination, the track applies restrained edge resistance and returns to rest. Navigation never wraps.

The gesture commits when either distance or horizontal velocity crosses the approved threshold. An incomplete gesture returns to the active page with an overshoot-clamped spring.

### Route commitment

While dragging, the active route does not change. On commit, the navigator dispatches a standard tab jump to the adjacent route. The scene track completes its settlement using the already-rendered destination, then resets its local translation to zero without a visible discontinuity.

Deep links and bottom-navigation taps dispatch through the same router. Non-adjacent taps jump directly with the existing short fade rather than animating through intermediate pages.

### Bottom navigation

The bottom capsule reads selected state from the tab router. During an interactive swipe it may interpolate toward the adjacent destination, but the committed selection changes only when the route commits. A cancelled swipe restores the capsule to its origin.

The initial visual order is Chats, Home, You, with Home selected on launch.

## Rendering and Efficiency

- Mount only the active scene and the adjacent scene needed by an active gesture.
- Prepare the likely adjacent descriptor without starting its foreground data work.
- Use route focus to pause timers, network refresh, sensors, and other foreground effects on inactive scenes.
- Preserve each route's scroll position through normal route state.
- Drop distant inactive scenes according to a bounded cache policy when destination count grows.
- Respect reduced motion by replacing spatial tracking with the existing overlapping fade while preserving immediate route commitment.

For three destinations, both neighbors may be kept warm when memory allows. At four or more, the implementation defaults to directional adjacent preparation and a bounded recent-scene cache.

## Visual Behavior

During an eligible swipe:

1. The active page follows the finger immediately with approximately 98% tracking, creating barely perceptible weight without visible lag.
2. The adjacent page is already present immediately beyond the viewport and remains spatially locked to the active page with no gap, parallax, or independent fade.
3. The background behind both scenes remains the standard page backdrop, never the dark chat-sheet backdrop.
4. Direction reversals preserve a trace of momentum so the track feels viscous rather than mechanically attached, while remaining responsive.
5. A successful swipe settles in under 300 ms with an overshoot-clamped spring.
6. A cancelled swipe returns without bounce.
7. Stronger resistance appears only when pulling beyond the Chats or You boundary.

The viscosity must be felt as subtle weight, not seen as delayed response. There is no activation pause after horizontal intent is established, no decorative scaling, and no opacity transition during an interactive swipe.

The dark backdrop remains reserved for the intentional full-screen chat sheet scale-back effect.

## Accessibility

- VoiceOver focus moves to the committed destination after settlement.
- Route changes announce the destination label once.
- Horizontal gestures do not replace visible, accessible bottom-navigation controls.
- Reduced Motion disables the spatial page track and uses an overlapping fade.
- Keyboard and assistive navigation dispatch ordinary tab actions without gesture animation.

## Failure and Recovery

If an adjacent scene cannot render, the current scene remains active and the gesture cancels. Route commitment does not occur until a valid destination descriptor exists. Rendering errors stay within the destination's existing error boundary.

The navigator must never leave its translation between pages after interruption, app backgrounding, dimension changes, or route replacement. Those events cancel the gesture and normalize the track to the router's current index.

## Migration

1. Remove the temporary slide-to-empty gesture from the current tab layout and restore overlapping fades as the safe baseline.
2. Extract the destination registry and pure adjacency/commit policy.
3. Introduce the custom tab-router layout with route-driven selection.
4. Add the clipped interactive scene track and gesture arbitration.
5. Connect bottom-capsule interpolation and direct tab actions.
6. Verify deep links, back behavior, focus effects, rotation, reduced motion, and the chat overlay.
7. Validate on the paired iPhone before replacing the baseline transition.

The migration keeps the standard route layout usable at every checkpoint. If the interactive layer fails verification, the app falls back to immediate route commitment with the existing fade and no black frame.

## Verification

Automated coverage must include:

- Home initializes at the middle route index.
- Left and right adjacency resolve correctly with hard edges.
- Only the active and relevant adjacent scenes render during a gesture.
- Vertical intent does not activate horizontal paging.
- Distance and velocity thresholds commit exactly one adjacent route.
- Interactive tracking stays spatially locked without gaps, parallax, or opacity changes.
- Settlement and cancellation never overshoot or bounce.
- Cancelled and interrupted gestures normalize translation.
- Deep links select the correct route and scene index.
- Bottom capsule state follows router state and rolls back on cancellation.
- Reduced Motion uses the fade path.
- Removed route names cannot resolve.

Device QA must cover slow drags, fast flicks, reversals, edge resistance, vertical scrolling, capsule taps, app backgrounding mid-gesture, rotation, chat open/close, and repeated navigation without black frames.

## Success Criteria

- The adjacent page is continuously visible while swiping.
- No black, empty, or late-mounted frame appears.
- Home remains the default middle destination.
- URLs, deep links, back behavior, and bottom selection stay route-driven.
- Adding destinations does not require keeping every page mounted.
- Vertical page scrolling and chat pull-down remain reliable.
- The implementation introduces no native pager dependency.
