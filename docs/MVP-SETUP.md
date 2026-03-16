# Notes Bridge - Run Result

## Backend (verified)

```bash
cd server
npm install --ignore-scripts
npm run build
node dist/main.js
```

Base URL: `http://127.0.0.1:3000/v1`

Current backend uses local JSON persistence at:

- `server/data/db.json`

No PostgreSQL setup required in current runnable version.

## Verified API flow

- `POST /v1/auth/email/login`
- `POST /v1/notes`
- `GET /v1/notes`

Verified result: login success + note created + list returns created note.

## Flutter

Flutter SDK is not installed in this environment, so build/run is currently blocked.
