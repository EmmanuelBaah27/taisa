# Taisa

> "I wish I could shadow a senior version of myself while I work."

A personal AI career companion that lives close to your work life. Capture what's happening day-to-day, get coached by a senior version of yourself, and have polished outputs (CV bullets, quarterly reviews) ready when you need them.

Built for one person first — the builder. Validated by real use before expanding.

---

## What It Does

```
You log what happened at work (voice or text)
  ↓
Claude analyses it as a senior career coach
  ↓
Wins, challenges, action items, and CV moments are captured
  ↓
When you need a quarterly review or CV update,
the material is already shaped and waiting
```

---

## Tech Stack

| Layer | Technology |
|---|---|
| Mobile | React Native + Expo (managed workflow) |
| Styling | NativeWind (Tailwind CSS for React Native) |
| State | Zustand |
| Backend | Node.js + Express + TypeScript |
| Database | SQLite (local, via better-sqlite3) |
| AI — coaching | Anthropic Claude (claude-sonnet-4-6) |
| AI — transcription | OpenAI Whisper |

---

## Running Locally

See [SETUP.md](SETUP.md) for first-time setup (API keys, environment files).

**Common issue:** If port 3001 is in use by another local dev server, change `PORT` in `backend/.env` and update `EXPO_PUBLIC_API_URL` in `mobile/.env` to match.

```bash
# Terminal 1 — backend (from repo root)
npm run backend

# Terminal 2 — mobile (from repo root)
npm run mobile
```

Your Mac's local IP (needed for `EXPO_PUBLIC_API_URL` in `mobile/.env`):
```bash
ipconfig getifaddr en0
```

---

## Project Structure

```
taisa/
├── mobile/       React Native app (Expo) — has its own node_modules
├── backend/      Node.js + Express API
├── shared/       TypeScript types shared between mobile and backend
└── docs/         All documentation
```

---

## Documentation

| Doc | What it's for |
|---|---|
| [docs/v1-status.md](docs/v1-status.md) | What's built, what diverged from spec, what's next |
| [docs/architecture.md](docs/architecture.md) | System overview, data flow, how Claude is wired |
| [docs/data-model.md](docs/data-model.md) | Database schema, entity relationships |
| [docs/api.md](docs/api.md) | All API endpoints, request/response shapes |
| [docs/agent-persona.md](docs/agent-persona.md) | The Senior Self spec + build guide for the AI layer |
| [docs/design-system.md](docs/design-system.md) | Visual language, tokens, component structure |
| [SETUP.md](SETUP.md) | First-time setup, API keys, dev build instructions |
| [docs/product/](docs/product/) | Product design artifacts #001–#005 (.docx) |

**Start with [docs/v1-status.md](docs/v1-status.md)** to understand where the project is right now.

---

## Product Vision

See [docs/product/01-product/product-brief-001.docx](docs/product/01-product/product-brief-001.docx) for the full product brief.

The problem is a chain — memory gap → lost context → missing guidance → navigating career growth alone with incomplete information. Taisa closes the loop.
