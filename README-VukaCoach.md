# VukaCoach PWA — Setup Guide

Rebuilt version of the VukaCoach single-file PWA (originally generated with Kimi, lost in the E: drive crash). This rebuild keeps the same concept and adds several improvements (see "What's new" below).

## Files

| File | Purpose |
|---|---|
| `vukacoach.html` | The entire app — single file, no build step |
| `manifest.json` | PWA manifest (installable, standalone) |
| `sw.js` | Service worker — offline shell cache |
| `icons/icon-192.png`, `icons/icon-512.png` | App icons (regenerate with `node icons/make-icons.js`) |
| `icons/make-icons.js` | Icon generator script (no dependencies) |

## Hosting (free)

1. **Vercel / Netlify**: drag-and-drop the `vukacoach` folder, or
   ```bash
   npx vercel          # or: npx netlify deploy --prod --dir .
   ```
2. Open the URL on your phone → the browser offers "Add to Home Screen" (the in-app install banner appears on Android Chrome).
3. HTTPS is required for the service worker and voice input — Netlify/Vercel give you that for free.

## Wire up the AI (n8n)

1. In the app: **⚙ Settings → n8n webhook URL**, paste your webhook, hit **Test webhook**.
2. Your n8n workflow receives a POST with this payload:
   ```json
   {
     "session_token": "uuid",
     "message": "I feel tired today",
     "user_profile": { "goal": "lose_weight", "gender": "male", "age": "28",
                        "weight": "85", "height": "175", "target": "80",
                        "activity": "moderate", "time": "30",
                        "injuries": "Bad knee", "diet": "halal", "lang": "en", "name": "" },
     "memory": ["Goal: Lose weight", "Injury/limitation: Bad knee", "..."],
     "conversation_history": [{ "role": "coach", "text": "..." }],
     "stats": { "streak": 3, "workouts": 5, "checkins": 3, "messages": 12, "water": 4 },
     "targets": { "bmr": 1780, "cal": 2200, "protein": 136 },
     "time_of_day": "morning",
     "day_of_week": "Monday",
     "language": "en"
   }
   ```
3. Your workflow must reply with JSON containing at least a `message` field:
   ```json
   {
     "message": "I hear you. With that knee, let's skip squats today...",
     "suggested_actions": ["Show me a workout", "I need to rest"],
     "memory_updates": ["User felt tired on Monday morning"]
   }
   ```
   - `memory_updates` (optional): strings added to the coach's long-term memory.
   - `suggested_actions` (optional): up to 3 quick-reply chips shown under the chat.
4. **CORS**: the n8n Webhook node must allow the app's origin (`Access-Control-Allow-Origin`). In n8n, set "Allowed Origins (CORS)" in the webhook node options.

Without a webhook, the app runs in **offline mode**: a built-in rule-based coach answers (meal logging, workouts, motivation, check-ins) and clearly says it's offline. Nothing is broken — it's just not smart yet.

## The 3-month kill clause (unchanged)

| Metric | Kill threshold |
|---|---|
| Downloads | < 50 organic |
| Weekly active | < 20% of installers |
| Week 1→4 retention | < 10% |
| Reviews | < 5, avg < 3.5★ |
| Revenue | $0 from 100+ users |

3 of 5 red at Month 3 = kill it. No emotion.

## What's new in this rebuild (improvements over the original)

1. **Smart calorie/protein targets** — Mifflin-St Jeor BMR with activity multiplier, goal-adjusted (deficit for weight loss, surplus for muscle), auto-referenced by the coach and shown at onboarding.
2. **Weight logging + trend** — weekly weigh-ins tracked in Progress; the trend is announced in chat and remembered in memory.
3. **Dynamic coach suggestions** — n8n can return `suggested_actions` that render as one-tap chips.
4. **Webhook test button + status indicator** — the header shows "online" vs "offline mode"; settings has a one-click ping test with clear failure reasons (URL, CORS, wrong reply shape).
5. **Progress photos are downscaled** before storage (canvas → JPEG, 360px, 70%) so localStorage doesn't blow up.
6. **Injury-aware offline workouts** — even offline, the workout generator avoids knee-hostile exercises if "knee" appears in injuries.
7. **Voice input matches coach language** — Speech Recognition locale follows the onboarding language (en-ZA, af-ZA, zu-ZA…).
8. **Day separators in chat + streak protection** — streak counts consecutive days with any check-in or full hydration.
9. **TWA-ready** — `start_url` and scope are set so Bubblewrap can wrap it to a Play Store app as-is (see below).

## Wrap for the Play Store (TWA, $25)

```bash
npm i -g @bubblewrap/cli
bubblewrap init --manifest https://YOUR-DOMAIN/manifest.json
bubblewrap build
```
Upload the generated `.aab` to the Play Console. Update the PWA → Play Store updates automatically.

## Known limits

- All data stays in localStorage — clearing browser data wipes it. Use ⚙ Settings → Export (JSON) regularly.
- Single-user per device; no server-side accounts yet (ghost auth by design).
- Voice input needs Chrome/Edge on Android or desktop; iOS Safari doesn't support Web Speech well.
