# 🚀 Quick Start - BLV System

## ⚡ 5-Minute Setup

### 1️⃣ Backend Setup (2 minutes)

```powershell
# Navigate to server directory
cd server

# Install dependencies (if not done)
npm install

# Configure environment
# Edit server/.env with your DATABASE_URL

# Start server
npm run dev
```

**Expected output:**
```
✓ Server running on port 5000
✓ Database connected
✓ BLV endpoints ready
```

---

### 2️⃣ Flutter Setup (2 minutes)

```powershell
# Navigate to project root
cd ..

# Get dependencies (if not done)
flutter pub get

# Run app
flutter run
```

**Select your device:**
- Chrome (for web testing)
- Android Emulator
- iOS Simulator
- Physical device

---

### 3️⃣ Configure Notifications (Optional - 5 minutes)

#### Slack Webhook:
1. Go to https://api.slack.com/apps
2. Create New App → From scratch
3. Add **Incoming Webhooks**
4. Copy webhook URL
5. Paste in `server/.env`:
   ```env
   SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
   ```

#### Telegram Bot:
1. Talk to [@BotFather](https://t.me/BotFather) on Telegram
2. Send `/newbot`
3. Follow instructions
4. Copy token
5. Send a message to your bot
6. Visit: `https://api.telegram.org/bot<TOKEN>/getUpdates`
7. Copy chat_id
8. Paste in `server/.env`:
   ```env
   TELEGRAM_BOT_TOKEN=123456:ABC-DEF
   TELEGRAM_CHAT_ID=-100123456
   ```

---

### 4️⃣ Run Database Migration (1 minute)

#### In Neon Console:
1. Open [Neon Console](https://console.neon.tech)
2. Go to SQL Editor
3. Copy content from `migrations/add_blv_enhancements.sql`
4. Paste and Run

See `migrations/MIGRATION_GUIDE.md` for detailed steps.

---

## ✅ Verification

### Test Backend:
```bash
curl http://localhost:5000/api/health
# Should return: {"status":"ok"}
```

### Test BLV Endpoint:
```bash
curl http://localhost:5000/api/baselines
# Should return: [] or array of baselines
```

### Test Flutter App:
1. Login with test employee
2. Check if pulses are being sent
3. Manager: Check BLV Flags icon (should show badge)

---

## 🧪 Testing Phases

### Phase 1: Learning Mode (Start Now!)

**Duration:** 2 weeks

**Goal:** Collect environmental data

**Configuration:**
```sql
-- In blv_system_config table
UPDATE blv_system_config 
SET 
  is_active = true,
  enable_no_motion_flag = false,
  fallback_to_wifi_only = true
WHERE id = 1;
```

**Monitor:**
```sql
-- Check data collection
SELECT 
  DATE(created_at) as date,
  COUNT(*) as total_pulses,
  COUNT(*) FILTER (WHERE wifi_count IS NOT NULL) as with_blv_data,
  ROUND(100.0 * COUNT(*) FILTER (WHERE wifi_count IS NOT NULL) / COUNT(*), 2) as percentage
FROM pulses
WHERE created_at >= NOW() - INTERVAL '7 days'
GROUP BY DATE(created_at)
ORDER BY date DESC;
```

**Target:** > 95% of pulses with BLV data

---

### Phase 2: Hybrid Mode (After 2 weeks)

**Run baseline calculation:**
```bash
curl -X POST http://localhost:5000/api/baselines/calculate \
  -H "Content-Type: application/json" \
  -d '{"daysBack": 14}'
```

**Enable flags:**
```sql
UPDATE blv_system_config 
SET 
  enable_no_motion_flag = true,
  min_presence_score = 0.6,
  min_trust_score = 0.5
WHERE id = 1;
```

**Monitor agreement:**
```sql
SELECT * FROM v_blv_system_health 
WHERE date >= CURRENT_DATE - 7;
```

**Target:** BLV-WiFi agreement > 85%

---

### Phase 3: Full BLV (After 4 weeks)

**Switch to BLV primary:**
```sql
UPDATE blv_system_config 
SET 
  fallback_to_wifi_only = false,
  min_presence_score = 0.7,
  min_trust_score = 0.6
WHERE id = 1;
```

**Monitor system:**
```sql
-- Daily stats
SELECT * FROM v_blv_system_health 
ORDER BY date DESC LIMIT 30;

-- Flagged employees
SELECT * FROM v_top_flagged_employees;

-- Device trust
SELECT * FROM v_device_trust_scores 
WHERE reliability_index < 0.5;
```

---

## 🔧 Troubleshooting

### Backend not starting:
```powershell
# Check port is free
netstat -ano | findstr :5000

# Kill process if needed
taskkill /PID <PID> /F

# Restart
npm run dev
```

### Flutter build errors:
```powershell
# Clean build
flutter clean
flutter pub get
flutter run
```

### Database connection issues:
```powershell
# Test connection
psql $DATABASE_URL -c "SELECT NOW();"

# Check .env file has correct DATABASE_URL
```

### No BLV data in pulses:
```dart
// Check permissions in app
// Android: Manifest permissions for sensors
// iOS: Info.plist permissions for motion/mic
```

---

## 📚 Documentation

- **Testing Phases:** `BLV_TESTING_PHASES.md`
- **Enhancements:** `BLV_ENHANCEMENTS.md`
- **Branch Onboarding:** `BRANCH_ONBOARDING_GUIDE.md`
- **Fairness System:** `FAIRNESS_SYSTEM.md`
- **Migration Guide:** `migrations/MIGRATION_GUIDE.md`

---

## 📞 Next Steps

1. ✅ Start backend server
2. ✅ Run Flutter app
3. ✅ Login and test pulse submission
4. ✅ Run database migration
5. ✅ Start Learning Mode (Phase 1)
6. ⏳ Wait 2 weeks
7. ⏳ Calculate baselines
8. ⏳ Start Hybrid Mode (Phase 2)
9. ⏳ Monitor for 2 weeks
10. ⏳ Switch to Full BLV (Phase 3)

**Timeline:** 6-8 weeks from Learning to Full Production 🚀
