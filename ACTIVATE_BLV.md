# 🚀 BLV System Activation Guide

## ⏰ Timeline (بعد 14 يوم من اليوم)
**تاريخ التفعيل المقترح:** 21 نوفمبر 2025

---

## 📝 Step 1: Calculate Baselines (بعد 14 يوم بالظبط)

### من PowerShell:
```powershell
Invoke-RestMethod -Uri "http://16.171.208.249:5000/api/baselines/calculate" -Method POST -Headers @{"Content-Type"="application/json"} -Body '{"daysBack": 14}'
```

### من Terminal/CMD:
```bash
curl -X POST http://16.171.208.249:5000/api/baselines/calculate \
  -H "Content-Type: application/json" \
  -d "{\"daysBack\": 14}"
```

---

## ✅ Step 2: Verify Baselines

### في Neon Console:
```sql
-- تأكد إن الـ baselines اتحسبت
SELECT 
  b.name as branch_name,
  beb.time_slot,
  beb.avg_wifi_count,
  beb.avg_battery_level,
  beb.confidence,
  beb.sample_count
FROM branch_environment_baselines beb
JOIN branches b ON b.id = beb.branch_id
ORDER BY b.name, beb.time_slot;

-- المفروض تلاقي على الأقل 3 صفوف لكل فرع (morning, afternoon, evening)
-- Confidence لازم > 0.7
-- Sample count لازم > 100
```

---

## 📊 Step 3: Monitor Performance (أسبوعين)

### يومياً راقب الأداء:
```sql
-- System Health
SELECT * FROM v_blv_system_health 
ORDER BY date DESC 
LIMIT 7;

-- Success Rate لازم > 85%
```

### راجع الـ Flags:
```sql
-- Flagged Employees
SELECT * FROM v_top_flagged_employees;

-- لو فيه موظف معاه flags كتير، اتحقق منه يدوياً
```

---

## 🎯 Step 4: Activate Full BLV (بعد شهر - 5 ديسمبر 2025)

### لو Success Rate > 85% لمدة أسبوعين متتاليين:

1. **Update Server Config:**
   Edit `server/index.ts` and add at the top:
   ```typescript
   // BLV Configuration (after line 20)
   const BLV_STRICT_MODE = true;  // Enable strict BLV validation
   const BLV_MIN_CONFIDENCE = 0.7; // Minimum baseline confidence
   ```

2. **Upload to EC2:**
   ```powershell
   scp -i "D:\mytest123.pem" "server\index.ts" ubuntu@16.171.208.249:~/oldies-server/server/
   ssh -i "D:\mytest123.pem" ubuntu@16.171.208.249 "pm2 restart oldies-server"
   ```

3. **Announce to Staff:**
   - أخبر الموظفين إن النظام الجديد فعّال
   - اشرح إنهم لازم يبقوا في الفرع عشان BLV يشتغل
   - وضح إن النظام بيكشف التلاعب

---

## 🔍 Monitoring Queries

### Daily Health Check:
```sql
-- Today's BLV Performance
SELECT 
  DATE(created_at) as date,
  COUNT(*) FILTER (WHERE verification_method = 'BLV') as blv_count,
  COUNT(*) FILTER (WHERE verification_method = 'WiFi') as wifi_count,
  COUNT(*) FILTER (WHERE verification_method = 'GPS') as gps_count,
  AVG(presence_score) as avg_presence,
  AVG(trust_score) as avg_trust
FROM pulses
WHERE created_at >= CURRENT_DATE
GROUP BY DATE(created_at);
```

### Weekly Summary:
```sql
-- Last 7 Days Performance
SELECT * FROM v_blv_system_health 
WHERE date >= CURRENT_DATE - INTERVAL '7 days'
ORDER BY date DESC;
```

### Device Trust:
```sql
-- Suspicious Devices
SELECT * FROM v_device_trust_scores
WHERE reliability_index < 0.5 OR flag_rate_percent > 30
ORDER BY reliability_index ASC;
```

---

## ⚠️ Troubleshooting

### If Success Rate < 85%:
1. Check baseline confidence: `SELECT * FROM v_baseline_freshness;`
2. If confidence < 0.7: Recalculate baselines
3. Check for environment changes (new WiFi, renovations, etc.)
4. Review flagged employees manually

### If Many False Positives:
1. Adjust thresholds in BLV config (lower to 0.6/0.5)
2. Check if branch environment changed
3. Recalculate baselines for affected branch

### If BLV Not Working:
1. Check server logs: `ssh -i "D:\mytest123.pem" ubuntu@16.171.208.249 "pm2 logs oldies-server --lines 50"`
2. Verify pulses have sensor data: `SELECT COUNT(*) FROM pulses WHERE wifi_count IS NOT NULL;`
3. Check Flutter app is sending BLV data

---

## 📞 Support

For issues, check:
- Server logs: `pm2 logs oldies-server`
- Database queries above
- Error flags in manager dashboard

---

**Good Luck! 🎉**
النظام جاهز - بس استنى 14 يوم وابدأ المراحل دي بالترتيب.
