# Swift native audio streaming — physical-device matrix

**Status:** Pending exact-build iPhone and iPad QA
**Privacy rule:** Record only the enumerated identifiers, pass/fail state, and bounded performance numbers. Never add audio, transcript, coaching, private-context, or filesystem-path fields.

## Procedure

1. Start from the reviewed commit integrated into `preview/taisa`; confirm the signed `Taisa-Personal` artifact and signed-build record identify that exact commit.
2. Install the same build on the registered physical iPhone and iPad. Replace every `PENDING` value below with inspected build/device metadata, set `physicalDevice` to `true`, and record each result.
3. Exercise microphone allow/deny, local pause/resume and the Send boundary; phone, Siri and alarm interruptions; Bluetooth and wired route loss; background/foreground, lock/unlock and force-quit recovery; Wi-Fi and cellular loss/return; cancellation during capture, transcription and coaching; same-conversation multi-turn continuation; VoiceOver, Dynamic Type and Reduce Motion.
4. Run the content-free privacy scan. For the two performance cases on each device, supply measured positive `durationMS` and peak `peakMemoryMB`; leave both values `null` for every other case.
5. Record and inspect one canonical Personal signed-build record for each installed device with `apple/scripts/record-signed-build.mjs`. Put the inspected signer certificate SHA-256 and provisioning profile UUID in the evidence fields below.
6. Run `node apple/scripts/verify-voice-evidence.mjs docs/qa/swift-native-audio-streaming-device-matrix.md <iphone-signed-build.json> <ipad-signed-build.json>`. The verifier cryptographically revalidates retained artifacts when available and requires the matrix to match both signed records. Any failure returns the feature to Build with QA notes.

The block below is the sole machine-readable evidence record.

<!-- TAISA_VOICE_EVIDENCE
{
  "schemaVersion": 1,
  "candidateCommit": "PENDING_FULL_COMMIT",
  "installedCommit": "PENDING_FULL_COMMIT",
  "dirty": false,
  "fixtureRevision": "voice-session-fixtures-v1",
  "backendEnvironment": "PENDING",
  "appVersion": "PENDING",
  "buildNumber": "PENDING",
  "databaseSchemaVersion": "2",
  "signer": "PENDING",
  "provisioningProfile": "PENDING",
  "rows": [
    {
      "deviceFamily": "iPhone",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "permission.microphone-allow",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPhone",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "permission.microphone-deny",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPhone",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "capture.pause-resume",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPhone",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "capture.send-boundary",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPhone",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "interruption.phone",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPhone",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "interruption.siri",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPhone",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "interruption.alarm",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPhone",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "route.bluetooth-removal",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPhone",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "route.wired-removal",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPhone",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "lifecycle.background-foreground",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPhone",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "lifecycle.lock-unlock",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPhone",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "lifecycle.force-quit",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPhone",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "connectivity.wifi-loss-return",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPhone",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "connectivity.cellular-loss-return",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPhone",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "cancellation.capture",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPhone",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "cancellation.transcription",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPhone",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "cancellation.coaching",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPhone",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "conversation.multi-turn",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPhone",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "privacy.artifact-scan",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPhone",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "accessibility.voiceover",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPhone",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "accessibility.dynamic-type",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPhone",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "accessibility.reduce-motion",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPhone",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "performance.recording",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPhone",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "performance.streaming",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPad",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "permission.microphone-allow",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPad",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "permission.microphone-deny",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPad",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "capture.pause-resume",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPad",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "capture.send-boundary",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPad",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "interruption.phone",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPad",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "interruption.siri",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPad",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "interruption.alarm",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPad",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "route.bluetooth-removal",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPad",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "route.wired-removal",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPad",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "lifecycle.background-foreground",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPad",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "lifecycle.lock-unlock",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPad",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "lifecycle.force-quit",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPad",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "connectivity.wifi-loss-return",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPad",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "connectivity.cellular-loss-return",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPad",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "cancellation.capture",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPad",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "cancellation.transcription",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPad",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "cancellation.coaching",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPad",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "conversation.multi-turn",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPad",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "privacy.artifact-scan",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPad",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "accessibility.voiceover",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPad",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "accessibility.dynamic-type",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPad",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "accessibility.reduce-motion",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPad",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "performance.recording",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    },
    {
      "deviceFamily": "iPad",
      "deviceName": "PENDING",
      "deviceIdentifier": "PENDING",
      "operatingSystem": "PENDING",
      "physicalDevice": false,
      "caseID": "performance.streaming",
      "result": "pending",
      "durationMS": null,
      "peakMemoryMB": null
    }
  ]
}
-->
