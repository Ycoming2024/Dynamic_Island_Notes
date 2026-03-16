# Notes Bridge (Open Source Edition)

Cross-platform notes/reminders app with a Flutter client and NestJS backend.

## Project Structure

- `apps/flutter_app`: Flutter app (Windows + Android)
- `server`: NestJS API (SQLite/Prisma)
- `docs`: schema and setup notes
- `run_build_windows.bat`: one-click Windows desktop build
- `run_android_apk.bat`: one-click Android APK build

## Privacy-Safe Open Source Export

This export intentionally removes personal deployment details:

- No private `.env`
- No runtime databases/logs/build caches
- Domain/app branding replaced with generic placeholders (`https://example.com`)

## Quick Start

### 1) Backend

```bash
cd server
cp .env.example .env
npm ci
npx prisma generate
npm run build
npm run start:prod
```

Default API: `http://127.0.0.1:3000/v1`

### 2) Flutter app

```bash
cd apps/flutter_app
flutter pub get
flutter run -d windows --dart-define=API_BASE_URL=http://127.0.0.1:3000 --dart-define=API_PREFIX=/v1
```

Android example:

```bash
flutter run -d android --dart-define=API_BASE_URL=http://10.0.2.2:3000 --dart-define=API_PREFIX=/v1
```

## Build Scripts

At repository root:

- Windows: `run_build_windows.bat`
- Android APK: `run_android_apk.bat`

Both scripts use:

- `API_BASE_URL` default: `https://example.com`
- `API_PREFIX` default: `/v1`

Adjust them in the script file if needed.

## License

Add your preferred open-source license file before publishing.
