# Taisa Personal Alpha Release

**Tier:** Full

**Tracks:** Platform + Product

**Status:** Scope agreed; plan approved
**Owner:** Baah

## What is it?

A standalone iPhone build of Taisa that works away from Baah's Mac, backed by a private hosted
Taisa API. The phone remains authoritative for conversations, career memory, goals, actions,
evidence, recordings, and recovery archives. Only deliberate coaching/transcription requests and
explicitly shared feedback examples leave the phone.

## Why now?

The core voice/text coaching loop works well enough to learn from daily use. Daily use is currently
blocked by Metro and a Mac-hosted API, while response improvement lacks a consented evidence loop.

## Acceptance criteria

- [ ] A release-mode iPhone build launches without Metro and works on cellular or unrelated Wi-Fi.
- [ ] The public API requires an enrolled device credential; installation IDs alone grant no access.
- [ ] One-time enrollment secrets are short-lived and cannot be reused after successful enrollment.
- [ ] OpenAI credentials exist only in hosted secrets, never in the app binary or local archive.
- [ ] Hosted request handling is stateless for conversation content and logs no prompt, transcript,
      response, profile, memory, goal, action, or evidence text.
- [ ] Daily/monthly AI spending limits reject before provider calls and remain durable across restarts.
- [ ] Users can mark a response helpful or unhelpful entirely locally.
- [ ] Sharing an improvement example is optional per response and shows the exact payload first.
- [ ] The shared payload is limited to the submitted turn, bounded context actually used, response,
      decision metadata, reaction, optional improvement note, and explicit consent timestamp.
- [ ] Users can redact the preview, upload it, see its receipt ID, and delete that shared example.
- [ ] No recording, full archive, unrelated conversation, database key, backup passphrase, device
      credential, or replacement map is included in feedback.
- [ ] Hosted feedback content is encrypted at application level; indexes and logs remain content-free.
- [ ] The app clearly separates private local reactions from explicitly shared examples.
- [ ] Personal-alpha QA covers cellular coaching, voice transcription, force-quit recovery, cost
      rejection, credential revocation, feedback preview/upload/deletion, and local-only behavior.

## Product decisions

- Improve prompts, retrieval, guardrails, and evals before considering fine-tuning.
- Sharing is explicit per example; rating alone never uploads content.
- Railway Hobby is the first hosted runtime because the current Node backend and durable operational
  SQLite ledger can run without an infrastructure rewrite. Expected minimum: USD 5/month plus AI use.
- The first bundle is a locally installed release build for Baah's registered iPhone. TestFlight is a
  later distribution option and requires Apple Developer Program/App Store Connect setup.

## Out of scope

- Fine-tuning or uploading a training dataset to an AI provider.
- Automatic conversation sharing, background archive sync, cloud career memory, or cloud recordings.
- Multi-user accounts, subscriptions, public signup, team administration, or external beta testers.
- App Store launch, analytics SDKs, integrations, todos, Notion, Granola, or meeting ingestion.
- Legacy-route retirement before the existing recovery/privacy gate is complete.
