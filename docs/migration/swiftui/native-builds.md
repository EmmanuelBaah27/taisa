# Native Apple Signed-Build Records

Signed records are append-only evidence for physical-device QA. A record is valid only when the commit embedded in the installed app matches the clean candidate revision and the expected environment bundle identifier.

Validate a JSON record with:

```sh
node apple/scripts/record-signed-build.mjs path/to/record.json
```

Personal records retain the complete evidence produced by the original live artifact
inspection. While the recorded app and embedded profile still exist, validation always
repeats the cryptographic and linkage inspection and rejects any retained evidence that
disagrees. After both temporary artifacts are unavailable, validation can check only the
retained attestation's structure and internal consistency; its output is explicitly
labelled `retained-attestation-only` and is not a substitute for live reinspection.

## 2026-10-03 — Native foundation candidate

Candidate revision: `c72eef6f7e5fba4d2607d45ebfe4a166b3ea8ac7` (`feature/swift-native-foundation`, clean)  
Xcode: `26.1.1` (`17B100`)  
App version/build: `1.0` (`1`)  
Contract/fixture revision: `transcription-fixtures-v1`  
Signing team: Emmanuel Baah Personal Team (`XH59HG6MSY`)  
Tester: Baah  
Acceptance: **passed — Baah confirmed both builds on both devices on 2026-10-04**

### iPhone 15 Pro

- Device: Beat's iPhone, iPhone 15 Pro (`00008130-000834AA34C2001C`)
- OS: iOS 26.6.1 (`23G83`)
- Development: `com.taisa.app.dev` — installed and launched
- Preview: `com.taisa.app.preview` — installed and launched
- Tester confirmation: passed; development shell, isolated preview catalog, required scenarios, readable accessibility text, centered iPad layout, and exact diagnostics confirmed

### iPad Pro 11-inch (4th generation)

- Device: Beat's iPad, iPad Pro 11-inch (4th generation) (`00008112-000C25CA0107401E`)
- OS: iOS 26.6.1 (`23G83`)
- Development: `com.taisa.app.dev` — installed and launched
- Preview: `com.taisa.app.preview` — installed and launched
- Tester confirmation: passed; development shell, isolated preview catalog, required scenarios, readable accessibility text, centered iPad layout, and exact diagnostics confirmed

The development, Preview, Personal, and production bundle identifiers remain distinct so test installations do not overwrite one another.

## 2026-10-06 — Personal encrypted recovery candidate

Candidate revision: `3184e9054f022514ad29603528b5093ddebc1222` (`feature/swift-native-encrypted-sync`, clean when signed)

- Xcode: `26.1.1` (`17B100`)
- App version/build: `1.0` (`1`)
- Bundle/environment: `com.taisa.app.personal` / `personal`
- Signing team: Emmanuel Baah Personal Team (`XH59HG6MSY`)
- Profile: `ceef9351-2080-45b2-ba3e-d390247426be`, expires 2026-10-13 14:41:05 UTC
- Tester: Baah
Acceptance: **passed — local encryption, install-over persistence, encrypted Files transfer, restore, and force-reopen were confirmed on 2026-10-06**

The iPhone was the authoritative source. Baah created one public QA canary, then the same signed identity was installed over the existing app without uninstalling. The record remained present with canary count 1, conversation count 1, and SHA-256 `ccec885e1c7c69364095415e88d75bb0736224accdb5dad95d9905ba47898d64`.

The iPad was first inspected as a clean receiver with zero canaries and zero conversations. It restored the encrypted `.taisa-backup` transferred through Files using the separately stored recovery key. After replacement and a forced close/reopen, it reported the same counts and SHA-256. Both apps reported **Stored securely on this device**.

Artifact inspection verified the exact bundle, environment, candidate commit, explicit authorization for both device UDIDs, Apple Development signer certificate/profile binding, and all four Mach-O images. The signed app and profile contained no iCloud, CloudKit, push, Associated Domains, background mode, or live-transport linkage. This is evidence for deliberate encrypted local transfer, not automatic synchronization.

Validated records:

- `native-build-records/2026-10-06-iphone-personal.json`
- `native-build-records/2026-10-06-ipad-personal.json`

### Weekly Personal Team refresh

Free Personal Team provisioning expires after about seven days; the recorded profile's actual expiry is authoritative. Rebuild and install `com.taisa.app.personal` **over the existing app with the same bundle identifier**. Never uninstall the Personal app as part of refresh because uninstalling removes its device-local container. Create a fresh encrypted backup and verify the recovery key before any risky device or signing change. If an install is blocked by the free-team three-app limit, remove another explicitly approved disposable development identity—not `com.taisa.app.personal`—only after confirming its data may be lost.

Files and AirDrop copy an encrypted snapshot; they do not merge histories. Choose one authoritative device, avoid editing both copies between transfers, and accept replacement on the receiving device only after verifying which copy is authoritative. The recovery key must remain separate from the backup, saved in Passwords and in a distinct offline copy.
# SwiftUI functional Home candidate

The candidate SHA is recorded only after final automated verification and review. Signed Personal builds must be produced from that exact clean revision and integrated into `preview/taisa` before Baah is asked to test.

Required evidence: bundle identity, signer, provisioning profile, embedded commit, iOS 26+ environment, entitlements, authorized iPhone/iPad UDIDs, and completed `docs/qa/swiftui-functional-home-device-matrix.md`. Simulator results do not satisfy the Ship gate.
