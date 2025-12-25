#!/bin/bash
# Deploy Session Validation Edge Function to Supabase

echo "🚀 Deploying Session Validation Edge Function..."
echo ""

# Check if supabase CLI is installed
if ! command -v supabase &> /dev/null
then
    echo "❌ Supabase CLI not found!"
    echo "📦 Install it: npm install -g supabase"
    exit 1
fi

# Check if logged in
echo "🔐 Checking Supabase login status..."
if ! supabase projects list &> /dev/null
then
    echo "❌ Not logged in to Supabase!"
    echo "🔑 Run: supabase login"
    exit 1
fi

echo "✅ Logged in successfully"
echo ""

# Deploy the function
echo "📤 Deploying session-validation-action function..."
supabase functions deploy session-validation-action

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Edge Function deployed successfully!"
    echo ""
    echo "📋 Next steps:"
    echo "1. Run the SQL script: create_session_validation_table.sql"
    echo "2. Test the function on Supabase Dashboard"
    echo "3. Deploy the Flutter app"
    echo ""
    echo "🎉 Session Validation System is ready!"
else
    echo ""
    echo "❌ Deployment failed!"
    echo "📝 Check the error messages above"
    exit 1
fi
