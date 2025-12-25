# 🚀 رفع سريع - Edge Functions

## ⚡ طريقة سريعة (موصى بها)

### على Windows:
```bash
DEPLOY_NOW.bat
```

### على Mac/Linux:
```bash
chmod +x DEPLOY_NOW.sh
./DEPLOY_NOW.sh
```

---

## 📝 طريقة يدوية (خطوة بخطوة)

### 1. تثبيت Supabase CLI:
```bash
npm install -g supabase
```

### 2. تسجيل الدخول:
```bash
supabase login
```
سيتم فتح المتصفح لتسجيل الدخول.

### 3. ربط المشروع:
```bash
supabase link --project-ref bbxuyuaemigrqsvsnxkj
```

### 4. رفع الـ Functions (الأساسية):

```bash
# 1. تسجيل الحضور
supabase functions deploy attendance-check-in --no-verify-jwt

# 2. تسجيل الانصراف
supabase functions deploy attendance-check-out --no-verify-jwt

# 3. رفع النبضات (مهم جداً!)
supabase functions deploy sync-pulses --no-verify-jwt
```

### 5. رفع الـ Functions (الإضافية):

```bash
# 4. استراحات الموظفين
supabase functions deploy employee-break --no-verify-jwt

# 5. طلبات الفروع
supabase functions deploy branch-requests --no-verify-jwt

# 6. معالجة الطلبات
supabase functions deploy branch-request-action --no-verify-jwt

# 7. تقارير الحضور
supabase functions deploy branch-attendance-report --no-verify-jwt

# 8. ملخص النبضات
supabase functions deploy branch-pulse-summary --no-verify-jwt

# 9. حساب المرتبات
supabase functions deploy calculate-payroll --no-verify-jwt
```

---

## ✅ التحقق من الرفع

### من Terminal:
```bash
supabase functions list
```

### من Supabase Dashboard:
1. افتح: https://app.supabase.com/project/bbxuyuaemigrqsvsnxkj
2. اذهب إلى: **Edge Functions** في القائمة الجانبية
3. يجب أن ترى جميع الـ Functions المرفوعة

---

## 🔧 إعداد المتغيرات البيئية (اختياري)

إذا احتجت متغيرات بيئية للـ Functions:

```bash
supabase secrets set SUPABASE_URL=https://bbxuyuaemigrqsvsnxkj.supabase.co
supabase secrets set SERVICE_ROLE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJieHV5dWFlbWlncnFzdnNueGtqIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2MjYwOTI0MCwiZXhwIjoyMDc4MTg1MjQwfQ.cXhEdAG3T-eDDbUI__o1P6JuiYO6eJGuJT-F01p6RE4
```

**ملاحظة:** الـ Functions تستخدم `Deno.env.get()` للحصول على هذه القيم تلقائياً من Supabase.

---

## 🐛 استكشاف الأخطاء

### المشكلة: "Supabase CLI is not installed"
**الحل:**
```bash
npm install -g supabase
```

### المشكلة: "Not logged in"
**الحل:**
```bash
supabase login
```

### المشكلة: "Project not linked"
**الحل:**
```bash
supabase link --project-ref bbxuyuaemigrqsvsnxkj
```

### المشكلة: "Function deployment failed"
**الحل:**
1. تحقق من وجود الملف `supabase/functions/<function-name>/index.ts`
2. تحقق من الأخطاء في الـ logs:
   ```bash
   supabase functions logs <function-name>
   ```

---

## 📊 معلومات المشروع

- **Project URL:** https://bbxuyuaemigrqsvsnxkj.supabase.co
- **Project Ref:** bbxuyuaemigrqsvsnxkj
- **Anon Key:** (موجود في `lib/config/supabase_config.dart`)
- **Service Role Key:** (موجود أعلاه)

---

## ⚠️ ملاحظات مهمة

1. **لا تنسى رفع `sync-pulses`** - هذا الـ function مهم جداً لتحديث الحضور والمرتب
2. بعد رفع أي function، انتظر دقيقة قبل اختباره
3. تأكد من أن قاعدة البيانات تحتوي على جميع الجداول المطلوبة
4. الـ Functions الأساسية (attendance-check-in, attendance-check-out, sync-pulses) **ضرورية** لعمل النظام

---

## 🎯 بعد الرفع

1. ✅ افتح Supabase Dashboard → Edge Functions
2. ✅ تحقق من وجود جميع الـ Functions
3. ✅ اختبر من التطبيق: سجل حضور/انصراف
4. ✅ تحقق من الـ logs للتأكد من عدم وجود أخطاء

