# SwiftUI Functional Home — Device Matrix

**Status:** Pending exact signed candidate
**Required gate:** Baah device approval before Ship

Record the candidate SHA, signed-build record, device model, OS version, result, and notes for every applicable row. Do not reuse evidence from another revision.

| Area | iPhone | iPad / window | Required observation |
|---|---|---|---|
| Exact launch | Pending | Pending | Installed build identity matches candidate; Home is ordinary root |
| Empty store | Pending | Pending | Native empty state is clear and non-error-like |
| Populated Home | Pending | Pending | Conversations, active goals, and open actions are ordered and readable |
| This Week | Pending | Pending | Weekly work, deliberate carry-over review, completion, undo, and replanning remain reachable |
| Lead insight | Pending | Pending | At most one grounded lead insight appears and opens the nested Insights destination |
| Insights | Pending | Pending | Current, Needs review, and History remain nested; Sources and Revisions are inspectable in detail |
| Refresh success | Pending | Pending | Existing content remains visible while refreshing |
| Refresh failure | Pending | Pending | Existing content remains; retry is reachable |
| Recovery routing | Pending | Pending | Unsafe store state opens recovery without replacing local data |
| Dynamic Type | Pending | Pending | Largest accessibility size remains readable and operable |
| VoiceOver | Pending | Pending | Sections, rows, retry, refresh, and recovery have useful labels/order |
| Increased contrast | Pending | Pending | Meaning does not depend on low-contrast decoration |
| Reduce Motion | Pending | Pending | All functionality remains available without spatial motion dependence |
| Reduced transparency | Pending | Pending | Native materials remain legible |
| Narrow iPad window | N/A | Pending | Rows wrap and actions remain reachable without horizontal scrolling |
| Offline behavior | Pending | Pending | Local Home loads and refresh failure remains safe |
| Background/foreground | Pending | Pending | No duplicate load, stale overwrite, or unintended recovery route |

## Automated evidence available before device QA

- Home query ordering, limits, tombstones, empty state, and safe errors.
- Home model loading, content, refresh, retry, cancellation, and stale-result rejection.
- iPhone simulator launch and native empty state.
- iPad simulator Accessibility XXXL, adaptable content, retry, and recovery reachability.
- Deterministic synthetic preview states with no Keychain, SQLCipher, CloudKit, network, or production content.
