# 🚀 رفع التطبيق على iOS - الخطوات السريعة

## ✅ الإعداد تم! (Done)

تم تجهيز المشروع للرفع على iOS بدون الحاجة لـ Mac!

---

## 📋 خطوات التشغيل (3 دقائق فقط!)

### 1️⃣ سجل في Codemagic (مجاني)
1. اذهب: https://codemagic.io/signup
2. اختر **Sign up with GitHub**
3. وافق على الصلاحيات

### 2️⃣ اربط المشروع
1. في Codemagic Dashboard
2. **Applications** → **Add application**
3. اختر **badpower45/test123**
4. اختر **Flutter**
5. ✅ Done!

### 3️⃣ ابدأ أول Build
1. اختر التطبيق من القائمة
2. اضغط **Start new build**
3. اختر الـ Workflow:
   - **ios-workflow** → للآيفون
   - **android-workflow** → للأندرويد
4. اضغط **Start new build**
5. انتظر 15-20 دقيقة ☕

---

## 🍎 للرفع على App Store (بعد البناء الأول)

### المتطلبات:
- ✅ Apple Developer Account ($99/سنة)
- ✅ App Store Connect

### الخطوات:
1. سجل في: https://developer.apple.com
2. أنشئ App في: https://appstoreconnect.apple.com
3. في Codemagic:
   - **Team settings** → **Integrations**
   - **App Store Connect** → Enable
   - سجل دخول بـ Apple ID
4. عدّل `codemagic.yaml`:
   ```yaml
   email:
     recipients:
       - بريدك@example.com  # ضع بريدك هنا
   ```
5. Push الكود → Codemagic يرفع تلقائياً! 🎉

---

## 📱 للتجربة بدون App Store (TestFlight)

بعد اكتمال Build في Codemagic:
1. حمّل الـ `.ipa` من Artifacts
2. ارفعه على https://www.diawi.com
3. اضغط **Send**
4. احصل على رابط التحميل
5. افتح الرابط من الآيفون → Install!

---

## 🔥 الطريقة الأسرع: GitHub Actions

تم تجهيز GitHub Actions أيضاً!

كل ما تعمل **Push** للكود:
- ✅ يبني Android APK تلقائياً
- ✅ يبني iOS (بدون توقيع)
- ✅ تلاقي الملفات في **Actions** → **Artifacts**

لتفعيل iOS Build كامل:
- شوف `IOS_DEPLOYMENT_GUIDE.md` (الدليل الكامل)

---

## 🎯 الملخص

| الطريقة | المميزات | العيوب |
|---------|----------|---------|
| **Codemagic** ⭐ | آلي 100%، سهل، مجاني للبداية | محدود في النسخة المجانية |
| **GitHub Actions** | مجاني تماماً، تحكم كامل | يحتاج إعداد certificates يدوي |
| **Diawi** | تجربة فورية بدون App Store | مؤقت (7 أيام) |

---

## 🆘 مساعدة

- الدليل الكامل: `IOS_DEPLOYMENT_GUIDE.md`
- Codemagic Docs: https://docs.codemagic.io
- إذا واجهت مشكلة، اتصل بي! 💬

---

**✨ جاهز للإطلاق! كل ما تعمل Push للكود، Codemagic هيبني iOS تلقائياً!**
