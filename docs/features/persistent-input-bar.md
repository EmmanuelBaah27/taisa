# Scope — Persistent Input Bar + Chat UI

**Status:** Ready to plan
**Track:** Product (UI) + Platform (mobile dependency)
**Blocks:** All other pages

---

## What is it?

A persistent input bar fixed above the tab bar on every screen. One button. Tapping it opens the chat UI.

The chat UI is the single, universal conversation screen across the entire app. It handles all three scenarios: a new conversation with no context, a new conversation anchored to a specific item, and continuing an existing session. The input experience is identical in all three — voice by default, switchable to text.

---

## Why now?

Every other page depends on this. It is the core interaction surface of the product. Nothing else ships without it.

---

## Entry points

Every surface in the app that triggers conversation opens this same screen.

| Trigger | Context passed | Chat opens as |
|---|---|---|
| Input bar (any tab) | None | New — blank slate |
| Summary page input | Current growth theme | New — theme pre-loaded |
| Tap a goal (Goals page) | Goal ID | New — goal as context |
| Tap a log entry (Logs page) | Session ID | Continue existing session — history visible, same input at bottom |
| Tap a dashboard highlight | Insight content | New — insight as context |
| Tap an action item | Action item ID | New — action item as context |

---

## Chat UI — three modes

**Mode 1: New, no context**
Screen opens auto-ready — listening state is active, waveform animated, no recording yet. First sound triggers transcription automatically. No tap required to start speaking.

**Mode 2: New, with context**
Same auto-ready behaviour as Mode 1. A context card appears at the top (goal name, theme, insight, or action item). Context is injected into the pipeline on submit.

**Mode 3: Continue existing session (chat history)**
Past messages load in the conversation view. There is no separate read-only history screen — the chat screen is always the history view. Input starts inactive, user taps mic to continue. Once triggered, recording and transcription behaviour is identical to Modes 1 and 2.

**The recording mechanic is a shared component across all three modes.** Visual feedback, silence detection, transcription quality, and the transition from listening → recording → done must be consistent regardless of which mode opened the screen. The only thing that changes between modes is what appears above the input.

---

## Acceptance criteria

**Input bar**
- [ ] Visible and usable on all 5 tabs, fixed above the tab bar
- [ ] Single CTA — one button, communicates "speak"
- [ ] Light theme styling

**Chat screen (`app/chat/index.tsx`)**
- [ ] Accepts optional params: `sessionId` (continue mode) or `contextType` + `contextId` (context mode)
- [ ] Mode 1 (no params): auto-ready on open — waveform active, first sound starts transcription
- [ ] Mode 2 (contextType + contextId): context card at top, same auto-ready behaviour below
- [ ] Mode 3 (sessionId): loads existing messages, input starts inactive, tap mic to begin
- [ ] Live transcription — words appear on screen as user speaks (`@react-native-voice/voice`)
- [ ] Silence detection tuned — brief pauses do not cut off, deliberate stop triggers Done state
- [ ] User confirms Done — transcript submitted, Taisa's response appears in the same view
- [ ] Switch to text mode available within the screen — keyboard replaces mic, same send flow
- [ ] Recording component is identical across all three modes — same waveform, same feedback, same behaviour
- [ ] Error state handled with retry

**Replaces**
- [ ] `recording/index.tsx` — removed
- [ ] `thread/[id].tsx` — removed, replaced by chat screen in continue mode

---

## Platform dependencies

| What | Where | Notes |
|---|---|---|
| `@react-native-voice/voice` | `mobile/` | New dependency |
| `useLiveTranscription` hook | `mobile/src/hooks/` | Replaces `useVoiceRecorder` |
| iOS speech + mic permissions | `app.json` | Verify SFSpeechRecognizer entitlement |
| Context params on `/analyze` | Backend | Pass `contextType` + `contextId` through to Claude prompt |
| `POST /entries` inputType: 'text' | Backend | Already exists — verify |

---

## Out of scope

- File / media upload
- Dark mode styling
- The 5 tab pages themselves (separate features)
- Entry categorization / type suggestion (separate feature)
- Context-aware placeholder text variations
</content>
