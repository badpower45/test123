# 🚀 Oldies Workers - دليل التشغيل الكامل

## ✅ الحالة الحالية

### السيرفر Node.js
- ✅ **يعمل بنجاح** على http://127.0.0.1:5000
- ✅ قاعدة البيانات متصلة (PostgreSQL/Neon)
- ✅ جميع الـ APIs شغالة

### صفحة الاختبار
- ✅ متاحة على: http://127.0.0.1:5000/test-api.html
- يمكنك اختبار جميع الوظائف من المتصفح

## 📝 ملاحظات مهمة

### 1. المشكلة التي تم حلها
- كانت المشكلة في `ensureTestEmployee()` - تم تعطيلها مؤقتاً
- السيرفر الآن يعمل بشكل مستقر

### 2. الأوامر الصحيحة للتشغيل

#### تشغيل السيرفر:
```bash
npm run dev:simple
```
**لا تستخدم** `npm run dev` (tsx watch تسبب مشاكل)

#### تشغيل Flutter:
```bash
flutter run -d windows
```
أو من VS Code: اضغط F5

## 🔧 التعديلات التي تمت

### 1. API Endpoints (lib/constants/api_endpoints.dart)
```dart
const String API_BASE_URL = 'http://localhost:5000/api';
const String ROOT_BASE_URL = 'http://localhost:5000';
```

### 2. Server Configuration (server/index.ts)
- إضافة `0.0.0.0` binding للـ IPv4
- إضافة error handling محسّن
- تعطيل `ensureTestEmployee()` المؤقت
- إضافة keep-alive interval

### 3. Package.json
```json
"dev:simple": "tsx server/index.ts"  // استخدم هذا الأمر
```

## 🧪 اختبار النظام

### 1. اختبار السيرفر من المتصفح:
- افتح: http://127.0.0.1:5000/health
- يجب أن ترى: `{"status":"ok","message":"Oldies Workers API is running"}`

### 2. اختبار صفحة التجربة:
- افتح: http://127.0.0.1:5000/test-api.html
- جرب:
  - عرض حالة الموظف (EMP001)
  - طلب إجازة
  - طلب سلفة
  - إرسال نبضة

### 3. اختبار Flutter:
- شغل `flutter run -d windows`
- سجل دخول بـ:
  - Employee ID: `EMP001`
  - PIN: `1234`

## 📊 Endpoints الموجودة

### Authentication
- POST `/api/auth/login` - تسجيل الدخول

### Attendance
- POST `/api/attendance/check-in` - تسجيل حضور
- POST `/api/attendance/check-out` - تسجيل انصراف
- GET `/api/employees/:id/status` - **جديد!** عرض حالة الموظف والنبضات
- DELETE `/api/attendance/:id` - **جديد!** حذف سجل حضور

### Pulses
- POST `/api/pulses` - إرسال نبضة
- تتحفظ كل نبضة في الداتابيز

### Leave Requests
- POST `/api/leave/request` - طلب إجازة
- GET `/api/leave/requests` - عرض طلبات الإجازة
- POST `/api/leave/requests/:id/review` - الموافقة/الرفض

### Advances  
- POST `/api/advances/request` - طلب سلفة
- GET `/api/advances` - عرض طلبات السلف
- POST `/api/advances/:id/review` - الموافقة/الرفض

## 🐛 استكشاف الأخطاء

### إذا السيرفر مش شغال:
```bash
# 1. أقفل كل عمليات Node
taskkill /F /IM node.exe

# 2. شغل السيرفر من جديد
npm run dev:simple
```

### إذا Flutter مش شغال:
```bash
# 1. نظف المشروع
flutter clean

# 2. احصل على الـ dependencies
flutter pub get

# 3. شغل مرة تانية
flutter run -d windows
```

### إذا فيه مشكلة CORS:
- السيرفر فيه `cors()` middleware مفعّل
- يسمح بكل الـ origins

## 🎯 الخطوات التالية

1. ✅ السيرفر شغال
2. ✅ الداتابيز متصلة
3. ✅ الـ APIs كلها جاهزة
4. ⏳ Flutter - جرب تشغله بـ F5 من VS Code
5. ⏳ اختبر كل الوظائف من صفحة الاختبار

## 📱 الموظفين المتاحين للاختبار

### EMP001 - أحمد علي
- PIN: 1234
- Role: Staff
- Branch: فرع المعادي

### EMP002 - سارة أحمد  
- PIN: 2222
- Role: Staff

### EMP003 - محمد حسن
- PIN: 3333
- Role: Manager

### EMP004 - فاطمة محمد
- PIN: 4444
- Role: Staff

## 🎉 كل حاجة جاهزة!

السيرفر شغال والـ APIs كلها تعمل. افتح صفحة الاختبار وابدأ التجربة! 🚀
