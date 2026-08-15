# Local-first coaching platform — device QA notes

## 2026-08-13 voice composer refinement

Observed on iPhone:

- A failed voice submission still permitted recording to resume or text to be edited.
- Deleting a voice draft did not consistently return to the default focused keyboard entry.
- Voice entry used inconsistent microphone and waveform symbols.
- Non-speech recordings could appear as a `0:00` voice draft.
- Retained recordings could display the reset recorder timer instead of their saved duration.

Implemented for renewed QA:

- Only locally detected speech is eligible for a voice draft; uncertain noise and silence are
  discarded through the existing local audio-cleanup path.
- All composer voice entry uses the waveform symbol. The text field contains no voice icon.
- A valid saved draft displays its duration and opens Delete, Resume, and Send actions.
- A failed submitted voice turn hides the editable composer and permits only retry or deletion.
- Retry resubmits the retained audio even when failure occurred before a durable request ID was
  created. Deletion also works in that pre-durable failure state.
- Deleting returns to text mode and requests keyboard focus.

Superseded on 2026-08-15: on-device amplitude classification remains useful for
the recorder presentation, but it no longer decides whether a deliberate Send
may reach transcription. Final recognition evidence now owns clear, uncertain,
and no-speech outcomes.

Verification before renewed device QA:

- `cd mobile && npm test -- voiceActivity voiceComposerState localCaptureRoutes --runInBand`
  — 3 suites, 33 tests passed.
- `cd mobile && npm run typecheck` — passed.
- `cd mobile && npm test -- --runInBand` — 41 suites, 401 tests passed.

Pending device checks:

- Noise and sub-second non-speech create no draft.
- Short detected speech remains available even if the rounded timer initially reads `0:00`.
- Plain waveform starts recording; waveform plus duration opens draft actions without recording.
- Failed submission shows only Try again and Discard recording.
- Retry uses the retained recording; deletion returns to a focused keyboard composer.

## 2026-08-14 managed iPhone QA

- Encrypted local conversation containing `QA persistence 14 Aug` survived a remotely verified force-quit and relaunch.
- Taisa's app-switcher preview remained obscured.
- Cancelling device authentication kept conversation content shielded.
- Enabling and completing Face ID restored the conversation content.
- Voice capture initially hit a reaction-state render loop; the empty conversation message selector is now referentially stable and covered by regression tests.
- Noise-only and unintelligible recordings were repeatedly hallucinated as `BACKGROUND NOISES` or `Thanks for watching`, then incorrectly reached coaching.
- Phrase filtering and single Whisper segment thresholds were tried and rejected: the same words may be legitimate speech, and one acoustic threshold did not generalize to fan noise or other gibberish.
- The replacement streams transcription only after Send. Strong recognition automatically coaches, uncertain recognition becomes editable composer text without coaching, and no usable speech creates a recoverable error with no message or coaching interaction.
- Provider confidence stays inside the gateway; temporary audio, transcript content, and provider payloads remain absent from logs.

Automated verification completed before renewed device QA:

- Backend: 20 suites and 242 tests passed; TypeScript build passed.
- Mobile: 46 suites and 426 tests passed; TypeScript check passed.
- Workflow verification and `git diff --check` passed.

Pending managed-iPhone calibration:

- Clear speech streams visible text and produces exactly one coaching response.
- Silence, steady background noise, and general unintelligible audio produce no coaching response.
- Uncertain recognition opens as editable text without a confirmation screen.
- Legitimately saying `Thanks for watching` remains valid when speech evidence is strong.

## 2026-08-13 OpenAI coaching contract correction

Observed on iPhone:

- Voice transcription completed and persisted locally, but coaching returned a retryable failure.
- Content-free diagnostics isolated the failure to OpenAI HTTP 400 `invalid_request_error`.
- The generated empty-proposal tuple used `items: []`, outside OpenAI's supported Structured
  Outputs subset.

Implemented and verified:

- Provider-facing empty arrays now use an item schema with `maxItems: 0`; Taisa's Zod parser still
  enforces the exact portable response contract.
- Provider-facing schema normalization does not weaken local response validation.
- A synthetic, content-free `gpt-4o-mini` request was accepted and parsed as `redirect`.
- Backend: 15 suites, 201 tests, and TypeScript build passed.
- Mobile: 41 suites, 403 tests, and TypeScript check passed.

Pending device check:

- Retry the retained real submission and confirm the coaching response persists and renders.
