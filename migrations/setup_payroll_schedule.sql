-- ============================================================================
-- Setup Payroll Calculation Schedule with pg_cron
-- ============================================================================
-- This script sets up automatic scheduled execution of the calculate-payroll
-- Edge Function using PostgreSQL's pg_cron extension.
--
-- Schedule: Every 15 days at 2:00 AM (configurable below)
-- Function: calculate-payroll Edge Function
--
-- Prerequisites:
--   1. calculate-payroll Edge Function must be deployed
--   2. pg_cron extension must be enabled (usually enabled by default in Supabase)
--
-- Author: Claude Code
-- Date: 2025-11-09
-- Task: 10.5 - Deploy and Schedule Payroll Calculation Edge Function
-- ============================================================================

-- ============================================================================
-- CONFIGURATION - UPDATE THESE VALUES
-- ============================================================================

-- Your Supabase project URL
-- Example: https://abcdefghijklmnop.supabase.co
\set SUPABASE_URL 'YOUR_SUPABASE_PROJECT_URL'

-- Your Supabase service role key (keep this secret!)
-- Find it in: Project Settings > API > service_role key
\set SERVICE_ROLE_KEY 'YOUR_SERVICE_ROLE_KEY'

-- ============================================================================
-- Step 1: Enable pg_cron Extension
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Grant usage to postgres user (if needed)
GRANT USAGE ON SCHEMA cron TO postgres;

-- ============================================================================
-- Step 2: Create Payroll Calculation Job
-- ============================================================================

-- Remove existing job if it exists
SELECT cron.unschedule('calculate-payroll-biweekly') WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'calculate-payroll-biweekly'
);

-- Schedule payroll calculation every 15 days at 2:00 AM
-- Cron format: minute hour day-of-month month day-of-week
-- '0 2 */15 * *' = At 02:00 on every 15th day
SELECT cron.schedule(
  'calculate-payroll-biweekly',     -- Job name
  '0 2 */15 * *',                   -- Cron schedule: Every 15 days at 2 AM
  $$
  SELECT
    net.http_post(
      url := :'SUPABASE_URL' || '/functions/v1/calculate-payroll',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || :'SERVICE_ROLE_KEY'
      ),
      body := '{}'::jsonb
    ) as request_id;
  $$
);

-- ============================================================================
-- Alternative Schedules (comment/uncomment as needed)
-- ============================================================================

-- Option 1: Monthly on the 1st and 16th at 2 AM
-- SELECT cron.schedule(
--   'calculate-payroll-biweekly',
--   '0 2 1,16 * *',
--   $$ [same body as above] $$
-- );

-- Option 2: Every Monday at 3 AM (weekly)
-- SELECT cron.schedule(
--   'calculate-payroll-weekly',
--   '0 3 * * 1',
--   $$ [same body as above] $$
-- );

-- Option 3: First day of every month at 1 AM
-- SELECT cron.schedule(
--   'calculate-payroll-monthly',
--   '0 1 1 * *',
--   $$ [same body as above] $$
-- );

-- ============================================================================
-- Step 3: Create Manual Trigger Function (Optional)
-- ============================================================================

-- This allows you to manually trigger payroll calculation from SQL
CREATE OR REPLACE FUNCTION trigger_payroll_calculation(
  p_period_start DATE DEFAULT NULL,
  p_period_end DATE DEFAULT NULL,
  p_employee_id TEXT DEFAULT NULL,
  p_branch_id TEXT DEFAULT NULL,
  p_auto_approve BOOLEAN DEFAULT FALSE
)
RETURNS TEXT AS $$
DECLARE
  v_url TEXT := :'SUPABASE_URL' || '/functions/v1/calculate-payroll';
  v_headers JSONB;
  v_body JSONB;
  v_response TEXT;
BEGIN
  -- Build headers
  v_headers := jsonb_build_object(
    'Content-Type', 'application/json',
    'Authorization', 'Bearer ' || :'SERVICE_ROLE_KEY'
  );

  -- Build request body
  v_body := jsonb_build_object(
    'period_start', p_period_start,
    'period_end', p_period_end,
    'employee_id', p_employee_id,
    'branch_id', p_branch_id,
    'auto_approve', p_auto_approve
  );

  -- Make HTTP request
  SELECT net.http_post(
    url := v_url,
    headers := v_headers,
    body := v_body
  ) INTO v_response;

  RETURN 'Payroll calculation triggered: ' || v_response;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION trigger_payroll_calculation TO authenticated;

-- ============================================================================
-- Step 4: View Scheduled Jobs
-- ============================================================================

-- View all cron jobs
SELECT
  jobid,
  jobname,
  schedule,
  active,
  command
FROM cron.job;

-- View job run history
SELECT
  jobid,
  runid,
  job_pid,
  database,
  username,
  command,
  status,
  return_message,
  start_time,
  end_time
FROM cron.job_run_details
ORDER BY start_time DESC
LIMIT 20;

-- ============================================================================
-- Step 5: Success Message and Usage Instructions
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '✅ Payroll schedule setup complete!';
  RAISE NOTICE '';
  RAISE NOTICE '📅 Schedule: Every 15 days at 2:00 AM';
  RAISE NOTICE '🔧 Job name: calculate-payroll-biweekly';
  RAISE NOTICE '';
  RAISE NOTICE '📋 Useful commands:';
  RAISE NOTICE '   • View jobs: SELECT * FROM cron.job;';
  RAISE NOTICE '   • View history: SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 10;';
  RAISE NOTICE '   • Unschedule: SELECT cron.unschedule(''calculate-payroll-biweekly'');';
  RAISE NOTICE '';
  RAISE NOTICE '💡 Manual trigger:';
  RAISE NOTICE '   SELECT trigger_payroll_calculation();';
  RAISE NOTICE '   SELECT trigger_payroll_calculation(''2025-01-01'', ''2025-01-15'');';
  RAISE NOTICE '';
  RAISE NOTICE '⚠️  IMPORTANT: Update SUPABASE_URL and SERVICE_ROLE_KEY above before running!';
END $$;

-- ============================================================================
-- Cleanup Commands (for reference - DO NOT RUN unless you want to remove)
-- ============================================================================

-- To unschedule the job:
-- SELECT cron.unschedule('calculate-payroll-biweekly');

-- To drop the manual trigger function:
-- DROP FUNCTION IF EXISTS trigger_payroll_calculation;

-- To disable pg_cron (not recommended):
-- DROP EXTENSION pg_cron;
