# Swift Native Encrypted Storage, Sync, and Recovery

**Tier:** Full  
**Track:** Platform  
**Stage:** Scope  
**Depends on:** accepted Swift native foundation

## What is it?

A native Apple data foundation that keeps Taisa's durable career data encrypted locally, synchronizes end-to-end encrypted records between an iPhone and iPad using the same Apple Account, and provides versioned encrypted disaster-recovery snapshots.

Each device remains fully usable offline. Product features read and write only through local repositories; CloudKit is a replaceable synchronization transport rather than the product's data model. A generated recovery key is the primary way to authorize a new device or restore a backup.

## Why now?

The native shell, build identities, preview lane, contracts, and exact-build device QA are proven. Every real product slice will depend on durable private data. Establishing encryption, synchronization, conflicts, migrations, and recovery first prevents each screen from inventing incompatible storage behavior.

Baah uses both iPhone and iPad, so backup-only behavior is insufficient. The foundation must synchronize both devices without requiring a Taisa account while retaining a path to a future Taisa-account transport.

## Acceptance criteria

- [ ] A fresh device creates an encrypted local store with its database key protected by device Keychain.
- [ ] Taisa generates a high-entropy recovery key and keeps cloud sync disabled until the user confirms saving it in Passwords and making a separate offline copy.
- [ ] Private data is encrypted on-device before entering the user's private CloudKit database; neither Apple-visible payloads nor Taisa infrastructure contain readable career content.
- [ ] Profile, conversations, messages, goals, milestones, actions, evidence, governed memory, and required sync metadata work offline and synchronize incrementally between the registered iPhone and iPad.
- [ ] Local writes commit immediately and queue sync atomically; network or iCloud failure never loses accepted local work.
- [ ] Immutable history merges without duplication, non-overlapping edits merge, same-field conflicts preserve both values for explicit review, and tombstones prevent deleted records from reappearing.
- [ ] A device cannot decrypt synchronized data or recovery snapshots without the recovery key.
- [ ] Recovery-key rotation preserves data and prevents the old key from authorizing future recovery material.
- [ ] Versioned database-only snapshots are authenticated, bounded, and restorable without including recordings or temporary audio.
- [ ] Restore validates key, integrity, schema, and expected data before atomic promotion; every failure preserves the active local store.
- [ ] iCloud sign-out/account change, quota exhaustion, expired change tokens, interrupted transfers, malformed records, incompatible schemas, keychain reset, and corrupted snapshots become typed recoverable states.
- [ ] Diagnostics and logs remain content-free.
- [ ] Exact signed builds pass automated and physical-device encryption, offline, synchronization, conflict, deletion, restore, rotation, privacy, and performance checks on the registered iPhone and iPad.
- [ ] Storage and sync interfaces do not embed Apple identity into domain records and can support a future Taisa-account transport without rebuilding product repositories.

## Platform dependencies

- Accepted Swift native foundation, deterministic project generation, build identity, preview isolation, and CI.
- Apple Developer capabilities for Keychain sharing/Password AutoFill as applicable, iCloud, and CloudKit development and production containers.
- A web-credentials associated domain if the system Passwords save API requires one for the final deployment target.

## Out of scope

- Taisa accounts, email login, server-managed identity, cross-Apple-Account sharing, collaboration, Android/web sync, or a custom Taisa sync server.
- Live multi-user editing.
- Recorded audio, temporary audio, attachment backup, or audio synchronization.
- Importing data from the React Native app or backend.
- Product-screen redesign beyond narrow setup, status, conflict, and recovery validation surfaces.
- Deleting React Native code, retiring backend routes, or changing the existing production app.
- Shipping later audio/streaming or advanced resources/platform-service foundations.

## Closeout

- **Actual outcome:** Pending implementation.
- **Plan deviations:** None yet.
- **Learnings and decisions:** Pending review.
- **Remaining debt:** Pending review.
- **Canonical docs updated:** Pending.
- **PR and merge evidence:** Pending.
