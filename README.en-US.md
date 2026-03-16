# Notes Bridge (English)

Notes Bridge is a cross-platform notes and reminders project.

## Tech Stack

- Client: Flutter (Windows, Android)
- Server: NestJS + Prisma + SQLite
- Notifications: local notifications + custom Windows dynamic-island style overlay

## Repository Structure

- `apps/flutter_app`: Flutter client
- `server`: backend API and data layer
- `docs`: extra schema/setup notes
- `run_build_windows.bat`: one-click Windows release build
- `run_android_apk.bat`: one-click Android APK build

## Privacy and Open Source

This open-source version is sanitized:

- private `.env` is excluded
- runtime caches/build artifacts are excluded
- personal domain/branding replaced with generic values

## Quick Start

### 1) Start backend

```bash
cd server
cp .env.example .env
npm ci
npx prisma generate
npm run build
npm run start:prod
```

Default local API base: `http://127.0.0.1:3000`
Default API prefix: `/v1`

### 2) Run Flutter app (Windows)

```bash
cd apps/flutter_app
flutter pub get
flutter run -d windows --dart-define=API_BASE_URL=http://127.0.0.1:3000 --dart-define=API_PREFIX=/v1
```

### 3) Run Flutter app (Android)

```bash
flutter run -d android --dart-define=API_BASE_URL=http://10.0.2.2:3000 --dart-define=API_PREFIX=/v1
```

## Build

At repository root:

- Windows: `run_build_windows.bat`
- Android APK: `run_android_apk.bat`

You can edit API defaults inside the scripts.

## License

MIT. See `LICENSE`.
