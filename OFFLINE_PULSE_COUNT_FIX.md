# إصلاح مشكلة عدّ النبضات في الوضع الأوفلاين ✅

## المشكلة
التطبيق في الوضع الأوفلاين كان **لا يحسب النبضات بشكل صحيح**. عندما يقوم الموظف بإغلاق التطبيق ثم إعادة فتحه، كان العداد يبدأ من الصفر مرة أخرى بدلاً من الاستمرار من حيث توقف.

### السبب الجذري:
1. **العدادات في الذاكرة (In-Memory Counters)**: المتغير `_pulsesCount` كان يُخزن فقط في الرام، وعند إغلاق التطبيق كان يضيع.
2. **تشتت البيانات**: النبضات كانت تُحفظ في مكانين:
   - **Hive**: النبضات التي تم رفعها للسيرفر (المزامنة)
   - **SQLite**: النبضات المعلقة التي لم تُرفع بعد (أوفلاين تماماً)
3. **عدم توحيد المصدر**: الواجهة كانت تقرأ من الرام فقط ولا تجمع من كل المصادر.

---

## الحل المُطبَّق ✅

### 1. تعديل `startTracking` - استئناف العد من قاعدة البيانات
**الملف**: `lib/services/pulse_tracking_service.dart`

**قبل**:
```dart
_pulsesCount = 0; // ❌ كان يبدأ من صفر دائماً
```

**بعد**:
```dart
// ✅ بدل ما نبدأ من صفر، نجيب العدد من قاعدة البيانات
final stats = await getTrackingStats(employeeId);
_pulsesCount = stats['total_pulses'] ?? 0;
print('📊 استئناف تتبع النبضات: عدد النبضات الحالي = $_pulsesCount');
```

**الفائدة**: عندما يعيد الموظف فتح التطبيق، يستأنف العد من حيث توقف وليس من صفر.

---

### 2. تعديل `getTrackingStats` - جمع النبضات من جميع المصادر
**الملف**: `lib/services/pulse_tracking_service.dart`

**قبل**:
```dart
// ❌ كان يقرأ من Hive فقط (النبضات المزامنة)
final pulses = await _offlineService.getPulsesForDate(...);
return {'total_pulses': pulses.length, ...};
```

**بعد**:
```dart
// ✅ يجمع من Hive (المزامنة) + SQLite (المعلقة)
// 1. النبضات المزامنة من Hive
final syncedPulses = await _offlineService.getPulsesForDate(...);

// 2. النبضات المعلقة من SQLite
final db = OfflineDatabase.instance;
final allPending = await db.getPendingPulses();
final pendingPulses = allPending.where((p) {
  return p['employee_id'] == employeeId && 
         timestamp.isAfter(startOfDay) && 
         timestamp.isBefore(endOfDay);
}).toList();

// 3. حساب المجموع
int insideCount = 0;
// من Hive
for (var pulse in syncedPulses) {
  if (pulse['inside_geofence'] == true) insideCount++;
}
// من SQLite
for (var pulse in pendingPulses) {
  if (pulse['inside_geofence'] == 1) insideCount++; // SQLite = int
}

final totalPulses = syncedPulses.length + pendingPulses.length;
return {'total_pulses': totalPulses, ...};
```

**الفائدة**: الآن العداد يرى **كل** النبضات، سواء تم رفعها للسيرفر أو لا تزال معلقة محلياً.

---

### 3. تحديث العداد بعد كل نبضة - ضمان الدقة
**الملف**: `lib/services/pulse_tracking_service.dart`

تم إضافة تحديث العداد من قاعدة البيانات في **4 أماكن** بعد حفظ النبضة:

#### أ) نبضة أثناء الاستراحة (Break)
```dart
_pulsesCount++;
_lastPulseTime = timestamp;

// ✅ تحديث العداد من قاعدة البيانات لضمان الدقة
final updatedStats = await getTrackingStats(_currentEmployeeId!);
_pulsesCount = updatedStats['total_pulses'] ?? _pulsesCount;

notifyListeners();
```

#### ب) نبضة مصادقة بواسطة Wi-Fi
```dart
_pulsesCount++;
_lastPulseTime = timestamp;

// ✅ تحديث العداد من قاعدة البيانات لضمان الدقة
final updatedStats = await getTrackingStats(_currentEmployeeId!);
_pulsesCount = updatedStats['total_pulses'] ?? _pulsesCount;

notifyListeners();
```

#### ج) نبضة مع GPS مغلق
```dart
_pulsesCount++;
_lastPulseTime = timestamp;

// ✅ تحديث العداد من قاعدة البيانات لضمان الدقة
final updatedStats = await getTrackingStats(_currentEmployeeId!);
_pulsesCount = updatedStats['total_pulses'] ?? _pulsesCount;

// Send warning notification
```

#### د) نبضة مصادقة بواسطة GPS
```dart
_pulsesCount++;
_lastPulseTime = timestamp;

// ✅ تحديث العداد من قاعدة البيانات لضمان الدقة
final updatedStats = await getTrackingStats(_currentEmployeeId!);
_pulsesCount = updatedStats['total_pulses'] ?? _pulsesCount;

// Print pulse status
```

**الفائدة**: حتى لو حدث خطأ في الرام، العداد سيُصحح نفسه تلقائياً من قاعدة البيانات.

---

## النتيجة النهائية 🎯

### قبل الإصلاح ❌
- الموظف يدخل → 5 نبضات → يغلق التطبيق
- يعيد الفتح → **العداد = 0** (ضاعت البيانات!)
- نبضة جديدة → العداد = 1 (بدلاً من 6)

### بعد الإصلاح ✅
- الموظف يدخل → 5 نبضات → يغلق التطبيق
- يعيد الفتح → **العداد = 5** (مستمر!)
- نبضة جديدة → العداد = 6 (صحيح! ✅)

---

## الملفات المُعدَّلة
- ✅ `lib/services/pulse_tracking_service.dart`

## الاختبار المطلوب
1. تسجيل حضور موظف في الوضع الأوفلاين
2. إغلاق التطبيق بعد 3-4 نبضات
3. إعادة فتح التطبيق
4. **التحقق**: العداد يستأنف من 3-4 وليس من 0
5. إضافة نبضات جديدة والتأكد من استمرار الزيادة بشكل صحيح

---

## ملاحظات فنية
- الحل يعمل على **Mobile (SQLite)** و **Web (Hive)**
- في Web: يقرأ من Hive فقط (لا يوجد SQLite)
- في Mobile: يجمع من Hive + SQLite
- العداد يُحدَّث بعد **كل** نبضة لضمان الدقة القصوى

---

**تاريخ الإصلاح**: 4 يناير 2026
**الحالة**: ✅ مكتمل ومطبق
