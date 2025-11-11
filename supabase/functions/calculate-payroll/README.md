# Calculate Payroll Edge Function

Automated payroll calculation based on BLV-verified working hours.

## Features

- **Automated Calculation**: Calculates payroll for all employees in a given period
- **BLV Integration**: Uses BLV-verified hours (deducts time out of valid zone)
- **Smart Deductions**: Automatically applies salary advances and other deductions
- **Audit Trail**: Maintains detailed calculation breakdown for transparency
- **Idempotent**: Can be run multiple times safely (updates existing records)
- **Flexible**: Supports filtering by employee, branch, or pay period

## How It Works

1. **Fetch Attendance**: Retrieves all completed attendance records for the period
2. **Calculate Hours**:
   - Total hours = checkout time - checkin time
   - BLV verified hours = total hours - (pause_duration_minutes / 60)
3. **Get Hourly Rate**: Uses employee.hourly_rate or calculates from monthly_salary
4. **Calculate Gross Pay**: blv_verified_hours * hourly_rate
5. **Apply Deductions**:
   - Salary advances (approved, not yet deducted)
   - Other deductions for the period
   - Absence penalties (if configured)
   - Late arrival penalties (if configured)
6. **Persist to Database**: Creates or updates payroll records with full audit trail

## Usage

### Manual Invocation

```bash
# Calculate payroll for default period (last 15 days)
curl -X POST 'https://YOUR_PROJECT.supabase.co/functions/v1/calculate-payroll' \
  -H 'Authorization: Bearer YOUR_ANON_KEY' \
  -H 'Content-Type: application/json'

# Calculate for specific period
curl -X POST 'https://YOUR_PROJECT.supabase.co/functions/v1/calculate-payroll' \
  -H 'Authorization: Bearer YOUR_ANON_KEY' \
  -H 'Content-Type: application/json' \
  -d '{
    "period_start": "2025-01-01",
    "period_end": "2025-01-15"
  }'

# Calculate for specific employee
curl -X POST 'https://YOUR_PROJECT.supabase.co/functions/v1/calculate-payroll' \
  -H 'Authorization: Bearer YOUR_ANON_KEY' \
  -H 'Content-Type: application/json' \
  -d '{
    "employee_id": "emp123",
    "period_start": "2025-01-01",
    "period_end": "2025-01-31"
  }'

# Calculate and auto-approve
curl -X POST 'https://YOUR_PROJECT.supabase.co/functions/v1/calculate-payroll' \
  -H 'Authorization: Bearer YOUR_ANON_KEY' \
  -H 'Content-Type: application/json' \
  -d '{
    "period_start": "2025-01-01",
    "period_end": "2025-01-15",
    "auto_approve": true
  }'
```

### Request Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `period_start` | string (YYYY-MM-DD) | No | Start date of pay period (defaults to 15 days ago) |
| `period_end` | string (YYYY-MM-DD) | No | End date of pay period (defaults to yesterday) |
| `employee_id` | string | No | Calculate for specific employee only |
| `branch_id` | string | No | Calculate for specific branch only |
| `auto_approve` | boolean | No | Automatically approve calculated payroll (default: false) |

### Response Format

```json
{
  "success": true,
  "period": {
    "start": "2025-01-01",
    "end": "2025-01-15"
  },
  "summary": {
    "employees_processed": 25,
    "payroll_records_created": 20,
    "payroll_records_updated": 5,
    "total_gross_pay": 45000.00,
    "total_deductions": 5000.00,
    "total_net_pay": 40000.00
  },
  "records": [
    {
      "employee_id": "emp123",
      "employee_name": "John Doe",
      "blv_verified_hours": 120.5,
      "gross_pay": 1800.00,
      "net_pay": 1500.00,
      "action": "created",
      "id": "payroll-uuid"
    }
  ],
  "errors": []
}
```

## Deployment

### Step 1: Deploy the Function

```bash
# Login to Supabase CLI
supabase login

# Link to your project
supabase link --project-ref YOUR_PROJECT_REF

# Deploy the function
supabase functions deploy calculate-payroll
```

### Step 2: Set Environment Variables

The function requires these environment variables (automatically set in Supabase):
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`

### Step 3: Schedule with pg_cron

Run this SQL in your Supabase SQL editor to schedule automatic payroll calculation:

```sql
-- Enable pg_cron extension
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Schedule payroll calculation every 15 days at 2 AM
SELECT cron.schedule(
  'calculate-payroll-biweekly',
  '0 2 */15 * *', -- Every 15 days at 2:00 AM
  $$
  SELECT
    net.http_post(
      url:='https://YOUR_PROJECT.supabase.co/functions/v1/calculate-payroll',
      headers:='{"Content-Type": "application/json", "Authorization": "Bearer YOUR_SERVICE_ROLE_KEY"}'::jsonb,
      body:='{}'::jsonb
    ) as request_id;
  $$
);

-- View scheduled jobs
SELECT * FROM cron.job;

-- Unschedule if needed
SELECT cron.unschedule('calculate-payroll-biweekly');
```

### Alternative: Schedule with Supabase Database Webhooks

1. Go to Database > Webhooks in Supabase Dashboard
2. Create a new webhook:
   - **Name**: Calculate Payroll
   - **Table**: attendance (or any table)
   - **Events**: INSERT
   - **Type**: Supabase Edge Function
   - **Function**: calculate-payroll
   - **HTTP Method**: POST

## Database Requirements

This function requires the following tables:
- `attendance` - with fields: check_in_time, check_out_time, work_hours, pause_duration_minutes, blv_verified_hours
- `employees` - with fields: id, full_name, hourly_rate, monthly_salary, branch_id
- `advances` - with fields: employee_id, amount, status, deducted_at
- `deductions` - with fields: employee_id, amount, deduction_date
- `payroll` - destination table for calculated payroll
- `payroll_history` - audit trail for payroll changes

Run the migration: `migrations/add_payroll_system.sql`

## Monitoring

### Check Payroll Status

```sql
-- View all pending payroll (calculated but not approved)
SELECT * FROM v_payroll_summary
WHERE is_calculated = true AND is_approved = false
ORDER BY period_start DESC;

-- View payroll for specific period
SELECT * FROM v_payroll_summary
WHERE period_start = '2025-01-01'
  AND period_end = '2025-01-15';

-- Check audit trail
SELECT * FROM payroll_history
WHERE payroll_id = 'YOUR_PAYROLL_ID'
ORDER BY changed_at DESC;
```

### View Function Logs

```bash
# View real-time logs
supabase functions logs calculate-payroll --follow

# View recent logs
supabase functions logs calculate-payroll --limit 100
```

## Troubleshooting

### No records created

Check:
1. Are there completed attendance records (with check_out_time)?
2. Do employees have hourly_rate or monthly_salary set?
3. Is the date range correct?

### Incorrect calculations

- Review `calculation_details` field in payroll table for breakdown
- Check `pause_duration_minutes` in attendance records
- Verify `blv_verified_hours` is being calculated correctly

### Advances not deducted

- Ensure advances have `status = 'approved'`
- Check that `deducted_at` is NULL
- Verify `request_date` is before or on `period_end`

## Testing

```typescript
// Test with sample data
const testPayload = {
  period_start: '2025-01-01',
  period_end: '2025-01-15',
  employee_id: 'test-employee-id'
};

// Expected: Creates payroll record with accurate calculations
// Verify: calculation_details matches manual calculation
```

## Support

For issues or questions:
- Check function logs: `supabase functions logs calculate-payroll`
- Review database schema: `migrations/add_payroll_system.sql`
- Verify test strategy in PRD section 10

## Version History

- **v1.0.0** (2025-11-09): Initial release
  - Complete payroll calculation with BLV integration
  - Automatic deductions (advances, absences, late arrivals)
  - Audit trail and transparency features
