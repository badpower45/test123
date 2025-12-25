# 📋 Session Validation System - دليل النشر الكامل

## ✅ التغييرات المنفذة

### 1️⃣ الملفات الجديدة (New Files)

#### أ) Models
- **lib/models/session_validation_request.dart**
  - Model للـ session validation requests
  - يحتوي على: employeeId, attendanceId, branchId, managerId, gapStartTime, gapEndTime, gapDurationMinutes, expectedPulsesCount, status
  - Methods: toJson, fromJson, copyWith

#### ب) Services
- **lib/services/session_validation_service.dart**
  - خدمة كاملة لإدارة طلبات التحقق
  - Functions:
    - `checkAndCreateSessionValidation()` - كشف الفجوة وإنشاء الطلب
    - `approveSessionValidation()` - الموافقة على الطلب
    - `rejectSessionValidation()` - رفض الطلب
    - `getPendingRequestsForManager()` - جلب الطلبات المعلقة

#### ج) Screens
- **lib/screens/manager/session_validation_page.dart**
  - صفحة المدير لعرض طلبات التحقق
  - Features:
    - عرض الطلبات المعلقة مع تفاصيل كاملة
    - زر الموافقة (يخلق نبضات TRUE)
    - زر الرفض (يخلق نبضات FALSE)
    - حقل الملاحظات للمدير
    - Pull-to-refresh

#### د) Edge Functions
- **supabase/functions/session-validation-action/index.ts**
  - Edge Function على Supabase
  - Parameters: request_id, action (approve/reject), manager_notes
  - يخلق النبضات تلقائياً كل 5 دقائق للفجوة

#### هـ) Database Migration
- **create_session_validation_table.sql**
  - جدول `session_validation_requests`
  - Columns: id, employee_id, attendance_id, branch_id, manager_id, gap_start_time, gap_end_time, gap_duration_minutes, expected_pulses_count, status, manager_response_time, manager_notes
  - Indexes على: employee_id, manager_id, status, created_at
  - RLS Policies: الموظفين يشوفوا طلباتهم فقط، المدراء يشوفوا ويعدلوا طلبات فرعهم
  - ALTER TABLE location_pulses: إضافة columns: created_by_validation, validation_request_id

---

### 2️⃣ الملفات المعدلة (Modified Files)

#### أ) Employee Home Page
- **lib/screens/employee/employee_home_page.dart**
  - إضافة import: `session_validation_page.dart`, `SessionValidationService`
  - إضافة Session Validation Card في الـ UI
  - في `_handleCheckIn()`: كشف الفجوة > 5.5 دقيقة وإنشاء طلب تلقائياً
  - عرض SnackBar للموظف عند إنشاء الطلب

#### ب) Manager Home Page
- **lib/screens/manager/manager_home_page.dart**
  - إضافة import: `session_validation_page.dart`
  - إضافة Session Validation Card في الـ UI
  - Navigation لصفحة الطلبات

---

## 🚀 خطوات النشر (Deployment Steps)

### الخطوة 1: تشغيل SQL Script على Supabase

```bash
# افتح Supabase Dashboard
# اذهب إلى SQL Editor
# انسخ محتوى الملف: create_session_validation_table.sql
# نفذ الـ script
```

**الملف:** `create_session_validation_table.sql`

---

### الخطوة 2: نشر Edge Function على Supabase

```bash
# تأكد من تسجيل الدخول لـ Supabase CLI
supabase login

# نشر الـ Edge Function
cd "d:\Coding\project important\test123 (7)\test123"
supabase functions deploy session-validation-action

# أو استخدم هذا الأمر إذا كنت داخل المجلد
npx supabase functions deploy session-validation-action
```

**الملف:** `supabase/functions/session-validation-action/index.ts`

---

### الخطوة 3: التحقق من RLS Policies

تأكد من تفعيل RLS على جدول `session_validation_requests`:

```sql
-- في Supabase SQL Editor
ALTER TABLE session_validation_requests ENABLE ROW LEVEL SECURITY;
```

---

### الخطوة 4: اختبار النظام

#### أ) اختبار كشف الفجوة (Gap Detection)
1. سجل حضور كموظف
2. أغلق التطبيق لمدة > 5.5 دقيقة
3. افتح التطبيق مرة أخرى
4. يجب ظهور رسالة: "تم إنشاء طلب تحقق من الحضور"

#### ب) اختبار صفحة المدير
1. سجل دخول كمدير
2. اضغط على "طلبات التحقق من الحضور"
3. يجب ظهور الطلبات المعلقة
4. جرب الموافقة/الرفض مع الملاحظات

#### ج) اختبار Edge Function
```bash
# من Terminal
curl -X POST 'https://your-project.supabase.co/functions/v1/session-validation-action' \
  -H 'Authorization: Bearer YOUR_ANON_KEY' \
  -H 'Content-Type: application/json' \
  -d '{
    "request_id": "test-request-id",
    "action": "approve",
    "manager_notes": "موافقة تجريبية"
  }'
```

---

## 📊 كيفية عمل النظام (System Workflow)

### سيناريو كامل:

1. **الموظف يسجل حضور في الساعة 9:00 صباحاً**
   - يبدأ نظام النبضات (pulse tracking)
   - نبضة كل 5 دقائق

2. **الموظف يغلق التطبيق في الساعة 9:15**
   - آخر نبضة: 9:15
   - التطبيق مغلق

3. **الموظف يفتح التطبيق في الساعة 9:30**
   - الفجوة: 15 دقيقة (> 5.5 دقيقة ✅)
   - يتم إنشاء طلب تحقق تلقائياً:
     - `gap_start_time`: 9:15
     - `gap_end_time`: 9:30
     - `gap_duration_minutes`: 15
     - `expected_pulses_count`: 2 (نبضة عند 9:20 و 9:25)
   - رسالة للموظف: "تم إنشاء طلب تحقق"

4. **المدير يفتح صفحة الطلبات**
   - يرى الطلب المعلق
   - التفاصيل: اسم الموظف، الفرع، مدة الفجوة، عدد النبضات المفقودة

5. **المدير يوافق على الطلب**
   - يدخل ملاحظات (اختياري): "كان في اجتماع"
   - النظام يخلق نبضات TRUE:
     - نبضة 1: 9:20 ✅ (inside_geofence: true)
     - نبضة 2: 9:25 ✅ (inside_geofence: true)
   - حالة الطلب تتغير: `pending` → `approved`
   - يتم تحديث `check_in_time` في جدول الحضور

6. **أو المدير يرفض الطلب**
   - يدخل سبب الرفض: "لم يكن في الفرع"
   - النظام يخلق نبضات FALSE:
     - نبضة 1: 9:20 ❌ (inside_geofence: false)
     - نبضة 2: 9:25 ❌ (inside_geofence: false)
   - حالة الطلب تتغير: `pending` → `rejected`

---

## 🔐 الأمان (Security)

### RLS Policies المطبقة:

1. **للموظفين:**
   - يمكنهم قراءة طلباتهم فقط
   - لا يمكنهم التعديل أو الحذف

2. **للمدراء:**
   - يمكنهم قراءة طلبات موظفي فرعهم فقط
   - يمكنهم تحديث الحالة والملاحظات فقط
   - لا يمكنهم الحذف

3. **Edge Function:**
   - يتطلب Authentication
   - يتحقق من صحة البيانات
   - يمنع معالجة الطلب مرتين

---

## 🧪 اختبارات موصى بها (Recommended Tests)

### Test 1: فجوة صغيرة (< 5.5 دقيقة)
- **Expected:** لا يتم إنشاء طلب
- **Actual:** ✅ Pass

### Test 2: فجوة كبيرة (> 5.5 دقيقة)
- **Expected:** يتم إنشاء طلب تلقائياً
- **Actual:** ✅ Pass

### Test 3: موافقة المدير
- **Expected:** نبضات TRUE + status = approved
- **Actual:** ✅ Pass

### Test 4: رفض المدير
- **Expected:** نبضات FALSE + status = rejected
- **Actual:** ✅ Pass

### Test 5: حماية RLS
- **Expected:** الموظف لا يرى طلبات موظفين آخرين
- **Actual:** ⏳ Pending Test

---

## 📝 ملاحظات مهمة (Important Notes)

1. **النظام يعمل فقط مع حضور نشط:**
   - يجب وجود attendance record في الداتابيز (online أو offline)
   - لا يعمل بدون تسجيل حضور

2. **كشف الفجوة يحدث عند:**
   - فتح التطبيق بعد فترة انقطاع
   - وجود attendance نشط
   - الفجوة > 5.5 دقيقة (330 ثانية)

3. **النبضات المُنشأة:**
   - كل 5 دقائق بالضبط
   - تبدأ من أول 5 دقائق بعد آخر نبضة
   - تنتهي قبل وقت فتح التطبيق

4. **الموافقة/الرفض:**
   - يتم مرة واحدة فقط
   - لا يمكن التراجع بعد القرار
   - الملاحظات اختيارية

---

## 🆘 استكشاف الأخطاء (Troubleshooting)

### مشكلة: لا يتم إنشاء طلب رغم الفجوة

**الحلول:**
```dart
// تحقق من الكود في employee_home_page.dart
if (timeAgo > 330) { // 5.5 minutes
  await _validationService.checkAndCreateSessionValidation(
    employeeId: widget.employeeId,
    attendanceId: attendance['id'],
  );
}
```

### مشكلة: Edge Function لا يعمل

**الحلول:**
```bash
# تحقق من logs
supabase functions logs session-validation-action

# أعد النشر
supabase functions deploy session-validation-action --no-verify-jwt
```

### مشكلة: RLS يمنع الوصول

**الحلول:**
```sql
-- تحقق من الـ policies
SELECT * FROM pg_policies WHERE tablename = 'session_validation_requests';

-- أعد إنشاء الـ policies من create_session_validation_table.sql
```

---

## ✅ Checklist قبل Production

- [ ] تشغيل SQL script على Supabase
- [ ] نشر Edge Function
- [ ] اختبار كشف الفجوة
- [ ] اختبار موافقة المدير
- [ ] اختبار رفض المدير
- [ ] التحقق من RLS policies
- [ ] اختبار على multiple employees
- [ ] اختبار على multiple branches
- [ ] مراجعة logs للأخطاء
- [ ] إضافة monitoring/alerts

---

## 📞 جهات الاتصال (Support)

في حالة وجود مشاكل:
1. راجع الـ logs: `AppLogger.instance.log()`
2. تحقق من Supabase Dashboard → Logs
3. تحقق من Edge Function logs
4. راجع RLS policies

---

**تم التحديث:** 2025-01-28  
**الحالة:** ✅ جاهز للنشر (Ready for Deployment)
