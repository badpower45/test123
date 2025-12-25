# تعليمات رفع تحديث sync-pulses على Supabase

## التغييرات المطلوبة

تم تحديث `supabase/functions/sync-pulses/index.ts` لإضافة:
1. تحديث جدول `attendance` بناءً على النبضات
2. تحديث جدول `daily_attendance_summary` لتقارير الحضور والمرتب
3. حساب ساعات العمل من النبضات (كل نبضة داخل الجيوفنس = 5 دقائق)

## خطوات الرفع

### 1. التأكد من وجود Supabase CLI
```bash
npm install -g supabase
```

### 2. تسجيل الدخول إلى Supabase
```bash
supabase login
```

### 3. ربط المشروع
```bash
supabase link --project-ref bbxuyuaemigrqsvsnxkj
```

### 4. رفع Edge Function
```bash
supabase functions deploy sync-pulses
```

### 5. التأكد من المتغيرات البيئية
تأكد من وجود المتغيرات التالية في Supabase Dashboard:
- `SUPABASE_URL`: https://bbxuyuaemigrqsvsnxkj.supabase.co
- `SERVICE_ROLE_KEY`: (من Supabase Dashboard > Settings > API)

## التحقق من الرفع

بعد الرفع، يمكنك اختبار الـ function من خلال:
1. الذهاب إلى Supabase Dashboard > Edge Functions
2. اختبار `sync-pulses` function
3. التأكد من أن البيانات تُحدث في جدول `attendance` و `daily_attendance_summary`

## ملاحظات مهمة

- تأكد من أن جدول `daily_attendance_summary` موجود في قاعدة البيانات
- تأكد من وجود `hourly_rate` في جدول `employees`
- تأكد من أن `pulses` table يحتوي على `bssid_address` column

