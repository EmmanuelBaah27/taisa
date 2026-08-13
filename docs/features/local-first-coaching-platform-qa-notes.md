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
