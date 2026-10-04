# Native Apple Signed-Build Records

Signed records are append-only evidence for physical-device QA. A record is valid only when the commit embedded in the installed app matches the clean candidate revision and the expected environment bundle identifier.

Validate a JSON record with:

```sh
node apple/scripts/record-signed-build.mjs path/to/record.json
```

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

The development and preview bundle identifiers are separate from `com.taisa.app`, so these installations do not overwrite the existing production React Native app.
