# Taisa — Setup Guide

## Prerequisites
- Node.js v24+ (via nvm)
- Xcode (for iOS simulator)
- An iPhone managed development build for SQLCipher/LocalAuthentication validation (Expo Go is insufficient)

## Maintained review runtime

The current local-first + Chats + chat-input + design-system build is maintained in the integration worktree:

```bash
cd /Users/emmanuelbaah/Documents/Beats/VibeCoding/Taisa/.worktrees/feature-current-experience/mobile
npm install
npm start
```

For the on-demand browser design-system catalog, run `npm run storybook:web` from the same directory. The `docs/reimagine-product-scope` worktree is documentation-only and is not a mobile runtime. Native SQLCipher, recording, and device-security checks still require the managed development build described below.

## API Keys Required
1. **OpenAI API key** — for primary coaching and transcription
2. **Anthropic API key** — for automatic coaching fallback

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
TAISA_ANTHROPIC_MODEL=your-approved-model
TAISA_ANTHROPIC_INPUT_PRICE_USD_PER_MILLION_TOKENS=your-current-price
TAISA_ANTHROPIC_OUTPUT_PRICE_USD_PER_MILLION_TOKENS=your-current-price
TAISA_ANTHROPIC_MAX_OUTPUT_TOKENS=your-output-cap
TAISA_ANTHROPIC_STRUCTURED_OUTPUT_INPUT_TOKEN_OVERHEAD=your-conservative-schema-token-bound
TAISA_AI_COST_CEILING_PER_REQUEST_USD=0.05
TAISA_AI_COST_CEILING_DAILY_USD=1
TAISA_AI_COST_CEILING_MONTHLY_USD=10
TAISA_TRANSCRIPTION_MODEL=gpt-4o-transcribe
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

Both providers' keys, models, current input/output prices, output caps, and positive
structured-output/tool-schema token overhead values are mandatory. `TAISA_COACHING_PROVIDER`
selects the primary (`openai` by default); the other provider becomes the automatic fallback. The
gateway adds each provider's overhead to its estimate and atomically reserves the combined
conservative maximum before either call. It calls the fallback at most once, and only after an
allowlisted operational failure: network/timeout, HTTP `408`, `409`, `429`, or `5xx`, or a
recognized provider rate-limit, overload, authentication, permission, billing, or unavailable
error. Validation, local configuration, spend, policy/safety, other invalid-request, invalid-output,
and unknown failures never trigger fallback. Blank, zero, or invalid required values fail closed.

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

The `personal-alpha` release profile sets `EXPO_PUBLIC_TAISA_BUILD_PROFILE=personal-alpha` and
requires `EXPO_PUBLIC_API_URL` to be a hosted HTTPS URL ending in `/api/v1`. It rejects localhost,
loopback, `.local`, and private LAN addresses at startup. This URL is public configuration, not a
secret; all provider keys, enrollment codes, credential peppers, and feedback keys remain backend
variables only.

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

After the private service is deployed and Baah separately approves signing/build execution, create
the standalone internal profile with `eas build --platform ios --profile personal-alpha` or a local
Xcode Release archive using the same profile variables. `developmentClient` is disabled for this
profile, so the installed app must launch and operate with Metro stopped. EAS upload, Apple
credential access, and installation remain gated external actions.

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

## Private Railway service (approval required before creation)

The repository includes `backend/Dockerfile` and root `railway.json`. Configure Railway with the
repository root as build context, one service replica, and one persistent volume mounted at an
absolute path such as `/data`. Set all four mutable SQLite paths beneath that mount:

- `DB_PATH`
- `TAISA_USAGE_LEDGER_PATH`
- `TAISA_DEVICE_AUTH_DATABASE_PATH`
- `TAISA_FEEDBACK_DATABASE_PATH`

Also set `NODE_ENV=production`, `TAISA_PUBLIC_ORIGIN` to one HTTPS origin, the provider and
transcription variables above, device-auth variables, feedback encryption key, and all three cost
ceilings. Production startup fails closed if any required secret, ceiling, HTTPS origin, or durable
path is absent. Keep one replica because the operational, credential, and feedback stores are
single-instance SQLite. `/health` is public and content-free; every `/api/v1` route except the
single-use enrollment exchange requires the enrolled bearer credential.

Do not paste secrets into source control, build arguments, or Expo public variables. Create the
Railway project, volume, billing, variables, and first deployment only after Baah approves that
external action. For rollback, select the last healthy Railway deployment without changing or
deleting the persistent volume.

Provider parity is a release gate, not part of ordinary tests. It makes paid provider calls and
therefore requires a separate explicit budget approval for each provider before running. After
that approval, run the same current synthetic pack against both providers with separately approved
hard total budgets and new artifact paths:

```bash
npm run eval:coaching --workspace=backend -- --provider=openai --max-cost-usd=<approved-openai-budget> --review-output=openai-coaching-eval-review.json
npm run eval:coaching --workspace=backend -- --provider=anthropic --max-cost-usd=<approved-anthropic-budget> --review-output=anthropic-coaching-eval-review.json
```

Every attempted scenario is reserved and recorded in the durable usage ledger. Stdout remains
content-free. The review artifact is marked synthetic-only and contains synthetic replies,
automated thresholds, and blank manual-review fields. Complete one review JSON per provider with
exactly one result for every current scenario, then produce each provider decision and combine
them:

```bash
npm run eval:coaching:review --workspace=backend -- --artifact=openai-coaching-eval-review.json --completed-review=openai-completed-review.json --decision-output=openai-coaching-decision.json
npm run eval:coaching:review --workspace=backend -- --artifact=anthropic-coaching-eval-review.json --completed-review=anthropic-completed-review.json --decision-output=anthropic-coaching-decision.json
npm run eval:coaching:parity --workspace=backend -- --openai-decision=openai-coaching-decision.json --anthropic-decision=anthropic-coaching-decision.json --parity-output=coaching-provider-parity.json
```

The review commands make no provider calls. Each provider must independently pass the same current
pack and automated thresholds, average manual usefulness of at least `0.8`, and all applicable
grounding, neutrality, privacy, and safety checks. Parity passes only when both decisions use the
same current pack version and both pass; model, prompt, schema, rubric, or material pricing changes
require fresh evidence.

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
