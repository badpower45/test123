# Delete Employee Edge Function

## الوصف
هذه الـ Edge Function تقوم بحذف الموظف وجميع السجلات المرتبطة به من قاعدة البيانات.

## الميزات
- ✅ حذف جميع السجلات المرتبطة بالموظف تلقائياً
- ✅ حذف من جميع الجداول المرتبطة (pulses, breaks, attendance, إلخ)
- ✅ فك ارتباط المدير من الفروع (إذا كان مديراً)
- ✅ استخدام SERVICE_ROLE_KEY لتجاوز RLS policies

## الجداول التي يتم حذفها
1. `pulses` - النبضات
2. `breaks` - الاستراحات
3. `attendance` - الحضور
4. `device_sessions` - جلسات الأجهزة
5. `notifications` - الإشعارات
6. `salary_calculations` - حسابات الرواتب
7. `attendance_requests` - طلبات الحضور
8. `leave_requests` - طلبات الإجازة
9. `salary_advances` - السلف
10. `deductions` - الخصومات
11. `absences` - الغياب
12. `absence_notifications` - إشعارات الغياب
13. `branch_managers` - روابط مديري الفروع

## الاستخدام

### من Flutter App:
```dart
final success = await SupabaseAuthService.deleteEmployee(employeeId);
```

### من HTTP Request:
```bash
curl -X DELETE 'https://YOUR_PROJECT.supabase.co/functions/v1/delete-employee?employee_id=EMP001' \
  -H 'Authorization: Bearer YOUR_ANON_KEY' \
  -H 'Content-Type: application/json'
```

## Parameters
- `employee_id` (query parameter): معرف الموظف المراد حذفه

## Response
```json
{
  "success": true,
  "message": "تم حذف الموظف وجميع سجلاته المرتبطة بنجاح",
  "employeeId": "EMP001"
}
```

## Errors
- `400`: `employee_id` غير موجود
- `404`: الموظف غير موجود
- `500`: خطأ في حذف الموظف

## الرفع
```bash
supabase functions deploy delete-employee --no-verify-jwt
```

أو استخدم ملف deploy script:
```bash
cd supabase/functions/delete-employee
chmod +x deploy.sh
./deploy.sh
```

## ملاحظات
- الـ Function تستخدم SERVICE_ROLE_KEY لذلك لا تحتاج للتحقق من المستخدم
- جميع عمليات الحذف تتم بشكل تسلسلي
- إذا فشل حذف من جدول معين، سيتم الاستمرار في حذف الجداول الأخرى

