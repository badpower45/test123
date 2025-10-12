# Supabase Backend Setup for Oldies Workers

## Overview
This directory contains the complete Supabase backend implementation for the Oldies Workers employee attendance system.

## Directory Structure
```
supabase/
├── migrations/
│   ├── 001_initial_schema.sql       # Database tables and indexes
│   ├── 002_geofence_function.sql    # PostGIS geofencing logic
│   └── 003_rls_policies.sql         # Row Level Security policies
├── functions/
│   └── calculate-payroll/
│       └── index.ts                 # Payroll calculation edge function
└── README.md                        # This file
```

## Prerequisites
1. A Supabase project ([Create one](https://app.supabase.com))
2. Supabase CLI installed (`npm install -g supabase`)
3. PostgreSQL with PostGIS extension (included in Supabase)

## Setup Instructions

### 1. Initialize Supabase Project
```bash
# Link to your Supabase project
supabase link --project-ref your-project-ref

# Or initialize a new local project
supabase init
```

### 2. Apply Database Migrations
Run the migrations in order to set up your database schema:

```bash
# Apply all migrations
supabase db push

# Or apply them individually
psql -h db.your-project.supabase.co -U postgres -d postgres -f supabase/migrations/001_initial_schema.sql
psql -h db.your-project.supabase.co -U postgres -d postgres -f supabase/migrations/002_geofence_function.sql
psql -h db.your-project.supabase.co -U postgres -d postgres -f supabase/migrations/003_rls_policies.sql
```

### 3. Deploy Edge Function
```bash
# Deploy the payroll calculation function
supabase functions deploy calculate-payroll

# Set environment variables for the function (if needed)
supabase secrets set HOURLY_RATE=30
```

### 4. Configure Flutter App
Update your Flutter app's `lib/config/app_config.dart`:

```dart
static const String supabaseUrl = 'https://your-project.supabase.co';
static const String supabaseAnonKey = 'your-anon-key';
```

## Database Schema

### Tables

#### `profiles`
Extends auth.users with employee information
- `id`: UUID (references auth.users)
- `full_name`: Employee's full name
- `employee_id`: Unique employee identifier
- `role`: employee | admin | hr | monitor

#### `shifts`
Records work shifts
- `id`: UUID
- `user_id`: References profiles
- `check_in_time`: Timestamp of check-in
- `check_out_time`: Timestamp of check-out (nullable)
- `status`: active | completed | cancelled

#### `pulses`
Location pulses for attendance verification
- `id`: UUID
- `shift_id`: References shifts
- `location`: PostGIS geography point (lat, lon)
- `is_within_geofence`: Boolean (auto-calculated)
- `created_at`: Timestamp

## Geofencing System

### How It Works
1. Employee sends location pulse during their shift
2. Pulse is inserted into the `pulses` table
3. `on_pulse_insert` trigger fires automatically
4. `check_geofence()` function calculates distance from restaurant
5. `is_within_geofence` is set to TRUE if within 100m, FALSE otherwise

### Configuring Restaurant Location
Default location: 30.0444°N, 31.2357°E (Cairo)

To change the restaurant location, edit `002_geofence_function.sql`:

```sql
restaurant_location := ST_GeogFromText('POINT(new_longitude new_latitude)');
geofence_radius_meters NUMERIC := 100; -- Change radius here
```

Then reapply the migration:
```bash
psql -f supabase/migrations/002_geofence_function.sql
```

## Row Level Security (RLS)

### Policies Summary

#### Employees Can:
- View/update their own profile
- View/create their own shifts
- Create pulses for their own shifts
- View pulses from their own shifts

#### Admins Can:
- View all profiles, shifts, and pulses
- Update any profile or shift
- Manage employee data

### Testing RLS
```sql
-- Test as regular user
SELECT * FROM pulses; -- Returns only user's pulses

-- Test as admin
SELECT * FROM pulses; -- Returns all pulses
```

## Edge Functions

### calculate-payroll

Calculates employee pay based on valid location pulses.

#### Request
```json
{
  "user_id": "uuid",
  "start_date": "2025-01-01T00:00:00Z",
  "end_date": "2025-01-31T23:59:59Z",
  "hourly_rate": 30
}
```

#### Response
```json
{
  "user_id": "uuid",
  "employee_id": "EMP001",
  "full_name": "مريم حسن",
  "period": {
    "start": "2025-01-01T00:00:00Z",
    "end": "2025-01-31T23:59:59Z"
  },
  "total_shifts": 20,
  "total_valid_pulses": 4800,
  "total_work_hours": 160,
  "hourly_rate": 30,
  "total_pay": 4800.00,
  "shifts_detail": [...]
}
```

#### Calling the Function
```dart
// From Flutter app
final response = await Supabase.instance.client.functions.invoke(
  'calculate-payroll',
  body: {
    'user_id': userId,
    'start_date': '2025-01-01T00:00:00Z',
    'end_date': '2025-01-31T23:59:59Z',
    'hourly_rate': 30,
  },
);
```

```bash
# From curl
curl -X POST 'https://your-project.supabase.co/functions/v1/calculate-payroll' \
  -H "Authorization: Bearer your-anon-key" \
  -H "Content-Type: application/json" \
  -d '{"user_id":"uuid","start_date":"2025-01-01","end_date":"2025-01-31"}'
```

## Testing

### Sample Data
Insert test data:

```sql
-- Insert test employee
INSERT INTO profiles (id, full_name, employee_id, role)
VALUES (
  auth.uid(), -- Current user's ID
  'Test Employee',
  'EMP999',
  'employee'
);

-- Insert test shift
INSERT INTO shifts (user_id)
VALUES (auth.uid())
RETURNING id;

-- Insert test pulse (will auto-validate geofence)
INSERT INTO pulses (shift_id, location)
VALUES (
  'shift-uuid',
  ST_GeogFromText('POINT(31.2357 30.0444)') -- Inside geofence
);

-- Check if geofence worked
SELECT id, is_within_geofence FROM pulses;
```

### Verify Geofencing
```sql
-- Test pulse inside geofence (should be TRUE)
INSERT INTO pulses (shift_id, location)
VALUES ('shift-id', ST_GeogFromText('POINT(31.2357 30.0444)'));

-- Test pulse outside geofence (should be FALSE)
INSERT INTO pulses (shift_id, location)
VALUES ('shift-id', ST_GeogFromText('POINT(31.0 30.0)'));

-- Verify results
SELECT 
  id,
  ST_AsText(location::geometry) as location_text,
  is_within_geofence,
  ST_Distance(
    location,
    ST_GeogFromText('POINT(31.2357 30.0444)')
  ) as distance_meters
FROM pulses;
```

## Monitoring

### View Attendance Statistics
```sql
-- Employee attendance summary
SELECT 
  p.employee_id,
  p.full_name,
  COUNT(DISTINCT s.id) as total_shifts,
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
GROUP BY p.id, p.employee_id, p.full_name;
```

### Detect Suspicious Activity
```sql
-- Find pulses outside geofence
SELECT 
  p.employee_id,
  p.full_name,
  pu.created_at,
  ST_AsText(pu.location::geometry) as location,
  ST_Distance(
    pu.location,
    ST_GeogFromText('POINT(31.2357 30.0444)')
  ) as distance_from_restaurant
FROM pulses pu
JOIN shifts s ON s.id = pu.shift_id
JOIN profiles p ON p.id = s.user_id
WHERE pu.is_within_geofence = FALSE
ORDER BY pu.created_at DESC;
```

## Troubleshooting

### Common Issues

**1. PostGIS extension not enabled**
```sql
CREATE EXTENSION IF NOT EXISTS postgis;
```

**2. RLS blocking access**
```sql
-- Temporarily disable RLS for testing (NOT for production!)
ALTER TABLE pulses DISABLE ROW LEVEL SECURITY;
```

**3. Edge function timeout**
Increase timeout in `supabase/functions/calculate-payroll/index.ts`:
```typescript
// Add timeout configuration
const controller = new AbortController();
const timeoutId = setTimeout(() => controller.abort(), 30000); // 30 seconds
```

## Security Notes

1. **Never commit real API keys** to version control
2. **Use environment variables** for sensitive configuration
3. **Test RLS policies** thoroughly before production
4. **Rotate service role key** periodically
5. **Monitor edge function usage** to prevent abuse

## Next Steps

1. ✅ Set up Supabase project
2. ✅ Apply migrations
3. ✅ Deploy edge functions
4. ✅ Configure Flutter app
5. 🔲 Test with real devices
6. 🔲 Set up monitoring and alerts
7. 🔲 Configure backup strategies
8. 🔲 Implement analytics dashboard

## Support

For issues related to:
- Supabase platform: https://supabase.com/docs
- PostGIS queries: https://postgis.net/documentation/
- Edge Functions: https://supabase.com/docs/guides/functions

## License
This backend implementation is part of the Oldies Workers attendance system.
