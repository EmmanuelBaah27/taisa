# Task 10 — Encrypted recovery and device privacy (ungated slice)

## Status

DONE_WITH_CONCERNS — the code-only encrypted recovery, deterministic redaction, optional device
unlock, app-switcher shielding, generic notifications, minimal You-tab controls, and canonical
documentation are implemented and pass the available automated checks. Task 10 Step 4 native
recovery/privacy QA and Step 6 legacy route retirement were deliberately not run. The feature is
not ready to Ship before the managed iPhone development-build evidence and Baah's later explicit
cutover approval.

## Scope reconciliation

- Task 7 remains removed. No migration endpoint, migration token, backend export, dual-authority
  flow, or legacy-data import was added; Baah has no backend archive that needs migration.
- `backend/src/index.ts` is unchanged. Profile, entries, analyze, reviews, goals, action-items,
  trajectory, notifications, chat, and today routes remain mounted as BUILD rollback compatibility.
  Verified encrypted recovery plus explicit Baah cutover approval are required before unmounting.
- No Expo prebuild, native/iOS/cloud build, simulator, physical-device action, live coaching,
  transcription, or provider request occurred. `mobile/.env` was not read or inspected.
- This slice adds only minimal You-tab export/restore/app-lock actions and a root privacy shield. It
  does not redesign the product UI or add the future visual redaction-selection experience.

## Changed behavior

### Encrypted export and rollback-safe restore

- `mobile/src/services/exportArchive.ts` provides injected filesystem, SQLCipher, lifecycle,
  secure-key, and hashing boundaries. Export requires a separate confirmed passphrase with at least
  12 non-whitespace characters; the device database key is never used as the backup passphrase or
  written into the backup.
- Export uses parameter-bound SQLCipher `ATTACH ... KEY`, `sqlcipher_export`, and `DETACH`. The
  encrypted manifest contains archive/schema versions, exact entity counts, and a deterministic
  SHA-256 content fingerprint.
- Restore stages the selected archive, rejects wrong passphrases/corruption/newer schemas/low-space
  conditions before promotion, validates SQLite integrity and message/evidence FTS alignment, and
  re-encrypts a verified candidate with the existing device-only key.
- The backup-only manifest is verified and then removed from the device candidate before promotion.
  This prevents a restored active database from colliding with manifest creation on its next export.
- The active database is checkpointed and closed only after candidate validation. A preserved
  original plus durable promotion marker makes interruption rollback-safe; startup recovery gives
  the original precedence until promoted counts/hash verify and the marker is committed.
- Local capture-service handles are invalidated before replacement and the database is reopened
  after successful verification or rollback. Temporary input/candidate artifacts are cleaned.
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
  offsets; rejects surrogate, combining-mark, variation-selector, emoji-modifier, and ZWJ splits;
  and requires numeric metrics.
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

Final self-review added two more RED/GREEN slices: a restored candidate initially retained the
backup-only manifest, and normalized archive errors retained the raw database failure as `cause`.
The implementation now removes the verified manifest before candidate promotion and discards raw
failure details from public/archive and privacy errors.

## Fresh automated verification

```bash
cd mobile && npm test -- --runInBand && npm run typecheck
```

Outcome: 26 suites / 267 tests passed; `tsc --noEmit` exited 0.

```bash
npm test --workspace=backend -- --runInBand
npm run build --workspace=backend
```

Outcome: 15 suites / 144 tests passed; backend `tsc` exited 0. The restricted sandbox first
returned `listen EPERM`; the fresh passing run used permission only for Supertest's temporary
localhost listener. It made no external/provider call.

```bash
npm run verify:workflow
git diff --check
git diff --exit-code -- backend/src/index.ts
```

Outcome: all exited 0; workflow verification passed and the legacy route mount file is unchanged.

## Gated actions not run and next approvals

Task 10 Step 4 was not run: no development build, physical-device export, clean-install removal,
restore, SQLCipher inspection, process-interruption exercise, search verification, Face ID flow,
app-switcher screenshot/timing check, lock-screen notification check, or Files/Share journey exists
as evidence yet. This is the next Baah approval gate.

Task 10 Step 6 was also not run. After Step 4 passes and a verified recovery export exists, Baah
must explicitly approve the authority cutover before a later change unmounts legacy routes. The
backend database remains the rollback artifact until Ship. There is no migration route to disable.

## Remaining concerns

- SQLCipher compilation, SQL grammar, Keychain behavior, filesystem interruption semantics, free
  space reporting, sharing/picking, and LocalAuthentication need the pending managed iPhone test.
- Manual export is not automatic backup or sync. A forgotten passphrase, an export left only in the
  app container, or loss/uninstall before copying it elsewhere can permanently lose the archive.
- The deterministic redaction engine is implemented and tested, but final selection/preview UI
  belongs to the later product-interface plan; its device QA row cannot pass through UI yet.
- The existing dependency-audit findings remain unresolved and should be handled in a separately
  scoped compatibility/security pass rather than an automatic audit rewrite.
