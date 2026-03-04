# Pregnancy AI Backend (Minimax Proxy)

Stateless backend proxy for the iOS app.

## Why this setup

- All phones use one backend endpoint.
- Minimax key stays on backend only.
- Conversation memory remains device-local:
- backend does not persist chat history
- iOS sends current context/history each request
- each phone keeps memory in local app storage

## Endpoints

- `GET /healthz`
- `POST /api/ai/chat`
- `POST /api/ai/home-summary`

## China-friendly deployment (Tencent Cloud)

If Render is unstable on your network, use Tencent Cloud Lighthouse.

- Step-by-step guide: [/Users/lpl/Desktop/孕期助手/docs/腾讯云轻量部署-小白步骤.md](/Users/lpl/Desktop/孕期助手/docs/腾讯云轻量部署-小白步骤.md)
- Deployment files: `/Users/lpl/Desktop/孕期助手/ai_backend/deploy/tencent`

## One-time cloud deploy (Render)

1. Push this repository to GitHub.
2. Open Render and create a new Blueprint from this repo.
3. Render will detect [render.yaml](/Users/lpl/Desktop/孕期助手/render.yaml).
4. In environment variables, set:
- `MINIMAX_API_KEY` = your Minimax key
- `AI_BACKEND_TOKEN` = random long secret (recommended)
5. Recommended timeout/retry settings (for Render free plan stability):
- `MINIMAX_CONNECT_TIMEOUT_SECONDS=8`
- `MINIMAX_READ_TIMEOUT_SECONDS=35`
- `MINIMAX_MAX_ATTEMPTS=2`
- `MINIMAX_RETRY_BACKOFF_SECONDS=0.8`
6. Keep Gunicorn worker count at 1 on free plan to reduce memory pressure / stalls.
7. Deploy and wait until service is live.
8. Open `https://<your-service>.onrender.com/healthz`, expect `{"ok":true,...}`.

After deploy, your backend URL is:
- `https://<your-service>.onrender.com`

## iOS configuration after cloud deploy

1. In Xcode Target Build Settings, set:
- `INFOPLIST_KEY_AI_BACKEND_URL = https://<your-service>.onrender.com`
- `INFOPLIST_KEY_AI_BACKEND_TOKEN = <same token as Render>`
- `INFOPLIST_KEY_AI_BACKEND_MODEL = MiniMax-M2.5`
2. Build and install to iPhone once.
3. Then app can run from home screen independently (backend is cloud, no Mac dependency).

## Local run (for debugging)

1. Create env file:
- `cp .env.example .env`
2. Fill required key:
- `MINIMAX_API_KEY=...`
3. Start:
- `./start.command`

The service defaults to `http://0.0.0.0:8787`.
