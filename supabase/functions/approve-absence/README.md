# Approve Absence Function

## الوصف
هذه الوظيفة تتعامل مع الموافقة على الغياب وتطبيق الخصم (يومين عمل) في جدول `daily_attendance_summary`.

## الوظيفة
- تحديث حالة الغياب (موافق/مرفوض)
- حساب الخصم: يومين عمل = (عدد ساعات الشيفت × سعر الساعة) × 2
- إنشاء سجل خصم في جدول `deductions`
- تحديث أو إنشاء سجل في `daily_attendance_summary` مع تفاصيل الخصم

## الاستخدام

### استدعاء API
```bash
curl -X POST https://YOUR_PROJECT.supabase.co/functions/v1/approve-absence \
  -H "Authorization: Bearer YOUR_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "absence_id": "uuid-of-absence",
    "reviewer_id": "manager-or-owner-id",
    "action": "approve",
    "reason": "موافق على الغياب - سيتم خصم يومين"
  }'
```

### Parameters
- `absence_id` (required): معرف سجل الغياب
- `reviewer_id` (required): معرف المدير أو الأونر الذي يراجع الغياب
- `action` (required): `"approve"` أو `"reject"`
- `reason` (optional): سبب الموافقة أو الرفض

### الموافقة على الغياب (approve)
عند الموافقة على الغياب:
1. يتم تحديث حالة الغياب إلى `approved`
2. يتم حساب الخصم: (عدد ساعات الشيفت × سعر الساعة) × 2
3. يتم إنشاء سجل خصم في جدول `deductions`
4. يتم تحديث أو إنشاء سجل في `daily_attendance_summary` مع:
   - `deduction_amount`: قيمة الخصم
   - `is_absent`: `true`
   - `attendance_date`: تاريخ الغياب

### رفض الغياب (reject)
عند رفض الغياب:
- يتم تحديث حالة الغياب إلى `rejected`
- لا يتم تطبيق أي خصم

## الاستجابة عند الموافقة

```json
{
  "success": true,
  "message": "تم الموافقة على الغياب وتم خصم 640.00 جنيه (يومين عمل)",
  "absence": {
    "id": "uuid-here",
    "status": "approved",
    "deduction_amount": 640.00
  },
  "deduction": {
    "id": "deduction-uuid",
    "amount": -640.00,
    "reason": "خصم غياب يوم 2024-01-15 - 640.00 جنيه (يومين عمل)"
  },
  "daily_summary_updated": true
}
```

## مثال على حساب الخصم

إذا كان الموظف لديه:
- `shift_start_time`: "09:00"
- `shift_end_time`: "17:00"
- `hourly_rate`: 40.00 جنيه

الحساب:
- عدد ساعات الشيفت: 8 ساعات
- قيمة اليوم الواحد: 8 × 40 = 320 جنيه
- الخصم (يومين): 320 × 2 = 640 جنيه

## ملاحظات
- الخصم يتم حسابه تلقائياً بناءً على ساعات الشيفت وسعر الساعة
- الخصم دائماً يومين عمل
- يتم تسجيل الخصم في `daily_attendance_summary` بتاريخ الغياب
- قيمة الخصم في جدول `deductions` تكون سالبة (negative)

