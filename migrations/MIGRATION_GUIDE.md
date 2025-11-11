# 🚀 Database Migration Guide

## Step 1: Run BLV Enhancements Migration

### في Neon Console:

1. افتح [Neon Console](https://console.neon.tech)
2. اختر الـ Database
3. اضغط على **SQL Editor**
4. افتح الملف: `migrations/add_blv_enhancements.sql`
5. Copy كل المحتوى والصقه في SQL Editor
6. اضغط **Run**

### أو عبر psql:

```bash
psql $DATABASE_URL -f migrations/add_blv_enhancements.sql
```

---

## Step 2: Verify Migration

### تحقق من الـ Tables الجديدة:

```sql
-- Check new tables exist
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
  AND table_name IN (
    'drift_alerts',
    'device_fingerprints', 
    'blv_health_logs'
  );

-- Should return 3 rows
```

### تحقق من الـ Indexes:

```sql
-- Check indexes created
SELECT indexname 
FROM pg_indexes 
WHERE tablename IN ('pulses', 'pulse_flags', 'wifi_signals', 'drift_alerts')
ORDER BY tablename, indexname;

-- Should show multiple indexes
```

### تحقق من الـ Views:

```sql
-- Check analytics views
SELECT table_name 
FROM information_schema.views 
WHERE table_schema = 'public' 
  AND table_name LIKE 'v_%';

-- Should return:
-- v_blv_system_health
-- v_top_flagged_employees
-- v_device_trust_scores
-- v_baseline_freshness
```

---

## Step 3: Test Analytics Views

### System Health:

```sql
SELECT * FROM v_blv_system_health 
ORDER BY date DESC 
LIMIT 7;
```

### Baseline Freshness:

```sql
SELECT * FROM v_baseline_freshness;
```

### Device Trust:

```sql
SELECT * FROM v_device_trust_scores 
ORDER BY reliability_index ASC 
LIMIT 10;
```

---

## ✅ Migration Complete!

If all queries return successfully, the migration is done! 🎉

Next steps:
1. Start the backend server
2. Deploy Flutter app
3. Begin Learning Mode (Phase 1)
