# نظام الغياب التلقائي - Absence System

## نظرة عامة
تم إنشاء نظام تلقائي للتحقق من الغياب في نهاية كل يوم وتطبيق الخصومات عند الموافقة.

## المكونات

### 1. وظيفة التحقق من الغياب (`check-daily-absences`)
**الموقع:** `supabase/functions/check-daily-absences/index.ts`

**الوظيفة:**
- تتحقق من جميع الموظفين النشطين في نهاية اليوم
- تتحقق من الموظفين الذين لم يسجلوا حضور (check-in) بعد انتهاء وقت شيفتهم
- تنشئ سجلات غياب في جدول `absences`
- ترسل إشعارات:
  - للمديرين: عند غياب موظف في فرعهم
  - للأونر: عند غياب مدير

**متى يتم استدعاؤها:**
- يجب إعداد cron job لاستدعاء هذه الوظيفة في نهاية كل يوم (مثلاً الساعة 11:00 مساءً)

### 2. وظيفة الموافقة على الغياب (`approve-absence`)
**الموقع:** `supabase/functions/approve-absence/index.ts`

**الوظيفة:**
- تتعامل مع الموافقة أو الرفض على الغياب
- عند الموافقة:
  - تحسب الخصم: (عدد ساعات الشيفت × سعر الساعة) × 2
  - تنشئ سجل خصم في جدول `deductions`
  - تحدث أو تنشئ سجل في `daily_attendance_summary` مع تفاصيل الخصم

## تدفق العمل

### 1. في نهاية اليوم
```
check-daily-absences function
  ↓
التحقق من الموظفين الذين لم يسجلوا حضور
  ↓
إنشاء سجلات غياب في جدول absences
  ↓
إرسال إشعارات للمديرين/الأونر
```

### 2. عند مراجعة الغياب
```
المدير/الأونر يراجع الغياب
  ↓
استدعاء approve-absence function
  ↓
إذا تمت الموافقة:
  - حساب الخصم (يومين)
  - إنشاء سجل خصم
  - تحديث daily_attendance_summary
```

## حساب الخصم

### الصيغة:
```
عدد ساعات الشيفت = (shift_end_time - shift_start_time)
قيمة اليوم الواحد = عدد ساعات الشيفت × سعر الساعة
الخصم = قيمة اليوم الواحد × 2
```

### مثال:
- `shift_start_time`: "09:00"
- `shift_end_time`: "17:00"
- `hourly_rate`: 40.00 جنيه

الحساب:
- عدد ساعات الشيفت: 8 ساعات
- قيمة اليوم الواحد: 8 × 40 = 320 جنيه
- الخصم (يومين): 320 × 2 = **640 جنيه**

## الجداول المستخدمة

### 1. `absences`
- `id`: معرف الغياب
- `employee_id`: معرف الموظف
- `branch_id`: معرف الفرع
- `absence_date`: تاريخ الغياب
- `shift_start_time`: وقت بداية الشيفت
- `shift_end_time`: وقت نهاية الشيفت
- `status`: الحالة (pending, approved, rejected)
- `deduction_amount`: قيمة الخصم

### 2. `deductions`
- `id`: معرف الخصم
- `employee_id`: معرف الموظف
- `absence_id`: معرف الغياب المرتبط
- `amount`: قيمة الخصم (سالب)
- `reason`: سبب الخصم
- `deduction_date`: تاريخ الخصم

### 3. `daily_attendance_summary`
- `employee_id`: معرف الموظف
- `attendance_date`: تاريخ الحضور/الغياب
- `deduction_amount`: قيمة الخصم
- `is_absent`: هل الموظف غائب
- `hourly_rate`: سعر الساعة

## إعداد Cron Job

### الطريقة 1: عبر SQL
```sql
-- تفعيل pg_cron
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- إعداد cron job
SELECT cron.schedule(
  'check-daily-absences',
  '0 23 * * *', -- 11:00 PM Cairo time
  $$
  SELECT
    net.http_post(
      url := 'https://YOUR_PROJECT.supabase.co/functions/v1/check-daily-absences',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer YOUR_SERVICE_ROLE_KEY'
      ),
      body := '{}'::jsonb
    ) AS request_id;
  $$
);
```

### الطريقة 2: عبر Supabase Dashboard
1. اذهب إلى Database > Extensions
2. فعّل `pg_cron`
3. اذهب إلى Database > Cron Jobs
4. أضف cron job جديد مع الجدول الزمني `0 23 * * *`

## الاستخدام

### استدعاء التحقق من الغياب
```bash
curl -X POST https://YOUR_PROJECT.supabase.co/functions/v1/check-daily-absences \
  -H "Authorization: Bearer YOUR_ANON_KEY" \
  -H "Content-Type: application/json"
```

### الموافقة على الغياب
```bash
curl -X POST https://YOUR_PROJECT.supabase.co/functions/v1/approve-absence \
  -H "Authorization: Bearer YOUR_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "absence_id": "uuid-here",
    "reviewer_id": "manager-or-owner-id",
    "action": "approve",
    "reason": "موافق على الغياب"
  }'
```

## النشر

تم إضافة الوظائف إلى `DEPLOY_UPDATES.bat`:

```batch
Step 4: Deploying check-daily-absences function...
Step 5: Deploying approve-absence function...
```

لتطبيق التحديثات:
```bash
DEPLOY_UPDATES.bat
```

## ملاحظات مهمة

1. **التوقيت:** الوظيفة تستخدم توقيت القاهرة (UTC+2)
2. **التحقق:** الوظيفة تتحقق فقط من الموظفين النشطين
3. **التكرار:** الوظيفة تمنع إنشاء سجلات غياب مكررة
4. **الإشعارات:** يتم إرسال الإشعارات تلقائياً للمديرين/الأونر
5. **الخصم:** الخصم دائماً يومين عمل عند الموافقة على الغياب

## الاختبار

### اختبار يدوي:
1. استدعي `check-daily-absences` في نهاية يوم عمل
2. تحقق من إنشاء سجلات غياب في جدول `absences`
3. تحقق من وصول الإشعارات للمديرين/الأونر
4. استدعي `approve-absence` للموافقة على غياب
5. تحقق من إنشاء سجل خصم في `deductions`
6. تحقق من تحديث `daily_attendance_summary`

## الدعم

للمزيد من المعلومات، راجع:
- `supabase/functions/check-daily-absences/README.md`
- `supabase/functions/approve-absence/README.md`

