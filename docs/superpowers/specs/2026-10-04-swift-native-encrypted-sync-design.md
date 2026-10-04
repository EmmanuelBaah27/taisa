# Swift Native Encrypted Storage, Sync, and Recovery Design

**Date:** 2026-10-04  
**Status:** Proposed for Baah review  
**Scope:** `docs/features/swift-native-encrypted-sync.md`

## Intent

Taisa must remain private, local-first, and usable offline while Baah moves naturally between iPhone and iPad. Both devices use the same Apple Account. Changes made on either device synchronize automatically without a Taisa account, and disaster recovery remains possible with a separately stored recovery key.

Success means encryption and synchronization are invisible during normal work, private content is never uploaded in readable form, competing edits are never silently destroyed, and every destructive recovery operation fails safely.

## Threat model

Application-layer encryption protects readable career content against a CloudKit data disclosure, accidental server-side inspection, backup-file exposure, and access to the Apple Account without the Taisa recovery key. Device data protection and SQLCipher protect a lost, locked device.

It does not protect an unlocked compromised device, malicious code running with Taisa's entitlements, content visible while the app is open, traffic/size/timing metadata, or a person who obtains both the private iCloud container and recovery key. Saving the recovery key in Passwords is convenient but places both materials within the broader Apple Account recovery boundary; the separately confirmed offline copy protects against account/keychain loss, not account compromise. The setup flow states these limits without claiming absolute secrecy.

## Boundaries

This foundation stores and synchronizes database content only: profile, conversations, messages, goals, milestones, actions, evidence, governed memory, and the minimum opaque metadata required for synchronization. It excludes recordings, temporary audio, React Native/backend migration, sharing, collaboration, Android/web clients, and Taisa accounts.

The first transport is the user's private CloudKit database. The domain and repository layers use transport-neutral identifiers and interfaces so a later Taisa-account service can coexist with or replace CloudKit.

## Architecture

Each device owns a complete encrypted SQLCipher database. Product features use local repositories and never call CloudKit directly. A transactionally coupled change journal/outbox records every synchronizable mutation alongside the local write. A background sync coordinator encrypts queued changes, uploads them in bounded batches, consumes CloudKit zone changes, and applies decrypted remote changes through the same repository rules.

The system is divided into focused units:

- **Store coordinator:** opens SQLCipher, verifies key/integrity, runs migrations, and exposes transactional access.
- **Repositories:** implement domain reads/writes, stable IDs, versions, and deletion semantics.
- **Change journal:** atomically records local mutations and tracks acknowledgement/idempotency.
- **Vault:** owns cloud-content encryption, key wrapping, rotation, and authenticated envelopes.
- **Sync engine:** exchanges opaque envelopes through a transport protocol and applies deterministic merge rules.
- **CloudKit transport:** implements private-zone upload, fetch, tokens, retries, account state, and quota errors.
- **Conflict store:** preserves competing values and exposes explicit resolution without leaking plaintext to telemetry.
- **Snapshot service:** creates, uploads, lists, verifies, and restores bounded encrypted recovery snapshots.
- **Diagnostics:** reports content-free state transitions, counts, sizes, durations, schema versions, and error categories.

All UI-visible data comes from the local store. Cloud availability never sits on the critical path of typing, saving, navigation, or reading existing content.

## Keys and cryptography

The device-local SQLCipher key and cloud sync-vault key are separate:

- The SQLCipher key is random, stored in the device's data-protection Keychain, and never synchronized.
- The sync-vault key is random and encrypts cloud record payloads and snapshot key material.
- Taisa generates a high-entropy recovery key in readable groups. It is not a user-chosen password.
- A key-encryption key derived from the recovery key wraps the sync-vault key using authenticated encryption and explicit algorithm/version metadata.
- CloudKit stores the wrapped vault key, salt/context, version, and ciphertext, never the recovery key.

Before cloud sync is enabled, the user must confirm both that the recovery key was saved to the preferred Passwords provider and that a separate offline copy was made. The app cannot prove the offline copy remains safe and says so.

Saving to Passwords is user-initiated. The implementation plan must verify the deployment target's AuthenticationServices credential-saving API and associated-domain requirements. It must not silently substitute an app-private synchronizable Keychain item and claim that the user can see it in Passwords.

Recovery-key rotation creates a new wrapping key and re-wraps the same vault key after device authentication and recovery verification. Rotation does not require decrypting and re-encrypting every domain record. New recovery material invalidates the old wrapping envelope; existing unlocked devices receive the new envelope through an authenticated transition.

Cloud record payloads use authenticated encryption with unique nonces and associated data binding ciphertext to vault ID, opaque record ID, entity type, schema/envelope version, and deletion state. The plan selects only Apple-supported audited primitives; it does not invent cryptography.

## Cloud representation and metadata

CloudKit uses a private custom zone. Domain content is an opaque encrypted payload. Server-visible fields are limited to what synchronization requires: opaque stable ID, opaque vault/device identifiers, entity/envelope version, change ordering metadata, tombstone state, and ciphertext asset/size.

Names, messages, transcripts, goals, actions, evidence, memory, conflict values, keys, and recovery material never appear as plaintext record fields, names, logs, notifications, analytics, or diagnostics. Documentation discloses that Apple can still observe account association, access timing, approximate record sizes/counts, device/network metadata, and other service-level metadata.

CloudKit change tokens and subscriptions are transport details. Losing or expiring a token triggers a bounded reconciliation, not deletion or a full blind overwrite.

## Data flow

For a local mutation:

1. The repository validates the mutation and assigns stable client IDs and logical version data.
2. One SQL transaction writes the domain state and encrypted outbox entry.
3. The UI observes the committed local state immediately.
4. The sync engine coalesces safe superseded updates, encrypts envelopes off the main actor, and uploads a bounded batch.
5. Acknowledgement advances outbox state idempotently; crashes can replay without duplicate domain effects.

For a remote mutation:

1. The transport downloads changed opaque records using the last durable token.
2. The vault authenticates and decrypts each envelope before any domain write.
3. Unsupported, malformed, or unauthenticated records are quarantined and surfaced as recovery errors.
4. The merge engine applies records transactionally and advances the durable token only after the batch commits.
5. Local observers render the updated store.

Network loss, process termination, duplicated delivery, partial batches, and out-of-order arrival are expected states.

## Merge and conflict policy

Messages and immutable history are append-only and merge by stable ID. Duplicate delivery is idempotent. Editable entities track field-level change ancestry sufficient to distinguish non-overlapping changes from competing changes without exposing field contents to CloudKit.

- Non-overlapping edits merge automatically.
- Same-field concurrent edits preserve both values in the encrypted conflict store.
- Conflict resolution is an explicit new mutation referencing both ancestors.
- Deletions create tombstones; an offline stale update cannot silently resurrect deleted content.
- Delete-versus-edit preserves the edit as a conflict and keeps the item deleted until the user chooses.
- Tombstones are retained until every known device has advanced beyond the deletion plus a conservative retention window defined in the plan.

The design optimizes for rare, explicit conflict review rather than last-write-wins data loss.

## Snapshots and restore

Live record sync and disaster-recovery snapshots are separate. A snapshot is a consistent, database-only encrypted archive created after checkpointing the local store. It never contains audio or temporary files. Taisa creates snapshots periodically, before schema migrations, and before high-risk recovery operations, subject to bounded retention and iCloud quota.

Each snapshot includes authenticated manifest data: vault ID, source device, creation time, database schema, envelope version, application/build compatibility, logical high-water marks, entity counts, hashes, and encrypted archive size. Private content and descriptive titles remain encrypted.

Restore is candidate-based:

1. Download to a temporary location.
2. Require and validate the recovery key before unwrapping vault material.
3. Authenticate the manifest/archive, check schema/application compatibility, and verify integrity and expected counts.
4. Build and migrate a candidate local store without touching the active store.
5. Require explicit confirmation if local data would be replaced.
6. Atomically promote the candidate only after every check succeeds.
7. Preserve the active database, device key, and recovery options on every failure.

Snapshots are versioned and bounded. Exact retention counts, cadence, size limits, and quota behavior are measured and fixed at the Plan gate rather than guessed in this design.

## Device enrollment and recovery

A first device creates the local store, vault, and recovery key. Cloud sync remains disabled until Passwords and offline-copy confirmations are complete.

A subsequent device discovers only opaque vault metadata in the same Apple Account's private CloudKit database. It must provide the recovery key, authenticate the wrapped vault, establish its own device-local SQLCipher key, restore or synchronize into a candidate store, and register an opaque device identity.

Apple Account access alone is insufficient to decrypt Taisa content. Conversely, a recovery key without access to the private CloudKit container does not grant cloud access. An already unlocked device can rotate recovery material. If every usable device and the recovery key are lost, Taisa cannot recover the encrypted content.

Ordinary device removal stops future sync registration and removes the device from tombstone/acknowledgement tracking after conservative reconciliation. It cannot revoke a vault key or erase data already copied or decrypted on that device. Cryptographic revocation is a separate explicit “remove and rotate vault” operation that rotates the vault key and re-encrypts current cloud records/snapshots before the removed device is considered excluded. The plan must make this expensive operation resumable and must not claim revocation until re-encryption is verified.

## User-visible states

The narrow foundation UI supports setup, recovery, sync status, conflicts, snapshots, and destructive confirmations using the native design system. It exposes only actionable states:

- Up to date
- Syncing
- Offline—changes saved locally
- iCloud unavailable or account changed
- iCloud storage full
- Recovery key required
- Conflicts need review
- Backup needs attention
- Restore or migration in progress

Normal network failure never blocks local work. Setup explains the recovery key before showing it, prevents screenshots/background exposure where supported, requires confirmation of both storage paths, and never logs or re-displays the key after the setup/rotation ceremony without fresh device authentication.

## Failure handling

Typed errors distinguish local key missing, local corruption, migration failure, vault authentication failure, wrong recovery key, malformed envelope, unsupported version, CloudKit unavailable, no account, account changed, quota, permission, token expiry, retryable transport, conflict, snapshot corruption, and insufficient local storage.

Unknown local integrity or key state fails closed. Taisa never generates a replacement key over an unreadable database, resets a cloud vault automatically, discards an outbox, replaces local data from cloud, or deletes a candidate/active store before preservation requirements are met.

Retries use bounded exponential backoff and respect system conditions. Diagnostics remain content-free and may include opaque IDs, state transitions, counts, byte sizes, durations, schema/envelope versions, and error categories only.

## Performance and lifecycle

Local persistence remains the interaction path. Encryption, envelope construction, CloudKit work, reconciliation, snapshot creation, and integrity scans run away from the main actor and use bounded memory/batches. Sync reacts to local work, CloudKit notifications, lifecycle opportunities, and explicit refresh; it does not continuously poll.

The implementation plan establishes measured pass thresholds on the registered iPhone and iPad for database open/migration, local save acknowledgement, incremental encryption/upload/download/apply, large initial restore, conflict reconciliation, snapshot creation/restore, peak memory, UI responsiveness, network transfer, and battery impact. Until measurements exist, this design does not invent numeric budgets.

## Verification

Deterministic unit and integration tests cover:

- SQLCipher open, missing-key refusal, integrity, and forward migration;
- recovery-key setup, wrong key, tampering, rotation, and envelope-version rejection;
- transactional outbox, crash/replay, duplicate delivery, ordering, batching, and token advancement;
- append merges, field merges, same-field conflict preservation/resolution, delete-versus-edit, and tombstones;
- CloudKit states through a transport fake: offline, account change, quota, token expiry, partial failure, and malformed records;
- consistent snapshots, bounded retention, corruption, incompatible schemas, insufficient storage, interrupted restore, and atomic rollback;
- content-free logs, diagnostics, notifications, and background/app-switcher protection.

Exact signed device QA uses the registered iPhone and iPad and verifies independent offline edits, reconnect synchronization, duplicate-free messages, explicit conflict review, deletion propagation, Passwords-assisted enrollment, denial without the recovery key, key rotation, snapshot restore, interruption recovery, iCloud unavailability, privacy, accessibility, and measured performance.

The complete native verification gate remains required. Missing CloudKit development/production schema, entitlements, physical-device evidence, or content-safety checks is a reported blocker, never treated as a passing test.

## Deployment and evolution

Development, preview, and production use distinct CloudKit containers or isolated environments with no fixture leakage into production. CloudKit schema promotion is explicit and verified before distribution. Preview scenarios use deterministic fakes and never access a real private database.

Domain IDs, repository contracts, encrypted envelope versions, merge rules, and change-journal semantics do not depend on Apple Account identifiers. A future Taisa account can introduce another authenticated transport and cross-platform key-distribution design without replacing the local store or product repositories. That future change requires its own scope, threat model, migration, and approval.

## Alternatives rejected

- **Whole encrypted database in iCloud Drive:** rejected for live multi-device use because simultaneous copies cannot merge safely and user file operations can disrupt automatic recovery.
- **Whole-database CloudKit snapshots as synchronization:** rejected because every edit becomes a destructive replacement race.
- **Custom Taisa encrypted-sync server now:** deferred because it requires accounts, device authorization, backend operations, and cross-platform recovery beyond the current need.
- **CloudKit-only encryption without a Taisa recovery key:** rejected because Apple Account access would be the sole content security boundary.
- **Silent last-write-wins:** rejected because career history is difficult to reconstruct after an overwrite.

## Approved decisions

- Same-Apple-Account iPhone/iPad synchronization is required.
- A generated recovery key is primary; it is saved to Passwords by explicit user action and copied offline.
- Sync remains disabled until both recovery-storage confirmations are complete.
- Database content is included; audio is excluded.
- CloudKit encrypted records provide live synchronization; versioned snapshots provide disaster recovery.
- Rare same-field conflicts are explicit and preserve both values.
- Taisa accounts and cross-platform sync remain future work, with transport-neutral interfaces preserved now.
