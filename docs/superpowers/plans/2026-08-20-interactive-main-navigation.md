# Interactive Main Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the temporary slide-to-empty tab gesture with route-driven interactive paging that visibly brings the adjacent destination into view with subtle weight and no black frame.

**Architecture:** Wrap a focused React Navigation `TabRouter` custom navigator with Expo Router's `withLayoutContext`. A clipped scene window renders the active descriptor and only the adjacent descriptor required by an active gesture; route state remains authoritative, while Reanimated owns transient gesture translation.

**Tech Stack:** React Native 0.81, Expo SDK 54, Expo Router 6, React Navigation 7 `TabRouter`, React Native Gesture Handler 2.28, React Native Reanimated 4.1, TypeScript 5.9, Jest 29.

**Spec:** `docs/superpowers/specs/2026-08-20-interactive-main-navigation-design.md`

**Status:** Approved — Build in progress

## Global Constraints

- Destination order is Chats, Home, You; Home is the initial middle route.
- Expo Router and React Navigation route state remain the single authority for URLs, deep links, back behavior, focus, and selected destination.
- Add no native pager dependency.
- Interactive tracking uses approximately `0.98` of finger translation after horizontal intent activates.
- Active and adjacent scenes remain spatially locked with no gap, parallax, scale, or opacity animation.
- Interactive settlement completes within `300ms` and never overshoots or bounces.
- Strong edge resistance applies only beyond Chats and You.
- Vertical scrolling and the full-screen chat's downward dismissal must retain gesture priority.
- Reduced Motion uses the overlapping white-backed fade, not spatial paging.
- The dark `#111111` backdrop remains visible only for intentional chat-sheet scale-back.
- Every task uses RED → GREEN tests and commits only its listed files.

---

### Task 1: Restore the safe route-transition baseline

**Files:**
- Modify: `mobile/app/(tabs)/_layout.tsx`
- Modify: `mobile/src/navigation/__tests__/bottomNavigation.test.ts`
- Modify: `mobile/src/navigation/__tests__/currentExperience.test.ts`
- Test: `mobile/src/navigation/__tests__/localCaptureRoutes.test.ts`

**Interfaces:**
- Consumes: `getBottomNavigationPageTransition()` and the approved `Chats | Home | You` route registry.
- Produces: standard Expo Router tabs with immediate route commitment and overlapping white-backed fade; no hand-written horizontal translation.

- [ ] **Step 1: Write the failing baseline source contract**

Add assertions to `localCaptureRoutes.test.ts`:

```ts
expect(tabLayout).not.toMatch(/pageTranslateX|pageSwipeGesture|exitX/);
expect(tabLayout).toMatch(/animation: PAGE_TRANSITION\.sceneAnimation/);
expect(tabLayout).toMatch(/backgroundColor: PAGE_TRANSITION\.backdropColor/);
expect(tabLayout).toMatch(/<Tabs\.Screen name="chats" \/>[\s\S]*name="index"[\s\S]*name="you"/);
expect(tabLayout).not.toMatch(/name="logs"|name="insights"|name="goals"/);
```

- [ ] **Step 2: Run the baseline tests and verify RED**

Run:

```bash
cd mobile
npm test -- --runInBand \
  src/navigation/__tests__/localCaptureRoutes.test.ts \
  src/navigation/__tests__/bottomNavigation.test.ts \
  src/navigation/__tests__/currentExperience.test.ts
```

Expected: FAIL because `_layout.tsx` still contains the temporary `pageTranslateX` slide-to-empty gesture.

- [ ] **Step 3: Remove only the temporary horizontal gesture**

Delete the layout's `GestureDetector`, `pageTranslateX`, swipe threshold, delayed `router.navigate`, and viewport-exit animation. Preserve the chat scale-back style, white backdrop, fade animation, `BottomNavBar`, and `VoiceButton`.

The tab screen list remains:

```tsx
<Tabs initialRouteName="index" screenOptions={{
  headerShown: false,
  tabBarStyle: { display: 'none' },
  animation: PAGE_TRANSITION.sceneAnimation,
}}>
  <Tabs.Screen name="chats" />
  <Tabs.Screen name="index" />
  <Tabs.Screen name="you" />
</Tabs>
```

- [ ] **Step 4: Run the baseline tests and verify GREEN**

Run the Step 2 command plus `npx tsc --noEmit`. Expected: all tests PASS and TypeScript exits `0`.

- [ ] **Step 5: Commit the safe baseline**

```bash
git add mobile/app/'(tabs)'/_layout.tsx \
  mobile/src/navigation/__tests__/localCaptureRoutes.test.ts \
  mobile/src/navigation/__tests__/bottomNavigation.test.ts \
  mobile/src/navigation/__tests__/currentExperience.test.ts
git commit -m "fix: restore safe main route fades"
```

---

### Task 2: Define pure interactive-transition policy

**Files:**
- Create: `mobile/src/navigation/interactiveMainNavigation.ts`
- Create: `mobile/src/navigation/__tests__/interactiveMainNavigation.test.ts`

**Interfaces:**
- Produces: `MainDestinationId = 'chats' | 'index' | 'you'`.
- Produces: `getInteractiveSceneWindow(routeNames: readonly string[], activeIndex: number, direction: -1 | 0 | 1): readonly number[]`.
- Produces: `resolveMainSwipe(input: MainSwipeInput): MainSwipeResolution`.
- Produces constants `MAIN_SWIPE_TRACKING = 0.98`, `MAIN_SWIPE_DISTANCE = 72`, `MAIN_SWIPE_VELOCITY = 700`, and `MAIN_EDGE_RESISTANCE = 0.18`.

- [ ] **Step 1: Write failing policy tests**

```ts
expect(getInteractiveSceneWindow(['chats', 'index', 'you'], 1, -1)).toEqual([0, 1]);
expect(getInteractiveSceneWindow(['chats', 'index', 'you'], 1, 1)).toEqual([1, 2]);
expect(getInteractiveSceneWindow(['chats', 'index', 'you'], 1, 0)).toEqual([1]);

expect(resolveMainSwipe({
  activeIndex: 1, routeCount: 3, translationX: -80, velocityX: -200,
})).toEqual({ kind: 'commit', destinationIndex: 2, direction: 1 });
expect(resolveMainSwipe({
  activeIndex: 0, routeCount: 3, translationX: 160, velocityX: 1200,
})).toEqual({ kind: 'cancel', edge: true });
expect(MAIN_SWIPE_TRACKING).toBe(0.98);
```

- [ ] **Step 2: Run the policy test and verify RED**

Run `npm test -- --runInBand src/navigation/__tests__/interactiveMainNavigation.test.ts`.

Expected: FAIL because the module does not exist.

- [ ] **Step 3: Implement the pure policy**

Define:

```ts
export interface MainSwipeInput {
  activeIndex: number;
  routeCount: number;
  translationX: number;
  velocityX: number;
}

export type MainSwipeResolution =
  | { kind: 'commit'; destinationIndex: number; direction: -1 | 1 }
  | { kind: 'cancel'; edge: boolean };
```

Resolve a leftward gesture to `activeIndex + 1` and a rightward gesture to `activeIndex - 1`. Commit when absolute translation exceeds `72` or velocity in the same direction exceeds `700`. Return `{ kind: 'cancel', edge: true }` for an out-of-range destination. Scene-window indices must be unique, sorted, and in range.

- [ ] **Step 4: Run the policy test and verify GREEN**

Run the Step 2 command. Expected: PASS.

- [ ] **Step 5: Commit the policy**

```bash
git add mobile/src/navigation/interactiveMainNavigation.ts \
  mobile/src/navigation/__tests__/interactiveMainNavigation.test.ts
git commit -m "feat: define interactive main navigation policy"
```

---

### Task 3: Build the route-authoritative custom tab navigator

**Files:**
- Create: `mobile/src/navigation/InteractiveMainNavigator.tsx`
- Create: `mobile/src/navigation/__tests__/InteractiveMainNavigator.test.tsx`
- Modify: `mobile/app/(tabs)/_layout.tsx`

**Interfaces:**
- Consumes: React Navigation `TabRouter`, `createNavigatorFactory`, and `useNavigationBuilder`.
- Produces: `InteractiveMainNavigator` wrapped by Expo Router `withLayoutContext`.
- Produces: `InteractiveMainNavigatorViewProps` containing router `state`, `navigation`, `descriptors`, and `BottomNavBar`/`VoiceButton` slots.

- [ ] **Step 1: Write the failing navigator-state test**

Render the view with three descriptor fixtures and assert:

```ts
expect(screen.getByTestId('main-scene-index')).toBeTruthy();
expect(screen.queryByTestId('main-scene-chats')).toBeNull();
expect(screen.queryByTestId('main-scene-you')).toBeNull();
expect(screen.getByTestId('main-navigation-shell')).toBeTruthy();
```

Add a source contract asserting the navigator uses `TabRouter` and `withLayoutContext`, not `react-native-pager-view`.

- [ ] **Step 2: Run the navigator test and verify RED**

Run `npm test -- --runInBand src/navigation/__tests__/InteractiveMainNavigator.test.tsx`.

Expected: FAIL because the navigator does not exist.

- [ ] **Step 3: Implement the custom navigator boundary**

Build the navigator with this state boundary:

```tsx
function InteractiveMainNavigatorBase({
  id,
  initialRouteName,
  children,
  screenListeners,
  screenOptions,
}: Props) {
  const { state, navigation, descriptors, NavigationContent } = useNavigationBuilder(
    TabRouter,
    { id, initialRouteName, children, screenListeners, screenOptions },
  );

  return (
    <NavigationContent>
      <InteractiveMainNavigatorView
        state={state}
        navigation={navigation}
        descriptors={descriptors}
      />
    </NavigationContent>
  );
}
```

Create the navigator with `createNavigatorFactory`, then export its `.Navigator` through `withLayoutContext`. At rest, render only `descriptors[state.routes[state.index].key].render()` inside a white clipped scene viewport. Render `BottomNavBar` and `VoiceButton` above that viewport.

- [ ] **Step 4: Replace Expo Router `Tabs` in the layout**

Use:

```tsx
<InteractiveMainNavigator initialRouteName={CURRENT_INITIAL_TAB}>
  <InteractiveMainNavigator.Screen name="chats" />
  <InteractiveMainNavigator.Screen name="index" />
  <InteractiveMainNavigator.Screen name="you" />
</InteractiveMainNavigator>
```

Keep the existing chat scale-back wrapper outside the navigator. Do not add gesture code yet.

- [ ] **Step 5: Run navigator, route, and type checks**

Run:

```bash
npm test -- --runInBand \
  src/navigation/__tests__/InteractiveMainNavigator.test.tsx \
  src/navigation/__tests__/currentExperience.test.ts \
  src/navigation/__tests__/bottomNavigation.test.ts
npx tsc --noEmit
```

Expected: PASS with Home selected at router index `1`.

- [ ] **Step 6: Commit the custom navigator skeleton**

```bash
git add mobile/src/navigation/InteractiveMainNavigator.tsx \
  mobile/src/navigation/__tests__/InteractiveMainNavigator.test.tsx \
  mobile/app/'(tabs)'/_layout.tsx
git commit -m "refactor: introduce route-driven main navigator"
```

---

### Task 4: Render and drag the adjacent scene window

**Files:**
- Modify: `mobile/src/navigation/InteractiveMainNavigator.tsx`
- Modify: `mobile/src/navigation/__tests__/InteractiveMainNavigator.test.tsx`
- Test: `mobile/src/navigation/__tests__/interactiveMainNavigation.test.ts`

**Interfaces:**
- Consumes: `getInteractiveSceneWindow`, `resolveMainSwipe`, and motion constants from Task 2.
- Produces: a clipped scene track with `testID="main-scene-track"` and direct adjacent route rendering.
- Dispatches: `CommonActions.navigate({ name: destination.name, merge: true })` only after successful settlement.

- [ ] **Step 1: Write failing scene-window tests**

Drive the exported view with an active leftward gesture state and assert both Home and You descriptors render while Chats does not. Assert each scene uses its route index offset:

```ts
expect(screen.getByTestId('main-scene-index')).toBeTruthy();
expect(screen.getByTestId('main-scene-you')).toBeTruthy();
expect(screen.queryByTestId('main-scene-chats')).toBeNull();
expect(sceneStyle('index')).toMatchObject({ left: 0 });
expect(sceneStyle('you')).toMatchObject({ left: viewportWidth });
```

- [ ] **Step 2: Run the scene-window test and verify RED**

Run the Task 3 focused navigator test. Expected: FAIL because only the active descriptor renders.

- [ ] **Step 3: Add horizontal gesture arbitration**

Use a direct native child under `GestureDetector`:

```tsx
<GestureDetector gesture={horizontalPan}>
  <Animated.View collapsable={false} testID="main-navigation-shell" style={styles.shell}>
    {sceneTrack}
  </Animated.View>
</GestureDetector>
```

Configure `Gesture.Pan()` with `activeOffsetX={[-18, 18]}` and `failOffsetY={[-14, 14]}`. On update, determine direction from `translationX`, update the scene window on the JS thread only when direction first changes, and set track translation to `translationX * 0.98`. At a hard edge use `translationX * 0.18`.

- [ ] **Step 4: Render active and adjacent descriptors on one locked track**

Each scene is absolutely positioned at `(routeIndex - activeIndex) * viewportWidth`. The track translation is the only animated horizontal property. Do not animate individual scene opacity, scale, or position.

- [ ] **Step 5: Implement cancellation and commitment**

On cancellation, animate track translation to `0` with:

```ts
withSpring(0, {
  damping: 30,
  stiffness: 340,
  overshootClamping: true,
});
```

On commit, settle to `direction * -viewportWidth`, dispatch the standard tab navigation action, synchronously normalize translation to `0` after router index changes, and clear the gesture direction. Cap timing fallback at `240ms`; do not traverse intermediate destinations.

- [ ] **Step 6: Verify GREEN and commit**

Run Task 2 and Task 3 test commands plus `npx tsc --noEmit`. Expected: PASS.

```bash
git add mobile/src/navigation/InteractiveMainNavigator.tsx \
  mobile/src/navigation/__tests__/InteractiveMainNavigator.test.tsx \
  mobile/src/navigation/__tests__/interactiveMainNavigation.test.ts
git commit -m "feat: reveal adjacent routes during main swipes"
```

---

### Task 5: Synchronize capsule taps and interactive selection

**Files:**
- Create: `mobile/src/navigation/MainNavigationInteractionContext.tsx`
- Modify: `mobile/src/navigation/InteractiveMainNavigator.tsx`
- Modify: `mobile/src/components/ui/BottomNavBar.tsx`
- Modify: `mobile/src/navigation/__tests__/bottomNavigation.test.ts`

**Interfaces:**
- Produces: `MainNavigationInteractionValue { progress: SharedValue<number>; fromIndex: number; toIndex: number | null; navigate(id: MainDestinationId): void }`.
- Consumes: route index from the custom navigator and navigation actions from `TabRouter`.
- Preserves: existing capsule tap motion and glass rendering.

- [ ] **Step 1: Write failing synchronization tests**

Assert capsule selection is derived from router route name, a cancelled interactive swipe reports the origin index, and a non-adjacent capsule tap dispatches one direct navigation action without interactive track traversal.

```ts
expect(resolveCapsuleInteractiveIndex({ fromIndex: 1, toIndex: 2, progress: 0.49 })).toBe(1);
expect(resolveCapsuleInteractiveIndex({ fromIndex: 1, toIndex: 2, progress: 0.51 })).toBe(2);
expect(resolveCapsuleInteractiveIndex({ fromIndex: 1, toIndex: null, progress: 0 })).toBe(1);
```

- [ ] **Step 2: Run the bottom-navigation test and verify RED**

Run `npm test -- --runInBand src/navigation/__tests__/bottomNavigation.test.ts`.

Expected: FAIL because the interactive resolver/context is absent.

- [ ] **Step 3: Add the interaction context**

The navigator provides route-derived `fromIndex`, gesture-derived `toIndex`, normalized `progress`, and a `navigate` callback. `BottomNavBar` consumes the context when present and falls back to pathname routing outside the custom navigator.

Capsule taps call the navigator callback immediately. Adjacent taps may use the same scene settlement; non-adjacent taps use the approved overlapping fade and direct tab action.

- [ ] **Step 4: Run tests and commit**

Run bottom-navigation, interactive-navigation, and navigator tests plus TypeScript. Expected: PASS.

```bash
git add mobile/src/navigation/MainNavigationInteractionContext.tsx \
  mobile/src/navigation/InteractiveMainNavigator.tsx \
  mobile/src/components/ui/BottomNavBar.tsx \
  mobile/src/navigation/__tests__/bottomNavigation.test.ts
git commit -m "feat: synchronize main pager and navigation capsule"
```

---

### Task 6: Handle reduced motion, interruptions, focus, and accessibility

**Files:**
- Modify: `mobile/src/navigation/InteractiveMainNavigator.tsx`
- Modify: `mobile/src/navigation/interactiveMainNavigation.ts`
- Modify: `mobile/src/navigation/__tests__/InteractiveMainNavigator.test.tsx`
- Modify: `mobile/src/navigation/__tests__/interactiveMainNavigation.test.ts`

**Interfaces:**
- Consumes: system Reduced Motion setting, app-state changes, layout width changes, and router index changes.
- Produces: deterministic normalization to the current router index and one destination accessibility announcement per committed route.

- [ ] **Step 1: Write failing lifecycle tests**

Cover these exact cases:

```ts
expect(resolveInterruption('background')).toEqual({ cancelGesture: true, normalizeTrack: true });
expect(resolveInterruption('dimension-change')).toEqual({ cancelGesture: true, normalizeTrack: true });
expect(resolveInterruption('route-replace')).toEqual({ cancelGesture: true, normalizeTrack: true });
expect(getInteractiveMotionMode(true)).toBe('fade');
expect(getInteractiveMotionMode(false)).toBe('spatial');
```

Assert the destination descriptor is focused only after router commitment and `AccessibilityInfo.announceForAccessibility` receives the committed label once.

- [ ] **Step 2: Run focused tests and verify RED**

Run Task 2 and Task 3 test commands. Expected: FAIL because lifecycle policy is absent.

- [ ] **Step 3: Implement lifecycle normalization**

Cancel the active Gesture Handler gesture where supported, call `cancelAnimation(trackX)`, set `trackX.value = 0`, clear directional scene state, and derive the visible descriptor from the latest router index after backgrounding, width changes, route replacement, or interrupted settlement.

When Reduced Motion is enabled, disable the spatial pan recognizer and retain Task 1's immediate white-backed fade. Keyboard and assistive actions dispatch route navigation without gesture settlement.

- [ ] **Step 4: Run tests and commit**

Run navigator, policy, bottom-navigation, current-experience, chat gesture, and TypeScript checks. Expected: PASS.

```bash
git add mobile/src/navigation/InteractiveMainNavigator.tsx \
  mobile/src/navigation/interactiveMainNavigation.ts \
  mobile/src/navigation/__tests__/InteractiveMainNavigator.test.tsx \
  mobile/src/navigation/__tests__/interactiveMainNavigation.test.ts
git commit -m "fix: normalize interactive navigation lifecycle"
```

---

### Task 7: Verify the integrated experience and record QA

**Files:**
- Modify: `docs/features/current-experience-consolidation-qa.md`
- Modify: `docs/workflow.md`
- Modify: `docs/superpowers/plans/2026-08-20-interactive-main-navigation.md`

**Interfaces:**
- Consumes: completed Tasks 1–6.
- Produces: automated evidence, paired-iPhone QA checklist, and workflow status `Review + QA` only after all checks pass.

- [ ] **Step 1: Run the complete focused suite**

```bash
cd mobile
npm test -- --runInBand \
  src/navigation/__tests__/interactiveMainNavigation.test.ts \
  src/navigation/__tests__/InteractiveMainNavigator.test.tsx \
  src/navigation/__tests__/bottomNavigation.test.ts \
  src/navigation/__tests__/currentExperience.test.ts \
  src/navigation/__tests__/localCaptureRoutes.test.ts \
  src/navigation/__tests__/chatCardExpansion.test.ts \
  src/components/ui/__tests__/PersistentNavigationCapsule.test.ts
npx tsc --noEmit
npm run verify:design-system
```

Expected: all tests PASS, TypeScript exits `0`, and design-system verification exits `0`.

- [ ] **Step 2: Run repository hygiene checks**

```bash
git diff --check
git status --short
```

Expected: no whitespace errors; status contains only deliberate scoped changes and preserved pre-existing user work.

- [ ] **Step 3: Complete paired-iPhone QA**

Verify:

- slow Home → Chats and Home → You drags reveal the adjacent page continuously;
- movement feels subtly weighted without visible lag;
- reversal has no gap, fade, scale, or page separation;
- incomplete swipes return without bounce;
- Chats and You edges resist and never wrap;
- vertical lists scroll without horizontal capture;
- chat pulls down only at its top and does not trigger tab paging;
- capsule taps, deep links, backgrounding, rotation, and repeated swipes never show black;
- Reduced Motion uses the overlapping fade.

- [ ] **Step 4: Record evidence and move to Review + QA**

Add the exact automated results and device observations to the QA document. Update Active Work to `Review + QA`, mark this plan `Complete — awaiting Baah device QA`, and identify Baah's next gate as Ship approval after device acceptance.

- [ ] **Step 5: Commit QA evidence**

```bash
git add docs/features/current-experience-consolidation-qa.md \
  docs/workflow.md \
  docs/superpowers/plans/2026-08-20-interactive-main-navigation.md
git commit -m "docs: record interactive navigation QA"
```
