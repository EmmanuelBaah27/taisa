# Local-First Cutover QA

## Encrypted database development-build gate

- [ ] Baah approves running the managed iPhone development-build verification step.
- [ ] Install and launch a development build containing the SQLCipher-enabled `expo-sqlite` module (unavailable in Expo Go).
- [ ] Create a local record and confirm it persists after force-quit and restart.
- [ ] Remove the SecureStore database key in a controlled test and confirm Taisa enters the recovery-required state instead of generating a replacement key.
- [ ] Confirm the SQLite file is unreadable without its SQLCipher key.

Status: pending. No prebuild, local native run, cloud/EAS build, simulator, or physical-device verification was performed during Task 5.

## Private capture and deliberate submission gate

- [ ] With gateway traffic inspection enabled, save private text and confirm there are zero transcription or coaching requests.
- [ ] Force-quit and reopen; confirm the private text remains in the local conversation.
- [ ] Submit text once and confirm exactly one coaching request is made with bounded local context.
- [ ] Rapidly double-tap text submit and voice submit; confirm each local intent creates one request/message and at most one paid call, with the submit controls disabled while busy.
- [ ] Interrupt a coaching request, retry explicitly, and confirm the same local request/message IDs are reused without duplicate messages.
- [ ] Stop a voice recording and confirm no upload occurs until **Submit to Taisa** is pressed.
- [ ] Submit the recording and confirm exactly one transcription request is made.
- [ ] Confirm the submitted recording is copied from recorder cache into Taisa's app-owned documents directory before the durable request appears, then force-quit/reopen and retry from that same file.
- [ ] After a transcript is committed locally, confirm the app-owned recording is queued and removed while the editable transcript remains; a transcription failure must retain that recording for retry.
- [ ] Press **Record again** and confirm the abandoned recorder-cache file is removed before the new recording begins.
- [ ] While recording, close the sheet, switch to the keyboard, and unmount the capture screen separately; confirm each path stops once and retires the returned recorder-cache URI without a state-update warning.
- [ ] Simulate one recorder-cache and one app-owned audio deletion failure, restart Taisa, and confirm the encrypted path-only cleanup queue retries each URI exactly and removes successful rows.
- [ ] Queue an audio URI still referenced by a retryable coaching request; restart Taisa and confirm cleanup does not delete it until that request is completed or explicitly abandoned.
- [ ] Edit the returned transcript and confirm no coaching request occurs until **Confirm and submit** is pressed.
- [ ] Confirm the coaching request uses the edited transcript and does not retranscribe the cached recording.
- [ ] Return an over-limit transcript, confirm it remains in editable transcript review, shorten it, and confirm the same request/message completes without rerecording.
- [ ] Interrupt transcription and coaching separately; confirm retry reuses the original audio/request IDs and never records or duplicates content.
- [ ] Confirm a provider proposal remains pending even when provider output claims confirmation is unnecessary.
- [ ] Confirm the proposal only becomes durable after the user presses the explicit local **Confirm memory** action.
- [ ] For a conflicting career direction, confirm the clarification question offers **Replace old direction**, **Pause old direction**, and **Keep both**; verify each choice changes only the selected predecessor lifecycle and a generic confirm cannot supersede it.
- [ ] Force-quit and reopen; confirm user message, assistant response, usage receipt, context manifest, and pending proposal remain complete.
- [ ] Force-quit during transcript review and after a retryable failure; reopen the conversation and confirm request ID, transcript, retry state, clarification, and pending proposal controls are restored without a network call.
- [ ] From conversation history, confirm the pending status/decision count is visible, press **Resume**, and verify the exact SQLite conversation/request/message IDs reopen with no replacement session or provider call.
- [ ] Resume conversation B after viewing conversation A; confirm no message, transcript, or proposal from A appears while B hydrates, and close returns to history (or home for a cold deep link).
- [ ] Open the Today card/digest capture CTA and the legacy `/recording` deep link; confirm both enter the local-first chat and no `/entries` or `/analyze` request is reachable.
- [ ] Inspect gateway/backend telemetry and confirm no request bodies, transcripts, coaching text, or response bodies were logged.

Status: pending explicit Baah approval for a SQLCipher-capable managed development build and physical-device journey. Task 9 stopped before the plan's Step 6 device verification. No Expo prebuild, native iOS run, cloud/EAS build, simulator, physical-device journey, or live provider request was performed.
