# Task Detail Sheet Design

## Intent

Keep task inspection close to the list where the user found the task. A task tap opens detail without moving the user to another page.

## Approved behavior

- “View all tasks” is the only Home control that opens the Tasks page.
- Tapping a task on Home opens the task detail in a sheet.
- Tapping a task on the Tasks page opens the same sheet.
- The sheet starts at medium height and can expand to the large height by dragging.
- Closing the sheet returns to the page where it opened.
- Editing, checklist work, completion, reopening, and deletion use the existing task model.
- A successful deletion closes the sheet and refreshes the presenting page.
- Other task changes refresh the sheet and the presenting page.
- The detail surface follows Figma node `169:5268` for its title, due date, sub-task list, add action, completion action, archive action, and delete action.
- Sub-tasks can be completed from the row and deleted with a swipe action.

## Non-goals

- Do not create a second task detail implementation.
- Do not route through the Tasks page before presenting the sheet.
- Do not change task storage or lifecycle rules.
- Do not add feature-local sheet styling.

## Component inventory

| Element | Verdict | File or component |
|---|---|---|
| Expandable sheet presentation | New shared contract | `TaisaExpandableSheet` in `TaisaDesignSystem` |
| Task detail content | Replace presentation, reuse model | Shared compact task-detail presentation backed by `CareerWorkModel` |
| Sheet title | Extend shared typography | 20/28 Inter Medium semantic role |
| Base UI and button label | Reconcile shared typography | 16/24 Inter Regular or Medium semantic roles |
| Supporting text | Reconcile shared typography | 14/20 Inter Regular or Medium semantic roles |
| Caption | Reconcile shared typography | 12/18 Inter Regular or Medium semantic roles |
| Completion affordance | Extend semantic color | Shared completed/success color |
| Archive and delete group | New shared component | DS-owned grouped icon action capsule |
| Home task row | Modify interaction | `HomeActionsPreviewSection` |
| Tasks collection row | Modify interaction | `CareerWorkView` task collection |
| “View all tasks” row | Reuse | Existing `TaisaTaskSummaryRow` and `.actions` intent |

## Product architecture and states

```mermaid
flowchart TD
    H[Home task row] --> S[Shared task detail sheet]
    T[Tasks page task row] --> S
    V[View all tasks] --> T
    S --> M[Existing CareerWorkModel]
    M --> U[Due date, sub-tasks, complete, archive]
    M --> D[Delete task]
    U --> S
    D --> X[Dismiss sheet and refresh presenter]
```

The app shell owns Home sheet presentation because it already owns the shared `CareerWorkModel`. The Tasks page uses the same sheet presentation contract and the same detail component. Each presenter owns only the selected task identifier and sheet visibility.

## Design-system treatment

Keep the shared expandable-sheet contract. It owns medium and large presentation positions, a visible drag indicator, semantic background treatment, and standard dismissal behavior. Product views provide content and selection state.

Reconcile native typography with the approved type guide: base UI and buttons use 16/24, supporting text uses 14/20, and captions use 12/18. Add a 20/28 Inter Medium sheet-title role. Add a semantic completed/success color and one grouped icon action capsule for the archive and delete actions. The Product view consumes these contracts without raw visual values or feature-local substitutes.

## Accessibility

- The task row keeps its visible title as its activation label.
- The sheet announces the visible task title as its heading.
- The drag indicator remains visible.
- Dismissal restores focus to the task row when the system can restore it.
- Existing detail actions keep their current labels and touch targets.

## Backend implications

None. The local encrypted task model already loads and mutates task detail.

## Approaches considered

1. App-shell-owned shared sheet for Home plus the same contract on Tasks. Selected because it reuses one model and one detail surface.
2. A Home-owned task model. Rejected because it would duplicate state and refresh behavior.
3. Route to Tasks before opening detail. Rejected because it breaks the approved navigation rule.

## Constraints

- SwiftUI on iOS and iPadOS 26 or later.
- Design-system components, semantic tokens, and Central Icons only.
- No feature-local substitutes or raw visual values.
- Existing and imported task data must remain valid.

## Status

Behavior approved by Baah on 2026-11-19. Figma visual treatment and the 16/24, 14/20, and 12/18 typography reconciliation approved by Baah on 2026-11-19.
