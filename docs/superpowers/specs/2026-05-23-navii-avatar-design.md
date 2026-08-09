# Navii Avatar — Design Spec

**Date:** 2026-05-23
**Status:** Approved

---

## What we're building

Replace the placeholder "T" circle avatar on the You screen with a real Navii mascot avatar. Also replace the `IconPeopleCircle` tab bar icon for the "You" tab with a smaller version of the same avatar. Both instances use the same seed, so the avatar is identical and personally consistent across the app.

---

## Locations changed

| Location | File | Current | After |
|---|---|---|---|
| You screen header | `mobile/app/(tabs)/you.tsx` | 40px "T" circle, inline row | 64px Navii, centered column |
| Tab bar — You tab | `mobile/src/components/ui/TopNavBar.tsx` | `IconPeopleCircle` icon | 22px Navii avatar |

---

## Avatar component

A new shared component `NaviiAvatar` lives at `mobile/src/components/ui/NaviiAvatar.tsx`.

**Props:**
```ts
interface NaviiAvatarProps {
  seed: string;
  size: number;
}
```

**Internals:**
- Calls `createAvatar(seed, { size })` from `@usenavii/core` to produce an SVG string
- Renders via `SvgXml` from `react-native-svg` (already installed)
- No state, no network — pure synchronous render

**Seed source:** `userId` from `expo-secure-store` (key `'userId'`). Currently the value is stored in SecureStore during `initUser` but not exposed in any Zustand store. The implementation adds `userId: string | null` to `careerStore` state: `initUser` sets it alongside the SecureStore write, and `fetchProfile` reads it from SecureStore on mount. Components then call `useCareerStore(s => s.userId)` — synchronous, no extra async in the render tree.

---

## You screen layout change

The header row shifts from a horizontal inline layout to a centered column:

**Before:**
```
[40px circle "T"] [Name]
                  [Role · N sessions]
```

**After:**
```
      [64px Navii]
       Name
       Role · N sessions
```

The rest of the screen (Taisa's read on you, Career context, Settings) is unchanged.

---

## Tab bar change

In `TopNavBar.tsx`, the `TABS` config passes an `icon` name to `TabButton`. The You tab currently uses `IconPeopleCircle`.

The `TabButton` component needs a small extension: if the tab id is `'you'`, render `<NaviiAvatar seed={userId} size={22} />` instead of `<Icon name={tab.icon} />`. The active/inactive colour logic (grey vs. black) doesn't apply to the Navii avatar — it always renders at full colour.

The `userId` is passed down from `TopNavBar` → `TabButton` as a prop.

---

## Dependency

`@usenavii/core` must be installed inside `mobile/`:

```bash
cd taisa/mobile && npm install @usenavii/core
```

`react-native-svg` (already installed) provides `SvgXml`.

---

## Out of scope

- Animation on the avatar (decided against — no Reanimated float)
- Changing avatar size on any screen other than You
- Any user-facing avatar picker or customisation
- Changing the avatar seed source (always device userId)

---

## Acceptance criteria

1. You screen shows a 64px Navii avatar centered above the user's name
2. Tab bar "You" tab shows a 22px Navii avatar in place of `IconPeopleCircle`
3. Both avatars show the same mascot (same seed)
4. App renders correctly with no network connection (offline-first)
5. No `StyleSheet.create()` introduced — NativeWind only
