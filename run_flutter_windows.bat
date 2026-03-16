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

set "PATH=%FLUTTER_ROOT%\bin\mingit\cmd;%FLUTTER_ROOT%\bin;%PATH%"
set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
set PUB_HOSTED_URL=https://pub.flutter-io.cn
set "HOME=%USERPROFILE%"

cd /d D:\newProject\apps\flutter_app
where git
git config --global --add safe.directory %FLUTTER_ROOT% >nul 2>nul
call flutter --version
if errorlevel 1 exit /b 1

call flutter config --enable-windows-desktop
if errorlevel 1 exit /b 1

call flutter pub get
if errorlevel 1 exit /b 1

call dart run build_runner build --delete-conflicting-outputs
if errorlevel 1 exit /b 1

call flutter build windows
if errorlevel 1 exit /b 1

echo [OK] Build finished: D:\newProject\apps\flutter_app\build\windows\x64\runner\Release
endlocal
