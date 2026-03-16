@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "ROOT_DIR=%~dp0"
set "APP_DIR=%ROOT_DIR%apps\flutter_app"
set "FLUTTER_BAT="

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

set "SDK_CANDIDATE="
if defined ANDROID_SDK_ROOT set "SDK_CANDIDATE=%ANDROID_SDK_ROOT%"
if not defined SDK_CANDIDATE if defined ANDROID_HOME set "SDK_CANDIDATE=%ANDROID_HOME%"
if not defined SDK_CANDIDATE if exist "%LOCALAPPDATA%\Android\Sdk" set "SDK_CANDIDATE=%LOCALAPPDATA%\Android\Sdk"

if not defined SDK_CANDIDATE (
  echo [ERROR] Android SDK not found.
  echo         Open Android Studio -^> More Actions -^> SDK Manager
  echo         Install: Android SDK, Platform-Tools, Build-Tools, Command-line Tools.
  echo         Suggested path: %LOCALAPPDATA%\Android\Sdk
  exit /b 1
)

if not exist "%SDK_CANDIDATE%\platform-tools\adb.exe" (
  echo [ERROR] SDK path found but platform-tools is missing:
  echo         %SDK_CANDIDATE%
  echo         Please install Platform-Tools in SDK Manager.
  exit /b 1
)

set "ANDROID_HOME=%SDK_CANDIDATE%"
set "ANDROID_SDK_ROOT=%SDK_CANDIDATE%"
set "PATH=%ANDROID_SDK_ROOT%\platform-tools;%ANDROID_SDK_ROOT%\cmdline-tools\latest\bin;%PATH%"
set "GRADLE_OPTS=-Dorg.gradle.daemon=false -Dorg.gradle.cache.internal.locklistener.port=0 -Dorg.gradle.cache.internal.lockListener.port=0 -Dorg.gradle.internal.plugins.portal.url.override=https://maven.aliyun.com/repository/gradle-plugin -Dhttps.protocols=TLSv1.2 -Dfile.encoding=UTF-8 %GRADLE_OPTS%"
set "JAVA_TOOL_OPTIONS=-Djava.net.preferIPv4Stack=true %JAVA_TOOL_OPTIONS%"
set "FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn"
set "API_BASE_URL=https://example.com"
set "API_PREFIX=/v1"
set "GRADLE_USER_HOME=%APP_DIR%\.gradle-user-home"

echo [INFO] Using Android SDK: %ANDROID_SDK_ROOT%
echo [INFO] Using Gradle plugin mirror: https://maven.aliyun.com/repository/gradle-plugin
echo [INFO] Using Flutter storage mirror: %FLUTTER_STORAGE_BASE_URL%
echo [INFO] Using API base URL: %API_BASE_URL%
echo [INFO] Using API prefix: %API_PREFIX%
echo [INFO] Using Gradle user home: %GRADLE_USER_HOME%

set "LOCAL_PROPERTIES=%APP_DIR%\android\local.properties"
if exist "%LOCAL_PROPERTIES%" (
  findstr /b /c:"sdk.dir=" "%LOCAL_PROPERTIES%" >nul
  if errorlevel 1 (
    >> "%LOCAL_PROPERTIES%" echo sdk.dir=%ANDROID_SDK_ROOT:\=\\%
  )
) else (
  (
    for %%I in ("%FLUTTER_BAT%") do set "FLUTTER_HOME=%%~dpI.."
    echo flutter.sdk=!FLUTTER_HOME:\=\\!
    echo sdk.dir=%ANDROID_SDK_ROOT:\=\\%
  )> "%LOCAL_PROPERTIES%"
)

pushd "%APP_DIR%"
echo [INFO] Stopping existing Gradle daemons...
if exist "android\gradlew.bat" (
  call "android\gradlew.bat" --stop >nul 2>nul
)
taskkill /F /IM gradle.exe >nul 2>nul
taskkill /F /IM java.exe >nul 2>nul
taskkill /F /IM javaw.exe >nul 2>nul
taskkill /F /IM kotlin-daemon.exe >nul 2>nul
taskkill /F /IM adb.exe >nul 2>nul
timeout /t 2 /nobreak >nul

if exist "%GRADLE_USER_HOME%\daemon" (
  rmdir /s /q "%GRADLE_USER_HOME%\daemon" >nul 2>nul
)
if exist "%GRADLE_USER_HOME%\caches\journal-1" (
  rmdir /s /q "%GRADLE_USER_HOME%\caches\journal-1" >nul 2>nul
)
if exist "%GRADLE_USER_HOME%\caches\8.14\executionHistory" (
  rmdir /s /q "%GRADLE_USER_HOME%\caches\8.14\executionHistory" >nul 2>nul
)

if exist ".dart_tool" (
  rmdir /s /q ".dart_tool"
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

if not exist ".dart_tool\package_config.json" (
  echo [ERROR] .dart_tool\package_config.json not found after pub get.
  echo         Try running manually in %APP_DIR%:
  echo         %FLUTTER_BAT% clean ^&^& %FLUTTER_BAT% pub get
  popd
  exit /b 1
)

call "%FLUTTER_BAT%" build apk --release --target-platform android-arm64 --dart-define=API_BASE_URL=%API_BASE_URL% --dart-define=API_PREFIX=%API_PREFIX%
set "BUILD_EXIT=%ERRORLEVEL%"
popd

if not "%BUILD_EXIT%"=="0" (
  exit /b %BUILD_EXIT%
)

echo [OK] APK generated:
echo      %APP_DIR%\build\app\outputs\flutter-apk\app-release.apk
exit /b 0

