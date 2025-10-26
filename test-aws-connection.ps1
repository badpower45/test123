# 🧪 Test AWS EC2 Server Connection
# Run this from your Windows machine (PowerShell)

$EC2_IP = "16.171.208.249"
$BASE_URL = "http://$EC2_IP:5000"

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "🧪 Testing Oldies Workers API on AWS EC2" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Server: $BASE_URL" -ForegroundColor Yellow
Write-Host ""

# Test 1: Health Check
Write-Host "Test 1: Health Check Endpoint" -ForegroundColor Green
Write-Host "-------------------------------"
try {
    $health = Invoke-RestMethod -Uri "$BASE_URL/health" -TimeoutSec 10
    Write-Host "✅ SUCCESS" -ForegroundColor Green
    Write-Host "Response:" -ForegroundColor White
    $health | ConvertTo-Json
} catch {
    Write-Host "❌ FAILED" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
}
Write-Host ""

# Test 2: Login with Default Employee
Write-Host "Test 2: Login API (EMP001 / 1234)" -ForegroundColor Green
Write-Host "-----------------------------------"
try {
    $loginBody = @{
        employee_id = "EMP001"
        pin = "1234"
    } | ConvertTo-Json

    $loginResponse = Invoke-RestMethod -Uri "$BASE_URL/api/auth/login" -Method Post -Body $loginBody -ContentType "application/json" -TimeoutSec 10
    Write-Host "✅ SUCCESS" -ForegroundColor Green
    Write-Host "Response:" -ForegroundColor White
    $loginResponse | ConvertTo-Json -Depth 3
} catch {
    Write-Host "❌ FAILED" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "This usually means:" -ForegroundColor Yellow
    Write-Host "  1. Database not seeded (run: curl http://$EC2_IP:5000/api/dev/seed)" -ForegroundColor Yellow
    Write-Host "  2. Database connection issue" -ForegroundColor Yellow
}
Write-Host ""

# Test 3: Seed Database
Write-Host "Test 3: Seed Database (Optional)" -ForegroundColor Green
Write-Host "----------------------------------"
$seed = Read-Host "Do you want to seed the database? (y/n)"
if ($seed -eq "y") {
    try {
        $seedResponse = Invoke-RestMethod -Uri "$BASE_URL/api/dev/seed" -TimeoutSec 30
        Write-Host "✅ SUCCESS" -ForegroundColor Green
        Write-Host "Response:" -ForegroundColor White
        $seedResponse | ConvertTo-Json -Depth 3
    } catch {
        Write-Host "❌ FAILED" -ForegroundColor Red
        Write-Host "Error: $_" -ForegroundColor Red
    }
} else {
    Write-Host "⏭️  Skipped" -ForegroundColor Yellow
}
Write-Host ""

# Test 4: Login with Manager
Write-Host "Test 4: Login API (MGR_MAADI / 8888)" -ForegroundColor Green
Write-Host "--------------------------------------"
try {
    $mgrLoginBody = @{
        employee_id = "MGR_MAADI"
        pin = "8888"
    } | ConvertTo-Json

    $mgrLoginResponse = Invoke-RestMethod -Uri "$BASE_URL/api/auth/login" -Method Post -Body $mgrLoginBody -ContentType "application/json" -TimeoutSec 10
    Write-Host "✅ SUCCESS" -ForegroundColor Green
    Write-Host "Response:" -ForegroundColor White
    $mgrLoginResponse | ConvertTo-Json -Depth 3
} catch {
    Write-Host "❌ FAILED" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
}
Write-Host ""

# Test 5: Login with Owner
Write-Host "Test 5: Login API (OWNER001 / 1234)" -ForegroundColor Green
Write-Host "-------------------------------------"
try {
    $ownerLoginBody = @{
        employee_id = "OWNER001"
        pin = "1234"
    } | ConvertTo-Json

    $ownerLoginResponse = Invoke-RestMethod -Uri "$BASE_URL/api/auth/login" -Method Post -Body $ownerLoginBody -ContentType "application/json" -TimeoutSec 10
    Write-Host "✅ SUCCESS" -ForegroundColor Green
    Write-Host "Response:" -ForegroundColor White
    $ownerLoginResponse | ConvertTo-Json -Depth 3
} catch {
    Write-Host "❌ FAILED" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
}
Write-Host ""

# Summary
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "✅ Testing Complete" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Update Flutter app API endpoint to: http://$EC2_IP:5000/api" -ForegroundColor White
Write-Host "  2. Test from Flutter app" -ForegroundColor White
Write-Host ""
Write-Host "Useful Commands:" -ForegroundColor Yellow
Write-Host "  - View PM2 logs: ssh ubuntu@$EC2_IP 'pm2 logs oldies-api'" -ForegroundColor White
Write-Host "  - Restart server: ssh ubuntu@$EC2_IP 'pm2 restart oldies-api'" -ForegroundColor White
Write-Host ""
