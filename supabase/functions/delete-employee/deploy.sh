#!/bin/bash

# ============================================================================
# Deploy Delete Employee Edge Function
# ============================================================================
# This script deploys the delete-employee Edge Function to Supabase
#
# Usage:
#   ./deploy.sh
#
# Prerequisites:
#   - Supabase CLI installed (npm install -g supabase)
#   - Logged in to Supabase CLI (supabase login)
#   - Project linked (supabase link --project-ref YOUR_REF)
# ============================================================================

set -e  # Exit on error

echo "🚀 Deploying Delete Employee Edge Function..."
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
echo "📦 Deploying delete-employee function..."
supabase functions deploy delete-employee --no-verify-jwt

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
echo "   curl -X DELETE 'https://YOUR_PROJECT.supabase.co/functions/v1/delete-employee?employee_id=EMP001' \\"
echo "     -H 'Authorization: Bearer YOUR_ANON_KEY' \\"
echo "     -H 'Content-Type: application/json'"
echo ""
echo "2. Monitor function logs:"
echo "   supabase functions logs delete-employee --follow"
echo ""
echo "✨ Deployment complete!"

