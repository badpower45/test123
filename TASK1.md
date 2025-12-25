# TASK 1 - تحسينات شاملة لنظام الحضور والنبضات

## 📋 نظرة عامة
تطوير شامل لنظام تسجيل الحضور والنبضات ليعمل بشكل احترافي في الخلفية مع حل المشاكل الحالية وإضافة ميزات جديدة.

---

## 🎯 PHASE 1: إصلاح مشكلة التعليق عند فحص السيرفر
**الحالة:** 🔴 لم يبدأ

### المشكلة
عند تسجيل الحضور، التطبيق يتعلق عند فحص السجلات النشطة على السيرفر (getActiveAttendance).

### الحل
1. تغيير منطق `_checkForActiveAttendance()` للعمل offline-first
2. فحص السجلات المحلية أولاً (SharedPreferences, SQLite, Hive)
3. فحص السيرفر بـ timeout قصير (3-5 ثواني)
4. عدم منع المستخدم من المتابعة في حالة فشل السيرفر

### الملفات المطلوب تعديلها
- `lib/screens/employee/employee_home_page.dart` (method: `_checkForActiveAttendance`)

### التفاصيل التقنية
```dart
// Priority:
// 1. Check SharedPreferences (active_attendance_id)
// 2. Check SQLite/Hive (local pending check-in)
// 3. Check Server with timeout (3 seconds)
// 4. If all fail, allow check-in
```

---

## 🎯 PHASE 2: إضافة نظام Session Validation (فحص الجلسة)
**الحالة:** 🔴 لم يبدأ

### المشكلة
عند استكمال حضور قديم، قد يكون قد مر أكثر من 5.5 دقيقة بدون نبضات (النظام لم يكن يعمل).

### الحل
عند فتح التطبيق أو استكمال الحضور:

#### السيناريو 1: لا توجد نبضات منذ أكثر من 5.5 دقيقة
1. احسب الوقت بين آخر نبضة/تسجيل حضور والوقت الحالي
2. إذا كان > 5.5 دقيقة → إنشاء طلب موافقة للمدير
3. الطلب يحتوي على:
   - اسم الموظف
   - وقت البداية (آخر نبضة/تسجيل حضور)
   - وقت النهاية (الوقت الحالي)
   - السؤال: "هل كان الموظف موجوداً في الفرع خلال هذه الفترة؟"
   - خيارات: قبول / رفض

#### نتائج قرار المدير

**إذا وافق المدير:**
- إنشاء نبضات TRUE للفترة المفقودة (كل 5 دقائق)
- تحديث جدول `attendance` بـ check_in_time الصحيح
- حساب الوقت في المرتب

**إذا رفض المدير:**
- إنشاء نبضات FALSE للفترة المفقودة
- عدم حساب الوقت في المرتب
- إرسال تنبيه للموظف

### الملفات المطلوب إنشاؤها/تعديلها
- `lib/services/session_validation_service.dart` (جديد)
- `lib/models/session_validation_request.dart` (جديد)
- `lib/screens/employee/employee_home_page.dart` (تعديل)
- جدول جديد في Supabase: `session_validation_requests`

### بنية جدول session_validation_requests
```sql
CREATE TABLE session_validation_requests (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  employee_id UUID REFERENCES employees(id),
  attendance_id UUID REFERENCES attendance(id),
  branch_id UUID REFERENCES branches(id),
  manager_id UUID REFERENCES employees(id),
  gap_start_time TIMESTAMPTZ NOT NULL,
  gap_end_time TIMESTAMPTZ NOT NULL,
  gap_duration_minutes INTEGER NOT NULL,
  expected_pulses_count INTEGER NOT NULL,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  manager_response_time TIMESTAMPTZ,
  manager_notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
```

---

## 🎯 PHASE 3: تطوير واجهة المدير لـ Session Validation
**الحالة:** 🔴 لم يبدأ

### المهمة
إضافة قسم جديد في لوحة المدير (Manager Dashboard / Simple Admin) لعرض طلبات Session Validation.

### الميزات المطلوبة
1. عرض جميع الطلبات المعلقة (pending)
2. عرض تفاصيل الطلب:
   - اسم الموظف
   - الفرع
   - الفترة الزمنية (من - إلى)
   - المدة بالدقائق
   - عدد النبضات المتوقع
3. أزرار: ✅ قبول | ❌ رفض
4. حقل ملاحظات اختياري
5. إشعار للموظف بعد القرار

### الملفات المطلوب تعديلها/إنشاؤها
- البحث عن: `simple_admin_dashboard.dart` أو `manager_dashboard_page.dart`
- إضافة: `session_validation_requests_tab.dart` (جديد)
- `lib/services/manager_api_service.dart` (تعديل - إضافة endpoints)

### API Endpoints المطلوبة
```dart
// GET /session-validation-requests?manager_id=xxx
// POST /session-validation-requests/{id}/approve
// POST /session-validation-requests/{id}/reject
```

---

## 🎯 PHASE 4: تطوير منطق النبضات - Wi-Fi Priority
**الحالة:** 🔴 لم يبدأ

### التحسين المطلوب
تغيير أولوية التحقق في النبضات:

#### المنطق الجديد:
```
1. التحقق من Wi-Fi BSSID أولاً
   ├─ إذا BSSID صحيح → ✅ TRUE مباشرة (بدون GPS)
   └─ إذا BSSID خاطئ أو غير متصل → انتقل للخطوة 2

2. التحقق من GPS
   ├─ إذا GPS مفعل وداخل الدائرة → ✅ TRUE
   ├─ إذا GPS مفعل وخارج الدائرة → ❌ FALSE
   └─ إذا GPS مغلق → ❌ FALSE (distance = 0)
```

### الملفات المطلوب تعديلها
- `lib/services/pulse_tracking_service.dart` (method: `_sendPulse`)
- `lib/services/local_geofence_service.dart` (إضافة: `isLocationServiceEnabled`)

### الكود المطلوب
```dart
// في _sendPulse():

// 1. Check Wi-Fi FIRST
String? wifiBssid;
bool wifiValidated = false;
final requiredBssids = _extractRequiredBssids(_currentBranchData!);

if (requiredBssids.isNotEmpty) {
  try {
    wifiBssid = await WiFiService.getCurrentWifiBssidValidated();
    wifiValidated = requiredBssids.contains(wifiBssid);
    
    if (wifiValidated) {
      // ✅ Wi-Fi صحيح = TRUE مباشرة
      print('✅ Pulse TRUE - Valid Wi-Fi: $wifiBssid');
      await _savePulse(
        insideGeofence: true,
        validatedByWifi: true,
        validatedByLocation: false,
        wifiBssid: wifiBssid,
        latitude: null, // لا حاجة للـ GPS
        longitude: null,
        distance: 0,
      );
      return;
    }
  } catch (e) {
    print('⚠️ Wi-Fi check error: $e');
  }
}

// 2. Check GPS (only if Wi-Fi failed)
final locationEnabled = await Geolocator.isLocationServiceEnabled();
if (!locationEnabled) {
  // GPS مغلق = FALSE
  print('❌ Pulse FALSE - GPS disabled');
  await _savePulse(
    insideGeofence: false,
    validatedByWifi: false,
    validatedByLocation: false,
    wifiBssid: wifiBssid,
    latitude: null,
    longitude: null,
    distance: 0,
  );
  return;
}

// GPS مفعل - تابع الفحص العادي
final result = await LocalGeofenceService.validateGeofence(...);
```

---

## 🎯 PHASE 5: إصلاح وتحسين ForegroundAttendanceService
**الحالة:** 🔴 لم يبدأ

### المشكلة
خدمة المقدمة (Foreground Service) تتعلق أحياناً أو تتوقف في الخلفية.

### التحسينات المطلوبة

#### 1. إضافة Watchdog Timer
```dart
// كل دقيقة، تحقق من أن الخدمة تعمل
Timer.periodic(Duration(minutes: 1), (timer) {
  if (!_isServiceHealthy()) {
    print('⚠️ Service unhealthy - restarting');
    _restartService();
  }
});
```

#### 2. إضافة Wake Lock
منع النظام من إيقاف الخدمة عند توفير البطارية:
```yaml
# pubspec.yaml
dependencies:
  wakelock_plus: ^1.2.0
```

```dart
import 'package:wakelock_plus/wakelock_plus.dart';

// عند بدء الخدمة
await WakelockPlus.enable();

// عند إيقاف الخدمة
await WakelockPlus.disable();
```

#### 3. تحسين الإشعار
- إضافة زر "إيقاف التتبع" في الإشعار
- عرض عدد النبضات الحالي
- عرض آخر وقت نبضة

### الملفات المطلوب تعديلها
- `lib/services/foreground_attendance_service.dart`
- `pubspec.yaml` (إضافة wakelock_plus)

---

## 🎯 PHASE 6: تفعيل AlarmManager مع طلب Permission
**الحالة:** 🔴 لم يبدأ

### المشكلة
AlarmManager لم يعمل مطلقاً لأنه يحتاج permission خاص في Android 12+.

### الحل

#### 1. إضافة Permission في Manifest
```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
<uses-permission android:name="android.permission.USE_EXACT_ALARM" />
```

#### 2. طلب Permission في الكود
```dart
// في alarm_manager_pulse_service.dart

import 'package:permission_handler/permission_handler.dart';

Future<bool> requestExactAlarmPermission() async {
  if (Platform.isAndroid) {
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    if (androidInfo.version.sdkInt >= 31) { // Android 12+
      // Request SCHEDULE_EXACT_ALARM
      final status = await Permission.scheduleExactAlarm.request();
      if (!status.isGranted) {
        // توجيه المستخدم للإعدادات
        await openAppSettings();
        return false;
      }
    }
  }
  return true;
}
```

#### 3. طلب Permission عند Check-in
```dart
// في _handleCheckIn():

// Request AlarmManager permission
final alarmService = AlarmManagerPulseService();
final hasPermission = await alarmService.requestExactAlarmPermission();
if (!hasPermission) {
  // عرض رسالة للمستخدم
  showDialog(...);
}
```

### الملفات المطلوب تعديلها
- `android/app/src/main/AndroidManifest.xml`
- `lib/services/alarm_manager_pulse_service.dart`
- `lib/screens/employee/employee_home_page.dart`

---

## 🎯 PHASE 7: طلب Location Permission عند Check-in
**الحالة:** 🔴 لم يبدأ

### المهمة
التأكد من أن المستخدم قد فعّل Location Permission قبل السماح بتسجيل الحضور.

### التنفيذ
```dart
// في _handleCheckIn():

Future<bool> _ensureLocationPermission() async {
  // 1. Check if permission granted
  final permission = await Permission.location.status;
  
  if (permission.isGranted) {
    return true;
  }
  
  // 2. Show explanation dialog
  final userAccepted = await _showLocationPermissionDialog();
  if (!userAccepted) {
    return false;
  }
  
  // 3. Request permission
  final result = await Permission.location.request();
  
  if (result.isGranted) {
    return true;
  }
  
  // 4. If denied permanently, guide to settings
  if (result.isPermanentlyDenied) {
    await _showOpenSettingsDialog();
  }
  
  return false;
}

// في بداية _handleCheckIn():
if (!kIsWeb) {
  final hasPermission = await _ensureLocationPermission();
  if (!hasPermission) {
    setState(() => _isLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('يجب تفعيل صلاحية الموقع لتسجيل الحضور'),
        backgroundColor: AppColors.error,
      ),
    );
    return;
  }
}
```

### الملفات المطلوب تعديلها
- `lib/screens/employee/employee_home_page.dart`

---

## 🎯 PHASE 8: إصلاح خطأ "Failed to persist today total"
**الحالة:** 🔴 لم يبدأ

### المشكلة
```
ClientException with SocketException: Failed host lookup: 
'bbxuyuaemigrqsvsnxkj.supabase.co' (OS Error: No address associated with hostname, errno = 7)
```

### السبب
- مشكلة في الاتصال بالإنترنت
- DNS resolution failure
- Timeout في الطلب

### الحل

#### 1. إضافة Timeout قصير
```dart
// في SupabaseFunctionClient.post():

Future<Map<String, dynamic>?> post(
  String functionName,
  Map<String, dynamic> data, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  try {
    final response = await _supabase.functions
        .invoke(functionName, body: data)
        .timeout(timeout);
    
    // ... rest of code
  } on TimeoutException {
    print('⏱️ Function timeout: $functionName');
    return null;
  } catch (e) {
    print('❌ Function error: $e');
    return null;
  }
}
```

#### 2. عدم إيقاف التطبيق عند الفشل
```dart
// في _refreshTodayTotal():

Future<void> _refreshTodayTotal() async {
  try {
    await SupabaseFunctionClient.post(
      'employee-today-earnings',
      {'employee_id': widget.employeeId, 'persist': true},
    ).timeout(Duration(seconds: 3));
  } catch (e) {
    // Don't crash - just log
    print('⚠️ Failed to persist today total: $e');
    // Continue normal operation
  }
}
```

### الملفات المطلوب تعديلها
- `lib/services/supabase_function_client.dart`
- `lib/screens/employee/employee_home_page.dart`

---

## 🎯 PHASE 9: اختبار النظام الشامل
**الحالة:** 🔴 لم يبدأ

### سيناريوهات الاختبار

#### Test 1: Offline Check-in
- [ ] فصل الإنترنت
- [ ] تسجيل حضور
- [ ] التحقق من حفظ البيانات محلياً
- [ ] إعادة الإنترنت
- [ ] التحقق من المزامنة التلقائية

#### Test 2: Session Validation
- [ ] تسجيل حضور
- [ ] إيقاف التطبيق > 5.5 دقيقة
- [ ] فتح التطبيق
- [ ] التحقق من ظهور طلب Session Validation
- [ ] الموافقة من المدير
- [ ] التحقق من إنشاء النبضات TRUE

#### Test 3: Wi-Fi Priority
- [ ] الاتصال بشبكة الفرع
- [ ] تسجيل حضور
- [ ] التحقق من نبضة TRUE بدون GPS
- [ ] قطع Wi-Fi وتفعيل GPS
- [ ] التحقق من النبضة حسب الموقع

#### Test 4: Background Services
- [ ] تسجيل حضور
- [ ] تصغير التطبيق
- [ ] الانتظار 15 دقيقة
- [ ] التحقق من عمل النبضات
- [ ] التحقق من عمل الخدمات الثلاثة

#### Test 5: Permissions
- [ ] تجربة Check-in بدون Location Permission
- [ ] التحقق من طلب Permission
- [ ] تجربة AlarmManager بدون Permission
- [ ] التحقق من طلب Permission

---

## 📊 ملخص التقدم

### إحصائيات
- **إجمالي المراحل:** 9
- **المكتملة:** 0
- **قيد العمل:** 0
- **لم تبدأ:** 9

### الأولويات
1. 🔴 **عاجل:** PHASE 1 (إصلاح التعليق)
2. 🔴 **عاجل:** PHASE 4 (Wi-Fi Priority)
3. 🟠 **مهم:** PHASE 2 (Session Validation)
4. 🟠 **مهم:** PHASE 6 (AlarmManager)
5. 🟡 **متوسط:** PHASE 5 (ForegroundService)
6. 🟡 **متوسط:** PHASE 7 (Location Permission)
7. 🟢 **منخفض:** PHASE 8 (Today Total Error)

---

## 📝 ملاحظات مهمة

### اعتبارات الأداء
- استخدام offline-first approach لتقليل الاعتماد على السيرفر
- Timeout قصير للطلبات (3-5 ثواني)
- Caching محلي قوي

### اعتبارات UX
- عدم منع المستخدم من العمل بسبب مشاكل الشبكة
- رسائل واضحة ومفيدة
- Permissions مع شرح واضح

### اعتبارات الأمان
- التحقق من صلاحيات المدير قبل الموافقة
- تسجيل جميع الإجراءات (audit log)
- عدم السماح بتعديل البيانات التاريخية

---

## 🚀 البدء في العمل

### الخطوات التالية:
1. ✅ قراءة وفهم جميع المراحل
2. 🔄 البدء بـ PHASE 1 (الأعلى أولوية)
3. 🔄 الانتقال تدريجياً للمراحل التالية
4. ✅ اختبار كل مرحلة قبل الانتقال للتالية

---

**تاريخ الإنشاء:** 2025-11-28
**آخر تحديث:** 2025-11-28
**الحالة العامة:** 🔴 بدء العمل
