@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "ROOT_DIR=%~dp0"
set "APP_DIR=%ROOT_DIR%apps\flutter_app"
set "FLUTTER_BAT="
set "API_BASE_URL=https://example.com"
set "API_PREFIX=/v1"

if not exist "%APP_DIR%" (
  echo [ERROR] Flutter app folder not found: %APP_DIR%
  exit /b 1
)

for /f "delims=" %%F in ('where flutter.bat 2^>nul') do (
  if not defined FLUTTER_BAT set "FLUTTER_BAT=%%F"
)

if not defined FLUTTER_BAT (
  echo [ERROR] flutter.bat not found in PATH.
  echo         Install Flutter and add it to PATH.
  exit /b 1
)

pushd "%APP_DIR%"

echo [INFO] Closing possible file-locking processes...
taskkill /F /IM notes_bridge.exe >nul 2>nul
taskkill /F /IM flutter_tester.exe >nul 2>nul
taskkill /F /IM dart.exe >nul 2>nul
taskkill /F /IM devenv.exe >nul 2>nul

call "%FLUTTER_BAT%" config --enable-windows-desktop
if errorlevel 1 (
  popd
  exit /b 1
)

call "%FLUTTER_BAT%" clean
if errorlevel 1 (
  echo [WARN] flutter clean failed, trying to remove release folder manually...
  if exist "build\windows\x64\runner\Release" (
    rmdir /s /q "build\windows\x64\runner\Release" >nul 2>nul
  )
)

call "%FLUTTER_BAT%" pub get
if errorlevel 1 (
  popd
  exit /b 1
)

echo [INFO] Generating app icons from assets\branding\logo.jpg ...
call "%FLUTTER_BAT%" pub run flutter_launcher_icons
if errorlevel 1 (
  echo [WARN] Icon generation failed. Continue with existing icons.
)

call "%FLUTTER_BAT%" build windows --release --dart-define=API_BASE_URL=%API_BASE_URL% --dart-define=API_PREFIX=%API_PREFIX%
set "BUILD_EXIT=%ERRORLEVEL%"

popd

if not "%BUILD_EXIT%"=="0" (
  exit /b %BUILD_EXIT%
)

echo [OK] Windows app built:
echo      %APP_DIR%\build\windows\x64\runner\Release\
exit /b 0

