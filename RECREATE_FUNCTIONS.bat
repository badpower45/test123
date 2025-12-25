@echo off
REM ============================================================================
REM إعادة إنشاء جميع Edge Functions على Supabase - Windows
REM ============================================================================

echo.
echo ==========================================
echo   🔄 إعادة إنشاء Edge Functions
echo ==========================================
echo.

REM التحقق من تثبيت Supabase CLI
where supabase >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [❌] Supabase CLI غير مثبت
    echo.
    echo قم بتثبيته أولاً:
    echo   npm install -g supabase
    echo.
    pause
    exit /b 1
)

echo [✅] Supabase CLI مثبت
echo.

REM التحقق من تسجيل الدخول
echo [1/5] التحقق من تسجيل الدخول...
supabase projects list >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [⚠️] غير مسجل دخول، جاري تسجيل الدخول...
    echo.
    echo ⚠️  سيتم فتح المتصفح لتسجيل الدخول
    echo.
    supabase login
    if %ERRORLEVEL% NEQ 0 (
        echo [❌] فشل تسجيل الدخول
        pause
        exit /b 1
    )
) else (
    echo [✅] مسجل دخول بالفعل
)
echo.

REM ربط المشروع
echo [2/5] ربط المشروع...
supabase link --project-ref bbxuyuaemigrqsvsnxkj
if %ERRORLEVEL% NEQ 0 (
    echo [⚠️] فشل ربط المشروع (قد يكون مربوط بالفعل)
    echo.
    echo جاري المحاولة بدون ربط...
) else (
    echo [✅] تم ربط المشروع بنجاح
)
echo.

REM قائمة الـ Functions
echo [3/5] جاري رفع Edge Functions...
echo.
echo ⚠️  هذه العملية قد تستغرق بضع دقائق...
echo.

set SUCCESS=0
set FAILED=0

REM Function 1: branch-requests (الأولوية - المشكلة هنا!)
echo [📦] رفع branch-requests (الأولوية)...
supabase functions deploy branch-requests --no-verify-jwt
if %ERRORLEVEL% EQU 0 (
    echo [✅] branch-requests تم الرفع بنجاح
    set /a SUCCESS+=1
) else (
    echo [❌] branch-requests فشل الرفع
    set /a FAILED+=1
)
echo.

REM Function 2: branch-pulse-summary (الأولوية - المشكلة هنا!)
echo [📦] رفع branch-pulse-summary (الأولوية)...
supabase functions deploy branch-pulse-summary --no-verify-jwt
if %ERRORLEVEL% EQU 0 (
    echo [✅] branch-pulse-summary تم الرفع بنجاح
    set /a SUCCESS+=1
) else (
    echo [❌] branch-pulse-summary فشل الرفع
    set /a FAILED+=1
)
echo.

REM Function 3: sync-pulses (مهم جداً!)
echo [📦] رفع sync-pulses (مهم جداً!)...
supabase functions deploy sync-pulses --no-verify-jwt
if %ERRORLEVEL% EQU 0 (
    echo [✅] sync-pulses تم الرفع بنجاح
    set /a SUCCESS+=1
) else (
    echo [❌] sync-pulses فشل الرفع
    set /a FAILED+=1
)
echo.

REM Function 4: attendance-check-in
echo [📦] رفع attendance-check-in...
supabase functions deploy attendance-check-in --no-verify-jwt
if %ERRORLEVEL% EQU 0 (
    echo [✅] attendance-check-in تم الرفع بنجاح
    set /a SUCCESS+=1
) else (
    echo [❌] attendance-check-in فشل الرفع
    set /a FAILED+=1
)
echo.

REM Function 5: attendance-check-out
echo [📦] رفع attendance-check-out...
supabase functions deploy attendance-check-out --no-verify-jwt
if %ERRORLEVEL% EQU 0 (
    echo [✅] attendance-check-out تم الرفع بنجاح
    set /a SUCCESS+=1
) else (
    echo [❌] attendance-check-out فشل الرفع
    set /a FAILED+=1
)
echo.

REM Function 6: employee-break
echo [📦] رفع employee-break...
supabase functions deploy employee-break --no-verify-jwt
if %ERRORLEVEL% EQU 0 (
    echo [✅] employee-break تم الرفع بنجاح
    set /a SUCCESS+=1
) else (
    echo [❌] employee-break فشل الرفع
    set /a FAILED+=1
)
echo.

REM Function 7: branch-request-action
echo [📦] رفع branch-request-action...
supabase functions deploy branch-request-action --no-verify-jwt
if %ERRORLEVEL% EQU 0 (
    echo [✅] branch-request-action تم الرفع بنجاح
    set /a SUCCESS+=1
) else (
    echo [❌] branch-request-action فشل الرفع
    set /a FAILED+=1
)
echo.

REM Function 8: branch-attendance-report
echo [📦] رفع branch-attendance-report...
supabase functions deploy branch-attendance-report --no-verify-jwt
if %ERRORLEVEL% EQU 0 (
    echo [✅] branch-attendance-report تم الرفع بنجاح
    set /a SUCCESS+=1
) else (
    echo [❌] branch-attendance-report فشل الرفع
    set /a FAILED+=1
)
echo.

REM Function 9: calculate-payroll
echo [📦] رفع calculate-payroll...
supabase functions deploy calculate-payroll --no-verify-jwt
if %ERRORLEVEL% EQU 0 (
    echo [✅] calculate-payroll تم الرفع بنجاح
    set /a SUCCESS+=1
) else (
    echo [❌] calculate-payroll فشل الرفع
    set /a FAILED+=1
)
echo.

REM النتيجة النهائية
echo.
echo ==========================================
echo   📊 النتيجة النهائية
echo ==========================================
echo   ✅ نجح: %SUCCESS%
echo   ❌ فشل: %FAILED%
echo ==========================================
echo.

if %FAILED% EQU 0 (
    echo [🎉] تم رفع جميع الـ Functions بنجاح!
    echo.
    echo 📋 الخطوات التالية:
    echo   1. ارجع للتطبيق واعمل Hot Reload (اضغط r)
    echo   2. افتح لوحة المدير
    echo   3. تحقق من أن الطلبات والإحصائيات تظهر
) else (
    echo [⚠️] بعض الـ Functions فشل رفعها
    echo.
    echo 💡 حاول رفعها يدوياً:
    echo   supabase functions deploy <function-name> --no-verify-jwt
)

echo.
pause

