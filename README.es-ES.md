# Notes Bridge (Espanol)

Notes Bridge es un proyecto multiplataforma de notas y recordatorios.

## Tecnologia

- Cliente: Flutter (Windows, Android)
- Servidor: NestJS + Prisma + SQLite
- Notificaciones: notificaciones locales + superposicion estilo "isla dinamica" en Windows

## Estructura del repositorio

- `apps/flutter_app`: cliente Flutter
- `server`: API backend y capa de datos
- `docs`: notas adicionales (schema/despliegue)
- `run_build_windows.bat`: compilacion release para Windows
- `run_android_apk.bat`: compilacion APK para Android

## Privacidad y version open source

Esta version fue saneada para publicar:

- sin `.env` privado
- sin caches/artefactos de build
- dominio y marca personal reemplazados por valores genericos

## Inicio rapido

### 1) Iniciar backend

```bash
cd server
cp .env.example .env
npm ci
npx prisma generate
npm run build
npm run start:prod
```

API local por defecto: `http://127.0.0.1:3000`
Prefijo por defecto: `/v1`

### 2) Ejecutar Flutter (Windows)

```bash
cd apps/flutter_app
flutter pub get
flutter run -d windows --dart-define=API_BASE_URL=http://127.0.0.1:3000 --dart-define=API_PREFIX=/v1
```

### 3) Ejecutar Flutter (Android)

```bash
flutter run -d android --dart-define=API_BASE_URL=http://10.0.2.2:3000 --dart-define=API_PREFIX=/v1
```

## Build

En la raiz del repositorio:

- Windows: `run_build_windows.bat`
- Android APK: `run_android_apk.bat`

Puedes ajustar los valores API por defecto dentro de los scripts.

## Licencia

MIT. Ver `LICENSE`.
