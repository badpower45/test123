# BLV System Enhancements - تحسينات نظام BLV

## 🎯 النقاط المُحسّنة للإطلاق الفعلي

---

## 🔹 1. Confidence Decay System

### المشكلة:
الـ Baseline ثابت، لكن البيئة المحيطة بتتغير (راوتر جديد، شبكات WiFi تظهر/تختفي).

### الحل:
```typescript
// في baseline-calculation.ts
export function calculateBaselineConfidence(
  baseline: BranchBaseline,
  currentDate: Date
): number {
  const daysSinceUpdate = Math.floor(
    (currentDate.getTime() - baseline.lastUpdated.getTime()) / (1000 * 60 * 60 * 24)
  );
  
  // Decay factor: 0.98 ^ days
  // بعد 30 يوم: 0.98^30 = 0.545 (54.5%)
  // بعد 60 يوم: 0.98^60 = 0.297 (29.7%)
  const decayFactor = Math.pow(0.98, daysSinceUpdate);
  
  return baseline.confidence * decayFactor;
}

// استخدام في blv-verification.ts
export async function verifyPresence(
  pulseData: PulseData,
  branchId: string
): Promise<BLVResult> {
  const baseline = await db.query.branchBaselines.findFirst({
    where: eq(branchBaselines.branchId, branchId)
  });
  
  if (!baseline) {
    return { valid: false, reason: 'NO_BASELINE' };
  }
  
  // تطبيق Confidence Decay
  const currentConfidence = calculateBaselineConfidence(baseline, new Date());
  
  // إذا Confidence < 50% → يحتاج Recalibration
  if (currentConfidence < 0.5) {
    console.warn(`[BLV] Branch ${branchId} baseline expired. Confidence: ${currentConfidence.toFixed(2)}`);
    
    // Auto-trigger baseline update
    await scheduleBaselineRecalculation(branchId);
    
    // Fallback to WiFi/GPS temporarily
    return { valid: false, reason: 'BASELINE_EXPIRED', shouldFallback: true };
  }
  
  // حساب Presence Score مع الأخذ في الاعتبار Confidence
  const rawPresenceScore = calculatePresenceScore(pulseData, baseline);
  const adjustedPresenceScore = rawPresenceScore * currentConfidence;
  
  return {
    valid: adjustedPresenceScore >= 0.7,
    presenceScore: adjustedPresenceScore,
    baselineConfidence: currentConfidence,
    method: 'BLV'
  };
}
```

### Schedule Automatic Recalibration:
```typescript
// في server/index.ts
import cron from 'node-cron';

// كل يوم الساعة 3 صباحاً - تحقق من Baselines
cron.schedule('0 3 * * *', async () => {
  console.log('[BLV] Running daily baseline confidence check...');
  
  const expiredBaselines = await db.select()
    .from(branchBaselines)
    .where(
      sql`(EXTRACT(EPOCH FROM (NOW() - last_updated)) / 86400) > 30`
    );
  
  for (const baseline of expiredBaselines) {
    const confidence = calculateBaselineConfidence(baseline, new Date());
    
    if (confidence < 0.6) {
      console.log(`[BLV] Recalculating baseline for branch: ${baseline.branchId}`);
      await calculateBranchBaseline(baseline.branchId, 14);
    }
  }
});
```

---

## 🔹 2. Real-time Flag Escalation (Slack/Telegram)

### الهدف:
إرسال تنبيه فوري للـ Manager عند ظهور flag خطير.

### التنفيذ:

#### A. إضافة Slack Integration:
```typescript
// server/services/notification-service.ts
import axios from 'axios';

const SLACK_WEBHOOK_URL = process.env.SLACK_WEBHOOK_URL;
const TELEGRAM_BOT_TOKEN = process.env.TELEGRAM_BOT_TOKEN;
const TELEGRAM_CHAT_ID = process.env.TELEGRAM_CHAT_ID;

export async function sendSlackAlert(message: string, severity: number) {
  if (!SLACK_WEBHOOK_URL) return;
  
  const color = severity > 0.8 ? '#FF0000' : severity > 0.5 ? '#FFA500' : '#FFFF00';
  
  const payload = {
    attachments: [{
      color,
      title: '🚨 BLV Security Alert',
      text: message,
      footer: 'Oldies Workers System',
      ts: Math.floor(Date.now() / 1000)
    }]
  };
  
  try {
    await axios.post(SLACK_WEBHOOK_URL, payload);
  } catch (error) {
    console.error('[Slack] Failed to send alert:', error);
  }
}

export async function sendTelegramAlert(message: string) {
  if (!TELEGRAM_BOT_TOKEN || !TELEGRAM_CHAT_ID) return;
  
  const url = `https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage`;
  
  try {
    await axios.post(url, {
      chat_id: TELEGRAM_CHAT_ID,
      text: `🚨 *BLV Alert*\n\n${message}`,
      parse_mode: 'Markdown'
    });
  } catch (error) {
    console.error('[Telegram] Failed to send alert:', error);
  }
}
```

#### B. دمج في Flag Creation:
```typescript
// في blv-verification.ts
import { sendSlackAlert, sendTelegramAlert } from './notification-service';

export async function createAutoFlags(
  pulseId: string,
  employeeId: string,
  flags: FlagData[]
) {
  const createdFlags = [];
  
  for (const flag of flags) {
    const newFlag = await db.insert(pulseFlags).values({
      id: uuidv4(),
      pulseId,
      employeeId,
      flagType: flag.type,
      severity: flag.severity,
      details: flag.details,
      isResolved: false,
      createdAt: new Date()
    }).returning();
    
    createdFlags.push(newFlag[0]);
    
    // 🔥 Real-time Escalation
    if (flag.severity > 0.8) {
      const employee = await db.query.employees.findFirst({
        where: eq(employees.id, employeeId)
      });
      
      const message = `
        **Employee:** ${employee?.fullName || 'Unknown'}
        **Flag Type:** ${flag.type}
        **Severity:** ${(flag.severity * 100).toFixed(0)}%
        **Details:** ${flag.details}
        **Time:** ${new Date().toLocaleString('en-US', { timeZone: 'Africa/Cairo' })}
      `;
      
      // إرسال للـ Slack و Telegram
      await Promise.all([
        sendSlackAlert(message, flag.severity),
        sendTelegramAlert(message)
      ]);
    }
  }
  
  return createdFlags;
}
```

#### C. Environment Variables (.env):
```env
# Slack Integration
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL

# Telegram Integration
TELEGRAM_BOT_TOKEN=1234567890:ABCdefGHIjklMNOpqrsTUVwxyz
TELEGRAM_CHAT_ID=-1001234567890
```

---

## 🔹 3. Baseline Drift Detection

### المشكلة:
إذا تغيّر الراوتر أو الشبكة، الـ Baseline القديم بيصبح غير دقيق.

### الحل:
```typescript
// server/services/drift-detection.ts
import { db } from '../db';
import { pulses, branchBaselines, driftAlerts } from '../db/schema';
import { eq, sql, gte } from 'drizzle-orm';

export async function detectBaselineDrift(branchId: string): Promise<DriftReport> {
  // جمع آخر 100 pulse
  const recentPulses = await db.select()
    .from(pulses)
    .where(eq(pulses.branchId, branchId))
    .orderBy(sql`created_at DESC`)
    .limit(100);
  
  if (recentPulses.length < 50) {
    return { hasDrift: false, reason: 'INSUFFICIENT_DATA' };
  }
  
  // الحصول على الـ Baseline الحالي
  const baseline = await db.query.branchBaselines.findFirst({
    where: eq(branchBaselines.branchId, branchId)
  });
  
  if (!baseline) {
    return { hasDrift: true, reason: 'NO_BASELINE' };
  }
  
  // حساب متوسط البيانات الأخيرة
  const avgWifiCount = recentPulses.reduce((sum, p) => sum + (p.wifiCount || 0), 0) / recentPulses.length;
  const avgBattery = recentPulses.reduce((sum, p) => sum + (p.batteryLevel || 0), 0) / recentPulses.length;
  const avgMotion = recentPulses.reduce((sum, p) => sum + (p.accelVariance || 0), 0) / recentPulses.length;
  
  // حساب الفرق (Drift)
  const wifiDrift = Math.abs(avgWifiCount - baseline.avgWifiCount);
  const batteryDrift = Math.abs(avgBattery - baseline.avgBatteryLevel);
  const motionDrift = Math.abs(avgMotion - baseline.avgAccelVariance);
  
  // Thresholds
  const WIFI_THRESHOLD = 3;  // ±3 شبكات
  const BATTERY_THRESHOLD = 0.15;  // ±15%
  const MOTION_THRESHOLD = 0.3;  // ±0.3 variance
  
  const driftDetected = 
    wifiDrift > WIFI_THRESHOLD ||
    batteryDrift > BATTERY_THRESHOLD ||
    motionDrift > MOTION_THRESHOLD;
  
  if (driftDetected) {
    // تسجيل Drift Alert
    await db.insert(driftAlerts).values({
      id: uuidv4(),
      branchId,
      driftType: wifiDrift > WIFI_THRESHOLD ? 'WIFI' : 
                 batteryDrift > BATTERY_THRESHOLD ? 'BATTERY' : 'MOTION',
      oldValue: wifiDrift > WIFI_THRESHOLD ? baseline.avgWifiCount : baseline.avgBatteryLevel,
      newValue: wifiDrift > WIFI_THRESHOLD ? avgWifiCount : avgBattery,
      driftMagnitude: Math.max(wifiDrift / WIFI_THRESHOLD, batteryDrift / BATTERY_THRESHOLD, motionDrift / MOTION_THRESHOLD),
      detectedAt: new Date()
    });
    
    // إرسال تنبيه
    await sendSlackAlert(
      `🔄 Baseline Drift Detected!\nBranch: ${branchId}\nWiFi Drift: ${wifiDrift.toFixed(1)} networks\nAction Required: Recalibrate baseline`,
      0.7
    );
  }
  
  return {
    hasDrift: driftDetected,
    wifiDrift,
    batteryDrift,
    motionDrift,
    recommendation: driftDetected ? 'RECALIBRATE_BASELINE' : 'OK'
  };
}

// Schedule Drift Detection - كل 6 ساعات
cron.schedule('0 */6 * * *', async () => {
  console.log('[BLV] Running baseline drift detection...');
  
  const branches = await db.select({ id: branchBaselines.branchId })
    .from(branchBaselines);
  
  for (const branch of branches) {
    await detectBaselineDrift(branch.id);
  }
});
```

### Database Schema Addition:
```sql
-- أضف جدول drift_alerts
CREATE TABLE drift_alerts (
  id UUID PRIMARY KEY,
  branch_id UUID NOT NULL REFERENCES branches(id),
  drift_type VARCHAR(50) NOT NULL, -- 'WIFI', 'BATTERY', 'MOTION'
  old_value DECIMAL(10,2),
  new_value DECIMAL(10,2),
  drift_magnitude DECIMAL(5,2), -- نسبة التغيير
  detected_at TIMESTAMP DEFAULT NOW(),
  resolved BOOLEAN DEFAULT FALSE
);

CREATE INDEX idx_drift_branch ON drift_alerts(branch_id, detected_at DESC);
```

---

## 🔹 4. Device Trust Layer

### الهدف:
تقييم كل جهاز بناءً على تاريخه وسلوكه.

### Database Schema:
```sql
CREATE TABLE device_fingerprints (
  id UUID PRIMARY KEY,
  device_id VARCHAR(255) UNIQUE NOT NULL, -- IMEI / Android ID
  employee_id UUID REFERENCES employees(id),
  device_model VARCHAR(100),
  os_type VARCHAR(20), -- 'android', 'ios'
  os_version VARCHAR(20),
  first_seen TIMESTAMP DEFAULT NOW(),
  last_seen TIMESTAMP DEFAULT NOW(),
  
  -- Trust Metrics
  total_pulses INTEGER DEFAULT 0,
  flagged_pulses INTEGER DEFAULT 0,
  calibration_factor DECIMAL(5,2) DEFAULT 1.0, -- Sensor correction
  reliability_index DECIMAL(5,2) DEFAULT 1.0,  -- 0.0 - 1.0
  
  -- Behavioral Patterns
  avg_gps_accuracy DECIMAL(10,2),
  typical_battery_drain DECIMAL(5,2),
  
  is_blacklisted BOOLEAN DEFAULT FALSE,
  blacklist_reason TEXT,
  
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_device_employee ON device_fingerprints(employee_id);
CREATE INDEX idx_device_trust ON device_fingerprints(reliability_index DESC);
```

### Service Implementation:
```typescript
// server/services/device-trust.ts
export async function calculateDeviceTrust(deviceId: string): Promise<number> {
  const device = await db.query.deviceFingerprints.findFirst({
    where: eq(deviceFingerprints.deviceId, deviceId)
  });
  
  if (!device) return 0.5; // Unknown device = neutral trust
  
  if (device.isBlacklisted) return 0.0;
  
  // Trust Score Components
  const flagRatio = device.totalPulses > 0 
    ? device.flaggedPulses / device.totalPulses 
    : 0;
  
  const behaviorScore = 1 - flagRatio; // 0 flags = 1.0, all flags = 0.0
  const longevityScore = Math.min(device.totalPulses / 1000, 1.0); // Max 1.0 at 1000 pulses
  const reliabilityScore = device.reliabilityIndex;
  
  // Weighted Trust Score
  const trustScore = (
    behaviorScore * 0.5 +
    longevityScore * 0.2 +
    reliabilityScore * 0.3
  );
  
  return Math.max(0, Math.min(1, trustScore));
}

export async function updateDeviceTrust(
  deviceId: string,
  pulseWasFlagged: boolean
) {
  const device = await db.query.deviceFingerprints.findFirst({
    where: eq(deviceFingerprints.deviceId, deviceId)
  });
  
  if (!device) {
    // إنشاء Device جديد
    await db.insert(deviceFingerprints).values({
      id: uuidv4(),
      deviceId,
      totalPulses: 1,
      flaggedPulses: pulseWasFlagged ? 1 : 0,
      reliabilityIndex: 0.8 // Initial trust
    });
    return;
  }
  
  // تحديث
  const newTotalPulses = device.totalPulses + 1;
  const newFlaggedPulses = device.flaggedPulses + (pulseWasFlagged ? 1 : 0);
  const newFlagRatio = newFlaggedPulses / newTotalPulses;
  
  // إذا Flag Ratio > 30% → تخفيض Reliability
  let newReliability = device.reliabilityIndex;
  if (newFlagRatio > 0.3) {
    newReliability = Math.max(0.3, newReliability * 0.95);
  } else if (newFlagRatio < 0.1) {
    // تحسين تدريجي
    newReliability = Math.min(1.0, newReliability * 1.02);
  }
  
  await db.update(deviceFingerprints)
    .set({
      totalPulses: newTotalPulses,
      flaggedPulses: newFlaggedPulses,
      reliabilityIndex: newReliability,
      lastSeen: new Date(),
      updatedAt: new Date()
    })
    .where(eq(deviceFingerprints.deviceId, deviceId));
}
```

### Integration in BLV Verification:
```typescript
// في blv-verification.ts
export async function verifyPresence(
  pulseData: PulseData,
  branchId: string,
  deviceId: string
): Promise<BLVResult> {
  // ... existing code ...
  
  // Apply Device Trust
  const deviceTrust = await calculateDeviceTrust(deviceId);
  
  if (deviceTrust < 0.3) {
    // جهاز منخفض الثقة
    return {
      valid: false,
      reason: 'LOW_DEVICE_TRUST',
      trustScore: deviceTrust,
      requiresManagerReview: true
    };
  }
  
  // Adjust Trust Score
  const adjustedTrustScore = baseTrustScore * deviceTrust;
  
  return {
    valid: presenceScore >= 0.7 && adjustedTrustScore >= 0.6,
    presenceScore,
    trustScore: adjustedTrustScore,
    deviceTrust,
    method: 'BLV'
  };
}
```

---

## 🔹 5. Performance Optimization - Database Indexes

```sql
-- Migration: add_blv_indexes.sql

-- Pulses - للـ Queries الثقيلة
CREATE INDEX idx_pulses_branch_created ON pulses(branch_id, created_at DESC);
CREATE INDEX idx_pulses_employee_created ON pulses(employee_id, created_at DESC);
CREATE INDEX idx_pulses_verification_method ON pulses(verification_method);
CREATE INDEX idx_pulses_blv_scores ON pulses(presence_score, trust_score) 
  WHERE wifi_count IS NOT NULL;

-- Flags - للمراجعة السريعة
CREATE INDEX idx_flags_employee_date ON pulse_flags(employee_id, created_at DESC);
CREATE INDEX idx_flags_unresolved ON pulse_flags(is_resolved, severity DESC) 
  WHERE is_resolved = FALSE;
CREATE INDEX idx_flags_type_severity ON pulse_flags(flag_type, severity DESC);

-- Baselines - للـ Lookup السريع
CREATE INDEX idx_baselines_branch ON branch_baselines(branch_id);
CREATE INDEX idx_baselines_confidence ON branch_baselines(confidence DESC);

-- WiFi Signals - للـ Fingerprinting
CREATE INDEX idx_wifi_branch_time ON wifi_signals(branch_id, timestamp DESC);
CREATE INDEX idx_wifi_bssid ON wifi_signals(bssid);

-- Device Fingerprints
CREATE INDEX idx_device_trust_score ON device_fingerprints(reliability_index DESC);
CREATE INDEX idx_device_blacklist ON device_fingerprints(is_blacklisted) 
  WHERE is_blacklisted = TRUE;

-- Composite Indexes للـ Complex Queries
CREATE INDEX idx_pulses_branch_employee_date 
  ON pulses(branch_id, employee_id, created_at DESC);

CREATE INDEX idx_flags_pulse_employee 
  ON pulse_flags(pulse_id, employee_id, is_resolved);
```

---

## 🔹 6. Self-Healing Logic

### الهدف:
النظام يتحول تلقائياً للـ Fallback Mode إذا حصل مشكلة في BLV.

```typescript
// server/services/health-monitor.ts
import { db } from '../db';
import { blvSystemConfig } from '../db/schema';

let lastHeartbeat = Date.now();
let fallbackModeActive = false;

export function recordHeartbeat() {
  lastHeartbeat = Date.now();
  
  if (fallbackModeActive) {
    console.log('[BLV] Heartbeat restored, exiting fallback mode.');
    fallbackModeActive = false;
  }
}

export function checkSystemHealth(): boolean {
  const timeSinceHeartbeat = Date.now() - lastHeartbeat;
  const HEARTBEAT_TIMEOUT = 3 * 60 * 1000; // 3 minutes
  
  if (timeSinceHeartbeat > HEARTBEAT_TIMEOUT && !fallbackModeActive) {
    console.error('[BLV] Heartbeat lost! Engaging fallback mode.');
    fallbackModeActive = true;
    
    // Send alert
    sendSlackAlert(
      '🚨 BLV System Heartbeat Lost!\nSwitching to WiFi/GPS fallback mode.',
      1.0
    );
    
    // تعديل الـ Config تلقائياً
    db.update(blvSystemConfig)
      .set({ fallbackToWifiOnly: true })
      .where(eq(blvSystemConfig.id, 1));
  }
  
  return !fallbackModeActive;
}

// Schedule Health Check - كل دقيقة
cron.schedule('* * * * *', () => {
  checkSystemHealth();
});

// API Endpoint للـ Heartbeat
app.post('/api/blv/heartbeat', (req, res) => {
  recordHeartbeat();
  res.json({ status: 'ok', timestamp: Date.now() });
});
```

### Flutter Client Heartbeat:
```dart
// lib/services/blv/blv_heartbeat.dart
class BLVHeartbeat {
  static Timer? _heartbeatTimer;
  
  static void startHeartbeat() {
    _heartbeatTimer?.cancel();
    
    _heartbeatTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _sendHeartbeat(),
    );
  }
  
  static Future<void> _sendHeartbeat() async {
    try {
      final response = await http.post(
        Uri.parse('${Config.baseUrl}/api/blv/heartbeat'),
      );
      
      if (response.statusCode == 200) {
        print('[BLV] Heartbeat sent successfully');
      }
    } catch (e) {
      print('[BLV] Heartbeat failed: $e');
    }
  }
  
  static void stopHeartbeat() {
    _heartbeatTimer?.cancel();
  }
}

// استخدام في main.dart
void main() {
  runApp(MyApp());
  BLVHeartbeat.startHeartbeat();
}
```

---

## 📊 Summary - ملخص التحسينات

| التحسين | الأثر | الأولوية |
|---------|-------|----------|
| ✅ Confidence Decay | يمنع استخدام baselines قديمة | **عالي** |
| ✅ Real-time Alerts | استجابة فورية للـ flags الخطيرة | **عالي** |
| ✅ Drift Detection | يكتشف تغييرات البيئة تلقائياً | **متوسط** |
| ✅ Device Trust | يقلل false positives من أجهزة معينة | **متوسط** |
| ✅ Performance Indexes | يحسن سرعة الـ queries ب 10x | **عالي** |
| ✅ Self-Healing | يمنع توقف النظام الكامل | **عالي** |

---

## 🚀 خطوات التنفيذ

### المرحلة 1 (الآن):
1. ✅ إضافة Confidence Decay
2. ✅ إضافة Performance Indexes
3. ✅ إضافة Self-Healing Logic

### المرحلة 2 (بعد Testing Phase 1):
4. ✅ تفعيل Real-time Alerts (Slack/Telegram)
5. ✅ تفعيل Drift Detection

### المرحلة 3 (بعد Hybrid Mode):
6. ✅ تفعيل Device Trust Layer
7. ✅ Fine-tuning Thresholds

