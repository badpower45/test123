#!/bin/bash

# ============================================================================
# Deploy ONLY sync-pulses with Time Reconciliation
# ============================================================================

echo ""
echo "🚀 Deploying sync-pulses with Time Reconciliation..."
echo ""

# Install Supabase CLI if not installed
if ! command -v supabase &> /dev/null; then
    echo "📥 Installing Supabase CLI..."
    npm install -g supabase
fi

# Login and link
echo "🔐 Login to Supabase..."
supabase login

echo "🔗 Linking project..."
supabase link --project-ref bbxuyuaemigrqsvsnxkj

# Deploy sync-pulses
echo ""
echo "📦 Deploying sync-pulses..."
if supabase functions deploy sync-pulses --no-verify-jwt; then
    echo ""
    echo "✅ SUCCESS! sync-pulses deployed with Time Reconciliation"
    echo ""
    echo "📊 Test it with your phone now:"
    echo "   1. Check-in normally"
    echo "   2. Wait 5 minutes (1 pulse)"
    echo "   3. Turn OFF phone for 15 minutes"
    echo "   4. Turn ON phone and wait for sync"
    echo "   5. Check database - session should auto-close at last pulse!"
    echo ""
else
    echo ""
    echo "❌ FAILED to deploy sync-pulses"
    exit 1
fi
