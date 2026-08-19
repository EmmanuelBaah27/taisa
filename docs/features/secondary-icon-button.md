# Secondary Icon Button

## What is it?

A reusable Design System icon button matching Figma node `414:706`, built separately from the recording page. It establishes the visual and motion treatment for compact secondary actions.

## Why now?

The recording experience needs pause, keyboard, and close actions that share one secondary hierarchy. Defining the primitive first prevents screen-specific copies and keeps future secondary icon actions consistent.

## Acceptance criteria

- [x] The button is a 56×56 circle with a 24px icon and 16px inset.
- [x] The surface uses the Figma translucent-white fill, subtle border, and soft shadow.
- [x] Pressing uses the navigation shell's fluid scale contract: 1 → 1.12 in 70ms, hold for 100ms, then return to 1 in 90ms.
- [x] Reduced-motion users receive an immediate, non-spatial interaction.
- [x] The API exposes an icon, accessibility label, disabled state, and press handler without business logic.
- [x] The component is exported, catalogued in Storybook, documented, and covered by focused tests.

## Platform dependencies

None. This is a presentation-only Product/Design System primitive.

## Out of scope

- Recording-page composition or recorder behavior.
- Text secondary buttons.
- Replacing unrelated existing controls.
