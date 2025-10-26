# دليل التحديث السريع - تشغيل المشروع على AWS

## 🎯 الهدف
تحديث السيرفر على AWS ليشتغل بشكل كامل مع Flutter

---

## خطوة 1: رفع التعديلات على AWS

### الطريقة الأولى: SCP (نسخ الملفات)

**من Windows PowerShell:**

```powershell
# انتقل لمجلد المشروع
cd "D:\Coding\project important\test123 (7)\test123"

# انسخ server/index.ts للسيرفر
scp -i "D:\mytest123.pem" server/index.ts ubuntu@16.171.208.249:~/oldies-server/server/
```

### الطريقة الثانية: SSH وتعديل يدوي

```bash
# اتصل بالسيرفر
ssh -i "D:\mytest123.pem" ubuntu@16.171.208.249

# انتقل للمشروع
cd ~/oldies-server

# افتح الملف
nano server/index.ts
```

ثم انسخ الكود الجديد من الملف المحلي

---

## خطوة 2: بناء وإعادة تشغيل السيرفر

**على AWS EC2 (بعد SSH):**

```bash
cd ~/oldies-server

# تثبيت Dependencies (لو أول مرة)
npm install

# بناء TypeScript
npm run build

# إعادة تشغيل PM2
pm2 restart oldies-api

# تحقق من الحالة
pm2 status

# شوف اللوجز
pm2 logs oldies-api --lines 50
```

---

## خطوة 3: Seed قاعدة البيانات

**من Windows PowerShell:**

```powershell
# Seed الداتابيز
Invoke-RestMethod -Uri "http://16.171.208.249:5000/api/dev/seed"
```

**المفروض ترجعلك:**
```json
{
  "success": true,
  "message": "Database seeded successfully",
  "employees": [
    { "id": "OWNER001", "pin": "1234", "role": "owner" },
    { "id": "EMP001", "pin": "1234", "role": "employee" },
    { "id": "EMP_MAADI", "pin": "5555", "role": "employee" },
    { "id": "MGR_MAADI", "pin": "8888", "role": "manager" }
  ]
}
```

---

## خطوة 4: اختبار تسجيل الدخول

```powershell
# اختبر تسجيل دخول موظف
$body = @{ employee_id = "EMP001"; pin = "1234" } | ConvertTo-Json
Invoke-RestMethod -Uri "http://16.171.208.249:5000/api/auth/login" -Method Post -Body $body -ContentType "application/json"

# اختبر تسجيل دخول مدير
$body = @{ employee_id = "MGR_MAADI"; pin = "8888" } | ConvertTo-Json
Invoke-RestMethod -Uri "http://16.171.208.249:5000/api/auth/login" -Method Post -Body $body -ContentType "application/json"

# اختبر تسجيل دخول مالك
$body = @{ employee_id = "OWNER001"; pin = "1234" } | ConvertTo-Json
Invoke-RestMethod -Uri "http://16.171.208.249:5000/api/auth/login" -Method Post -Body $body -ContentType "application/json"
```

---

## خطوة 5: اختبار Flutter

1. شغل التطبيق على Flutter
2. جرب تسجيل الدخول بالحسابات دي:

| Employee ID | PIN  | Role     |
|-------------|------|----------|
| OWNER001    | 1234 | Owner    |
| EMP001      | 1234 | Employee |
| EMP_MAADI   | 5555 | Employee |
| MGR_MAADI   | 8888 | Manager  |

---

## 🔧 استكشاف الأخطاء

### مشكلة: "Connection refused"

```bash
# تأكد من إن السيرفر شغال
pm2 status

# لو مش شغال
pm2 start ecosystem.config.js
```

### مشكلة: "Invalid credentials"

```bash
# تأكد إن الداتابيز اتعملها seed
curl http://localhost:5000/api/dev/seed
```

### مشكلة: "Database connection error"

```bash
# تحقق من .env
cat .env

# المفروض يكون فيه
# DATABASE_URL=postgresql://neondb_owner:npg_D25sTdkbJxjf@ep-young-voice-ady0hrfd-pooler.c-2.us-east-1.aws.neon.tech/neondb?sslmode=require
```

---

## ✅ Checklist النهائي

- [ ] رفعت server/index.ts للسيرفر
- [ ] بنيت المشروع (`npm run build`)
- [ ] PM2 شغال (`pm2 status` = online)
- [ ] Seed نجح (`/api/dev/seed`)
- [ ] Login شغال من PowerShell
- [ ] Flutter بيقدر يسجل دخول
- [ ] التطبيق بيحدد نوع المستخدم صح (موظف/مدير/مالك)

---

## 🎉 بعد النجاح

التطبيق دلوقتي:
- ✅ شغال على السيرفر الخارجي (AWS)
- ✅ بياخد بيانات اللوجن من قاعدة البيانات
- ✅ بيحدد نوع المستخدم من الداتابيز
- ✅ مفيش بيانات محلية/demo

**كل حاجة هتيجي من السيرفر! 🚀**
