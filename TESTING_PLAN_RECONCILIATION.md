# 🧪 خطة الاختبار - Time Reconciliation

## ✅ ما تم تطبيقه

### 1. النقطة #1: Check-out صارم ✅
**مُطبق بالفعل في Phase 1**
- لا يمكن check-out إلا من داخل النطاق أو بواسطة WiFi
- نفس المنطق الصارم لـ check-in

### 2. النقطة #3: نبضة واحدة = warning، نبضتين = auto checkout ✅
**مُطبق بالفعل في Phase 2**
- نبضة خارج النطاق → تحذير فقط
- نبضتين متتاليتين خارج النطاق → Auto Check-out

### 3. النقطة #2: Time Reconciliation ✅ **NEW!**
**مُطبق الآن في sync-pulses Edge Function**
- فحص الفجوات الزمنية > 10 دقائق
- إغلاق تلقائي عند آخر نبضة قبل الفجوة

---

## 🚀 النشر

### الطريقة 1: سكريبت جاهز (الأسهل)
```bash
cd "/Users/abdelrahmanelezaby/untitled folder/test123"
./deploy_sync_pulses_only.sh
```

### الطريقة 2: يدوياً
```bash
# تثبيت Supabase CLI (إذا لم يكن مثبتاً)
npm install -g supabase

# تسجيل الدخول
supabase login

# ربط المشروع
supabase link --project-ref bbxuyuaemigrqsvsnxkj

# نشر sync-pulses
supabase functions deploy sync-pulses --no-verify-jwt
```

---

## 🧪 الاختبار على الموبايل

### Test Case 1: الوضع الطبيعي (لا إغلاق)
```
⏱️ Timeline:
08:00 - Check-in من العمل
08:05 - Pulse #1 (auto) ✅
08:10 - Pulse #2 (auto) ✅
08:15 - Pulse #3 (auto) ✅
08:20 - Check-out عادي

✅ Expected: لا إغلاق تلقائي (كل الفجوات < 10 دقائق)
```

**الخطوات:**
1. افتح التطبيق على الموبايل
2. Check-in عادي
3. انتظر 15 دقيقة (3 نبضات)
4. Check-out عادي
5. تحقق من الـ attendance table: `status = completed`, `notes = null`

---

### Test Case 2: إغلاق الموبايل (إغلاق تلقائي!)
```
⏱️ Timeline:
08:00 - Check-in من العمل
08:05 - Pulse #1 (auto) ✅
08:10 - Pulse #2 (auto) ✅
[📱 إقفال الموبايل - 15 دقيقة]
08:25 - Phone ON, app tries to sync
08:26 - Pulse #3 arrives (gap = 16 min!) 🚨

✅ Expected: 
- Session auto-closed at 08:10
- Note: "Auto-closed by Time Reconciliation: 16 min gap"
```

**الخطوات:**
1. Check-in عادي
2. انتظر 10 دقائق (2 نبضات)
3. **أطفئ الموبايل تماماً** (أو أطفئ الإنترنت)
4. انتظر 15 دقيقة
5. شغّل الموبايل + افتح التطبيق
6. انتظر 1-2 دقيقة (sync service يرفع النبضات)
7. **تحقق من Database:**
   ```sql
   SELECT id, employee_id, check_in_time, check_out_time, status, notes
   FROM attendance
   WHERE employee_id = 'YOUR_ID'
   ORDER BY check_in_time DESC
   LIMIT 1;
   ```
8. **النتيجة المتوقعة:**
   - `status = 'completed'`
   - `check_out_time = '2025-12-25 08:10:...'` (آخر نبضة)
   - `notes = 'Auto-closed by Time Reconciliation: 16 min gap'`

---

### Test Case 3: انقطاع إنترنت قصير (لا إغلاق)
```
⏱️ Timeline:
08:00 - Check-in
08:05 - Pulse #1 ✅
[📶 انقطاع إنترنت - 8 دقائق]
08:13 - Internet back, Pulse #2 (gap = 8 min) ✅

✅ Expected: لا إغلاق (Gap < 10 دقائق)
```

**الخطوات:**
1. Check-in عادي
2. انتظر 5 دقائق (نبضة واحدة)
3. أطفئ WiFi/Mobile Data لمدة 8 دقائق
4. شغّل الإنترنت
5. انتظر 2 دقيقة (sync)
6. تحقق: الجلسة لا تزال `active` ✅

---

## 📊 مراقبة النتائج

### في Supabase Dashboard

#### 1. فحص الـ Logs
```
Supabase Dashboard → Edge Functions → sync-pulses → Logs
```
ابحث عن:
```
[Reconciliation] Gap detected for employee xxx: 16 minutes
[Reconciliation] Closing session at: 2025-12-25T08:10:00.000Z
[Reconciliation] ✅ Session uuid-123 auto-closed
```

#### 2. فحص الـ Attendance Table
```sql
-- جلسات مُغلقة تلقائياً
SELECT 
  id,
  employee_id,
  check_in_time,
  check_out_time,
  status,
  notes
FROM attendance
WHERE notes LIKE '%Time Reconciliation%'
ORDER BY check_out_time DESC;
```

#### 3. فحص الـ Pulses
```sql
-- النبضات لجلسة معينة
SELECT 
  id,
  timestamp,
  is_within_geofence,
  distance_from_center,
  EXTRACT(EPOCH FROM (timestamp - LAG(timestamp) OVER (ORDER BY timestamp))) / 60 as gap_minutes
FROM pulses
WHERE attendance_id = 'YOUR_ATTENDANCE_ID'
ORDER BY timestamp;
```

---

## ⚠️ ملاحظات مهمة

### 1. الفجوة القصوى = 10 دقائق
- 5 دقائق = النبضة العادية
- 10 دقائق = نبضة واحدة فائتة (مقبول)
- > 10 دقائق = نبضتين فائتتين = غير طبيعي → إغلاق!

### 2. الـ Sync Service
- يعمل كل 60 ثانية (Phase 6)
- يرفع النبضات المحلية تلقائياً
- Time Reconciliation يعمل فوراً عند الرفع

### 3. النبضات المحلية (SQLite)
- محفوظة في `pending_pulses` table
- ترفع تلقائياً عند عودة الإنترنت
- الـ Edge Function يفحص الفجوات بعد الرفع

---

## 🎯 النجاح المتوقع

### ✅ Scenario A: موظف صادق
```
Check-in → Work 8 hours → Regular pulses → Check-out
النتيجة: راتب كامل ✅
```

### ❌ Scenario B: موظف يحاول التلاعب
```
Check-in → Work 1 hour → Turn off phone → Go home → Turn on after 5 hours
النتيجة: راتب ساعة واحدة فقط ✅ (Session closed automatically)
```

### ⚠️ Scenario C: انقطاع قصير
```
Check-in → Work → Internet down 8 min → Work continues
النتيجة: راتب كامل ✅ (Gap acceptable)
```

---

## 📱 الاختبار السريع (5 دقائق)

1. **Check-in** من الموبايل
2. انتظر **6 دقائق** (نبضة واحدة)
3. **أطفئ الموبايل** تماماً
4. انتظر **12 دقيقة**
5. **شغّل الموبايل** وافتح التطبيق
6. انتظر دقيقة واحدة
7. **تحقق من Database**: الجلسة مُغلقة؟ ✅

**إذا نجح هذا الاختبار → النظام جاهز للإنتاج!** 🎉

---

## 🆘 Troubleshooting

### المشكلة: الجلسة لم تُغلق تلقائياً
**الحلول:**
1. تأكد من نشر Edge Function: `supabase functions deploy sync-pulses`
2. تحقق من Logs: هل وصلت النبضات؟
3. تحقق من الفجوة: هل فعلاً > 10 دقائق؟
4. تحقق من SyncService: هل يعمل؟

### المشكلة: النبضات لا ترفع
**الحلول:**
1. تحقق من الإنترنت
2. تحقق من SyncService في check-in (Phase 6)
3. تحقق من SQLite: `SELECT * FROM pending_pulses WHERE synced = 0`

---

**Created:** December 25, 2025  
**Status:** ✅ READY TO TEST  
**Device Required:** Physical Android phone

**يلا نجرب! 🚀**
