# 🚀 سكريبت سريع لتحديث السيرفر على AWS
# اركن هذا السكريبت من Windows PowerShell

$EC2_IP = "16.171.208.249"
$PEM_PATH = "D:\mytest123.pem"
$LOCAL_PROJECT = "D:\Coding\project important\test123 (7)\test123"
$REMOTE_PATH = "ubuntu@${EC2_IP}:~/oldies-server"

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "🚀 تحديث Oldies Workers على AWS EC2" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# الخطوة 1: نسخ الملفات المحدثة
Write-Host "الخطوة 1: نسخ server/index.ts..." -ForegroundColor Green
try {
    scp -i $PEM_PATH "$LOCAL_PROJECT\server\index.ts" "${REMOTE_PATH}/server/"
    Write-Host "✅ تم نسخ server/index.ts" -ForegroundColor Green
} catch {
    Write-Host "❌ فشل نسخ الملف: $_" -ForegroundColor Red
    exit 1
}
Write-Host ""

# الخطوة 2: بناء وإعادة تشغيل السيرفر
Write-Host "الخطوة 2: بناء وإعادة تشغيل السيرفر..." -ForegroundColor Green
try {
    $buildScript = @"
cd ~/oldies-server && \
npm install && \
npm run build && \
pm2 restart oldies-api && \
pm2 status
"@
    
    ssh -i $PEM_PATH "ubuntu@$EC2_IP" $buildScript
    Write-Host "✅ تم البناء والتشغيل" -ForegroundColor Green
} catch {
    Write-Host "❌ فشل البناء: $_" -ForegroundColor Red
    exit 1
}
Write-Host ""

# الخطوة 3: انتظار السيرفر
Write-Host "الخطوة 3: انتظار جاهزية السيرفر..." -ForegroundColor Green
Start-Sleep -Seconds 3
Write-Host ""

# الخطوة 4: Seed قاعدة البيانات
Write-Host "الخطوة 4: Seed قاعدة البيانات..." -ForegroundColor Green
try {
    $seedResponse = Invoke-RestMethod -Uri "http://$EC2_IP:5000/api/dev/seed" -TimeoutSec 30
    Write-Host "✅ نجح Seed" -ForegroundColor Green
    Write-Host "Response:" -ForegroundColor White
    $seedResponse | ConvertTo-Json -Depth 3
} catch {
    Write-Host "⚠️  قد تكون قاعدة البيانات معبأة مسبقاً" -ForegroundColor Yellow
    Write-Host "Error: $_" -ForegroundColor Yellow
}
Write-Host ""

# الخطوة 5: اختبار تسجيل الدخول
Write-Host "الخطوة 5: اختبار تسجيل الدخول..." -ForegroundColor Green

# اختبار موظف
Write-Host "  - اختبار موظف (EMP001)..." -ForegroundColor Cyan
try {
    $empBody = @{ employee_id = "EMP001"; pin = "1234" } | ConvertTo-Json
    $empResponse = Invoke-RestMethod -Uri "http://$EC2_IP:5000/api/auth/login" -Method Post -Body $empBody -ContentType "application/json" -TimeoutSec 10
    Write-Host "    ✅ نجح تسجيل دخول الموظف" -ForegroundColor Green
    Write-Host "    الاسم: $($empResponse.employee.fullName)" -ForegroundColor White
    Write-Host "    الدور: $($empResponse.employee.role)" -ForegroundColor White
} catch {
    Write-Host "    ❌ فشل تسجيل دخول الموظف: $_" -ForegroundColor Red
}

# اختبار مدير
Write-Host "  - اختبار مدير (MGR_MAADI)..." -ForegroundColor Cyan
try {
    $mgrBody = @{ employee_id = "MGR_MAADI"; pin = "8888" } | ConvertTo-Json
    $mgrResponse = Invoke-RestMethod -Uri "http://$EC2_IP:5000/api/auth/login" -Method Post -Body $mgrBody -ContentType "application/json" -TimeoutSec 10
    Write-Host "    ✅ نجح تسجيل دخول المدير" -ForegroundColor Green
    Write-Host "    الاسم: $($mgrResponse.employee.fullName)" -ForegroundColor White
    Write-Host "    الدور: $($mgrResponse.employee.role)" -ForegroundColor White
} catch {
    Write-Host "    ❌ فشل تسجيل دخول المدير: $_" -ForegroundColor Red
}

# اختبار مالك
Write-Host "  - اختبار مالك (OWNER001)..." -ForegroundColor Cyan
try {
    $ownerBody = @{ employee_id = "OWNER001"; pin = "1234" } | ConvertTo-Json
    $ownerResponse = Invoke-RestMethod -Uri "http://$EC2_IP:5000/api/auth/login" -Method Post -Body $ownerBody -ContentType "application/json" -TimeoutSec 10
    Write-Host "    ✅ نجح تسجيل دخول المالك" -ForegroundColor Green
    Write-Host "    الاسم: $($ownerResponse.employee.fullName)" -ForegroundColor White
    Write-Host "    الدور: $($ownerResponse.employee.role)" -ForegroundColor White
} catch {
    Write-Host "    ❌ فشل تسجيل دخول المالك: $_" -ForegroundColor Red
}
Write-Host ""

# النتيجة النهائية
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "✅ اكتمل التحديث!" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "الخطوات التالية:" -ForegroundColor Yellow
Write-Host "  1. جرب التطبيق من Flutter" -ForegroundColor White
Write-Host "  2. سجل دخول بـ EMP001 / 1234 (موظف)" -ForegroundColor White
Write-Host "  3. سجل دخول بـ MGR_MAADI / 8888 (مدير)" -ForegroundColor White
Write-Host "  4. سجل دخول بـ OWNER001 / 1234 (مالك)" -ForegroundColor White
Write-Host ""
Write-Host "للتحقق من logs السيرفر:" -ForegroundColor Yellow
Write-Host "  ssh -i '$PEM_PATH' ubuntu@$EC2_IP 'pm2 logs oldies-api'" -ForegroundColor White
Write-Host ""
