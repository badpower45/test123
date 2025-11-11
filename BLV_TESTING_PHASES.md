# BLV Testing Phases - مراحل اختبار نظام BLV

## 📋 نظرة عامة

نظام BLV (Behavioral Location Verification) يمر بـ **3 مراحل اختبار** تدريجية لضمان دقة عالية وتجنب False Positives.

---

## 🔬 **المرحلة 1: Learning Mode (أسبوعين)**

### الهدف:
جمع بيانات بيئية كافية لبناء الـ Baseline الخاص بكل فرع.

### الإعدادات:
```typescript
// في blv_system_config
{
  isActive: true,  // النظام يعمل
  enableNoMotionFlag: false,  // إيقاف التنبيهات
  enableHeartbeatCheck: false,
  fallbackToWifiOnly: true,  // GPS/WiFi فقط للتحقق
}
```

### ما يحدث:
1. ✅ **جمع البيانات فقط** - لا يؤثر على validation
2. ✅ كل pulse يرسل environmental data للـ backend
3. ✅ النظام يخزن البيانات في جدول `pulses`
4. ✅ لا توجد flags أو تنبيهات
5. ✅ الموظفين يستخدمون WiFi/GPS كالمعتاد

### المراقبة:
```sql
-- 1. تحقق من عدد البيانات المجمعة
SELECT COUNT(*) 
FROM pulses 
WHERE wifi_count IS NOT NULL 
  AND created_at >= NOW() - INTERVAL '14 days';
-- يجب أن يكون > 1000 pulse لكل فرع

-- 2. تحقق من جودة البيانات
SELECT 
  branch_id,
  COUNT(*) as total_pulses,
  AVG(wifi_count) as avg_wifi,
  AVG(battery_level) as avg_battery,
  AVG(accel_variance) as avg_motion
FROM pulses
WHERE wifi_count IS NOT NULL
GROUP BY branch_id;
```

### الخطوة التالية:
بعد **14 يوم**، شغّل حساب الـ Baseline:
```bash
# عبر API
POST /api/baselines/calculate
{
  "branchId": "branch-uuid",
  "daysBack": 14
}
```

---

## ⚖️ **المرحلة 2: Hybrid Mode (أسبوعين)**

### الهدف:
اختبار دقة BLV بدون إيقاف الأنظمة القديمة (WiFi/GPS).

### الإعدادات:
```typescript
{
  isActive: true,
  enableNoMotionFlag: true,  // تفعيل التنبيهات
  enableHeartbeatCheck: false,  // heartbeat لاحقاً
  fallbackToWifiOnly: true,  // WiFi/GPS كـ backup
  
  // Thresholds متساهلة في البداية
  minPresenceScore: 0.6,  // بدلاً من 0.7
  minTrustScore: 0.5,     // بدلاً من 0.6
}
```

### ما يحدث:
1. ✅ **BLV يشتغل بجانب WiFi/GPS**
2. ✅ إذا BLV قال Valid → ✅ القبول
3. ✅ إذا BLV قال Invalid → تحقق من WiFi/GPS
4. ✅ إذا WiFi/GPS قالوا Valid → ✅ القبول (مع flag تحذير)
5. ⚠️ Flags يتم إنشاؤها لكن **لا ترفض** الـ pulse

### الحالات:

| BLV Score | WiFi/GPS | النتيجة | Flag |
|-----------|----------|---------|------|
| ≥ 0.6 | ✅/❌ | ✅ VALID | - |
| < 0.6 | ✅ | ✅ VALID | ⚠️ BLV_Suspicious |
| < 0.6 | ❌ | ❌ INVALID | 🚫 Location_Mismatch |

### المراقبة:
```sql
-- 1. نسبة توافق BLV مع WiFi/GPS
SELECT 
  verification_method,
  COUNT(*) as count,
  AVG(presence_score) as avg_presence,
  AVG(trust_score) as avg_trust
FROM pulses
WHERE created_at >= NOW() - INTERVAL '7 days'
GROUP BY verification_method;

-- 2. Flags المكررة (نفس الموظف كل يوم)
SELECT 
  employee_id,
  flag_type,
  COUNT(*) as occurrence_count,
  AVG(severity) as avg_severity
FROM pulse_flags
WHERE is_resolved = false
GROUP BY employee_id, flag_type
HAVING COUNT(*) > 5;  -- 5 مرات في أسبوع = مشكلة حقيقية
```

### معايير النجاح:
- ✅ BLV Agreement مع WiFi/GPS > **85%**
- ✅ False Positive Rate < **10%**
- ✅ عدد الـ Flags < **20 يومياً**

### التعديلات المتوقعة:
```typescript
// إذا كان False Positives كثيرة:
{
  minPresenceScore: 0.55,  // خفض الحد
  wifiWeight: 0.5,         // زيادة وزن WiFi
  motionWeight: 0.15,      // تقليل وزن Motion
}
```

---

## 🚀 **المرحلة 3: Full BLV Mode**

### الهدف:
**BLV يصبح النظام الأساسي** للتحقق، WiFi/GPS backup فقط.

### الإعدادات:
```typescript
{
  isActive: true,
  enableNoMotionFlag: true,
  enableHeartbeatCheck: true,  // تفعيل كل الحماية
  fallbackToWifiOnly: false,   // BLV أولاً
  
  // Thresholds نهائية
  minPresenceScore: 0.7,
  minTrustScore: 0.6,
  
  // Weights محسنة بناءً على Phase 2
  wifiWeight: 0.45,
  motionWeight: 0.20,
  soundWeight: 0.20,
  batteryWeight: 0.15,
}
```

### ما يحدث:
1. ✅ **BLV هو الأساس**
2. ⚠️ إذا BLV Invalid → **ترفض** الـ pulse
3. 🔄 WiFi/GPS يُستخدمان فقط إذا BLV فشل (error)
4. 🚫 Flags تؤدي لـ **تعليق الحساب** حتى يراجع Manager

### Logic Flow:
```typescript
if (blvData exists) {
  const blvResult = verifyPresence(environmentalData);
  
  if (blvResult.presenceScore >= 0.7 && blvResult.trustScore >= 0.6) {
    return { valid: true, method: 'BLV' };
  } else {
    // إنشاء Flag
    createAutoFlags(pulseId, employeeId, blvResult.flags);
    
    return { 
      valid: false, 
      method: 'BLV',
      status: 'SUSPICIOUS',
      requiresManagerReview: true 
    };
  }
} else {
  // Fallback to WiFi/GPS (في حالة خطأ فني فقط)
  return wifiGpsValidation();
}
```

### Manager Actions:
عندما يظهر flag:
1. **Review** - مراجعة تفاصيل الـ pulse
2. **Approve** - موافقة (إذا كان false positive)
3. **Reject** - رفض (إذا كان غش فعلي)
4. **Override** - تعديل يدوي للـ score

### المراقبة المستمرة:
```sql
-- 1. Daily Stats
SELECT 
  DATE(created_at) as date,
  COUNT(*) FILTER (WHERE verification_method = 'BLV') as blv_count,
  COUNT(*) FILTER (WHERE verification_method = 'WiFi') as wifi_count,
  COUNT(*) FILTER (WHERE status = 'SUSPICIOUS') as suspicious_count,
  AVG(presence_score) as avg_presence,
  AVG(trust_score) as avg_trust
FROM pulses
WHERE created_at >= NOW() - INTERVAL '30 days'
GROUP BY DATE(created_at)
ORDER BY date DESC;

-- 2. Top Offenders (كثيري التنبيهات)
SELECT 
  e.full_name,
  e.id,
  COUNT(pf.id) as flag_count,
  array_agg(DISTINCT pf.flag_type) as flag_types
FROM employees e
JOIN pulse_flags pf ON pf.employee_id = e.id
WHERE pf.is_resolved = false
  AND pf.created_at >= NOW() - INTERVAL '7 days'
GROUP BY e.id, e.full_name
ORDER BY flag_count DESC
LIMIT 10;

-- 3. System Health
SELECT 
  'Total Pulses' as metric,
  COUNT(*) as value
FROM pulses
WHERE created_at >= NOW() - INTERVAL '1 day'
UNION ALL
SELECT 
  'BLV Success Rate',
  ROUND(100.0 * COUNT(*) FILTER (WHERE presence_score >= 0.7 AND trust_score >= 0.6) / COUNT(*), 2)
FROM pulses
WHERE wifi_count IS NOT NULL
  AND created_at >= NOW() - INTERVAL '1 day'
UNION ALL
SELECT 
  'Unresolved Flags',
  COUNT(*)::text
FROM pulse_flags
WHERE is_resolved = false;
```

---

## 📊 **KPIs لكل مرحلة**

### Learning Mode:
- ✅ Data Collection Rate: **> 95%** من الـ pulses
- ✅ WiFi Data Quality: **> 80%** بيانات WiFi صحيحة
- ✅ Baseline Confidence: **> 0.7** بعد أسبوعين

### Hybrid Mode:
- ✅ BLV-WiFi Agreement: **> 85%**
- ✅ False Positive Rate: **< 10%**
- ✅ Manager Approval Rate: **> 90%** للـ flags

### Full BLV Mode:
- ✅ BLV Usage: **> 90%** من الـ pulses
- ✅ Fraud Detection: **> 5** حالات غش حقيقية شهرياً
- ✅ System Uptime: **> 99%**
- ✅ Average Response Time: **< 2 seconds**

---

## 🔧 **Troubleshooting**

### مشكلة: False Positives كثيرة
**الحل:**
```typescript
// خفض الـ thresholds
minPresenceScore: 0.6 → 0.55
minTrustScore: 0.5 → 0.45

// تعديل الأوزان
wifiWeight: 0.4 → 0.5  // زيادة اعتماد WiFi
motionWeight: 0.2 → 0.15  // تقليل Motion
```

### مشكلة: Baselines غير دقيقة
**الحل:**
```sql
-- إعادة حساب باستخدام بيانات أكثر
POST /api/baselines/calculate
{
  "branchId": "xxx",
  "daysBack": 30  -- بدلاً من 14
}
```

### مشكلة: أجهزة معينة دايماً flagged
**الحل:**
```typescript
// إضافة device calibration
INSERT INTO device_calibrations (device_model, os_type, accel_calibration_factor)
VALUES ('Samsung Galaxy A50', 'android', 1.5);
// Factor > 1 = الجهاز حساس أكثر من المعتاد
```

---

## ✅ **Checklist قبل كل مرحلة**

### قبل Phase 1:
- [ ] Database migration منفذة
- [ ] Flutter app محدثة بـ BLV SDK
- [ ] Server endpoints شغالة
- [ ] Monitoring dashboard جاهز

### قبل Phase 2:
- [ ] Baselines محسوبة لكل الفروع
- [ ] False Positive Rate < 15%
- [ ] Manager training على الـ Flags page
- [ ] Baseline confidence > 0.7

### قبل Phase 3:
- [ ] False Positive Rate < 10%
- [ ] BLV-WiFi Agreement > 85%
- [ ] Manager approval process واضح
- [ ] Support team جاهز للـ escalations

---

## 📞 **Support**

عند حدوث مشاكل:
1. تحقق من الـ logs: `console.log('[BLV]')`
2. راجع الـ SQL queries أعلاه
3. تحقق من الـ baseline confidence
4. اعمل manual override للحالات الصعبة

**التواصل:** أرسل الـ pulse ID + employee ID + screenshot للـ flag
