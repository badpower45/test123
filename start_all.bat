@echo off
echo ===============================================
echo   Oldies Workers - Complete System Startup
echo ===============================================
echo.

echo [1/3] Checking Node.js...
node --version
if errorlevel 1 (
    echo ERROR: Node.js not found!
    pause
    exit /b 1
)

echo.
echo [2/3] Checking Flutter...
flutter --version | findstr "Flutter"
if errorlevel 1 (
    echo ERROR: Flutter not found!
    pause
    exit /b 1
)

echo.
echo [3/3] Starting services...
echo.

echo Starting Backend Server on Port 5000...
start "Oldies Backend Server" cmd /k "npm run dev"

timeout /t 5 /nobreak >nul

echo.
echo Starting Flutter Application...
start "Oldies Flutter App" cmd /k "flutter run -d windows"

echo.
echo ===============================================
echo   All services started successfully!
echo ===============================================
echo   Backend: http://localhost:5000
echo   Test Page: http://localhost:5000/test-api.html
echo ===============================================
echo.
echo Press any key to exit (services will continue running)...
pause >nul
