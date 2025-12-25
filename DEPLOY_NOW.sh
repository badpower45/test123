#!/bin/bash

# ============================================================================
# رفع جميع Edge Functions على Supabase - Mac/Linux
# ============================================================================

echo ""
echo "=========================================="
echo "  رفع Edge Functions على Supabase"
echo "=========================================="
echo ""

# التحقق من تثبيت Supabase CLI
if ! command -v supabase &> /dev/null; then
    echo "[❌] Supabase CLI غير مثبت"
    echo ""
    echo "قم بتثبيته أولاً:"
    echo "  npm install -g supabase"
    echo ""
    exit 1
fi

echo "[✅] Supabase CLI مثبت"
echo ""

# تسجيل الدخول
echo "[1/4] تسجيل الدخول إلى Supabase..."
echo ""
echo "⚠️  سيتم فتح المتصفح لتسجيل الدخول"
echo ""

if ! supabase login; then
    echo "[❌] فشل تسجيل الدخول"
    exit 1
fi

echo ""
echo "[✅] تم تسجيل الدخول بنجاح"
echo ""

# ربط المشروع
echo "[2/4] ربط المشروع..."
echo ""

if ! supabase link --project-ref bbxuyuaemigrqsvsnxkj; then
    echo "[❌] فشل ربط المشروع"
    echo ""
    echo "حاول يدوياً:"
    echo "  supabase link --project-ref bbxuyuaemigrqsvsnxkj"
    exit 1
fi

echo ""
echo "[✅] تم ربط المشروع بنجاح"
echo ""

# رفع الـ Functions
echo "[3/4] رفع Edge Functions..."
echo ""
echo "⚠️  هذه العملية قد تستغرق بضع دقائق..."
echo ""

SUCCESS=0
FAILED=0

# Function 1: attendance-check-in
echo "[📦] رفع attendance-check-in..."
if supabase functions deploy attendance-check-in --no-verify-jwt; then
    echo "[✅] attendance-check-in تم الرفع بنجاح"
    ((SUCCESS++))
else
    echo "[❌] attendance-check-in فشل الرفع"
    ((FAILED++))
fi
echo ""

# Function 2: attendance-check-out
echo "[📦] رفع attendance-check-out..."
if supabase functions deploy attendance-check-out --no-verify-jwt; then
    echo "[✅] attendance-check-out تم الرفع بنجاح"
    ((SUCCESS++))
else
    echo "[❌] attendance-check-out فشل الرفع"
    ((FAILED++))
fi
echo ""

# Function 3: sync-pulses (مهم جداً!)
echo "[📦] رفع sync-pulses (مهم جداً!)..."
if supabase functions deploy sync-pulses --no-verify-jwt; then
    echo "[✅] sync-pulses تم الرفع بنجاح"
    ((SUCCESS++))
else
    echo "[❌] sync-pulses فشل الرفع"
    ((FAILED++))
fi
echo ""

# Function 4: employee-break
echo "[📦] رفع employee-break..."
if supabase functions deploy employee-break --no-verify-jwt; then
    echo "[✅] employee-break تم الرفع بنجاح"
    ((SUCCESS++))
else
    echo "[❌] employee-break فشل الرفع"
    ((FAILED++))
fi
echo ""

# Function 5: branch-requests
echo "[📦] رفع branch-requests..."
if supabase functions deploy branch-requests --no-verify-jwt; then
    echo "[✅] branch-requests تم الرفع بنجاح"
    ((SUCCESS++))
else
    echo "[❌] branch-requests فشل الرفع"
    ((FAILED++))
fi
echo ""

# Function 6: branch-request-action
echo "[📦] رفع branch-request-action..."
if supabase functions deploy branch-request-action --no-verify-jwt; then
    echo "[✅] branch-request-action تم الرفع بنجاح"
    ((SUCCESS++))
else
    echo "[❌] branch-request-action فشل الرفع"
    ((FAILED++))
fi
echo ""

# Function 7: branch-attendance-report
echo "[📦] رفع branch-attendance-report..."
if supabase functions deploy branch-attendance-report --no-verify-jwt; then
    echo "[✅] branch-attendance-report تم الرفع بنجاح"
    ((SUCCESS++))
else
    echo "[❌] branch-attendance-report فشل الرفع"
    ((FAILED++))
fi
echo ""

# Function 8: branch-pulse-summary
echo "[📦] رفع branch-pulse-summary..."
if supabase functions deploy branch-pulse-summary --no-verify-jwt; then
    echo "[✅] branch-pulse-summary تم الرفع بنجاح"
    ((SUCCESS++))
else
    echo "[❌] branch-pulse-summary فشل الرفع"
    ((FAILED++))
fi
echo ""

# Function 9: calculate-payroll
echo "[📦] رفع calculate-payroll..."
if supabase functions deploy calculate-payroll --no-verify-jwt; then
    echo "[✅] calculate-payroll تم الرفع بنجاح"
    ((SUCCESS++))
else
    echo "[❌] calculate-payroll فشل الرفع"
    ((FAILED++))
fi
echo ""

# النتيجة النهائية
echo ""
echo "=========================================="
echo "  📊 النتيجة النهائية"
echo "=========================================="
echo "  ✅ نجح: $SUCCESS"
echo "  ❌ فشل: $FAILED"
echo "=========================================="
echo ""

if [ $FAILED -eq 0 ]; then
    echo "[🎉] تم رفع جميع الـ Functions بنجاح!"
    echo ""
    echo "📋 الخطوات التالية:"
    echo "  1. افتح Supabase Dashboard"
    echo "  2. اذهب إلى Edge Functions"
    echo "  3. تحقق من وجود جميع الـ Functions"
    echo "  4. اختبر النظام من التطبيق"
else
    echo "[⚠️] بعض الـ Functions فشل رفعها"
    echo ""
    echo "💡 حاول رفعها يدوياً:"
    echo "  supabase functions deploy <function-name> --no-verify-jwt"
fi

echo ""

