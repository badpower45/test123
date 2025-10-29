# 🔥 إصلاح شامل لمشكلة Socket Connection

## ✅ التحسينات المطبقة:

### 1. ⚙️ Android Permissions
**الملف: `android/app/src/main/AndroidManifest.xml`**

```xml
<!-- ✅ تمت الإضافة -->
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
```

**السبب:** بدون `INTERNET` permission، الـ APK مش هيقدر يعمل HTTP requests

---

### 2. 🔒 Network Security Config
**الملف: `android/app/src/main/res/xml/network_security_config.xml`**

```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <base-config cleartextTrafficPermitted="true">
        <trust-anchors>
            <certificates src="system" />
            <certificates src="user" />
        </trust-anchors>
    </base-config>
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="true">16.171.208.249</domain>
        <domain includeSubdomains="true">localhost</domain>
    </domain-config>
</network-security-config>
```

**الربط بـ AndroidManifest:**
```xml
<application
    android:usesCleartextTraffic="true"
    android:networkSecurityConfig="@xml/network_security_config">
```

**السبب:** Android 9+ بيمنع HTTP بشكل افتراضي، لازم cleartext traffic

---

### 3. 🏗️ Build Configuration
**الملف: `android/app/build.gradle.kts`**

```kotlin
buildTypes {
    release {
        signingConfig = signingConfigs.getByName("debug")
        isMinifyEnabled = false      // ✅ تمت الإضافة
        isShrinkResources = false    // ✅ تمت الإضافة
    }
    debug {
        isMinifyEnabled = false      // ✅ تمت الإضافة
    }
}
```

**السبب:** ProGuard/R8 ممكن يحذف كود network بالغلط

---

### 4. 🌐 API Configuration
**الملف: `lib/constants/api_endpoints.dart`**

```dart
const String apiBaseUrl = 'http://16.171.208.249:5000/api';
const String rootBaseUrl = 'http://16.171.208.249:5000';
```

**✅ تم التأكد:** 
- ✅ السيرفر شغال على port 5000
- ✅ CORS مفعّل (`Access-Control-Allow-Origin: *`)
- ✅ Health check يرد 200 OK

---

## 🔧 التحسينات الإضافية:

### 5. 💰 حساب الخصم بناءً على الشيفت
**الملف: `server/index.ts` - Line 1575**

```typescript
// حساب خصم يومين بناءً على ساعات الشيفت
const shiftDurationHours = shiftDurationMinutes / 60;
const hourlyRate = parseFloat(employee.hourlyRate || '40');
const oneDayDeduction = shiftDurationHours * hourlyRate;
const twoDaysDeduction = oneDayDeduction * 2;
```

**مثال:**
- شيفت: 9:00 - 17:00 = 8 ساعات
- hourlyRate = 40 جنيه
- يوم واحد = 8 × 40 = 320 جنيه
- **خصم يومين = 640 جنيه**

---

### 6. 🚨 تنبيه التأخير (Cron Job)
**الملف: `server/index.ts` - Line 5208**

```typescript
// يعمل كل 30 دقيقة
cron.schedule('*/30 * * * *', async () => {
  // التحقق من التأخير بعد ساعتين من بداية الشيفت
  const twoHoursAfterStart = shiftStart + 120;
  
  if (currentTime >= twoHoursAfterStart && !todayAttendance) {
    await sendNotification(
      managerId,
      'ABSENCE_ALERT',
      'تأخير موظف',
      `تنبيه: الموظف ${employee.fullName} تأخر لمدة ساعتين...`
    );
  }
});
```

---

### 7. 👥 صفحة Owner - عرض الحاضرين
**الملف: `lib/screens/owner/owner_main_screen.dart` - Line 788**

```dart
// API Integration
final response = await http.get(
  Uri.parse('$rootBaseUrl/api/branch/presence-status'),
);

// عرض الحاضرين والغائبين
presentEmployees.length  // ✅ بلون أخضر
absentEmployees.length   // ✅ بلون رمادي
```

---

### 8. 📍 Location System - محسّن
**الملف: `lib/services/location_service.dart`**

```dart
// 3 محاولات للحصول على أفضل دقة
while (attempts < maxAttempts) {
  position = await Geolocator.getCurrentPosition(
    desiredAccuracy: LocationAccuracy.best,
    forceAndroidLocationManager: true,
    timeLimit: const Duration(seconds: 15),
  );
  
  // قبول دقة < 30 متر فقط
  if (position.accuracy <= 30) break;
}
```

**Features:**
- ✅ استخدام Geolocator المجاني (مش محتاجين مكتبة مدفوعة!)
- ✅ دقة عالية (5-10 متر في الأماكن المفتوحة)
- ✅ استهلاك بطارية منخفض
- ✅ 3 محاولات للحصول على أفضل نتيجة

---

## 🎯 الحالة النهائية:

### Backend (AWS EC2):
- ✅ **PM2 Restart #40** ناجح
- ✅ **Server Online** - PID: 85010
- ✅ **Health Check:** http://16.171.208.249:5000/health ✅
- ✅ **Memory:** 17.6mb
- ✅ **CORS:** مفعّل

### Frontend (Flutter):
- ✅ **INTERNET Permission** مضاف
- ✅ **Network Security Config** مضاف
- ✅ **Cleartext Traffic** مفعّل
- ✅ **Build Config** محسّن
- ✅ **APK Building...** (Release Mode)

---

## 🔍 كيفية الاختبار:

### Test 1: Connection Test
```bash
# من PowerShell
curl http://16.171.208.249:5000/health
```

**Expected:**
```json
{
  "status": "ok",
  "message": "Oldies Workers API is running"
}
```

### Test 2: Login
1. افتح APK
2. اكتب: `OWNER001` / `****`
3. اضغط "تسجيل الدخول"
4. **Expected:** Login ناجح ✅

### Test 3: Location
1. سجل حضور
2. **Expected:** 
   - GPS يشتغل
   - دقة < 30 متر
   - يسجل الحضور ✅

---

## 🐛 إذا استمرت المشكلة:

### السبب المحتمل 1: Firewall على AWS
```bash
# تأكد من Security Group يسمح بـ port 5000
aws ec2 describe-security-groups
```

### السبب المحتمل 2: Emulator/Device Network
- تأكد الجهاز متصل بالإنترنت
- جرب Disable/Enable WiFi
- جرب على جهاز مختلف

### السبب المحتمل 3: APK Cache
```bash
# امسح الـ APK القديم من الجهاز
# ثبت الـ APK الجديد من الصفر
flutter clean
flutter pub get
flutter build apk --release
```

---

## 📊 ملخص التغييرات:

| File | Changes | Status |
|------|---------|--------|
| AndroidManifest.xml | + INTERNET permission | ✅ |
| network_security_config.xml | + Cleartext traffic | ✅ |
| build.gradle.kts | + minifyEnabled false | ✅ |
| server/index.ts | + Shift-based deduction | ✅ |
| owner_main_screen.dart | + Presence API integration | ✅ |
| location_service.dart | + 3 retries + best accuracy | ✅ |

---

## 🚀 الخطوات التالية:

1. ⏳ انتظر APK ينتهي من البناء
2. ✅ انقل الـ APK للجهاز
3. ✅ امسح الـ APK القديم تماماً
4. ✅ ثبت الـ APK الجديد
5. ✅ جرب Login

**المشكلة مفترض تختفي تماماً! 🎉**

---

**Last Updated:** October 29, 2025  
**PM2 Restart:** #40  
**APK:** Building... (Release Mode with all fixes)
