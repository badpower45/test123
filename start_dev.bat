@echo off
setlocal enabledelayedexpansion

set "ROOT_DIR=%~dp0"
if "%ROOT_DIR:~-1%"=="\" set "ROOT_DIR=%ROOT_DIR:~0,-1%"
set "SERVER_PORT=5000"

call :launch_backend

set "LOCAL_IP="
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' -and $_.IPAddress -notlike '0.*' } | Select-Object -First 1 -ExpandProperty IPAddress); if (-not $ip) { $ip = (Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $_.IPAddress } | ForEach-Object { $_.IPAddress } | Where-Object { $_ -match '^\\d+\\.\\d+\\.\\d+\\.\\d+$' -and $_ -notlike '127.*' -and $_ -notlike '169.254.*' } | Select-Object -First 1) }; if (-not $ip) { exit 1 } else { Write-Output $ip }"`) do (
    set "LOCAL_IP=%%I"
)
if not defined LOCAL_IP (
    echo Error: Unable to detect local IPv4 address.
    exit /b 1
)

set "API_FILE=%ROOT_DIR%\lib\constants\api_endpoints.dart"
if not exist "%API_FILE%" (
    echo Error: API endpoints file not found at %API_FILE%
    exit /b 1
)

set "BASE_URL=http://%LOCAL_IP%:%SERVER_PORT%/api"
powershell -NoProfile -Command "$apiFile = '%API_FILE%'; $baseUrl = '%BASE_URL%'; $content = Get-Content -Raw $apiFile; $updated = $content -replace \"const String API_BASE_URL = '.*';\", \"const String API_BASE_URL = '$baseUrl';\"; Set-Content -Encoding UTF8 $apiFile $updated"
if errorlevel 1 (
    echo Error: Failed to update API_BASE_URL in %API_FILE%.
    exit /b 1
)

cd /d "%ROOT_DIR%"
flutter pub get
if errorlevel 1 (
    echo Error: flutter pub get failed.
    exit /b 1
)

flutter run
exit /b %errorlevel%

:launch_backend
start "Oldies Backend" cmd /k "cd /d ""%ROOT_DIR%\server"" && npm install && npm start"
exit /b 0
