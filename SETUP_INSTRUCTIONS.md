# 🚀 إعداد تطبيق Oldies Workers - دليل كامل

## ✅ التحضيرات المكتملة

تم إعداد التالي بنجاح:
- ✅ تحديث Supabase credentials في Flutter app
- ✅ بناء Flutter web version
- ✅ تشغيل الـ web server على port 5000
- ✅ إعداد نظام النبضات (online/offline)
- ✅ إنشاء migration جديدة لحل مشكلة schema

---

## 🔧 الخطوة الأولى: تطبيق Database Migration على Supabase

**المشكلة**: Flutter app بتبعت `latitude` و `longitude` منفصلين، لكن Supabase schema بتتوقع `geography(Point)` واحد.

**الحل**: تطبيق migration جديدة `004_add_lat_lon_columns.sql`

### كيفية التطبيق:

#### الطريقة 1: باستخدام Supabase CLI (الموصى بها)

```bash
# 1. تأكد أن Supabase CLI مثبت
npm install -g supabase

# 2. اربط المشروع
supabase link --project-ref rxlckqprxskhnkrnsaem

# 3. طبق الـ migration
supabase db push
```

#### الطريقة 2: باستخدام SQL Editor في Supabase Dashboard

1. افتح [Supabase Dashboard](https://supabase.com/dashboard)
2. اختر مشروعك: `rxlckqprxskhnkrnsaem`
3. اذهب إلى **SQL Editor**
4. افتح ملف `supabase/migrations/004_add_lat_lon_columns.sql`
5. انسخ كل المحتوى والصقه في SQL Editor
6. اضغط **Run** لتطبيق الـ migration

### ما الذي تفعله Migration؟

✅ إضافة columns جديدة: `latitude` و `longitude` كـ NUMERIC  
✅ تحديث `check_geofence()` function لبناء geography point تلقائياً  
✅ الحفاظ على البيانات الموجودة (backfill من location إلى lat/lon)  
✅ تحديث الـ trigger ليشتغل مع الـ format الجديد  

---

## 📱 الخطوة الثانية: اختبار نظام النبضات

### 1. افتح التطبيق

التطبيق شغال على: `https://[your-replit-url].repl.co`

### 2. تسجيل الدخول

استخدم أحد الحسابات التجريبية:

| الموظف | Employee ID | PIN | الدور |
|--------|-------------|-----|-------|
| مريم حسن | EMP001 | 1234 | Admin |
| عمر سعيد | EMP002 | 5678 | HR |
| نورة عادل | EMP003 | 2468 | Monitor |

### 3. اختبار النبضات

#### اختبار Online:
1. سجل دخول كموظف
2. اضغط "ابدأ الوردية"
3. لاحظ النبضات تُرسل كل 30 ثانية
4. افحص Supabase Dashboard → Table Editor → `pulses`
5. تأكد أن:
   - `latitude` و `longitude` موجودين
   - `location` geography point موجود
   - `is_within_geofence` = `true` أو `false` (حسب الموقع)

#### اختبار Offline:
1. افصل الإنترنت (أو قطع الاتصال)
2. لاحظ أن النبضات تُخزن محلياً
3. أعد الاتصال بالإنترنت
4. لاحظ أن النبضات تتزامن تلقائياً
5. تحقق من Supabase أن النبضات وصلت

---

## 🔒 الخطوة الثالثة: التحقق من Geofencing

### إعدادات المطعم الافتراضية:

```dart
// في lib/constants/restaurant_config.dart
latitude: 30.0444  // Cairo Tahrir Square
longitude: 31.2357
allowedRadiusInMeters: 120  // 120 متر
```

### تغيير موقع المطعم:

#### Option 1: في Flutter Config
عدل `lib/constants/restaurant_config.dart`:
```dart
static const double latitude = YOUR_LAT;
static const double longitude = YOUR_LON;
```

#### Option 2: في Supabase Function
عدل `supabase/migrations/004_add_lat_lon_columns.sql`:
```sql
restaurant_location := ST_GeogFromText('POINT(YOUR_LON YOUR_LAT)');
geofence_radius_meters NUMERIC := 100; -- غير النصف القطر هنا
```

### اختبار Geofencing:

1. **داخل المحيط** (pulse should be valid):
   ```sql
   -- في SQL Editor
   INSERT INTO pulses (shift_id, latitude, longitude)
   VALUES ('your-shift-id', 30.0444, 31.2357);
   
   -- تحقق من النتيجة
   SELECT id, latitude, longitude, is_within_geofence 
   FROM pulses 
   ORDER BY created_at DESC 
   LIMIT 1;
   ```

2. **خارج المحيط** (pulse should be invalid):
   ```sql
   INSERT INTO pulses (shift_id, latitude, longitude)
   VALUES ('your-shift-id', 30.0, 31.0);
   
   SELECT id, latitude, longitude, is_within_geofence 
   FROM pulses 
   ORDER BY created_at DESC 
   LIMIT 1;
   ```

---

## 💰 الخطوة الرابعة: اختبار حساب الراتب

### استخدام Edge Function:

```bash
curl -X POST 'https://rxlckqprxskhnkrnsaem.supabase.co/functions/v1/calculate-payroll' \
  -H "Authorization: Bearer eyJhbGci...YOUR_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "USER_UUID",
    "start_date": "2025-01-01T00:00:00Z",
    "end_date": "2025-01-31T23:59:59Z",
    "hourly_rate": 30
  }'
```

### من Flutter App:

```dart
final response = await Supabase.instance.client.functions.invoke(
  'calculate-payroll',
  body: {
    'user_id': userId,
    'start_date': startDate.toIso8601String(),
    'end_date': endDate.toIso8601String(),
    'hourly_rate': 30,
  },
);
```

---

## 🎯 نظام النبضات - كيف يعمل؟

### Online Mode:
```
1. Flutter app → يرسل latitude/longitude
2. Supabase receives → يخزن في columns منفصلة
3. Trigger fires → check_geofence()
4. Function creates → geography point من lat/lon
5. Function checks → المسافة من المطعم
6. Sets → is_within_geofence = true/false
```

### Offline Mode:
```
1. Flutter app → لا يوجد اتصال
2. Hive stores → النبضة في offline_pulses box
3. App monitors → connectivity changes
4. Connection restored → PulseSyncManager.syncPendingPulses()
5. Bulk insert → جميع النبضات المؤجلة
6. Same geofencing → يطبق على كل نبضة
```

---

## 🔍 استكشاف الأخطاء

### المشكلة: النبضات لا تُرسل

**الحل**:
1. تحقق من Supabase credentials في `lib/config/app_config.dart`
2. تأكد أن Migration 004 مطبقة
3. افحص browser console للأخطاء
4. تحقق من Supabase logs

### المشكلة: Geofencing لا يعمل

**الحل**:
1. تأكد أن `check_geofence()` function محدثة
2. تحقق من إحداثيات المطعم
3. اختبر بـ SQL queries مباشرة
4. افحص `is_within_geofence` values في الـ table

### المشكلة: Offline sync لا يعمل

**الحل**:
1. تحقق من `offline_pulses` Hive box
2. افحص `PulseSyncManager` initialization
3. تأكد من connectivity permissions
4. راجع `PulseBackendClient.sendBulk()`

---

## 📊 مراقبة النظام

### Dashboard Queries:

#### 1. ملخص الحضور اليومي:
```sql
SELECT 
  p.employee_id,
  p.full_name,
  COUNT(pu.id) as total_pulses,
  COUNT(pu.id) FILTER (WHERE pu.is_within_geofence) as valid_pulses,
  ROUND(
    COUNT(pu.id) FILTER (WHERE pu.is_within_geofence)::NUMERIC / 
    NULLIF(COUNT(pu.id), 0) * 100, 
    2
  ) as valid_percentage
FROM profiles p
LEFT JOIN shifts s ON s.user_id = p.id
LEFT JOIN pulses pu ON pu.shift_id = s.id
WHERE DATE(pu.created_at) = CURRENT_DATE
GROUP BY p.id, p.employee_id, p.full_name;
```

#### 2. النبضات المشبوهة (خارج المحيط):
```sql
SELECT 
  p.employee_id,
  p.full_name,
  pu.created_at,
  pu.latitude,
  pu.longitude,
  ST_Distance(
    pu.location,
    ST_GeogFromText('POINT(31.2357 30.0444)')
  ) as distance_meters
FROM pulses pu
JOIN shifts s ON s.id = pu.shift_id
JOIN profiles p ON p.id = s.user_id
WHERE pu.is_within_geofence = FALSE
  AND DATE(pu.created_at) = CURRENT_DATE
ORDER BY pu.created_at DESC;
```

---

## 🚀 الخطوات التالية

### للإنتاج:

1. **تأمين الـ API Keys**:
   - غيّر `supabaseAnonKey` لـ production key
   - استخدم RLS policies بشكل صحيح
   - فعّل Rate Limiting

2. **تحسين الأداء**:
   - راجع indexes على الـ database
   - قلل pulse interval إذا لزم
   - استخدم connection pooling

3. **Mobile Apps**:
   - بناء Android APK: `flutter build apk --release`
   - بناء iOS IPA: `flutter build ipa --release`
   - تثبيت على الأجهزة الفعلية

4. **Monitoring & Alerts**:
   - إعداد Supabase webhooks
   - مراقبة edge function performance
   - تنبيهات للنبضات المشبوهة

---

## 📞 الدعم

### Resources:
- [Supabase Docs](https://supabase.com/docs)
- [Flutter Docs](https://docs.flutter.dev)
- [PostGIS Documentation](https://postgis.net/documentation/)

### ملفات مهمة في المشروع:
- `supabase/migrations/` - Database migrations
- `lib/services/pulse_backend_client.dart` - Supabase integration
- `lib/services/pulse_sync_manager.dart` - Offline sync logic
- `lib/services/background_pulse_service.dart` - Background pulses

---

## ✅ Checklist النهائي

- [ ] تطبيق Migration 004 على Supabase
- [ ] اختبار النبضات online
- [ ] اختبار النبضات offline
- [ ] اختبار الـ sync
- [ ] اختبار geofencing (داخل/خارج المحيط)
- [ ] اختبار calculate-payroll function
- [ ] مراجعة RLS policies
- [ ] تجهيز mobile builds للأجهزة الفعلية

---

**ملاحظة مهمة**: Migration 004 **ضرورية جداً** - بدونها النبضات لن تُخزن في Supabase! تأكد من تطبيقها قبل البدء.
