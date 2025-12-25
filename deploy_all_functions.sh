#!/bin/bash

# ============================================================================
# Deploy All Supabase Edge Functions
# ============================================================================
# This script deploys all Edge Functions to Supabase
#
# Prerequisites:
#   - Supabase CLI installed (npm install -g supabase)
#   - Logged in to Supabase CLI (supabase login)
#   - Project linked (supabase link --project-ref YOUR_REF)
# ============================================================================

set -e  # Exit on error

echo "🚀 Deploying All Supabase Edge Functions..."
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

# List of functions to deploy
FUNCTIONS=(
    "attendance-check-in"
    "attendance-check-out"
    "sync-pulses"
    "employee-break"
    "branch-requests"
    "branch-request-action"
    "branch-attendance-report"
    "branch-pulse-summary"
    "calculate-payroll"
    "delete-employee"
)

# Deploy each function
SUCCESS_COUNT=0
FAILED_COUNT=0

for func in "${FUNCTIONS[@]}"; do
    echo "📦 Deploying $func..."
    
    if supabase functions deploy "$func" --no-verify-jwt; then
        echo "   ✅ $func deployed successfully!"
        ((SUCCESS_COUNT++))
    else
        echo "   ❌ $func deployment failed"
        ((FAILED_COUNT++))
    fi
    echo ""
done

# Summary
echo "=========================================="
echo "📊 Deployment Summary:"
echo "   ✅ Success: $SUCCESS_COUNT"
echo "   ❌ Failed: $FAILED_COUNT"
echo "=========================================="
echo ""

if [ $FAILED_COUNT -eq 0 ]; then
    echo "🎉 All functions deployed successfully!"
    echo ""
    echo "📋 Next steps:"
    echo "1. Test the functions from Supabase Dashboard"
    echo "2. Check Edge Functions logs for any errors"
    echo "3. Verify environment variables are set correctly"
else
    echo "⚠️ Some functions failed to deploy. Check the errors above."
    exit 1
fi

