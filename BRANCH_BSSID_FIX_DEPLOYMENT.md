# إصلاح ربط BSSID بالفروع - دليل النشر

## التعديلات التي تم إجراؤها

### 1. إصلاح حفظ BSSID عند إنشاء الفرع (Backend) ✅

**الملف:** `server/index.ts`

**التعديل:** تم تعديل الـ endpoint `POST /api/branches` لحفظ الـ BSSID في جدول `branchBssids` عند إنشاء فرع جديد.

**الميزات الجديدة:**
- يتم حفظ الـ BSSID تلقائياً في جدول `branchBssids` مع ربطه بالـ `branch.id` الجديد
- يتم تحويل الـ BSSID إلى Uppercase تلقائياً
- إضافة logs لتتبع عملية إنشاء الفروع
- إرجاع `branchId` في الـ response

### 2. إضافة ميزة جلب BSSID أوتوماتيكياً (Flutter) ✅

**الملف:** `lib/screens/owner/owner_main_screen.dart`

**التعديلات:**
- إضافة import لـ `network_info_plus` 
- إضافة دالة `_getCurrentWifiBssid()` لجلب BSSID الحالي
- إضافة زر بجانب حقل Wi-Fi BSSID لجلب البيانات تلقائياً
- تحسين label لـ "Wi-Fi BSSID" بدلاً من "اسم الواي فاي"
- إضافة hint text مع مثال على تنسيق BSSID

**الميزة:** يمكن للمالك الآن الضغط على أيقونة WiFi لجلب BSSID الشبكة المتصل بها تلقائياً.

### 3. التحقق من نظام النبضات (Pulses) ✅

**الملف:** `server/index.ts` - endpoint `POST /api/pulses`

**التأكيد:**
- ✅ يتم جلب BSSIDs من جدول `branchBssids` بناءً على `branchId` 
- ✅ يتم التحقق من الـ WiFi والـ GPS معاً
- ✅ يتم احتساب المسافة (distance) بناءً على إحداثيات الفرع
- ✅ يتم استخدام `geofenceRadius` الخاص بكل فرع
- ✅ يتم تعطيل النبضات أثناء الاستراحة (break)
- ✅ يتم حفظ حالة `isWithinGeofence` في قاعدة البيانات

## خطوات النشر على AWS

### الخطوة 1: رفع التعديلات لـ GitHub (من جهازك المحلي)

```powershell
# التأكد من حفظ كل الملفات
git add .

# عمل commit للتعديلات
git commit -m "Fix: Save BSSID when creating branch & Add auto-fetch BSSID feature"

# رفع التعديلات
git push origin main
```

### الخطوة 2: تحديث السيرفر على AWS

```powershell
# الاتصال بالسيرفر
ssh -i "D:\mytest123.pem" ubuntu@16.171.208.249

# بعد الاتصال، قم بتنفيذ الأوامر التالية:
cd ~/oldies-server

# سحب آخر تحديثات من GitHub
git pull origin main

# تثبيت أي dependencies جديدة (إن وجدت)
npm install

# إعادة بناء المشروع
npm run build

# إعادة تشغيل السيرفر
pm2 restart oldies-api

# التحقق من حالة السيرفر
pm2 status

# عرض logs للتأكد من عدم وجود أخطاء
pm2 logs oldies-api --lines 50
```

### الخطوة 3: تنفيذ seed للتأكد من وجود بيانات تجريبية (مرة واحدة فقط)

من جهازك المحلي، قم بتنفيذ:

```powershell
curl http://16.171.208.249:5000/api/dev/seed
```

**ملاحظة:** لا تقم بتنفيذ هذا الأمر إذا كانت لديك بيانات فعلية في قاعدة البيانات.

### الخطوة 4: اختبار الميزات الجديدة

#### اختبار إنشاء فرع مع BSSID:

1. افتح التطبيق وسجل دخول كـ Owner
2. انتقل إلى تبويب "الفروع"
3. اضغط على "إضافة فرع جديد"
4. اتصل بشبكة WiFi الخاصة بالفرع
5. اضغط على أيقونة WiFi بجانب حقل BSSID
6. تأكد من ملء الحقل تلقائياً
7. أكمل باقي البيانات واحفظ الفرع
8. تحقق من السيرفر logs أن BSSID تم حفظه

#### اختبار نظام النبضات:

1. قم بتعيين موظف للفرع الجديد
2. سجل دخول كموظف
3. تأكد من الاتصال بنفس شبكة WiFi
4. تأكد من وجودك في النطاق الجغرافي
5. قم بـ check-in
6. راقب النبضات (pulses) التي يتم إرسالها
7. تحقق أن `is_valid` = true فقط عند تطابق WiFi والموقع

## التحقق من نجاح التحديث

### على السيرفر:

```bash
# عرض آخر commits
cd ~/oldies-server
git log --oneline -5

# التحقق من أن الملف تم تحديثه
grep -A 20 "POST /api/branches" server/index.ts | head -25

# عرض logs للسيرفر
pm2 logs oldies-api --lines 100
```

### في التطبيق:

- تأكد من ظهور زر WiFi بجانب حقل BSSID ✅
- تأكد من عمل جلب BSSID تلقائياً ✅
- تأكد من حفظ BSSID عند إنشاء فرع ✅

## استكشاف الأخطاء

### إذا لم يظهر زر WiFi:

1. تأكد من أن مكتبة `network_info_plus` مثبتة
2. نفذ `flutter pub get`
3. أعد تشغيل التطبيق

### إذا لم يتم حفظ BSSID:

1. تحقق من logs السيرفر: `pm2 logs oldies-api`
2. تأكد من أن جدول `branchBssids` موجود في قاعدة البيانات
3. تحقق من أن التطبيق يرسل `wifi_bssid` في الـ request

### إذا لم تعمل النبضات:

1. تحقق من أن الموظف مرتبط بفرع (`branchId` موجود)
2. تحقق من وجود BSSID في جدول `branchBssids` للفرع
3. تأكد من الاتصال بنفس شبكة WiFi
4. تأكد من الوجود ضمن النطاق الجغرافي

## ملاحظات مهمة

### صلاحيات Android للحصول على BSSID:

في Android 10+ (API 29+)، يتطلب الحصول على BSSID الصلاحيات التالية:

```xml
<!-- في android/app/src/main/AndroidManifest.xml -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
```

وأيضاً يجب طلب الصلاحيات في runtime.

### تنسيق BSSID:

- BSSID يتم تخزينه بتنسيق Uppercase (XX:XX:XX:XX:XX:XX)
- المقارنة غير حساسة لحالة الأحرف (case-insensitive)

### نظام الأولويات:

1. إذا لم يكن الموظف مرتبط بفرع، يتم استخدام الإعدادات الافتراضية
2. إذا لم يكن للفرع BSSIDs مسجلة، يُسمح بأي WiFi
3. النبضات تُعطل تلقائياً أثناء الاستراحة (break)

## خلاصة التحديثات

✅ **Backend:** حفظ BSSID في `branchBssids` عند إنشاء فرع  
✅ **Flutter:** إضافة زر جلب BSSID تلقائياً  
✅ **Pulses:** التحقق من صحة النظام  
✅ **Documentation:** دليل النشر والاختبار

---

**تاريخ التحديث:** 26 أكتوبر 2025  
**الإصدار:** v1.2.0 - Branch BSSID Integration Fix
