# تكامل بدل الإجازة - الخطوات النهائية

## 📋 ملخص التحديثات

تم إجراء التحسينات التالية على نظام بدل الإجازة:

### 1. ✅ Edge Function المحسّنة
- **الملف**: `supabase/functions/calculate-leave-allowance/index.ts`
- **التحسينات**:
  - البحث عن الموظف باستخدام ID أو الاسم (للـ fallback)
  - حساب بدل الإجازة بناءً على آخر ساعات عمل × سعر الساعة
  - دعم الفترات ثنائية الأسبوعية (1-15، 16-نهاية الشهر)
  - رسائل تصحيح تفصيلية
- **الحالة**: ✅ منشورة على Supabase

### 2. ✅ تحسينات خدمة الأجور (PayrollService)
- **الملف**: `lib/services/payroll_service.dart`
- **التحسينات**:
  - إضافة معامل اختياري `employeeName` لـ method `calculateLeaveAllowance()`
  - تحسين معالجة الأخطاء والـ fallback
  - دعم multiple response formats
- **الحالة**: ✅ مُحدّثة

### 3. ✅ تحسينات صفحة الأجور للمالك
- **الملف**: `lib/screens/owner/owner_employee_payroll_report_page.dart`
- **التحسينات**:
  - إضافة بدل الإجازة إلى قسم الملخص (Summary Section)
  - عرض المكافآت والخصومات في الملخص أيضاً
  - معالجة الحالة حين الـ column لا يوجد بعد في قاعدة البيانات
  - تمرير اسم الموظف إلى Edge Function كـ fallback
- **الحالة**: ✅ مُحدّثة

## 🚀 خطوات التطبيق

### الخطوة 1: تطبيق Database Migration
**يجب تطبيق هذا على Supabase Dashboard مباشرة**:

1. اذهب إلى Supabase Dashboard: https://supabase.com/dashboard
2. اختر مشروعك: `bbxuyuaemigrqsvsnxkj`
3. انقر على **SQL Editor**
4. أنشئ Query جديدة
5. انسخ والصق الـ SQL التالي:

```sql
-- Add leave_allowance column to employees if not exists
ALTER TABLE public.employees
ADD COLUMN IF NOT EXISTS leave_allowance numeric DEFAULT 100;

-- Update NULL values
UPDATE public.employees
SET leave_allowance = 100
WHERE leave_allowance IS NULL;

-- Add comment
COMMENT ON COLUMN public.employees.leave_allowance IS 'Leave allowance amount per period (default: 100)';
```

6. انقر **Run** أو `Cmd+Enter`
7. تأكد من عدم وجود أخطاء في النتيجة

### الخطوة 2: التحقق من النتائج
بعد تطبيق الـ migration، تحقق من أن الـ column تم إضافته:

```sql
SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_schema = 'public' 
  AND table_name = 'employees'
  AND column_name = 'leave_allowance';
```

### الخطوة 3: اختبار الحساب
جرّب الآن:

1. افتح تطبيق Flutter
2. اذهب لصفحة الرواتب للموظف (Owner > Employee Payroll)
3. يجب أن ترى:
   - **في قسم الملخص** (Summary Section):
     - بدل الإجازة (القيمة المحسوبة أو الـ default 100)
     - المكافآت
     - الخصومات
   - **في Breakdown Cards** أسفل: نفس المعلومات

## 📊 كيفية عمل الحساب

### المنطق الأساسي:
```
إذا عدد الإجازات > 2:
  بدل الإجازة = 0
وإلا إذا عدد الإجازات = 0:
  بدل الإجازة = آخر ساعات عمل × سعر الساعة
وإلا (1-2 إجازات):
  بدل الإجازة = القيمة المحفوظة (default: 100)
```

### الفترات المدعومة:
- **الفترة 1**: 1-15 من الشهر
- **الفترة 2**: 16 إلى نهاية الشهر

## 🔧 استكشاف الأخطاء

### إذا ظهرت رسالة خطأ:

1. **"Employee not found"**:
   - تأكد من أن employee ID صحيح
   - الـ Edge Function الآن يحاول البحث بالاسم أيضاً

2. **"Column does not exist"**:
   - تطبيق الـ migration لم ينته بعد
   - أكمل الخطوة 1 أعلاه

3. **القيمة تظهر 100.00 دائماً**:
   - هذا الـ fallback الصحيح
   - قد لا توجد بيانات حضور (attendance) في النظام
   - أو أن الموظف لديه أكثر من إجازتين

## 📝 ملفات المرجع

- **Edge Function**: [supabase/functions/calculate-leave-allowance/index.ts](supabase/functions/calculate-leave-allowance/index.ts)
- **PayrollService**: [lib/services/payroll_service.dart](lib/services/payroll_service.dart)
- **صفحة الأجور**: [lib/screens/owner/owner_employee_payroll_report_page.dart](lib/screens/owner/owner_employee_payroll_report_page.dart)
- **Migration**: [migrations/20260430180000_add_leave_allowance_column.sql](migrations/20260430180000_add_leave_allowance_column.sql)

## ✨ الخطوات التالية

بعد تطبيق الـ migration، سيعمل النظام بشكل كامل:
1. ✅ حساب بدل الإجازة تلقائياً
2. ✅ عرضها في صفحة الأجور
3. ✅ تشمل في الإجمالي

---
**آخر تحديث**: 30 أبريل 2026 18:00
