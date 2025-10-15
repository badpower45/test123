# دليل صفحات الموظف - Oldies Workers

## نظرة عامة
تم إنشاء صفحات الموظف الجديدة بتصميم عصري وواجهة عربية RTL كاملة. كل صفحة مربوطة بـ API endpoints جاهزة للتكامل مع الـ Backend.

## الصفحات الأساسية

### 1. الصفحة الرئيسية (Employee Home Page)
**الملف**: `lib/screens/employee/employee_home_page.dart`

#### المميزات:
- ✅ بطاقة الحالة (قيد العمل / خارج العمل)
- ✅ عداد مباشر لساعات العمل
- ✅ زر تسجيل الحضور/الانصراف
- ✅ زر طلب حضور (للموظفين الذين نسوا التسجيل)
- ✅ إحصائيات النبضات والاتصال

#### API Endpoints:
- `POST /api/attendance/check-in` - تسجيل الحضور
- `POST /api/attendance/check-out` - تسجيل الانصراف
- `POST /api/attendance/request-checkin` - طلب تسجيل حضور بعد النسيان
- `POST /api/attendance/request-checkout` - طلب تسجيل انصراف بعد النسيان

---

### 2. صفحة الطلبات (Requests Page)
**الملف**: `lib/screens/employee/requests_page.dart`

#### التبويبات:
1. **طلبات الإجازة**
   - إجازة عادية (قبلها ب48 ساعة)
   - إجازة طارئة (قبلها ب24 ساعة + سبب إجباري)
   - عرض الطلبات السابقة مع الحالة

2. **طلبات السلف**
   - عرض المرتب الحالي
   - حساب الحد الأقصى (30%)
   - منع طلب أكثر من المسموح
   - نظام السلف كل 5 أيام

#### API Endpoints:
- `POST /api/leave/request` - طلب إجازة جديد (عادي أو طارئ)
- `GET /api/leave/requests?employee_id=X` - جلب طلبات الإجازة حسب الموظف
- `POST /api/advances/request` - طلب سلفة جديدة (بنسبة 30%)
- `GET /api/advances?employee_id=X` - جلب طلبات السلف
- `GET /api/absence/notifications?status=pending` - عرض إخطارات الغياب للمدير

#### القواعد المطبقة:
- الإجازة العادية: قبلها ب48 ساعة على الأقل
- الإجازة الطارئة: قبلها ب24 ساعة + كتابة السبب
- السلفة: 30% كحد أقصى من المرتب الحالي

---

### 3. صفحة التقارير (Reports Page)
**الملف**: `lib/screens/employee/reports_page.dart`

#### المميزات:
- ✅ فتح التقرير فقط يوم 1 و 16 من كل شهر
- ✅ عداد الأيام المتبقية
- ✅ تقرير منتصف الشهر (1-15)
- ✅ تقرير نهاية الشهر (16-آخر الشهر)

#### محتوى التقرير:
- جدول مفصل بالتواريخ
- وقت الحضور والانصراف
- عدد ساعات العمل
- السلف المأخوذة
- الخصومات
- الإجازات

#### API Endpoints:
- `GET /api/reports/attendance/:employeeId?start_date=YYYY-MM-DD&end_date=YYYY-MM-DD`
   - التقرير يفتح فقط يوم 1 أو 16 تبعًا للسياسة (يتم رفض الطلب في الأيام الأخرى)

---

### 4. صفحة الملف الشخصي (Profile Page)
**الملف**: `lib/screens/employee/profile_page.dart`

#### المعلومات المعروضة:
- الاسم الكامل
- رقم الموظف
- الوظيفة
- الفرع
- الراتب الشهري

#### الإعدادات:
- تغيير الرقم السري
- إعدادات الإشعارات
- المساعدة والدعم
- تسجيل الخروج

---

## التنقل بين الصفحات

### Main Navigation (BottomNavigationBar)
**الملف**: `lib/screens/employee/employee_main_screen.dart`

التنقل يتم عبر Task Bar ثابت في الأسفل:
1. 🏠 **الرئيسية** - الحضور والانصراف
2. 📋 **الطلبات** - الإجازات والسلف
3. 📊 **التقارير** - تقرير الحضور الشهري
4. 👤 **ملفي** - المعلومات الشخصية

---

## Models البيانات

### 1. LeaveRequest
**الملف**: `lib/models/leave_request.dart`
```dart
enum LeaveType { normal, emergency }
enum RequestStatus { pending, approved, rejected }
```

### 2. AdvanceRequest
**الملف**: `lib/models/advance_request.dart`
- المبلغ المطلوب
- المرتب الحالي
- الحد الأقصى (30%)

### 3. AttendanceRequest
**الملف**: `lib/models/attendance_request.dart`
- وقت النسيان
- السبب

### 4. AttendanceReport
**الملف**: `lib/models/attendance_report.dart`
- بيانات الموظف
- الفترة (منتصف/نهاية الشهر)
- سجلات الحضور اليومية

---

## API Services

### RequestsApiService
**الملف**: `lib/services/requests_api_service.dart`

Methods:
- `createLeaveRequest()` - إنشاء طلب إجازة
- `getLeaveRequests()` - جلب طلبات الإجازة
- `createAdvanceRequest()` - إنشاء طلب سلفة
- `getAdvanceRequests()` - جلب طلبات السلف
- `createAttendanceRequest()` - إنشاء طلب حضور
- `getCurrentEarnings()` - جلب المرتب الحالي

### AttendanceApiService
**الملف**: `lib/services/attendance_api_service.dart`

Methods:
- `checkIn()` - تسجيل الحضور
- `checkOut()` - تسجيل الانصراف
- `getReport()` - جلب التقرير الشهري
- `getRecentShifts()` - جلب آخر الورديات

---

## التكامل مع Backend

### API Base URL
في ملف `lib/config/app_config.dart`:
```dart
static const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:3000',
);
```

### تغيير الـ URL:
```bash
flutter run --dart-define=API_BASE_URL=https://api.oldies.com
```

---

## قواعد العمل (Business Rules)

### نظام الإجازات:
1. **بدل الإجازة**: 100 جنيه
   - يُمنح للموظف الذي أخذ إجازة يوم أو يومين
   - لا يُمنح إذا غاب أكثر من يومين (حتى لو بإذن)
   - لا يوجد خصم إذا كان بإذن المدير

2. **الغياب بدون إذن**:
   - إرسال إشعار فوري للمدير
   - إذا وافق المدير على الخصم: يتم خصم يومين عمل

### نظام السلف:
- كل 5 أيام يحق للموظف طلب سلفة
- الحد الأقصى: 30% من المرتب الحالي
- يتم احتسابها تلقائياً وعرضها في التقرير

### نظام التقارير:
- يُفتح التقرير يوم 1 و 16 فقط
- يعرض كل التفاصيل:
  - التاريخ
  - وقت الحضور/الانصراف
  - عدد الساعات
  - السلف
  - الخصومات
  - الإجازات

---

## الخطوات التالية

### للمطورين:
1. ✅ تطوير Backend APIs المطلوبة
2. ✅ ربط الصفحات بالـ APIs الحقيقية
3. ✅ اختبار كل الـ flows
4. ✅ إضافة معالجة الأخطاء

### APIs الرئيسية الحالية:
- [x] POST /api/attendance/check-in
- [x] POST /api/attendance/check-out
- [x] POST /api/attendance/request-checkin
- [x] POST /api/attendance/request-checkout
- [x] GET /api/attendance/requests & POST /api/attendance/requests/:id/review
- [x] POST /api/leave/request & GET /api/leave/requests
- [x] POST /api/leave/requests/:id/review
- [x] POST /api/advances/request & GET /api/advances
- [x] POST /api/advances/:id/review
- [x] POST /api/absence/notify & GET /api/absence/notifications
- [x] POST /api/absence/:id/apply-deduction
- [x] GET /api/reports/attendance/:employeeId
- [ ] GET /api/me/earnings (قيد التخطيط)

---

## التشغيل

### Development:
```bash
flutter run -d web-server --web-hostname=0.0.0.0 --web-port=5000
```

### Build for Production:
```bash
flutter build web --release
dhttpd --host 0.0.0.0 --port 5000 --path build/web
```

---

## الملاحظات الفنية

1. **RTL Support**: جميع الصفحات تدعم العربية بشكل كامل
2. **Material Design 3**: تصميم عصري ومتجاوب
3. **Google Fonts**: استخدام IBM Plex Sans Arabic
4. **State Management**: StatefulWidget مع setState
5. **Offline Support**: Hive للتخزين المحلي
6. **API Integration**: HTTP client جاهز للربط

---

## المساهمة

لإضافة صفحة جديدة:
1. إنشاء ملف جديد في `lib/screens/employee/`
2. إضافة route في `lib/main.dart`
3. تحديث `EmployeeMainScreen` إذا لزم الأمر

---

تم التطوير بواسطة: Replit Agent
التاريخ: أكتوبر 2025
