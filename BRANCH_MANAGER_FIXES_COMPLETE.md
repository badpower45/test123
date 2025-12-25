# إصلاح مشاكل لوحة المدير - Branch Manager Fixes

## المشاكل التي تم حلها ✅

### 1. مشكلة حذف الموظف (FK Constraint Violation)
**المشكلة:** عند حذف موظف، تحدث أخطاء بسبب Foreign Key Constraints في جداول الطلبات.

**الحل:**
- إنشاء migration: `20251116_set_null_on_delete_manager.sql`
- تغيير FK constraints إلى `ON DELETE SET NULL` بدلاً من `ON DELETE CASCADE`
- الجداول المعدلة:
  - `leave_requests.assigned_manager_id`
  - `salary_advances.assigned_manager_id`
  - `attendance_requests.assigned_manager_id`

**الملفات المعدلة:**
- `supabase/functions/migrations/20251116_set_null_on_delete_manager.sql`

---

### 2. مشكلة عرض طلبات الفرع الآخر (Cross-Branch Request Visibility)
**المشكلة:** مدير طرح البحر يرى طلبات فرع بورفؤاد والعكس.

**الحل:**
- إضافة عمود `assigned_manager_id` لجدول `breaks` (migration: `20251116_add_manager_to_breaks.sql`)
- تحديث Edge Function `branch-requests` لتصفية الطلبات حسب `manager_id`
- تحديث Edge Function `manager-pending-requests` لتصفية طلبات الاستراحة حسب `assigned_manager_id`
- تطبيق تصفية على جميع أنواع الطلبات:
  - طلبات الإجازات (leave_requests)
  - طلبات السلف (salary_advances)
  - طلبات الحضور/الانصراف (attendance_requests)
  - طلبات الاستراحة (breaks) ← تم إضافة العمود الجديد

**الملفات المعدلة:**
- `supabase/functions/migrations/20251116_add_manager_to_breaks.sql`
- `supabase/functions/branch-requests/index.ts`
- `supabase/functions/manager-pending-requests/index.ts`

---

### 3. مشكلة عدم ظهور أزرار الموافقة/الرفض للاستراحة
**المشكلة:** طلبات الاستراحة لا تظهر عليها أزرار الموافقة/الرفض في لوحة المدير.

**الحل:**
- إصلاح دالة `_buildBreakCard` في `branch_manager_screen.dart`
- إضافة فحص لحالة الطلب (pending/PENDING) مع تجاهل حالة الأحرف (case-insensitive)
- إضافة دالة `_reviewBreakRequest` للتعامل مع الموافقة/الرفض/التأجيل
- إضافة دالة `_getStatusColor` لتحديد لون الحالة

**التغييرات:**
```dart
// فحص الحالة بطريقة صحيحة
final breakStatus = (breakReq['status'] ?? '').toString();
final showActions = breakStatus.isEmpty || 
                   breakStatus.toLowerCase() == 'pending' || 
                   breakStatus.toUpperCase() == 'PENDING';

// عرض الأزرار
if (showActions) ...[
  Row(children: [
    ElevatedButton.icon(..., onPressed: () => _reviewBreakRequest(id, 'approve')),
    ElevatedButton.icon(..., onPressed: () => _reviewBreakRequest(id, 'reject')),
    ElevatedButton.icon(..., onPressed: () => _reviewBreakRequest(id, 'postpone')),
  ])
]
```

**الملفات المعدلة:**
- `lib/screens/branch_manager_screen.dart`

---

### 4. إصلاح الأخطاء البرمجية (94+ Compilation Errors)
**المشكلة:** أخطاء برمجية في `_buildBreakCard` بسبب:
- تكرار تعريف متغير `breakStatus`
- أقواس غير مغلقة
- دوال مفقودة

**الحل:**
- إعادة بناء دالة `_buildBreakCard` بالكامل
- إضافة دالة `_reviewBreakRequest` للتعامل مع طلبات الاستراحة
- إضافة دالة `_getStatusColor` لتحديد الألوان
- إصلاح جميع الأقواس والبنية الهيكلية

**الملفات المعدلة:**
- `lib/screens/branch_manager_screen.dart`

---

## خطوات التطبيق على السيرفر

### 1. تطبيق Migration للـ Foreign Keys
```bash
# تشغيل migration لتغيير ON DELETE CASCADE إلى ON DELETE SET NULL
psql -h <supabase-host> -U postgres -d postgres -f supabase/functions/migrations/20251116_set_null_on_delete_manager.sql
```

### 2. تطبيق Migration لإضافة assigned_manager_id للـ breaks
```bash
# تشغيل migration لإضافة عمود assigned_manager_id
psql -h <supabase-host> -U postgres -d postgres -f supabase/functions/migrations/20251116_add_manager_to_breaks.sql
```

### 3. نشر Edge Functions
```bash
# نشر branch-requests
supabase functions deploy branch-requests

# نشر manager-pending-requests
supabase functions deploy manager-pending-requests
```

### 4. اختبار التطبيق
```bash
# تشغيل التطبيق
flutter run
```

---

## اختبارات يجب إجراؤها

### ✅ اختبار حذف الموظف
1. حذف موظف لديه طلبات معلقة
2. التأكد من عدم حدوث أخطاء FK constraint
3. التحقق من أن الطلبات لا تزال موجودة مع `assigned_manager_id = NULL`

### ✅ اختبار عرض الطلبات حسب الفرع
1. تسجيل الدخول كمدير فرع طرح البحر
2. التأكد من ظهور طلبات موظفي طرح البحر فقط
3. تسجيل الدخول كمدير فرع بورفؤاد
4. التأكد من ظهور طلبات موظفي بورفؤاد فقط

### ✅ اختبار أزرار الموافقة/الرفض للاستراحة
1. إنشاء طلب استراحة من حساب موظف
2. تسجيل الدخول كمدير الفرع
3. التأكد من ظهور أزرار: موافقة، رفض، تأجيل
4. اختبار كل زر والتحقق من تغيير الحالة

---

## الملفات المعدلة - ملخص

### Backend (Supabase)
```
supabase/functions/migrations/
├── 20251116_set_null_on_delete_manager.sql     ← جديد (FK constraints)
└── 20251116_add_manager_to_breaks.sql          ← جديد (assigned_manager_id)

supabase/functions/
├── branch-requests/index.ts                    ← معدل (تصفية breaks)
└── manager-pending-requests/index.ts           ← معدل (استخدام assigned_manager_id)
```

### Frontend (Flutter)
```
lib/screens/
└── branch_manager_screen.dart                  ← معدل بالكامل
    ├── _buildBreakCard()                       ← إعادة بناء
    ├── _reviewBreakRequest()                   ← جديد
    └── _getStatusColor()                       ← جديد
```

---

## ملاحظات مهمة

1. **حذف الموظف:** الآن يمكن حذف الموظفين بدون مشاكل، والطلبات المعلقة ستبقى مع `assigned_manager_id = NULL`

2. **التصفية حسب الفرع:** جميع الطلبات (leave, salary, attendance, breaks) الآن تُصفى حسب `assigned_manager_id`

3. **طلبات الاستراحة:** تم إضافة عمود `assigned_manager_id` لجدول `breaks` لضمان التصفية الصحيحة

4. **الأزرار:** جميع طلبات الاستراحة المعلقة (pending/PENDING) تظهر عليها الأزرار بشكل صحيح

---

## ما تم تحسينه

- ✅ إصلاح 94+ خطأ برمجي في `branch_manager_screen.dart`
- ✅ حل مشكلة FK constraint عند حذف الموظف
- ✅ منع ظهور طلبات الفرع الآخر للمدير
- ✅ إضافة أزرار الموافقة/الرفض/التأجيل لطلبات الاستراحة
- ✅ تحسين Edge Functions للتصفية الصحيحة
- ✅ إضافة logging مفصل في Edge Functions لتتبع الطلبات

---

**تاريخ الإصلاح:** 16 نوفمبر 2024
**الحالة:** ✅ جاهز للنشر والاختبار
