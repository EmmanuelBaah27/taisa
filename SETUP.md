# Taisa — Setup Guide

## Prerequisites
- Node.js v24+ (via nvm)
- Xcode (for iOS simulator)
- An iPhone managed development build for SQLCipher/LocalAuthentication validation (Expo Go is insufficient)

## API Keys Required
1. **Anthropic API key** — for Claude (career coach AI)
2. **OpenAI API key** — for Whisper transcription

## First-Time Setup

### 1. Install dependencies
```bash
npm install --workspaces
cd mobile && npm install
```

### 2. Configure backend environment
```bash
cd backend
cp .env.example .env
```
Edit `backend/.env`:
```
PORT=3000
ANTHROPIC_API_KEY=sk-ant-...your key...
OPENAI_API_KEY=sk-...your key...
DB_PATH=./taisa.db
TAISA_COACHING_PROVIDER=openai
TAISA_OPENAI_MODEL=your-approved-model
TAISA_OPENAI_INPUT_PRICE_USD_PER_MILLION_TOKENS=your-current-price
TAISA_OPENAI_OUTPUT_PRICE_USD_PER_MILLION_TOKENS=your-current-price
TAISA_OPENAI_MAX_OUTPUT_TOKENS=your-output-cap
TAISA_OPENAI_STRUCTURED_OUTPUT_INPUT_TOKEN_OVERHEAD=your-conservative-schema-token-bound
TAISA_AI_COST_CEILING_PER_REQUEST_USD=your-limit
TAISA_AI_COST_CEILING_DAILY_USD=your-limit
TAISA_AI_COST_CEILING_MONTHLY_USD=your-limit
TAISA_TRANSCRIPTION_MODEL=whisper-1
TAISA_TRANSCRIPTION_MAX_DURATION_SECONDS=300
TAISA_TRANSCRIPTION_MAX_UPLOAD_BYTES=26214400
TAISA_TRANSCRIPTION_PRICE_USD_PER_MINUTE=your-current-price
TAISA_DEVICE_AUTH_REQUIRED=true
TAISA_DEVICE_CREDENTIAL_PEPPER=at-least-24-random-characters
TAISA_DEVICE_AUTH_DATABASE_PATH=./taisa-device-auth.sqlite
TAISA_DEVICE_ENROLLMENT_CODE=a-short-lived-one-time-code
TAISA_DEVICE_ENROLLMENT_EXPIRES_AT=an-ISO-8601-expiry
TAISA_FEEDBACK_ENCRYPTION_KEY=a-base64-encoded-32-byte-key
TAISA_FEEDBACK_DATABASE_PATH=./taisa-feedback.sqlite
```

The selected provider's model, current input/output prices, output cap, and positive structured-output/tool-schema token overhead are all required. The gateway adds the overhead before reserving spend, so set it to a conservative bound from the selected provider's current token accounting. Blank, zero, or invalid required values fail closed at startup or before a provider call. Configure the unselected provider only when switching to it.

Hosted production refuses to start without device authentication. The enrollment code is
single-use and only credential digests are stored by the service; the issued device token stays in
iPhone SecureStore. Feedback storage is optional in local development, but when enabled both
feedback variables are required. Shared examples are encrypted with AES-256-GCM and stored
separately from conversations. Never place the credential pepper, enrollment code, feedback key,
or provider key in `mobile/.env` or an Expo public variable.

### 3. Configure mobile environment
```bash
cd mobile
cp .env.example .env
```
Edit `mobile/.env`:
```
EXPO_PUBLIC_API_URL=http://YOUR_MAC_IP:3001/api/v1
```
> **Important:** Use your Mac's local IP (e.g. `192.168.1.5`), not `localhost`, so your phone can reach the backend over WiFi.
> Find it with: `ipconfig getifaddr en0`

### 4. Start the backend
```bash
npm run backend
```
You should see: `Taisa backend running on http://localhost:3000`

### 5. Start the mobile app
```bash
npm run mobile
```
This starts Metro for JavaScript-only work. Taisa's encrypted local platform cannot run in Expo Go.
After Baah approves and installs the managed development build described below, start Metro with
`cd mobile && npx expo start --dev-client` and open that development build on the iPhone.

> **Note:** Your phone and Mac must be on the same WiFi network.

## Building a Dev Build (required for SQLCipher and audio recording)
Expo Go does not include Taisa's SQLCipher-enabled SQLite module or some native audio features. A development build is therefore required to run the local-first app and before encrypted-database device QA:
```bash
cd mobile
npx expo install expo-dev-client
npx expo run:ios
```

This native command is an explicit execution gate: record it for setup, but do not run it, prebuild native projects, or start a simulator/device build until Baah approves the native verification step.

The managed configuration enables SQLCipher and LocalAuthentication. Do not claim encrypted-file,
Face ID, app-switcher, sharing, or restore behavior from Expo Go or unit tests.

## Manual encrypted backup and restore

The You tab exposes **Export my data** and **Restore encrypted backup**. Export requires a separate
passphrase with at least 12 non-whitespace characters and a matching confirmation. The device
database Keychain key is never used as the backup passphrase or written into the backup.

After creating an export, move the shared file somewhere outside Taisa's app container and keep the
passphrase separately. Restore copies a selected file into a candidate, verifies its schema,
integrity, entity counts, content hash, and search indexes, re-encrypts it with the device key, and
only then attempts rollback-safe promotion.

The backup contains encrypted database state, including completed voice transcripts, but it does
not bundle recorded audio files. Finish or abandon pending voice work before exporting. Export
fails closed before creating an artifact while a nonterminal coaching request still references an
audio file, so a clean-install restore cannot silently produce a request whose recording is absent.

Limitations:

- There is no automatic cloud backup or multi-device sync.
- Recorded audio files are not included; a backup preserves completed transcripts and other
  database state only.
- Taisa cannot recover a forgotten backup passphrase.
- Deleting the app or losing the phone before saving an export elsewhere can permanently lose data.
- AirDrop, Files, iCloud Drive, email, or another share target may create additional copies under
  that service's privacy policy.
- Native SQLCipher and filesystem behavior remains unverified until the gated device checklist is complete.

## Verification commands (code-only)

```bash
npm test --workspace=backend -- --runInBand
npm run build --workspace=backend
cd mobile && npm test -- --runInBand && npm run typecheck
cd .. && npm run verify:workflow
git diff --check
```

These commands make no live provider call. Device and paid-provider evaluations are recorded and
approved separately.

After explicit paid-provider approval, run an evaluation with a provider, hard total budget, and
new local review-artifact path:

```bash
npm run eval:coaching --workspace=backend -- --provider=openai --max-cost-usd=1 --review-output=coaching-eval-review.json
```

Every attempted scenario is reserved and recorded in the durable usage ledger. Stdout remains
content-free. The review artifact is marked synthetic-only and contains synthetic replies,
automated thresholds, and blank manual-usefulness scores. A provider passes only when
`automatedPassed` is true and at least 80% of replies pass manual usefulness.

## Project Structure
```
taisa/
├── mobile/          # React Native app (Expo)
│   ├── app/         # Expo Router screens
│   └── src/         # Components, hooks, services, stores
├── backend/         # Node.js + Express API
│   └── src/
│       ├── routes/           # API endpoints
│       ├── services/claude/  # AI agents
│       └── prompts/          # Claude system prompts
├── shared/          # TypeScript types shared across packages
└── docs/            # Product planning & design documents
```

## Key Decisions to Revisit
- Performance review file upload (PDF/Word) — currently paste-text only
- Cloud deployment (Railway/Render) when ready to use away from home WiFi
- Optional end-to-end encrypted cloud backup (future separate platform scope; Taisa must not hold the key)
- Gmail/Calendar integration (future)
