#!/bin/bash

# ============================================================================
# Deploy Calculate Payroll Edge Function
# ============================================================================
# This script deploys the calculate-payroll Edge Function to Supabase
# and optionally sets up scheduled execution using pg_cron
#
# Usage:
#   ./deploy.sh                    # Deploy function only
#   ./deploy.sh --with-schedule    # Deploy and setup pg_cron schedule
#
# Prerequisites:
#   - Supabase CLI installed (npm install -g supabase)
#   - Logged in to Supabase CLI (supabase login)
#   - Project linked (supabase link --project-ref YOUR_REF)
# ============================================================================

set -e  # Exit on error

echo "🚀 Deploying Calculate Payroll Edge Function..."
echo ""

# Check if Supabase CLI is installed
if ! command -v supabase &> /dev/null; then
    echo "❌ Error: Supabase CLI is not installed"
    echo "Install with: npm install -g supabase"
    exit 1
fi

# Check if logged in
if ! supabase projects list &> /dev/null; then
    echo "❌ Error: Not logged in to Supabase CLI"
    echo "Run: supabase login"
    exit 1
fi

# Deploy the function
echo "📦 Deploying calculate-payroll function..."
supabase functions deploy calculate-payroll

if [ $? -eq 0 ]; then
    echo "✅ Function deployed successfully!"
else
    echo "❌ Function deployment failed"
    exit 1
fi

echo ""
echo "📋 Next steps:"
echo ""
echo "1. Test the function manually:"
echo "   curl -X POST 'https://YOUR_PROJECT.supabase.co/functions/v1/calculate-payroll' \\"
echo "     -H 'Authorization: Bearer YOUR_ANON_KEY' \\"
echo "     -H 'Content-Type: application/json'"
echo ""

# Check if --with-schedule flag is provided
if [ "$1" == "--with-schedule" ]; then
    echo "⏰ Setting up pg_cron schedule..."
    echo ""
    echo "Please run the following SQL in your Supabase SQL Editor:"
    echo ""
    cat ../../../migrations/setup_payroll_schedule.sql
    echo ""
else
    echo "2. To set up automatic scheduling, run:"
    echo "   ./deploy.sh --with-schedule"
    echo ""
    echo "   Or manually execute: migrations/setup_payroll_schedule.sql"
    echo ""
fi

echo "3. Monitor function logs:"
echo "   supabase functions logs calculate-payroll --follow"
echo ""
echo "✨ Deployment complete!"
