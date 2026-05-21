---
name: motion
description: Use when implementing animations or transitions in Taisa — grounds decisions in Emil Kowalski's principles before writing animation code for React Native / Reanimated.
---

# Motion Animation — Taisa (React Native)

## Before any animation work

Read first:
- `.claude/skills/emil-design-eng/SKILL.md` — animation philosophy and decision framework

Apply the library mechanics below on top of those principles. Never invent duration or easing values.

---

## Stack

Taisa uses **React Native Reanimated v3** for animations. Not web Motion/Framer Motion. Not CSS.

```bash
# Already installed via Expo
# If not: cd mobile && npm install react-native-reanimated
```

Import pattern:
```tsx
import Animated, {
  useSharedValue,
  useAnimatedStyle,
  withTiming,
  withSpring,
  Easing,
} from 'react-native-reanimated';
```

---

## Token values (use these — never invent)

```ts
// Duration
const durations = {
  instant:  100,  // button press feedback
  fast:     150,  // tooltips, badges
  base:     200,  // dropdowns, small transitions
  moderate: 300,  // modals, drawers
  slow:     500,  // onboarding, celebrations
};

// Easing (map Emil's CSS curves to Reanimated)
const easings = {
  out:     Easing.bezier(0.23, 1, 0.32, 1),     // entering elements
  inOut:   Easing.bezier(0.77, 0, 0.175, 1),    // on-screen movement
  drawer:  Easing.bezier(0.32, 0.72, 0, 1),     // iOS-like drawer
};

// Springs (preferred over duration-based where possible)
const springs = {
  snappy:  { damping: 20, stiffness: 300 },
  smooth:  { damping: 20, stiffness: 200 },
  gentle:  { damping: 15, stiffness: 120 },
  bouncy:  { damping: 10, stiffness: 200 },
};
```

---

## Core patterns

### Fade + scale entry (never from scale 0)

```tsx
const opacity = useSharedValue(0);
const scale = useSharedValue(0.95);

const style = useAnimatedStyle(() => ({
  opacity: opacity.value,
  transform: [{ scale: scale.value }],
}));

// Trigger
opacity.value = withTiming(1, { duration: durations.base, easing: easings.out });
scale.value = withSpring(1, springs.smooth);
```

### Button press feedback

```tsx
const scale = useSharedValue(1);

const style = useAnimatedStyle(() => ({
  transform: [{ scale: scale.value }],
}));

<Animated.View style={style}>
  <Pressable
    onPressIn={() => { scale.value = withTiming(0.97, { duration: durations.instant }) }}
    onPressOut={() => { scale.value = withSpring(1, springs.snappy) }}
  />
</Animated.View>
```

### Slide in from bottom (modals, drawers)

```tsx
const translateY = useSharedValue(300);

const style = useAnimatedStyle(() => ({
  transform: [{ translateY: translateY.value }],
}));

// Open
translateY.value = withTiming(0, { duration: durations.moderate, easing: easings.drawer });

// Close (faster than open — Emil's asymmetric rule)
translateY.value = withTiming(300, { duration: durations.base, easing: easings.out });
```

### Stagger list items

```tsx
items.map((item, i) => {
  const opacity = useSharedValue(0);
  const translateY = useSharedValue(8);

  // Trigger on mount
  opacity.value = withDelay(i * 50, withTiming(1, { duration: durations.base, easing: easings.out }));
  translateY.value = withDelay(i * 50, withSpring(0, springs.smooth));
});
```

Keep stagger delay 30–80ms. Never block interaction during stagger.

---

## Reanimated vs Animated API

Always use Reanimated (`react-native-reanimated`), not React Native's built-in `Animated` API.

| | Built-in Animated | Reanimated v3 |
|---|---|---|
| Runs on | JS thread | UI thread |
| Drops frames under load | Yes | No |
| Springs | Limited | Full physics |
| Gesture integration | Manual | Native via `react-native-gesture-handler` |

---

## Gesture-driven animations

Use `react-native-gesture-handler` + Reanimated together:

```tsx
import { PanGestureHandler } from 'react-native-gesture-handler';
import { useAnimatedGestureHandler } from 'react-native-reanimated';

const translateY = useSharedValue(0);

const gestureHandler = useAnimatedGestureHandler({
  onActive: (event) => {
    translateY.value = event.translationY;
  },
  onEnd: (event) => {
    const velocity = Math.abs(event.translationY) / event.absoluteY;
    if (Math.abs(event.translationY) > 100 || velocity > 0.11) {
      // Dismiss
      translateY.value = withTiming(500, { duration: durations.base, easing: easings.out });
    } else {
      // Snap back
      translateY.value = withSpring(0, springs.snappy);
    }
  },
});
```

---

## Performance rules (React Native specific)

- **Always use `Animated.View`** — not regular `View` with animated styles
- **Avoid animating layout properties** (`width`, `height`, `padding`) — use `transform` and `opacity` only
- **`useSharedValue` runs on UI thread** — never call setState inside `useAnimatedStyle`
- **`runOnJS`** — to call JS functions from animated handlers: `runOnJS(setIsOpen)(false)`

---

## Accessibility

```tsx
import { useReducedMotion } from 'react-native-reanimated';

function AnimatedComponent() {
  const reduceMotion = useReducedMotion();

  const duration = reduceMotion ? 0 : durations.base;
  const translateY = reduceMotion ? 0 : 8;
}
```

---

## References

- `.claude/skills/emil-design-eng/SKILL.md` — full philosophy and decision framework
- Reanimated docs: https://docs.swmansion.com/react-native-reanimated/
