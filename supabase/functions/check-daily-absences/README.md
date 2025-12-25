# Check Daily Absences Function

## الوصف
هذه الوظيفة تتحقق من الموظفين الذين لم يسجلوا حضور (check-in) في نهاية اليوم وتقوم بإنشاء سجلات غياب وإرسال إشعارات.

## الوظيفة
- تتحقق من جميع الموظفين النشطين
- تتحقق من الموظفين الذين لم يسجلوا حضور بعد انتهاء وقت الشيفت
- تنشئ سجلات غياب في جدول `absences`
- ترسل إشعارات للمديرين (للموظفين) أو للأونر (للمديرين)

## الاستخدام

### استدعاء يدوي
```bash
curl -X POST https://YOUR_PROJECT.supabase.co/functions/v1/check-daily-absences \
  -H "Authorization: Bearer YOUR_ANON_KEY" \
  -H "Content-Type: application/json"
```

### إعداد Cron Job (pg_cron)

يمكنك إعداد cron job في Supabase لاستدعاء هذه الوظيفة تلقائياً في نهاية كل يوم:

```sql
-- تفعيل pg_cron extension
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- إعداد cron job لاستدعاء الوظيفة كل يوم في الساعة 11:00 مساءً (توقيت القاهرة)
SELECT cron.schedule(
  'check-daily-absences',
  '0 23 * * *', -- 11:00 PM Cairo time (UTC+2 = 21:00 UTC)
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

### إعداد Cron Job عبر Supabase Dashboard

1. اذهب إلى Supabase Dashboard
2. اذهب إلى Database > Extensions
3. فعّل `pg_cron` extension
4. اذهب إلى Database > Cron Jobs
5. أضف cron job جديد:
   - Name: `check-daily-absences`
   - Schedule: `0 23 * * *` (11:00 PM Cairo time)
   - SQL:
   ```sql
   SELECT
     net.http_post(
       url := 'https://YOUR_PROJECT.supabase.co/functions/v1/check-daily-absences',
       headers := jsonb_build_object(
         'Content-Type', 'application/json',
         'Authorization', 'Bearer YOUR_SERVICE_ROLE_KEY'
       ),
       body := '{}'::jsonb
     ) AS request_id;
   ```

## الاستجابة

```json
{
  "success": true,
  "message": "Checked absences for 2024-01-15",
  "absences_found": 2,
  "absences": [
    {
      "employee_id": "emp123",
      "employee_name": "أحمد محمد",
      "absence_id": "uuid-here",
      "deduction_amount": 640.00
    }
  ],
  "notifications_sent": 2,
  "notifications": [
    {
      "recipient_id": "manager123",
      "employee_name": "أحمد محمد"
    }
  ]
}
```

## ملاحظات
- الوظيفة تستخدم توقيت القاهرة (UTC+2)
- الوظيفة تتحقق فقط من الموظفين النشطين (`is_active = true`)
- الوظيفة تتحقق فقط من الموظفين الذين انتهى وقت شيفتهم
- الوظيفة تتخطى الموظفين الذين لديهم سجل حضور في نفس اليوم
- الوظيفة تتخطى الموظفين الذين لديهم سجل غياب موجود بالفعل

