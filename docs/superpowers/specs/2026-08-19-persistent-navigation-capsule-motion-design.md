# Persistent Navigation Capsule Motion Design

**Status:** Approved in chat; awaiting written-spec review  
**Track:** Product + Design System  
**Branch:** `feature/current-experience`  
**Figma reference:** node `454:738`

## Purpose

Make tab changes feel fluid and spatially continuous. The selected state should read as one persistent capsule travelling between Home, Chats, and Me—not as separate selected components disappearing and reappearing.

This replaces the navigation's internal selected-state rendering model while preserving its approved resting geometry, typography, icons, destinations, glass treatment, and 6% black selected fill.

## Interaction

### Tap sequence

1. A destination receives the tap immediately.
2. The entire translucent navigation pill scales uniformly from `1.00` to `1.12`. It must never use unequal X/Y scaling.
3. The selected capsule's 6% black fill fades to transparent, making the moving capsule read as plain glass.
4. The screen navigates immediately; navigation does not wait for the motion to finish.
5. One persistent capsule springs horizontally from its current position to the destination frame.
6. The old label fades, scales down slightly, and moves toward its icon.
7. The destination label begins near the destination icon at `scale 0.94`, `translateX -6`, and low opacity, then moves and scales into its final position.
8. After the capsule settles, the 6% black fill fades back in and the entire navigation pill springs to `1.00`.

### Interruption

A second tap during motion redirects the current spring from its present position and velocity. The navigation pill must not reset to `1.00`, flash grey, or restart from the previous tab. The selected fill remains transparent until the final destination settles.

### Reduced motion

When reduced motion is enabled:

- do not scale or translate the navigation pill or capsule;
- change the capsule position immediately;
- use only a short fill and label crossfade;
- navigate immediately as in the standard path.

## Resting geometry

The final state must continue to match Figma:

| Destination | Shell | Item widths | Selected fill |
| --- | --- | --- | --- |
| Home | 240×60 | 108 / 56 / 56 | `rgba(15,16,16,0.06)` |
| Chats | 240×60 | 56 / 108 / 56 | `rgba(15,16,16,0.06)` |
| Me | 220×60 | 56 / 56 / 88 | `rgba(15,16,16,0.06)` |

Selected content remains a horizontal 24px icon, 8px gap, and Inter Medium 16/24 label. Inactive icons remain 24px Neutral/400. The Me destination continues to use the existing Navii avatar.

## Component architecture

`BottomNavBar` will own one persistent animated capsule and the navigation-level motion state. It remains mounted across tab route changes.

- **Stable destination layer:** three accessible tap targets and inactive visuals remain present beneath the capsule.
- **Persistent capsule layer:** one absolutely positioned selected surface moves between measured destination frames.
- **Selected content layer:** old and new icon-label content overlap only during the controlled transition; opacity, translation, and uniform scale create the handoff.
- **Glass shell layer:** the existing native glass/material fallback remains unchanged visually and receives only a uniform scale transform.

The navigation model will expose destination frames and motion constants as testable data. Screen-routing logic remains outside the design-system primitives.

## Motion constraints

- Animate transform and opacity wherever possible.
- The navigation pill uses uniform scale only.
- The moving selected capsule has no grey fill until settlement.
- Springs must be interruptible and preserve current velocity.
- No motion sequence may delay route navigation or block another tap.
- Avoid decorative neighboring-icon nudges, drag gestures, blur, haptics, or sound.

The exact spring stiffness/damping values may be tuned on the paired iPhone, but these observable behaviors and `1.12` pressed scale are fixed.

## Verification

Automated checks:

- destination-frame and motion-contract unit tests;
- rapid retargeting state tests;
- selected fill visibility tests for resting, travelling, and settled phases;
- reduced-motion behavior tests;
- mobile TypeScript and design-system verification.

Device QA:

- tap every direction, including Home → Me and Me → Home;
- tap again before the first motion settles;
- confirm the shell scales uniformly without approaching the recording control uncomfortably;
- confirm the capsule is plain glass while moving and grey only when settled;
- confirm the destination label visibly emerges from its icon;
- confirm route content changes immediately;
- confirm reduced-motion behavior on iPhone.

## Out of scope

- Drag-to-select navigation; the experimental drag implementation remains reverted.
- Page-title wording and safe-area correction; this is a separate screen-layout task.
- Changes to navigation destinations or route names.
- Changes to the recording button or its placement.
