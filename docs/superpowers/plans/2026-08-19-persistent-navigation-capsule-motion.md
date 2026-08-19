# Persistent Navigation Capsule Motion Implementation Plan

**Status:** Complete — awaiting Baah device QA

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace remounted tab selections with one persistent capsule that moves immediately on touch-down while the entire glass navigation pill scales uniformly to `1.12` without compounded capsule scaling.

**Architecture:** Keep three stable accessible destination targets beneath one absolute selected-capsule layer. `BottomNavBar` owns route-aware Reanimated values; pure frame and phase functions remain in the navigation model, and visual primitives remain business-free.

**Tech Stack:** Expo SDK 54, React Native 0.81, Expo Router 6, Reanimated 4, NativeWind 4, TypeScript 5.9, Jest 29, Storybook React Native 10.

**Spec:** `docs/superpowers/specs/2026-08-19-persistent-navigation-capsule-motion-design.md`

## Global Constraints

- Preserve Figma resting geometry: Home/Chats shell 240×60, Me shell 220×60, selected widths 108/108/88, inactive width 56.
- Preserve selected fill `rgba(15,16,16,0.06)`, 24px icons, 8px gap, and Inter Medium 16/24 with `-0.36` tracking.
- Press feedback is one uniform `scale: 1.12` for the entire pill; the capsule adds no second scale, and neither uses separate `scaleX` and `scaleY`.
- The capsule is transparent while travelling and restores the 6% fill only after final settlement.
- Route immediately; never wait for motion completion.
- Rapid taps retarget the running spring without resetting scale or flashing grey.
- Reduced motion removes scale/translation and retains short fill/label crossfades.
- Do not add drag, blur, haptics, sound, neighboring-icon nudges, `StyleSheet.create()`, or title/safe-area changes.
- Preserve the Navii avatar, glass/material fallback, recording button, destinations, and route names.

---

### Task 1: Checkpoint the approved resting-navigation baseline

**Files:**
- Modify: `docs/design-system.md`, `docs/workflow.md`
- Modify: `mobile/src/components/ui/BottomNavBar.tsx`, `mobile/src/components/ui/index.ts`
- Create: `mobile/src/components/ui/SelectedNavigationItem.tsx`, `InactiveNavigationItem.tsx`, their stories, and selected-item test
- Modify: `mobile/src/navigation/bottomNavigation.ts`, `mobile/src/navigation/__tests__/bottomNavigation.test.ts`

**Interfaces:**
- Produces: approved selected/inactive primitives and tap-only jelly behavior in a recoverable commit.
- Consumed by: Tasks 2–4.

- [ ] **Step 1: Audit the dirty scope**

```bash
git status --short
git diff --check
git diff -- mobile/src/components/ui/BottomNavBar.tsx mobile/src/navigation/bottomNavigation.ts docs/design-system.md docs/workflow.md
```

Expected: selected/inactive navigation work only; no drag code or unrelated files.

- [ ] **Step 2: Verify the current baseline**

From `mobile/`:

```bash
npm test -- --runInBand src/navigation/__tests__/bottomNavigation.test.ts src/components/ui/__tests__/SelectedNavigationItem.test.ts
npm run typecheck
npm run verify:design-system
```

Expected: focused tests, TypeScript, and 21 catalog modules pass.

- [ ] **Step 3: Commit the approved baseline**

```bash
git add docs/design-system.md docs/workflow.md mobile/src/components/ui mobile/src/navigation/bottomNavigation.ts mobile/src/navigation/__tests__/bottomNavigation.test.ts
git commit -m "feat(ds): establish navigation states and jelly feedback"
```

---

### Task 2: Define capsule frames and transition phases

**Files:**
- Modify: `mobile/src/navigation/bottomNavigation.ts`
- Test: `mobile/src/navigation/__tests__/bottomNavigation.test.ts`

**Interfaces:**
- Produces:
  - `NavigationCapsuleFrame = { shellWidth: number; x: number; width: number }`
  - `NavigationCapsulePhase = 'resting' | 'travelling' | 'settling'`
  - `NavigationCapsuleState = { from: BottomNavigationItem['id']; to: BottomNavigationItem['id']; phase: NavigationCapsulePhase }`
  - `getBottomNavigationCapsuleFrame(id): NavigationCapsuleFrame`
  - `startBottomNavigationTransition(state, destination): NavigationCapsuleState`
  - `settleBottomNavigationTransition(state): NavigationCapsuleState`
  - `shouldShowBottomNavigationSelectedFill(state): boolean`
- Consumed by: Tasks 3–4.

- [ ] **Step 1: Write failing frame and phase tests**

```ts
expect(getBottomNavigationCapsuleFrame('index')).toEqual({ shellWidth: 240, x: 6, width: 108 });
expect(getBottomNavigationCapsuleFrame('logs')).toEqual({ shellWidth: 240, x: 66, width: 108 });
expect(getBottomNavigationCapsuleFrame('you')).toEqual({ shellWidth: 220, x: 126, width: 88 });

const resting = { from: 'logs', to: 'logs', phase: 'resting' } as const;
const travelling = startBottomNavigationTransition(resting, 'you');
expect(travelling).toEqual({ from: 'logs', to: 'you', phase: 'travelling' });
expect(shouldShowBottomNavigationSelectedFill(travelling)).toBe(false);
expect(startBottomNavigationTransition(travelling, 'index')).toEqual({
  from: 'logs', to: 'index', phase: 'travelling',
});
expect(settleBottomNavigationTransition(travelling)).toEqual({
  from: 'you', to: 'you', phase: 'resting',
});
```

- [ ] **Step 2: Verify RED**

Run `npm test -- --runInBand src/navigation/__tests__/bottomNavigation.test.ts`.

Expected: FAIL because the new exports do not exist.

- [ ] **Step 3: Implement exact frames and reducer**

```ts
export const BOTTOM_NAVIGATION_CAPSULE_FRAMES = {
  index: { shellWidth: 240, x: 6, width: 108 },
  logs: { shellWidth: 240, x: 66, width: 108 },
  you: { shellWidth: 220, x: 126, width: 88 },
} as const;

export function startBottomNavigationTransition(
  state: NavigationCapsuleState,
  destination: BottomNavigationItem['id'],
): NavigationCapsuleState {
  return {
    from: state.phase === 'resting' ? state.to : state.from,
    to: destination,
    phase: destination === state.to && state.phase === 'resting' ? 'resting' : 'travelling',
  };
}
```

`shouldShowBottomNavigationSelectedFill` returns true only while resting. `settleBottomNavigationTransition` copies `to` into both endpoints and sets `resting`.

- [ ] **Step 4: Verify GREEN and commit**

```bash
npm test -- --runInBand src/navigation/__tests__/bottomNavigation.test.ts
git add mobile/src/navigation/bottomNavigation.ts mobile/src/navigation/__tests__/bottomNavigation.test.ts
git commit -m "feat: model persistent navigation capsule motion"
```

---

### Task 3: Build the persistent capsule primitive

**Files:**
- Create: `mobile/src/components/ui/PersistentNavigationCapsule.tsx`
- Create: `mobile/src/components/ui/PersistentNavigationCapsule.stories.tsx`
- Create: `mobile/src/components/ui/__tests__/PersistentNavigationCapsule.test.ts`
- Modify: `mobile/src/components/ui/index.ts`, `docs/design-system.md`

**Interfaces:**
- Consumes: Task 2 frame/phase types.
- Produces:

```ts
export interface PersistentNavigationCapsuleProps {
  label: 'Home' | 'Chats' | 'Me';
  leadingVisual: ReactNode;
  frame: NavigationCapsuleFrame;
  phase: NavigationCapsulePhase;
  animatedContainerStyle?: StyleProp<ViewStyle>;
  animatedLabelStyle?: StyleProp<TextStyle>;
}
```

- [ ] **Step 1: Write a failing surface and typography test**

Call the component directly and inspect its capsule and label:

```ts
expect(restingCapsule.props.style).toContainEqual({ backgroundColor: 'rgba(15,16,16,0.06)' });
expect(travellingCapsule.props.style).toContainEqual({ backgroundColor: 'transparent' });
expect(label.props.className).toContain('font-sans-medium');
```

- [ ] **Step 2: Verify RED**

Run `npm test -- --runInBand src/components/ui/__tests__/PersistentNavigationCapsule.test.ts`.

Expected: FAIL because the component is missing.

- [ ] **Step 3: Implement the presentational component**

Use an absolute `Animated.View`, height 48, radius 32, `frame.width`, and no router/store/pathname imports. Content remains a horizontal row with 16px horizontal padding, 24px visual, 8px gap, and the existing Inter Medium label token. Surface is selected fill only for `resting`; otherwise transparent.

- [ ] **Step 4: Add review stories**

```ts
export const HomeResting: Story = { args: { label: 'Home', frame: homeFrame, phase: 'resting' } };
export const ChatsTravelling: Story = { args: { label: 'Chats', frame: chatsFrame, phase: 'travelling' } };
export const MeSettling: Story = { args: { label: 'Me', frame: meFrame, phase: 'settling' } };
```

Supply existing icons/Navii avatar and render on white.

- [ ] **Step 5: Verify and commit**

```bash
npm test -- --runInBand src/components/ui/__tests__/PersistentNavigationCapsule.test.ts
npm run typecheck
npm run verify:design-system
git add mobile/src/components/ui/PersistentNavigationCapsule* mobile/src/components/ui/__tests__/PersistentNavigationCapsule.test.ts mobile/src/components/ui/index.ts docs/design-system.md
git commit -m "feat(ds): add persistent navigation capsule"
```

---

### Task 4: Integrate uniform shell scale, capsule travel, and label handoff

**Files:**
- Modify: `mobile/src/components/ui/BottomNavBar.tsx`
- Modify: `mobile/src/navigation/bottomNavigation.ts`
- Test: `mobile/src/navigation/__tests__/bottomNavigation.test.ts`

**Interfaces:**
- Consumes: Task 2 model and Task 3 capsule.
- Produces: immediate routing plus interruptible persistent shell/capsule/content motion.

- [ ] **Step 1: Write failing motion-token tests**

```ts
expect(BOTTOM_NAVIGATION_FIGMA.shellMotion).toEqual({
  pressedScale: 1.12,
  pressDuration: 90,
  releaseDuration: 220,
  releaseDampingRatio: 0.78,
  releaseOverlapsTravel: true,
});
expect(BOTTOM_NAVIGATION_FIGMA.labelMotion).toEqual({
  enterScale: 0.94,
  enterTranslateX: -6,
  duration: 180,
});
```

- [ ] **Step 2: Verify RED**

Run the navigation test. Expected: FAIL because current shell motion uses unequal axes and no label token exists.

- [ ] **Step 3: Render stable destinations under one capsule**

Keep all three accessible inactive tap targets present. Position `PersistentNavigationCapsule` absolutely above them. Every target calls:

```ts
const navigateTo = (item: BottomNavigationItem) => {
  transitionRef.current = startBottomNavigationTransition(transitionRef.current, item.id);
  setMotionState(transitionRef.current);
  router.navigate(item.path as never);
  beginCapsuleTransition(item.id);
};
```

Updating phase before routing removes grey in the same interaction frame.

- [ ] **Step 4: Replace unequal axes with uniform shell scale**

Use one `shellScale` shared value:

```ts
shellScale.value = reduceMotion ? 1 : withTiming(1.12, {
  duration: 140,
  easing: Easing.bezier(0.23, 1, 0.32, 1),
});
```

Do not release on `onPressOut`; begin the 220ms return immediately after the 90ms press peak so it overlaps the capsule spring.

- [ ] **Step 5: Animate capsule position and resting width**

```ts
capsuleX.value = withSpring(frame.x, {
  duration: 220,
  dampingRatio: 0.78,
}, (finished) => {
  if (finished) runOnJS(finishCapsuleTransition)(destination);
});
capsuleWidth.value = withTiming(frame.width, {
  duration: 220,
  easing: Easing.bezier(0.77, 0, 0.175, 1),
});
```

`finishCapsuleTransition` compares the completed destination to the latest transition ref. Ignore stale completions. The valid completion settles state and restores grey fill; `shellScale` is already returning to `1.00` concurrently with travel.

- [ ] **Step 6: Animate label handoff from the icon**

Keep outgoing/incoming content layers only during travel. Incoming label begins at opacity 0, scale 0.94, and translateX -6, then reaches resting values in 180ms. Outgoing label uses the inverse motion toward its icon. Do not animate font size or padding.

- [ ] **Step 7: Add reduced-motion behavior**

Assign destination X/width immediately, keep shell scale 1, and animate only 180ms content/fill opacity. Call the same guarded finish function.

- [ ] **Step 8: Verify and commit**

```bash
npm test -- --runInBand src/navigation/__tests__/bottomNavigation.test.ts src/components/ui/__tests__/PersistentNavigationCapsule.test.ts
npm run typecheck
npm run verify:design-system
git diff --check
rg -n "scaleX|scaleY" mobile/src/components/ui/BottomNavBar.tsx
```

Expected: all checks pass and the final search finds no shell press transform using separate axes.

```bash
git add mobile/src/components/ui/BottomNavBar.tsx mobile/src/navigation/bottomNavigation.ts mobile/src/navigation/__tests__/bottomNavigation.test.ts
git commit -m "feat: animate persistent navigation capsule"
```

---

### Task 5: Full verification and paired-iPhone QA gate

**Files:**
- Modify: `docs/features/current-experience-consolidation-qa.md`
- Modify: `docs/workflow.md`
- Modify: this plan status

**Interfaces:**
- Produces: automated evidence and explicit Baah device-QA checklist; no Ship claim.

- [x] **Step 1: Run complete verification**

From `mobile/`:

```bash
npm test -- --runInBand
npm run typecheck
npm run verify:design-system
```

From repository root:

```bash
npm run verify:workflow
bash scripts/audit-current-experience.sh
git diff --check
```

- [x] **Step 2: Relaunch the paired iPhone**

Verify Metro, then relaunch `com.taisa.app` on `CB2D8D19-B858-55E5-A24E-3BC7AD31441D`. Process launch alone is not visual proof.

- [x] **Step 3: Record the exact device checklist**

```markdown
- [ ] On touch-down, the entire glass pill scales uniformly to 1.12 without a second capsule scale; neither stretches or squashes.
- [ ] Capsule is plain glass during travel and restores 6% grey only after settlement.
- [ ] Capsule visibly moves Home ↔ Chats ↔ Me while route content changes immediately.
- [ ] Destination label emerges from its icon; old label returns toward its icon.
- [ ] Rapid retargeting redirects smoothly without grey flashes or scale reset.
- [ ] Reduced Motion removes spatial/scale motion and preserves short crossfades.
```

- [x] **Step 4: Update status and commit evidence**

After automated checks pass, set Active Work to `Review + QA` and this plan to `Complete — awaiting Baah device QA`.

```bash
git add docs/features/current-experience-consolidation-qa.md docs/workflow.md docs/superpowers/plans/2026-08-19-persistent-navigation-capsule-motion.md
git commit -m "docs: record persistent navigation motion verification"
```

- [x] **Step 5: Stop at device QA**

Present the running build. Do not push, open a PR, merge, or clean branches until Baah explicitly approves Ship.
