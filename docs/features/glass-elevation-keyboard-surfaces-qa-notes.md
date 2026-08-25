# Glass Elevation and Keyboard Surfaces QA Notes

## 2026-08-20 — interaction alignment and tactile feedback

Device QA found that child content inside the native glass material was positioned at the material
origin, displacing the record waveform, and that the selected navigation capsule appeared one pixel
low. Baah also approved an explicit **Go back** action in destructive sheets and a restrained haptic
hierarchy for accepted recording, send, dismiss, pause/resume, page-selection, and destructive actions.

The correction passed 71 mobile suites / 601 tests, TypeScript, the 30-module design-system verifier,
and the button-surface verifier. The next gate is canonical preview publication followed by Baah
device QA.

## 2026-08-20 — recording dismissed immediately after start

Device QA exposed a synchronous native-haptic failure escaping into the recorder start lifecycle.
The existing catch interpreted that optional feedback failure as a microphone-start failure and
closed a fresh recording route. The haptic boundary now absorbs both synchronous native throws and
asynchronous rejections; tactile feedback can no longer fail the product action. A regression test
reproduces the native throw. Verification passes 71 mobile suites / 604 tests, TypeScript, the
design-system verifier, and the button-surface verifier.
