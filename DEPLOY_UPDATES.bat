@echo off
echo ========================================
echo   Deploying Updates to Supabase
echo ========================================
echo.

echo Step 1: Deploying sync-pulses function...
call supabase functions deploy sync-pulses --no-verify-jwt
if %errorlevel% neq 0 (
    echo [ERROR] Failed to deploy sync-pulses
    pause
    exit /b 1
)
echo.

echo Step 2: Deploying branch-requests function...
call supabase functions deploy branch-requests --no-verify-jwt
if %errorlevel% neq 0 (
    echo [ERROR] Failed to deploy branch-requests
    pause
    exit /b 1
)
echo.

echo Step 3: Deploying branch-pulse-summary function...
call supabase functions deploy branch-pulse-summary --no-verify-jwt
if %errorlevel% neq 0 (
    echo [ERROR] Failed to deploy branch-pulse-summary
    pause
    exit /b 1
)
echo.

echo Step 4: Deploying check-daily-absences function...
call supabase functions deploy check-daily-absences --no-verify-jwt
if %errorlevel% neq 0 (
    echo [ERROR] Failed to deploy check-daily-absences
    pause
    exit /b 1
)
echo.

echo Step 5: Deploying approve-absence function...
call supabase functions deploy approve-absence --no-verify-jwt
if %errorlevel% neq 0 (
    echo [ERROR] Failed to deploy approve-absence
    pause
    exit /b 1
)
echo.

echo Step 6: Deploying attendance-check-in function...
call supabase functions deploy attendance-check-in --no-verify-jwt
if %errorlevel% neq 0 (
    echo [ERROR] Failed to deploy attendance-check-in
    pause
    exit /b 1
)
echo.

echo Step 7: Deploying attendance-check-out function...
call supabase functions deploy attendance-check-out --no-verify-jwt
if %errorlevel% neq 0 (
    echo [ERROR] Failed to deploy attendance-check-out
    pause
    exit /b 1
)
echo.

echo ========================================
echo   All functions deployed successfully!
echo ========================================
echo.
echo Next steps:
echo 1. Run: flutter pub get
echo 2. Test the app (Edge/Chrome/Mobile)
echo 3. Verify pulse tracking and payroll calculations
echo.
pause

