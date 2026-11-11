# Domain docs

Start with `docs/project-memory.md`. It routes agents to Taisa’s canonical domain documents, accepted decisions, and reusable learnings.

Taisa uses a multi-context glossary layout when glossaries become necessary:

- `GLOSSARY-MAP.md`: routes topics to relevant contexts.
- `apple/GLOSSARY.md`: shipping SwiftUI product.
- `backend/GLOSSARY.md`: backend and hosted gateway.
- `shared/GLOSSARY.md`: shared contracts.
- `mobile/GLOSSARY.md`: legacy React Native migration source.
- `docs/adr/`: system-wide decisions.
- `<context>/docs/adr/`: context-specific decisions.

Read only the glossary and ADR material relevant to the active issue.

If these files do not exist, proceed silently. Create them lazily when domain terminology or a consequential decision is actually resolved.

Canonical domain documents remain authoritative for current behavior. Linear remains authoritative for live work and approvals. Surface contradictions before changing product code.
