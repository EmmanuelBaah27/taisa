# Personal Device Lane Design

**Date:** 2026-10-06
**Status:** Approved in conversation by Baah on 2026-10-06
**Amends:** `docs/superpowers/specs/2026-10-04-swift-native-encrypted-sync-design.md`
**Scope:** `docs/features/swift-native-encrypted-sync.md`

## Intent

Baah needs to keep building and testing the native Taisa app on an iPhone and iPad without paying for Apple Developer Program membership now. A free Xcode Personal Team can sign ordinary device builds, but it cannot provision the approved iCloud, CloudKit, and remote-notification capabilities. The interim lane must therefore make weekly device installation predictable without weakening or deleting the completed CloudKit architecture.

Success means Xcode can install a stable local-only Taisa build on each registered device, reinstalling over the same bundle identifier preserves its app container, the UI never claims that the devices are synchronized, and encrypted database recovery can move data deliberately between devices once the planned snapshot work is complete.

## Build identity and isolation

Add a generated `Taisa-Personal` scheme and configuration with the stable bundle identifier `com.taisa.app.personal`. It is signed by Baah's Personal Team and has no iCloud container, CloudKit service, remote-notification entitlement, Associated Domains entitlement, or background remote-notification mode.

The Personal target links no live CloudKit adapter and cannot instantiate `CKContainer`. It uses an explicit local-only sync capability whose status is unavailable, not a fake transport that reports successful synchronization. Preview remains deterministic and fake-only. Development and Production retain their existing CloudKit code, bundle identities, and entitlements for future paid-team activation.

Installing a new Personal build over the existing `com.taisa.app.personal` installation is the supported weekly refresh path. Deleting the app, changing its bundle identifier, or installing a conflicting identity may remove access to local data; the product and QA instructions must say this directly. A provisioning profile expiring must not be described as data deletion.

## Local data and recovery

The Personal build keeps the same SQLCipher store, device-protected Keychain database key, typed repositories, merge rules, recovery-key vault, and content-free diagnostics as the full encrypted-sync build. Cloud unavailability never blocks local reads or writes.

The existing snapshot task is adapted to support an explicit portable-file transport before any CloudKit snapshot upload is required. A manual backup:

- checkpoints the database and creates a versioned, authenticated, database-only archive;
- excludes recordings, temporary audio, and unfinished work that still depends on audio files;
- encrypts recovery material with the generated Taisa recovery key rather than introducing a second routine backup password;
- is exported through the system document/share flow to Files, AirDrop, or another destination chosen by Baah;
- never claims that choosing iCloud Drive in the Files interface provides live synchronization.

A receiving device imports the selected archive into a candidate store. It requires the recovery key, authenticates and validates the manifest, checks compatibility and space, verifies counts and hashes, and asks for explicit replacement confirmation. Only a fully verified candidate may atomically replace the active store. Every failure preserves the active database and its Keychain key.

Manual transfer is one-way at a time. It does not merge two independently edited device histories and must warn before replacing newer or divergent local data. Until paid CloudKit provisioning exists, Baah should treat one device as authoritative before exporting and avoid editing both copies between transfers.

## User-visible behavior

Personal builds show a truthful local-only state such as “Stored securely on this device.” They may offer **Back Up Now**, **Export Encrypted Backup**, and **Restore Backup** once snapshot UI is implemented. They do not show “Up to date,” “Syncing,” device enrollment, device removal, or CloudKit account errors because those states imply a live transport.

The recovery key remains the primary recovery secret and follows the already approved Passwords/manual-save ceremony. Export never embeds the recovery key in plaintext or displays it outside an authenticated recovery ceremony.

## Verification

Automated checks must prove:

- project generation is deterministic and includes the Personal scheme;
- Personal build products contain none of the CloudKit, iCloud, push, Associated Domains, or remote-notification capabilities;
- Personal products do not link or instantiate the live CloudKit adapter;
- Development and Production capability files remain unchanged;
- local encrypted storage and recovery-key tests pass under the Personal configuration;
- snapshot export rejects pending audio, wrong keys, tampering, incompatible schemas, insufficient space, and interrupted promotion without damaging the active store;
- archive fixtures and diagnostics contain no plaintext canaries or keys.

Physical-device QA installs the same Personal bundle identifier over itself on both devices, verifies launch and local persistence after a signing refresh, and exercises export from one device and verified restore on the other. Device QA must not delete the installed app before the persistence check.

## Deferred work

This lane does not satisfy the original automatic iPhone–iPad synchronization acceptance criterion. Live CloudKit provisioning, notification delivery, multi-device enrollment, cryptographic device removal, and production schema promotion remain deferred until Baah has an active Apple Developer Program team. The completed transport stays tested and dormant; it is not rewritten or removed.

Custom Taisa sync, third-party signing services, background peer-to-peer sync, and presenting Preview's fake transport to Baah as real sync remain out of scope.
