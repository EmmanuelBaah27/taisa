# SwiftUI Functional Home — Device Matrix

**Status:** Pending exact signed candidate
**Required gate:** Baah device approval before Ship

Record the candidate SHA, signed-build record, device model, OS version, result, and notes for every applicable row. Do not reuse evidence from another revision.

| Area | iPhone | Required observation |
|---|---|---|
| Exact launch | Pending | Installed build identity matches candidate. Home is the ordinary root. |
| Empty store | Pending | Native empty state is clear and non-error-like. |
| Populated Home | Pending | Conversations, active goals, and open actions are ordered and readable. |
| This Week | Pending | Weekly work, carry-over review, completion, undo, and replanning remain reachable. |
| Lead insight | Pending | At most one grounded lead insight appears and opens the nested Insights destination. |
| Insights | Pending | Current, Needs review, and History remain nested. Sources and Revisions are inspectable. |
| Refresh success | Pending | Existing content remains visible during refresh. |
| Refresh failure | Pending | Existing content remains. Retry is reachable. |
| Recovery routing | Pending | An unsafe store state opens recovery without replacing local data. |
| Dynamic Type | Pending | The largest accessibility size remains readable and operable. |
| VoiceOver | Pending | Sections, rows, retry, refresh, and recovery have useful labels and order. |
| Increased contrast | Pending | Meaning does not depend on low-contrast decoration. |
| Reduce Motion | Pending | All functionality remains available without spatial motion. |
| Reduced transparency | Pending | Native materials remain legible. |
| Compact iPhone width | Pending | Rows wrap and actions remain reachable without horizontal scrolling. |
| Offline behavior | Pending | Local Home loads and refresh failure remains safe. |
| Background/foreground | Pending | No duplicate load, stale overwrite, or unintended recovery route occurs. |

## Automated evidence available before device QA

- Home query ordering, limits, tombstones, empty state, and safe errors.
- Home model loading, content, refresh, retry, cancellation, and stale-result rejection.
- iPhone simulator launch and native empty state.
- iPhone simulator Accessibility XXXL, compact-width content, retry, and recovery reachability.
- Deterministic synthetic preview states with no Keychain, SQLCipher, CloudKit, network, or production content.
