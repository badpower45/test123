# 🍎 دليل رفع التطبيق على Apple Store بدون Mac

## الطريقة المختارة: Codemagic (الأسهل والأسرع) ⭐

### الخطوات:

## 1️⃣ التسجيل في Apple Developer Program
- اذهب إلى: https://developer.apple.com
- سجل كمطور (تكلفة: $99/سنة)
- ستحتاج:
  - Apple ID
  - بطاقة ائتمان
  - انتظر 24-48 ساعة للموافقة

## 2️⃣ إنشاء App على App Store Connect
1. اذهب إلى: https://appstoreconnect.apple.com
2. My Apps → ➕ New App
3. املأ البيانات:
   - **Platform**: iOS
   - **Name**: أولديزز وركرز (Oldies Workers)
   - **Primary Language**: Arabic
   - **Bundle ID**: `com.oldies.attendance.full`
   - **SKU**: يمكن أن يكون: `oldies-workers-001`
   - **User Access**: Full Access

## 3️⃣ التسجيل في Codemagic
1. اذهب إلى: https://codemagic.io
2. Sign up with GitHub
3. ربط الريبو: `badpower45/test123`

## 4️⃣ إعداد iOS Certificates & Provisioning Profiles

### طريقة آلية (الأسهل):
1. في Codemagic Dashboard
2. Teams → Your team → Integrations
3. App Store Connect → Enable
4. اضغط **Connect**
5. سجل دخول بـ Apple ID
6. Codemagic سيعمل كل شيء تلقائياً! ✨

### طريقة يدوية (إذا احتجت):
```bash
# على أي جهاز Mac (يمكن استخدام جهاز صديق لمدة 10 دقائق)
# أو استخدم VM أو Cloud Mac مثل MacStadium/MacinCloud

# 1. Install fastlane
sudo gem install fastlane

# 2. Setup certificates
cd ios
fastlane match init

# 3. Generate certificates
fastlane match appstore

# ارفع الملفات المُنشأة إلى GitHub Secrets
```

## 5️⃣ إعداد Codemagic Build

في ملف `codemagic.yaml` (تم إنشاؤه):

```yaml
# غيّر هذه القيم:
- BUNDLE_ID: "com.oldies.attendance.full"
- APP_STORE_ID: "YOUR_APP_ID_HERE"  # من App Store Connect
- your-email@example.com: "بريدك الإلكتروني"
```

## 6️⃣ تشغيل Build

### من Codemagic Dashboard:
1. Applications → test123
2. Start new build
3. اختر `ios-workflow`
4. اضغط **Start new build**
5. انتظر 15-20 دقيقة ☕
6. سيتم رفع التطبيق تلقائياً على TestFlight!

### من GitHub:
```bash
git add .
git commit -m "Setup iOS deployment"
git push
```
سيبدأ Build تلقائياً في Codemagic!

## 7️⃣ TestFlight
بعد اكتمال Build:
1. افتح https://appstoreconnect.apple.com
2. My Apps → أولديزز وركرز → TestFlight
3. شوف التطبيق موجود!
4. إضافة Testers:
   - Internal Testing: حتى 100 مستخدم (موظفينك)
   - External Testing: حتى 10,000 مستخدم (يحتاج مراجعة Apple)

## 8️⃣ النشر على App Store (Production)
1. في App Store Connect → My Apps
2. Prepare for Submission
3. املأ:
   - Screenshots (مطلوب 6.5" و 5.5" iPhone)
   - App Preview (فيديو اختياري)
   - Description باللغة العربية
   - Keywords
   - Support URL
   - Privacy Policy URL
   - Category: Business
4. اضغط **Submit for Review**
5. انتظر 24-48 ساعة للمراجعة

---

## ⚡ البديل: GitHub Actions مع Fastlane

إذا أردت استخدام GitHub Actions فقط (تم إنشاء الملف):

### الخطوات الإضافية:
1. احصل على certificates من Mac
2. حوّلها لـ Base64:
```bash
base64 -i certificate.p12 -o certificate.txt
base64 -i profile.mobileprovision -o profile.txt
```
3. ضعها في GitHub Secrets:
   - `IOS_CERTIFICATE_BASE64`
   - `IOS_PROVISION_PROFILE_BASE64`
   - `IOS_CERTIFICATE_PASSWORD`
   - `APPLE_ID`
   - `APPLE_PASSWORD`

---

## 📱 ملاحظات مهمة

### متطلبات Apple Store:
- ✅ Privacy Policy (مطلوب)
- ✅ Terms of Service
- ✅ Support URL
- ✅ App Icon (1024x1024)
- ✅ Screenshots لكل أحجام الشاشات
- ✅ وصف التطبيق باللغة العربية والإنجليزية

### الـ Permissions المطلوبة:
في `Info.plist` (موجودة بالفعل):
- ✅ Location (NSLocationWhenInUseUsageDescription)
- ⚠️ WiFi قد يحتاج: NSLocalNetworkUsageDescription

### أيقونة التطبيق:
```
ios/Runner/Assets.xcassets/AppIcon.appiconset/
- 20x20@2x.png (40x40)
- 20x20@3x.png (60x60)
- 29x29@2x.png (58x58)
- 29x29@3x.png (87x87)
- 40x40@2x.png (80x80)
- 40x40@3x.png (120x120)
- 60x60@2x.png (120x120)
- 60x60@3x.png (180x180)
- 1024x1024.png
```

---

## 🎯 الملخص السريع

1. ✅ سجل في Apple Developer ($99/سنة)
2. ✅ أنشئ App في App Store Connect
3. ✅ سجل في Codemagic (مجاني للبداية)
4. ✅ اربط GitHub مع Codemagic
5. ✅ اضبط `codemagic.yaml`
6. ✅ Push → يبني تلقائياً → يرفع على TestFlight!
7. ✅ اختبر على TestFlight
8. ✅ ارفع للـ App Store

**الوقت المتوقع:** 2-3 ساعات للإعداد الأولي + 24-48 ساعة مراجعة Apple

---

## 🆘 مشاكل شائعة

### Build Failed: "No certificate found"
- تأكد من إعداد App Store Connect Integration في Codemagic
- أو أنشئ certificates يدوياً

### Build Failed: "Pod install failed"
```bash
cd ios
rm -rf Pods Podfile.lock
pod install
git add .
git commit -m "Update pods"
git push
```

### "Bundle ID mismatch"
غيّر في `ios/Runner.xcodeproj/project.pbxproj`:
```
PRODUCT_BUNDLE_IDENTIFIER = com.oldies.attendance;
```

---

## 📞 روابط مفيدة

- Codemagic Docs: https://docs.codemagic.io
- App Store Connect: https://appstoreconnect.apple.com
- TestFlight: https://developer.apple.com/testflight/
- Flutter iOS Deployment: https://docs.flutter.dev/deployment/ios

