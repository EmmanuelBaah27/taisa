# Transcription Unification — Design Spec

**Date:** 2026-06-01
**Status:** Approved direction, pending spec review
**Author:** Baah + Claude

## Problem

Taisa has two parallel transcription systems:

| | Journal / recording screen | Chat screen |
|---|---|---|
| Engine | Record → upload → **Whisper** (server) | **expo-speech-recognition** (on-device, live) |
| Live? | No — transcript appears after stop | Yes — word-by-word |
| Accuracy | High (Whisper) | Mediocre (Apple/Android dictation) |
| Code | Simple (`useVoiceRecorder` + `transcribeAudio`) | Fragile (`useLiveTranscription`: iOS ~60s session cap worked around with auto-restart + error-restart timers) |

The chat path's native module (`expo-speech-recognition`) triggered today's "Cannot find native module ExpoSpeechRecognition" failure (pod never installed into the dev build). More importantly, the on-device engine is the weakest transcription source feeding the Senior Self agent.

## Decision

**Delete the live on-device path. Make the chat screen use the same record → Whisper path the journal screen already uses.** Remove `expo-speech-recognition` entirely.

## Rationale (honest version)

1. **Accuracy is paramount.** The chat transcript is the *input* to the Senior Self agent. Whisper is meaningfully more accurate than on-device dictation for reflective, jargon-heavy, emotional speech. Garbage-in → bad coaching.
2. **Reflective UX doesn't need live text.** Coaching is not rapid-fire dictation. You speak for 15–60s then the agent responds; a ~1–2s transcribe delay after a reflection is negligible, and live streaming text tends to pull the speaker into editing mode.
3. **Simplicity.** Deleting `useLiveTranscription` removes the auto-restart/silence/error-restart machinery — a whole class of edge-case bugs (dropped words at restart boundaries, double-fires).
4. **Unification.** One transcription path to maintain instead of two.

### What this is NOT (corrected premise)

This does **not** restore Expo Go. The app already requires a development build because of `@shopify/react-native-skia` (the glow/shader system), `@usenavii/core`, `@central-icons-react-native/*`, `react-native-worklets`, and `@react-native-community/datetimepicker` — none are in Expo Go. The app stays a dev-build app regardless. The win is accuracy + simplicity + unification, not escaping native builds.

## Rejected alternative: cloud streaming STT (Deepgram / AssemblyAI / OpenAI Realtime)

Gives live AND high accuracy, but requires streaming raw PCM off the device. `expo-av` only produces a finished file, so this would require *another* native audio-streaming module — reintroducing the dependency we're removing. The pure-managed workaround (chunked 3–5s clips to Whisper) is hacky, has word-boundary artifacts, and costs more. **YAGNI** for a single-user product. Not pursued.

## Architecture

### New chat turn loop (tap-to-talk)

```
tap mic ─► useVoiceRecorder.start()  (expo-av records .m4a, metering on)
            │  glow driven by recorder.amplitude (SharedValue 0–1, from metering)
            ▼
tap Stop ─► result = await recorder.stop()   → { uri, durationSeconds }
            │  phase = 'transcribing'
            ▼
         text = await transcribeAudio(uri, durationSeconds)   → POST /transcribe → Whisper
            │  phase = 'processing'
            ▼
         handleSubmit(text)   (unchanged: /chat/message or /entries+/analyze)
            │
            ▼
         append messages, phase = 'responded', loop back to idle
```

### Reuse, don't rebuild

The journal screen's [`useVoiceRecorder`](../../../mobile/src/hooks/useVoiceRecorder.ts) already provides `start`, `stop` (returns `{ uri, durationSeconds }`), `isRecording`, and `amplitude` (a `SharedValue<number>` 0–1 from expo-av metering). The chat screen consumes these directly:

- `recorder.amplitude` → `RecordingGlow` (drop the old `amplitude/10` bridge; metering is already 0–1).
- `recorder.start()` / `recorder.stop()` replace `useLiveTranscription.start()` / `.stop()`.
- `transcribeAudio()` (existing [service](../../../mobile/src/services/transcription.ts)) does the Whisper call.

### UX states

- **listening/recording** — glow active (amplitude metering), prompt "Listening…", primary button = **Stop**.
- **transcribing** — new brief state between Stop and text; show "Transcribing…" (replaces the live-text affordance).
- **processing** — unchanged ("Taisa is thinking…").
- **responded / error** — unchanged.

The 5-second silence auto-submit (`silenceTimerRef` watching live `transcript`) is **removed** — there is no live transcript to watch. Submission is explicit via the Stop button. (Optional future: metering-based silence auto-stop.)

## Files changed

| Action | Path | Change |
|---|---|---|
| Delete | `mobile/src/hooks/useLiveTranscription.ts` | Gone entirely |
| Modify | `mobile/app/chat/index.tsx` | Swap `useLiveTranscription` → `useVoiceRecorder` + `transcribeAudio`; remove silence timer; add `transcribing` phase; Stop button stops recording then transcribes; glow uses `recorder.amplitude` directly |
| Modify | `mobile/app/chat/index.tsx` | `LiveTranscriptionText` usage removed; show a plain inline "Transcribing…" status Text instead |
| Delete | `mobile/src/components/ui/LiveTranscriptionText.tsx` | Chat is its only consumer; live streaming is gone, so the component is dead |
| Modify | `mobile/src/components/ui/index.ts` | Remove the `LiveTranscriptionText` export |
| Modify | `mobile/app.json` | Remove the `expo-speech-recognition` plugin block. **Re-add iOS microphone permission** (currently provided by that plugin's `microphonePermission`) via the `expo-av` config plugin or `ios.infoPlist.NSMicrophoneUsageDescription`. **Do not lose mic permission.** |
| Modify | `mobile/package.json` | Remove `expo-speech-recognition` dependency |
| Native | `mobile/ios/` | `npx expo prebuild --platform ios` → `pod install` → rebuild, so the speech pod is dropped and mic permission re-applied |

## Critical detail: microphone permission

iOS mic usage string (`NSMicrophoneUsageDescription`) is **currently supplied by the `expo-speech-recognition` plugin**. Removing that plugin removes the string, which would make `expo-av` recording crash/deny on iOS. The spec **requires** re-declaring mic permission via either:
- `expo-av`'s config plugin `microphonePermission` option, or
- `ios.infoPlist.NSMicrophoneUsageDescription` in `app.json`.

Speech-recognition permission (`NSSpeechRecognitionUsageDescription`) is no longer needed and should be dropped.

## Out of scope (future, separate)

- **`whisper-1` → `gpt-4o-transcribe`** backend accuracy upgrade (isolated change to `backend/src/routes/transcribe.ts`).
- **Edit-before-send** of the transcript (the data model already has `rawTranscript` / `editedTranscript`).
- **Metering-based silence auto-stop** to recover hands-free flow without live STT.

## Testing / verification

- `npx tsc --noEmit` clean in `mobile/`.
- `grep -r expo-speech-recognition mobile/` returns nothing (full removal).
- Dev build: record a chat turn → "Transcribing…" → transcript posts → agent replies.
- Glow still animates with voice amplitude during recording (metering path).
- iOS mic permission prompt still appears on first record (permission string intact).
- New-session path (`/entries` + `/analyze`) and existing-session path (`/chat/message`) both still work.
