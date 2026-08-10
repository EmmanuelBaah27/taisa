# Local-First Cutover QA

## Encrypted database development-build gate

- [ ] Baah approves running the managed iPhone development-build verification step.
- [ ] Install and launch a development build containing the SQLCipher-enabled `expo-sqlite` module (unavailable in Expo Go).
- [ ] Create a local record and confirm it persists after force-quit and restart.
- [ ] Remove the SecureStore database key in a controlled test and confirm Taisa enters the recovery-required state instead of generating a replacement key.
- [ ] Confirm the SQLite file is unreadable without its SQLCipher key.

Status: pending. No prebuild, local native run, cloud/EAS build, simulator, or physical-device verification was performed during Task 5.
