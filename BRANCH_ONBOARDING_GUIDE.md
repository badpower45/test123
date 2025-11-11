# Branch Onboarding Flow - إضافة فرع جديد

## 🎯 الهدف
تسهيل إضافة فرع جديد على الأونر مع جمع بيانات BLV الأساسية.

---

## 📋 البيانات المطلوبة

### 1. البيانات الأساسية (إلزامية):
```typescript
{
  branchName: string,          // اسم الفرع
  latitude: number,            // خط العرض
  longitude: number,           // خط الطول
  geofenceRadius: number,      // نصف القطر (100-200 متر)
  managerEmployeeId: string,   // المدير المسؤول
  workingHours: {
    start: "09:00",
    end: "21:00"
  }
}
```

### 2. البيانات التلقائية (تُجمع تلقائياً):
```typescript
{
  connectedWifiSSID: string,      // اسم الشبكة (iOS/Android)
  wifiBSSIDs: string[],           // MAC addresses (Android فقط)
  avgWifiCount: number,           // متوسط عدد الشبكات
  avgSoundLevel: number,          // متوسط الصوت
  avgMotionVariance: number,      // متوسط الحركة
  batteryPattern: object          // نمط الشحن
}
```

---

## 🚀 خطوات Onboarding (5-15 دقيقة)

### الطريقة الموجهة (Guided Flow):

```
┌─────────────────────────────────────┐
│ Step 1: Basic Info                  │
│ ✅ اسم الفرع                        │
│ ✅ اختيار المدير                    │
│ ✅ ساعات العمل                      │
└─────────────────────────────────────┘
          ↓
┌─────────────────────────────────────┐
│ Step 2: Location Setup              │
│ 📍 حدد الموقع على الخريطة          │
│ 🔵 اضبط نصف القطر (slider)         │
│ ✅ Preview الدائرة الخضراء          │
└─────────────────────────────────────┘
          ↓
┌─────────────────────────────────────┐
│ Step 3: WiFi Setup (Auto)           │
│ 📡 النظام يكتشف WiFi تلقائياً      │
│    - iOS: SSID فقط                  │
│    - Android: SSID + BSSIDs         │
│ ✅ "نحفظ: Home WiFi"                │
└─────────────────────────────────────┘
          ↓
┌─────────────────────────────────────┐
│ Step 4: Baseline Calibration        │
│ 🚶 اجعل المدير يتحرك في الفرع      │
│    - 10-15 دقيقة                    │
│    - زر داخل الـ App                │
│    - النظام يجمع:                   │
│      • WiFi signals                 │
│      • Motion patterns              │
│      • Sound levels                 │
│      • Battery behavior             │
│ ✅ Progress: 8/10 samples           │
└─────────────────────────────────────┘
          ↓
┌─────────────────────────────────────┐
│ Step 5: QR Code Generation          │
│ 📄 طباعة QR Code للفرع             │
│    - Token يتغير يومياً             │
│    - للاستخدام على iOS              │
│    - علّقه عند المدخل               │
│ ✅ Download PDF                     │
└─────────────────────────────────────┘
          ↓
┌─────────────────────────────────────┐
│ ✅ Branch Created Successfully!     │
│ الفرع جاهز لاستقبال الموظفين        │
└─────────────────────────────────────┘
```

---

## 💾 ما يُحفظ في الـ Database

### 1. جدول `branches`:
```sql
INSERT INTO branches (
  id,
  name,
  latitude,
  longitude,
  geofence_radius,
  manager_id,
  created_at
) VALUES (
  gen_random_uuid(),
  'فرع المعادي',
  29.9606,
  31.2497,
  150,
  'manager-uuid',
  NOW()
);
```

### 2. جدول `branch_bssids`:
```sql
-- Android only (iOS لا يرى BSSIDs)
INSERT INTO branch_bssids (branch_id, bssid, ssid)
VALUES 
  ('branch-uuid', 'AA:BB:CC:DD:EE:FF', 'Home WiFi'),
  ('branch-uuid', '11:22:33:44:55:66', 'Neighbor WiFi');
```

### 3. جدول `branch_environment_baselines`:
```sql
INSERT INTO branch_environment_baselines (
  id,
  branch_id,
  time_slot,
  avg_wifi_count,
  avg_wifi_signal,
  avg_battery_level,
  avg_motion_variance,
  avg_sound_level,
  sample_count,
  confidence,
  last_updated
) VALUES (
  gen_random_uuid(),
  'branch-uuid',
  'all',                -- كل الأوقات
  12.5,                 -- متوسط 12.5 شبكة WiFi
  -65.0,                -- متوسط قوة إشارة
  0.45,                 -- متوسط البطارية
  0.35,                 -- متوسط الحركة
  0.28,                 -- متوسط الصوت
  50,                   -- 50 sample تم جمعها
  0.85,                 -- ثقة 85%
  NOW()
);
```

### 4. جدول `blv_system_config`:
```sql
-- إعدادات خاصة بالفرع (اختياري)
INSERT INTO blv_system_config (
  branch_id,
  is_active,
  enable_no_motion_flag,
  fallback_to_wifi_only,
  min_presence_score,
  min_trust_score
) VALUES (
  'branch-uuid',
  true,    -- BLV مفعّل
  false,   -- لا flags في Learning Mode
  true,    -- WiFi/GPS كـ backup
  0.6,     -- threshold منخفض في البداية
  0.5
);
```

### 5. QR Token Storage:
```sql
CREATE TABLE branch_qr_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id UUID REFERENCES branches(id),
  token VARCHAR(32) NOT NULL,
  valid_from DATE NOT NULL,
  valid_until DATE NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Generate daily token
INSERT INTO branch_qr_tokens (branch_id, token, valid_from, valid_until)
VALUES (
  'branch-uuid',
  'A3F7B2E9D1C4',      -- Random token
  CURRENT_DATE,
  CURRENT_DATE + 1     -- Valid for 1 day
);
```

---

## 🖥️ واجهة Owner Dashboard

### صفحة "Add Branch":

```typescript
// React/Flutter UI Flow
const BranchOnboarding = () => {
  const [step, setStep] = useState(1);
  const [branchData, setBranchData] = useState({});
  
  return (
    <Stepper activeStep={step}>
      {/* Step 1: Basic Info */}
      <Step>
        <TextField label="اسم الفرع" />
        <Select label="المدير" />
        <TimePicker label="ساعات العمل" />
      </Step>
      
      {/* Step 2: Location */}
      <Step>
        <Map 
          onLocationSelect={handleLocationSelect}
          radiusSlider={true}
        />
      </Step>
      
      {/* Step 3: WiFi Auto-detect */}
      <Step>
        <WiFiScanner 
          onDetect={(networks) => {
            setBranchData({
              ...branchData,
              ssid: networks[0].ssid,
              bssids: networks.map(n => n.bssid)
            });
          }}
        />
      </Step>
      
      {/* Step 4: Calibration */}
      <Step>
        <CalibrationWizard
          branchId={branchData.id}
          duration={15} // 15 minutes
          onComplete={(baseline) => {
            console.log('Baseline created:', baseline);
          }}
        />
      </Step>
      
      {/* Step 5: QR Code */}
      <Step>
        <QRCodeGenerator 
          branchId={branchData.id}
          onDownload={handleDownloadPDF}
        />
      </Step>
    </Stepper>
  );
};
```

---

## 📱 Calibration Wizard (Mobile)

### في تطبيق الـ Manager:

```dart
// Flutter - Manager App
class BranchCalibrationScreen extends StatefulWidget {
  final String branchId;
  
  @override
  _BranchCalibrationScreenState createState() => ...
}

class _BranchCalibrationScreenState extends State {
  int samplesCollected = 0;
  int targetSamples = 10;
  bool isCalibrating = false;
  
  Future<void> startCalibration() async {
    setState(() => isCalibrating = true);
    
    // جمع عينات كل دقيقة لمدة 10 دقائق
    Timer.periodic(Duration(minutes: 1), (timer) async {
      if (samplesCollected >= targetSamples) {
        timer.cancel();
        await finishCalibration();
        return;
      }
      
      // جمع بيانات بيئية
      final envData = await EnvironmentalDataCollector.collect();
      
      // إرسال للـ backend
      await BLVApiClient.submitCalibrationSample(
        branchId: widget.branchId,
        data: envData
      );
      
      setState(() => samplesCollected++);
    });
  }
  
  Future<void> finishCalibration() async {
    // حساب الـ baseline
    await BLVApiClient.calculateBaseline(widget.branchId);
    
    Navigator.pop(context);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('✅ Calibration Complete!'),
        content: Text('الفرع جاهز لاستقبال الموظفين'),
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Branch Calibration')),
      body: Center(
        child: Column(
          children: [
            Text('🚶 تجول في الفرع لمدة 10 دقائق'),
            SizedBox(height: 20),
            CircularProgressIndicator(
              value: samplesCollected / targetSamples,
            ),
            Text('$samplesCollected / $targetSamples samples'),
            SizedBox(height: 40),
            if (!isCalibrating)
              ElevatedButton(
                onPressed: startCalibration,
                child: Text('Start Calibration'),
              ),
          ],
        ),
      ),
    );
  }
}
```

---

## 🎯 الفرق بين الطريقة القديمة والجديدة

| البند | الطريقة القديمة | الطريقة الجديدة (BLV) |
|-------|-----------------|----------------------|
| **البيانات المطلوبة** | WiFi BSSID + GPS | WiFi + GPS + Environmental Baseline |
| **الوقت** | 2 دقيقة | 15 دقيقة (مرة واحدة فقط) |
| **الدقة** | 60-80% | 85-95% |
| **iOS** | BSSID غير متاح | يعمل مع QR fallback |
| **التكلفة** | 0 | 0 (طباعة QR فقط) |
| **الصيانة** | يدوي | تلقائي (drift detection) |

---

## ✅ Checklist للأونر

عند إضافة فرع جديد:

- [ ] ادخل اسم الفرع والمدير
- [ ] حدد الموقع على الخريطة (GPS)
- [ ] اضبط نصف القطر (100-200 متر)
- [ ] اترك النظام يكتشف WiFi تلقائياً
- [ ] قم بجولة 10-15 دقيقة في الفرع (Calibration)
- [ ] اطبع QR Code وعلّقه عند المدخل
- [ ] ✅ الفرع جاهز!

**الوقت الإجمالي:** 15-20 دقيقة (مرة واحدة فقط)

---

## 🔄 Recalibration (إعادة المعايرة)

متى نحتاج إعادة معايرة؟

1. **تغيير الراوتر** → النظام يكتشف drift تلقائياً
2. **تجديد الفرع** → Manager يضغط "Recalibrate"
3. **Confidence < 50%** → النظام ينبه تلقائياً
4. **False positives كثيرة** → HR يطلب recalibration

الإجراء: نفس خطوات Calibration (10-15 دقيقة)
