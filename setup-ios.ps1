# iOS Setup Script - تشغيل مرة واحدة فقط

Write-Host "🍎 Setting up iOS configuration..." -ForegroundColor Cyan

# 1. Update Bundle ID in project.pbxproj
$pbxprojPath = "ios\Runner.xcodeproj\project.pbxproj"
$content = Get-Content $pbxprojPath -Raw
$content = $content -replace 'com\.example\.heartbeat', 'com.oldies.attendance'
Set-Content $pbxprojPath $content
Write-Host "✅ Updated Bundle ID in project.pbxproj" -ForegroundColor Green

# 2. Update pubspec.yaml
$pubspecPath = "pubspec.yaml"
$pubspecContent = Get-Content $pubspecPath -Raw
if ($pubspecContent -notmatch 'version:') {
    Write-Host "⚠️  Adding version to pubspec.yaml" -ForegroundColor Yellow
    $pubspecContent = $pubspecContent -replace '(name: oldies_workers)', "`$1`nversion: 1.0.0+1"
    Set-Content $pubspecPath $pubspecContent
}
Write-Host "✅ Checked pubspec.yaml version" -ForegroundColor Green

# 3. Check Info.plist
$infoPlistPath = "ios\Runner\Info.plist"
if (Test-Path $infoPlistPath) {
    Write-Host "✅ Info.plist exists" -ForegroundColor Green
} else {
    Write-Host "❌ Info.plist not found!" -ForegroundColor Red
}

# 4. Create AppIcon placeholder
$appIconPath = "ios\Runner\Assets.xcassets\AppIcon.appiconset"
if (-not (Test-Path $appIconPath)) {
    New-Item -ItemType Directory -Path $appIconPath -Force | Out-Null
    Write-Host "✅ Created AppIcon.appiconset folder" -ForegroundColor Green
}

# 5. Summary
Write-Host "`n📋 Summary:" -ForegroundColor Cyan
Write-Host "  Bundle ID: com.oldies.attendance" -ForegroundColor White
Write-Host "  App Name: أولديزز وركرز (Oldies Workers)" -ForegroundColor White
Write-Host "  Version: 1.0.0+1" -ForegroundColor White

Write-Host "`n🎯 Next steps:" -ForegroundColor Yellow
Write-Host "  1. Sign up at https://codemagic.io" -ForegroundColor White
Write-Host "  2. Connect your GitHub repo" -ForegroundColor White
Write-Host "  3. Update codemagic.yaml with your email" -ForegroundColor White
Write-Host "  4. Push to GitHub and Codemagic will build automatically!" -ForegroundColor White
Write-Host "  5. See full guide in IOS_DEPLOYMENT_GUIDE.md" -ForegroundColor White

Write-Host "`n✨ Setup complete! Ready to deploy to iOS!" -ForegroundColor Green
