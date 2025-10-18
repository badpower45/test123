# تعليمات تحديث السيرفر على AWS

## الخطوة 1: الاتصال بالسيرفر
```bash
ssh -i /path/to/oldies-key.pem ubuntu@16.171.208.249
```

## الخطوة 2: الانتقال لمجلد المشروع وسحب التحديثات
```bash
cd ~/oldies
git pull origin main
```

## الخطوة 3: تثبيت أي dependencies جديدة
```bash
cd server
npm install
```

## الخطوة 4: إعادة بناء المشروع
```bash
npm run build
```

## الخطوة 5: إعادة تشغيل السيرفر
```bash
pm2 restart oldies-api
```

## الخطوة 6: التحقق من أن السيرفر يعمل
```bash
pm2 logs oldies-api
```

## الخطوة 7: تشغيل seed لإضافة البيانات التجريبية
من جهازك المحلي، قم بتشغيل:
```bash
curl http://16.171.208.249:5000/api/dev/seed
```

## التحديثات المهمة في هذا الإصدار:

### 1. إصلاح طلبات الإجازة والسلف
- تم إصلاح response format ليكون متوافق مع Flutter
- الآن يُرجع `request` بالإضافة إلى الحقول الأخرى

### 2. إصلاح طلبات الاستراحة
- تم إضافة endpoint جديد `POST /api/breaks` (بدون `/request`)
- تم إزالة التكرار في GET endpoint

### 3. بيانات تجريبية لـ EMP_MAADI
- تم إضافة 900 pulse لـ EMP_MAADI (امبارح)
- هذا يعادل 300 جنيه أرباح (7.5 ساعات عمل)
- السلفة المتاحة: 90 جنيه (30% من 300)

### 4. endpoint جديد للمدير
- `POST /api/branch/attendance/edit`
- يسمح للمدير بتعديل أوقات الحضور والانصراف للموظفين
- Parameters:
  - employee_id (required)
  - date (required) - format: YYYY-MM-DD
  - check_in_time (optional) - format: HH:MM:SS
  - check_out_time (optional) - format: HH:MM:SS

### 5. تحسينات لوحة المدير
- تصميم responsive جديد
- Statistics cards
- Tabbed interface (طلبات، حضور، غياب، استراحات)
- Filter by status (pending, approved, rejected)
- Better UI/UX

## اختبار التحديثات:

### EMP_MAADI (PIN: 5555)
1. سجل دخول
2. جرب طلب إجازة ✅
3. جرب طلب سلفة (هتلاقي 90 جنيه متاح) ✅
4. جرب طلب استراحة ✅

### MGR_MAADI (PIN: 8888)
1. سجل دخول
2. هتفتح على ManagerMainScreen (نفس شاشة الموظف بدون تبويب الاستراحة)
3. اضغط على أيقونة Dashboard في الـ AppBar
4. هتشوف لوحة التحكم الجديدة
5. وافق/ارفض الطلبات
6. شوف تقرير الحضور
7. عدل أوقات الحضور للموظفين (عبر API call)

## Endpoints الجديدة/المحدثة:

```
POST /api/leave/request
Response: { success, message, request, leaveRequest, allowanceAmount }

POST /api/advances/request
Response: { success, message, request, advance }

POST /api/breaks
Response: { success, message, break }

GET /api/breaks?employee_id=EMP_MAADI
Response: { success, breaks: [...] }

POST /api/branch/attendance/edit
Body: { employee_id, date, check_in_time, check_out_time }
Response: { success, message, attendance }
```

## ملاحظات:
- تأكد أن DATABASE_URL موجود في `.env` على السيرفر
- تأكد أن PM2 يعمل بشكل صحيح
- في حالة وجود مشاكل، تحقق من الـ logs: `pm2 logs oldies-api --lines 100`
