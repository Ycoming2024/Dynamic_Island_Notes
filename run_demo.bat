@echo off
setlocal

set "PROJECT_FLUTTER_ROOT=D:\newProject\tools\flutter"
set "SYSTEM_FLUTTER_ROOT=D:\flutter"

if exist "%SYSTEM_FLUTTER_ROOT%\bin\flutter.bat" (
  set "FLUTTER_ROOT=%SYSTEM_FLUTTER_ROOT%"
) else (
  set "FLUTTER_ROOT=%PROJECT_FLUTTER_ROOT%"
)

if not exist "%FLUTTER_ROOT%\bin\flutter.bat" (
  echo [ERROR] Flutter not found.
  echo Checked:
  echo   %PROJECT_FLUTTER_ROOT%
  echo   %SYSTEM_FLUTTER_ROOT%
  exit /b 1
)

start "notes-backend" cmd /k "cd /d D:\newProject\server && npm run build && node dist\main.js"

timeout /t 3 > nul

start "notes-app" cmd /k "cd /d D:\newProject\apps\flutter_app && set \"HOME=%USERPROFILE%\" && set \"PATH=%FLUTTER_ROOT%\bin\mingit\cmd;%FLUTTER_ROOT%\bin;%PATH%\" && set \"FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn\" && set \"PUB_HOSTED_URL=https://pub.flutter-io.cn\" && where git && git config --global --add safe.directory %FLUTTER_ROOT% >nul 2>nul && %FLUTTER_ROOT%\bin\flutter.bat config --enable-windows-desktop && %FLUTTER_ROOT%\bin\flutter.bat pub get && (if not exist windows (%FLUTTER_ROOT%\bin\flutter.bat create --platforms=windows .)) && %FLUTTER_ROOT%\bin\flutter.bat run -d windows"

endlocal
