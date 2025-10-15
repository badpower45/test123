# Oldies Workers API Contract (October 2025)

هذا المستند يلخص نقاط التكامل الأساسية بين واجهة الموظفين ولوحة المدير مع الـ Backend الحالي. جميع المسارات تعمل عبر `https://api.oldies.com` أو أي Base URL مماثل يتم ضبطه في `API_BASE_URL`.

> **ملاحظة:** كل الردود بصيغة JSON وتحتوي على `success`, `message`, أو `error` بالإضافة إلى الحمولة الخاصة بكل مسار. يتم حماية المسارات الحساسة عبر أذونات المدير لاحقًا.

## 1. المصادقة
- `POST /api/auth/login`
  - **Body:** `{ "employee_id": "EMP001", "pin": "1234" }`
  - **رد صالح:** بيانات الموظف النشطة والفرع والوظيفة.

## 2. الحضور والانصراف
- `POST /api/attendance/check-in`
  - يمنع التسجيل مرتين في نفس اليوم.
  - ينشئ Pulse للموقع إذا تم تمرير `latitude` و `longitude`.
- `POST /api/attendance/check-out`
  - يتطلب وجود حضور فعّال في نفس اليوم.
  - يحسب `workHours` تلقائيًا.

## 3. طلبات الحضور المتأخرة
- `POST /api/attendance/request-checkin`
- `POST /api/attendance/request-checkout`
  - **Body:** `{ "employee_id": "EMP001", "requested_time": "2025-10-15T09:30:00Z", "reason": "نست الحضور" }`
  - الحالة الافتراضية `pending` لحين مراجعة المدير.
- `GET /api/attendance/requests?status=pending`
- `POST /api/attendance/requests/{requestId}/review`
  - **Body:** `{ "action": "approve", "reviewer_id": "ADMIN01", "notes": "تم التأكد" }`
  - عند الموافقة يتم تعديل سجلات الحضور تلقائيًا (إنشاء check-in أو إغلاق check-out).

## 4. الإجازات
- `POST /api/leave/request`
  - يحدد النوع تلقائيًا: `regular` إذا كان الطلب قبل ≥48 ساعة، `emergency` خلاف ذلك مع سبب إجباري.
  - يصرف بدل إجازة 100 جنيه لكل يوم حتى يومين.
- `GET /api/leave/requests?employee_id=EMP001`
- `POST /api/leave/requests/{requestId}/review`
  - موافقة المدير تحفظ التاريخ والملاحظات.

## 5. السلف
- `POST /api/advances/request`
  - يتحقق من مرور 5 أيام منذ آخر سلفة.
  - الحد الأقصى 30% من `monthlySalary` الحالي.
- `GET /api/advances?employee_id=EMP001`
- `POST /api/advances/{advanceId}/review`
  - عند الموافقة يتم ختم `paidAt` بتاريخ اليوم.

## 6. الغياب والخصومات
- `POST /api/absence/notify`
  - يستخدم عندما لا يحضر الموظف ويحتاج إخطار المدير.
- `GET /api/absence/notifications?status=pending`
- `POST /api/absence/{notificationId}/apply-deduction`
  - القيمة الافتراضية 400 جنيه (يومان عمل). يتمكن المدير من تمرير `amount` مخصص.

## 7. التقارير الشهرية
- `GET /api/reports/attendance/{employeeId}?start_date=2025-10-01&end_date=2025-10-15`
  - **قيود العمل:** متاح فقط يوم 1 و 16 من كل شهر.
  - يعيد:
    - سجلات الحضور مع الساعات الإجمالية.
    - السلف المعتمدة في الفترة.
    - الإجازات المعتمدة في الفترة.
    - الخصومات المطبقة.
    - ملخص مالي (`summary`).

## 8. إدارة الموظفين
- `GET /api/employees`
- `GET /api/employees/{id}`
- `POST /api/employees`
  - لإضافة موظف جديد مع الراتب والفرع والدور.

## 9. لوحة المدير
- `GET /api/manager/dashboard`
  - يجمع طلبات الحضور، الإجازات، السلف، وإخطارات الغياب المعلقة مع ملخص للأعداد.

## 10. الفرق بين الأدوار
- الموظف العادي يستعمل مسارات الحضور، الطلبات، والتقارير.
- المدير / الأدمن يمتلك صلاحية الوصول إلى مراجعات الطلبات ولوحة القيادة.
- يوصى بدمج `requirePermission` في `server/auth.ts` لفرض الأذونات لكل مسار (الدوال جاهزة).

## 11. المهام التالية المقترحة
1. إضافة Endpoint مستقل لـ `GET /api/me/earnings` لعرض صافي الدخل الحالي.
2. تفعيل التحقق من الـ PIN عبر قاعدة البيانات بدل القبول المفتوح.
3. ربط إشعارات البريد أو WhatsApp عند إنشاء `absenceNotifications`.
4. إعداد اختبارات (integration tests) تغطي كل مسارات الطلبات والمراجعات.
