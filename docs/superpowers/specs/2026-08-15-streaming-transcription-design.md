# Post-Send Streaming Transcription Design

**Date:** 2026-08-15

**Status:** Approved design, pending implementation plan

**Track:** Platform + Product

**Tier:** Full

## Goal

Make voice submission feel immediate without transmitting audio before the user
taps Send and without requiring transcript confirmation for normal turns.

## Product behavior

1. Taisa records audio locally.
2. The user taps Send.
3. Taisa uploads the retained recording and streams provisional transcription
   text into the composer.
4. When transcription completes, the gateway classifies the result:
   - **clear** — persist the user message and start coaching automatically;
   - **uncertain** — leave the best transcript in the text composer for editing;
   - **no usable speech** — show a recoverable error and create no interaction.
5. A normal clear voice turn has no transcript review or confirmation screen.

## Privacy boundary

No audio leaves the device before Send. The backend receives audio only after
that deliberate action. Temporary gateway audio is deleted after transcription.
Failed or uncertain content does not become coaching context unless the user later
sends it as text.

## Architecture

### Mobile capture

The recorder retains the local audio file and activity summary. Send creates one
durable submission request and opens a transcription stream through the Taisa
gateway. Provisional deltas update a dedicated composer draft; they are not stored
as conversation messages.

The mobile client must tolerate reconnects and duplicate events by binding every
stream to the durable request ID. Stale events from an abandoned or superseded
request are ignored.

### Gateway transcription

Replace the non-streaming `whisper-1` response with a supported streaming
transcription model. The gateway owns provider credentials and forwards only typed,
content-minimal events:

- `transcript.delta`
- `transcript.completed`
- `transcript.no_speech`
- `transcript.failed`

`transcript.completed` carries `quality: clear | uncertain`. The final event
includes the durable request ID and the outcome needed by the mobile state
machine. Provider payloads and raw confidence details remain inside the gateway
boundary.

### Quality classification

Classification combines:

- voice-activity evidence;
- token or segment recognition confidence;
- stability of provisional transcript revisions.

It must not reject content because a phrase appears on a blacklist or because a
semantic model considers the user's wording unusual. Initial thresholds are
configuration with tested defaults and content-free diagnostics.

### Coaching handoff

Only `clear` completion can atomically persist the transcript as a user message
and begin coaching. `uncertain`, `no usable speech`, disconnects, and provider
failures cannot call coaching.

## User interface states

- **Recording:** waveform and elapsed time; no network transmission.
- **Transcribing:** streamed text appears progressively in the composer.
- **Clear completion:** transcript becomes the user message and coaching starts.
- **Uncertain:** composer remains populated and editable; Send submits the edited
  text through the normal text path.
- **No usable speech:** “I couldn’t hear any clear speech. Try recording again or
  use the keyboard.”
- **Connection failure:** retain the recording and offer retry or deletion.

## Error and recovery rules

- Retrying transcription reuses the durable request and retained audio.
- Closing or deleting abandons the stream and cleans up local audio when safe.
- A reconnect may resume or restart transcription but cannot duplicate a user
  message, usage receipt, or coaching request.
- Uncertain text is local composer state until explicitly submitted.

## Verification

Automated coverage must include:

- no provider request before Send;
- ordered delta delivery and stale-event rejection;
- clear completion automatically starts exactly one coaching request;
- uncertain completion populates the composer and starts zero coaching requests;
- no-speech completion creates neither a message nor coaching request;
- retry/reconnect remains idempotent;
- temporary and retained audio cleanup rules;
- content-free logging and usage accounting.

Managed-device QA must cover clear speech, silence, steady background noise,
unintelligible speech, network interruption, and editing an uncertain transcript.

## Out of scope

- Sending audio while the user is still recording.
- Mandatory confirmation of every transcript.
- Full duplex spoken conversation or synthesized voice responses.
- Semantic policing of what counts as a sensible thought.
