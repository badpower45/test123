# Deploy Session Validation Edge Function to Supabase (PowerShell)

Write-Host "🚀 Deploying Session Validation Edge Function..." -ForegroundColor Cyan
Write-Host ""

# Check if supabase CLI is installed
$supabaseCmd = Get-Command supabase -ErrorAction SilentlyContinue
if (-not $supabaseCmd) {
    Write-Host "❌ Supabase CLI not found!" -ForegroundColor Red
    Write-Host "📦 Install it: npm install -g supabase" -ForegroundColor Yellow
    exit 1
}

# Check if logged in
Write-Host "🔐 Checking Supabase login status..." -ForegroundColor Yellow
$loginCheck = supabase projects list 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Not logged in to Supabase!" -ForegroundColor Red
    Write-Host "🔑 Run: supabase login" -ForegroundColor Yellow
    exit 1
}

Write-Host "✅ Logged in successfully" -ForegroundColor Green
Write-Host ""

# Deploy the function
Write-Host "📤 Deploying session-validation-action function..." -ForegroundColor Cyan
supabase functions deploy session-validation-action

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "✅ Edge Function deployed successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "📋 Next steps:" -ForegroundColor Yellow
    Write-Host "1. Run the SQL script: create_session_validation_table.sql"
    Write-Host "2. Test the function on Supabase Dashboard"
    Write-Host "3. Deploy the Flutter app"
    Write-Host ""
    Write-Host "🎉 Session Validation System is ready!" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "❌ Deployment failed!" -ForegroundColor Red
    Write-Host "📝 Check the error messages above" -ForegroundColor Yellow
    exit 1
}
