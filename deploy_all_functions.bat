@echo off
REM ============================================================================
REM Deploy All Supabase Edge Functions (Windows)
REM ============================================================================

echo 🚀 Deploying All Supabase Edge Functions...
echo.

REM Check if Supabase CLI is installed
where supabase >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo ❌ Error: Supabase CLI is not installed
    echo Install with: npm install -g supabase
    exit /b 1
)

REM List of functions to deploy
set FUNCTIONS=attendance-check-in attendance-check-out sync-pulses employee-break branch-requests branch-request-action branch-attendance-report branch-pulse-summary calculate-payroll delete-employee

set SUCCESS_COUNT=0
set FAILED_COUNT=0

for %%f in (%FUNCTIONS%) do (
    echo 📦 Deploying %%f...
    supabase functions deploy %%f --no-verify-jwt
    if %ERRORLEVEL% EQU 0 (
        echo    ✅ %%f deployed successfully!
        set /a SUCCESS_COUNT+=1
    ) else (
        echo    ❌ %%f deployment failed
        set /a FAILED_COUNT+=1
    )
    echo.
)

echo ==========================================
echo 📊 Deployment Summary:
echo    ✅ Success: %SUCCESS_COUNT%
echo    ❌ Failed: %FAILED_COUNT%
echo ==========================================
echo.

if %FAILED_COUNT% EQU 0 (
    echo 🎉 All functions deployed successfully!
    echo.
    echo 📋 Next steps:
    echo 1. Test the functions from Supabase Dashboard
    echo 2. Check Edge Functions logs for any errors
    echo 3. Verify environment variables are set correctly
) else (
    echo ⚠️ Some functions failed to deploy. Check the errors above.
    exit /b 1
)

