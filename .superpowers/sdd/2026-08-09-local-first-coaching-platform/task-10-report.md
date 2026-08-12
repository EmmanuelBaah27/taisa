# Task 10 — Encrypted recovery and device privacy (ungated slice)

## Status

BUILD_FIX_VERIFIED — the ungated code-only recovery/privacy slice and its review fixes are
implemented and the complete available automated matrix passes. Task 10 Step 4 native
recovery/privacy QA and Step 6 legacy-route retirement were deliberately not run. The feature is
not ready to Ship before managed iPhone evidence and Baah's later separate route-retirement
approval.

## Scope reconciliation

- Task 7 remains removed. No migration endpoint, migration token, backend export, dual-authority
  flow, or legacy-data import was added; Baah has no backend archive that needs migration.
- `backend/src/index.ts` is unchanged. Profile, entries, analyze, reviews, goals, action-items,
  trajectory, notifications, chat, and today routes remain mounted as BUILD rollback compatibility.
  Verified encrypted recovery plus explicit Baah route-retirement approval are required before
  unmounting.
- No Expo prebuild, native/iOS/cloud build, simulator, physical-device action, live coaching,
  transcription, or provider request occurred. `mobile/.env` was not read or inspected.
- This slice adds only minimal You-tab export/restore/app-lock actions and a root privacy shield. It
  does not redesign the product UI or add the future visual redaction-selection experience.
- The approved plan is now explicitly reconciled: Task 7 is removed, no physical-device data
  migration is required, managed-device recovery/privacy QA is the next gate, and legacy-route
  retirement remains a later separately approved change.

## Changed behavior

### Encrypted export and rollback-safe restore

- `mobile/src/services/exportArchive.ts` provides injected filesystem, SQLCipher, lifecycle,
  secure-key, and hashing boundaries. Export requires a separate confirmed passphrase with at least
  12 non-whitespace characters; the device database key is never used as the backup passphrase or
  written into the backup.
- The encrypted export contains database state and completed transcripts, not recorded audio files.
  Before an export URI is allocated, export now fails content-safely if a nonterminal coaching
  request still references audio. The user must finish or abandon that voice work first.
- Export uses parameter-bound SQLCipher `ATTACH ... KEY`, `sqlcipher_export`, and `DETACH`. The
  encrypted manifest contains archive/schema versions, exact entity counts, and a deterministic
  SHA-256 content fingerprint.
- Restore stages the selected archive, rejects wrong passphrases/corruption/newer schemas/low-space
  conditions before promotion, validates SQLite integrity, foreign keys, exact allowlisted table
  mappings and ordinary object identities, exact counts/hash, and FTS5 external-content integrity.
- SQLCipher export writes the trusted current `user_version` onto the passphrase archive after
  `sqlcipher_export`, preventing a valid export from being rejected as schema version zero.
- Restore never promotes archive-owned schema. It creates a fresh device-key candidate using the
  trusted current migrations, reads the verified source through a query-only maintenance
  connection, and copies only explicit allowlisted columns with bound values. Trusted triggers
  rebuild search indexes; the backup-only manifest is never copied into the active candidate.
- The active database is checkpointed and closed only after candidate validation. A content-free
  marker records the preserved original's digest and size and is published through same-directory
  exclusive temporary creation plus atomic move. Startup recovery discards an
  uncommitted active candidate and its sidecars, copies (never consumes) the original back, verifies
  it, and removes the marker as the sole commit point. Repeating recovery after interruption at
  covered recovery and marker-publication boundaries converges safely.
- A database-wide maintenance coordinator rejects new operations and waits for existing scoped
  leases before checkpoint/close. Capture, transcription/coaching completion writes, profile, and
  conversation store operations hold tracked leases and cannot use a closed pre-restore handle.
- Export names contain cryptographic UUIDs and are reserved with exclusive no-overwrite creation.
  Temporary input/candidate files and sidecars are cleaned, with startup retry after interruption.
- The authoritative profile ID is discovered from the sole restored database profile. Zero profiles
  are initialized explicitly; archives with multiple profiles are rejected. The unrelated
  device/rate-limit installation ID has its own device-only SecureStore key.
- `mobile/src/services/archiveFileStore.ts` contains the Expo filesystem boundary and startup
  recovery marker protocol; `mobile/src/db/openDatabase.ts` invokes recovery before opening the
  encrypted database.

### Privacy controls

- `mobile/src/services/privacyGuard.ts` is a pure state machine around injected preference and
  device-authentication boundaries. It fails closed during preference loading, shields immediately
  on inactive/background transitions, remains locked after cancellation, and unshields only after
  successful authentication while active.
- Production stores only `1`/`0` in device-only SecureStore. iOS/Android owns biometric/passcode
  secrets through LocalAuthentication; no biometric material is stored by Taisa.
- `mobile/app/_layout.tsx` subscribes to AppState and covers the root view while private content
  must be hidden. `mobile/app/(tabs)/you.tsx` adds the optional lock switch and manual encrypted
  export/restore actions without a visual redesign.
- `mobile/src/services/notifications.ts` no longer requests personalized notification content from
  the backend. Scheduled reminders always contain only `Taisa`, `You have an open Taisa action`,
  and content-free navigation metadata.

### Deterministic submission redaction

- `mobile/src/services/redactSubmission.ts` copies and stably sorts user-selected name,
  organization, project, and metric ranges; validates integer/bounded/non-empty/non-overlapping
  offsets against runtime Unicode grapheme segmentation (including flags, Indic conjuncts, Hangul,
  ZWJ emoji, combining marks, and CRLF); fails closed if segmentation is unavailable; and requires
  numeric metrics.
- The replacement map is explicitly memory-only. `createRedactionPreview` returns the exact text
  shown to the user, and `confirmRedactionPreview` releases only that text after the
  `explicit-submit` action. No AI or network boundary is referenced.

## Installed API reconciliation

The implementation was checked against the installed Expo SDK 54 typings and source rather than
assuming a native API:

- Expo SQLite exposes `openDatabaseAsync(name, options?, directory?)`, `deleteDatabaseAsync`,
  parameterized `runAsync`, and the configured default database directory.
- Expo FileSystem exposes `File` picker/copy/move/delete/size operations and
  `Paths.availableDiskSpace` used by the boundary.
- Installed SQLCipher configuration is already enabled in `mobile/app.json`; LocalAuthentication
  was added as `expo-local-authentication@~17.0.8` with a Face ID usage description.

Unit/type evidence cannot prove native SQLCipher accepts the parameterized attachments, that the
platform filesystem completes the marker/move protocol across process interruption, or that Face
ID/shield timing and Files/Share behave correctly. Those remain explicit device checks rather than
being inferred from TypeScript.

Dependency installation used `npm install --ignore-scripts`; that reified `better-sqlite3` without
its local native binding, so `npm rebuild better-sqlite3` restored the existing test dependency
before verification. Installation reported 36 audit findings (2 low, 14 moderate, 18 high, 2
critical); no destructive or semver-major audit fix was applied.

## TDD evidence

Initial RED slices failed for missing recovery/redaction/privacy modules and notification privacy
behavior. Incremental failing cases then established:

- separate passphrase length/confirmation, counts/hash round trip, wrong/corrupt/newer archives,
  low space, interrupted promotion, promoted-fingerprint mismatch, and content-safe failures;
- background shielding, cancelled/successful unlock, unavailable authentication, boolean-only
  preference storage, and fail-closed preference reads;
- overlapping/invalid ranges, surrogate and combining-mark boundaries, metric validation, and
  explicit preview submission;
- content-free notifications with no backend personalization call.

Initial self-review added two more RED/GREEN slices: the first candidate design retained the
backup-only manifest, and normalized archive errors retained the raw database failure as `cause`.
The implementation no longer copies archive schema or the manifest into a candidate, and it
discards raw failure details from public/archive and privacy errors.

The fix round added RED/GREEN cases for exported `user_version`, pending audio rejection before
artifact allocation, trusted-schema import, foreign-key/FTS/mapped-column failures, exact profile
cardinality, interruption at every promotion-recovery file boundary, maintenance leases, restored
profile discovery, installation identity separation, exclusive UUID export reservation, UI
single-flight locking, post-commit cleanup interruption, Unicode grapheme validation, and failed
identity-load cleanup without unhandled promises.

Fix round 2 added real `better-sqlite3` RED/GREEN coverage for a nonempty relational archive whose
message parent and goal/action/memory supersession targets sort after their dependants. Import now
defers foreign keys transaction-wide and runs a final `foreign_key_check`. Real source and rebuilt
candidate corruption tests exercise FTS5's external-content comparison integrity mode rather than
reading through the content table. Crafted view, virtual-table, and unexpected-object archives are
rejected after `trusted_schema = OFF`; only ordinary tables with exact trusted object/column
identity are imported, and source `sqlite_schema.sql` is compared as inert text, never executed.
Real temporary-filesystem tests cover exclusive marker temp creation, write and atomic publication
interruptions, plus recovery from older empty/partial final markers. Secondary close, rollback, and
reopen failures surface only a cause-free `RESTORE_FAILED`, retain recovery artifacts, and never
reopen an unverified active database.

Fix round 4 narrows startup marker recovery further: only the exact empty marker that the previous
implementation could create before publication is treated as safely pre-promotion. Truncated JSON,
unknown JSON shapes or versions, and random content now throw a fixed cause-free
`ARCHIVE_PROMOTION_RECOVERY_REQUIRED` error while retaining the marker, rollback, active database,
sidecars, staged input, and candidate untouched. The exact legacy `restore-pending-v1` marker still
restores from the documented preserved rollback, and valid current JSON follows the verified
rollback protocol. Setup now consistently requires a development client rather than Expo Go, and
canonical docs distinguish local profile identity from the transport/rate-limit installation ID.

## Fresh automated verification

```bash
cd mobile && npm test -- --runInBand && npm run typecheck
```

Outcome: 30 suites / 317 tests passed; `tsc --noEmit` exited 0.

```bash
npm test --workspace=backend -- --runInBand
npm run build --workspace=backend
```

Outcome: 15 suites / 144 tests passed; backend `tsc` exited 0. The restricted sandbox first
returned `listen EPERM`; the passing rerun used permission only for Supertest's temporary localhost
listener. It made no external/provider call.

```bash
npm run verify:workflow
git diff --check
git diff --exit-code -- backend/src/index.ts
```

Outcome: all exited 0; workflow verification passed and the legacy route mount file is unchanged.
`git diff --check` is rerun immediately before commit as part of final branch verification.

## Gated actions not run and next approvals

Task 10 Step 4 was not run: no development build, physical-device export, clean-install removal,
restore, SQLCipher inspection, process-interruption exercise, search verification, Face ID flow,
app-switcher screenshot/timing check, lock-screen notification check, or Files/Share journey exists
as evidence yet. This is the next Baah approval gate.

Task 10 Step 6 was also not run. After Step 4 passes and a verified recovery export exists, Baah
must explicitly approve legacy-route retirement before a later change unmounts those routes. The
backend database remains the rollback artifact until Ship. There is no migration route to disable.

## Remaining concerns

- SQLCipher compilation, SQL grammar, Keychain behavior, filesystem interruption semantics, free
  space reporting, sharing/picking, and LocalAuthentication need the pending managed iPhone test.
- Manual export is not automatic backup or sync. A forgotten passphrase, an export left only in the
  app container, or loss/uninstall before copying it elsewhere can permanently lose the archive.
- The backup is database-only and never includes recorded audio files. Pending audio-backed voice
  work must be finished or abandoned before export; this guard still needs managed-device proof.
- JavaScript strings cannot be zeroized. The You screen clears retained passphrase/confirmation
  state immediately after capture and again after completion, but the immutable local operation
  string remains runtime-managed until garbage collection.
- The deterministic redaction engine is implemented and tested, but final selection/preview UI
  belongs to the later product-interface plan; its device QA row cannot pass through UI yet.
- The existing dependency-audit findings remain unresolved and should be handled in a separately
  scoped compatibility/security pass rather than an automatic audit rewrite.
