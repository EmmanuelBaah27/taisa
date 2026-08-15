# Voice should feel immediate without weakening the Send boundary

**Date:** 2026-08-15

**Status:** Implemented; managed-device calibration pending

**Area:** Voice capture, transcription, privacy

## Moment

During managed iPhone QA, recordings containing silence, fan noise, and unclear
audio were sometimes transcribed as plausible phrases such as “Thanks for
watching.” Taisa then treated the invented text as a real thought and generated a
coaching response. Comparing the experience with Claude Mobile also made the
delay in Taisa's record-then-wait transcription flow feel unnecessary.

## Tension

Taisa should feel conversational and automatic after the user chooses to send a
voice note. It should not insert a mandatory transcript review into every turn.
At the same time, Taisa's local-first promise requires audio to remain on-device
until the user deliberately taps Send, and uncertain recognition must not silently
become coaching context.

## Decision

Taisa will keep audio local while recording. After the user taps Send, Taisa will
begin streaming transcription results into the composer.

- Clear, stable transcription proceeds automatically to coaching.
- Uncertain transcription remains in the text composer for editing and deliberate
  resubmission.
- Audio with no usable speech returns a recoverable error.
- There is no mandatory transcript confirmation screen.

Uncertainty will be based on speech evidence, recognition confidence, and
transcript stability—not phrase blacklists or a broad semantic judgment about
whether the user's words sound sensible.

## Why

The Send action is the meaningful privacy boundary. Streaming before Send would
make the interface feel faster but would transmit private audio before the user
has chosen to share it. Streaming after Send preserves that boundary while still
making progress visible immediately.

Confidence-based fallback also respects natural speech. Names, acronyms,
unfinished thoughts, and unconventional phrasing should not be rejected merely
because they look unusual to a language model.

## Consequence

The current `whisper-1` batch path must be replaced with a transcription model and
transport that support streamed deltas and confidence metadata. The mobile
composer needs provisional transcript state, and the backend must classify the
final result as clear, uncertain, or no usable speech before coaching begins.

Thresholds will be calibrated through automated fixtures and managed-device QA.
They are policy, not universal truths, and should remain observable and adjustable.

Implementation uses typed NDJSON over the existing post-Send upload. Provisional
deltas remain transient. A clear terminal result atomically creates the user
message and starts coaching; an uncertain result is stored as a private draft
and loaded into the text composer; no-speech creates no message or coaching
interaction. Provider confidence remains inside the gateway.

## Story angle

This decision came from watching an AI confidently coach a sentence nobody had
said. The lesson was not merely to filter one strange phrase. It was to design the
handoff between hearing and understanding: fast enough to feel conversational,
explicit enough to preserve privacy, and humble enough to stop when recognition
is uncertain.
