# تعليمات رفع Edge Functions على Supabase

## ⚠️ مهم جداً

**نعم، تحتاج لرفع الـ Edge Functions على Supabase!** بدون رفعها، لن يعمل النظام.

## المتطلبات الأساسية

1. **تثبيت Supabase CLI:**
   ```bash
   npm install -g supabase
   ```

2. **تسجيل الدخول:**
   ```bash
   supabase login
   ```

3. **ربط المشروع:**
   ```bash
   supabase link --project-ref bbxuyuaemigrqsvsnxkj
   ```

## طريقة الرفع

### الطريقة الأولى: رفع جميع الـ Functions دفعة واحدة (موصى بها)

**على Windows:**
```bash
deploy_all_functions.bat
```

**على Mac/Linux:**
```bash
chmod +x deploy_all_functions.sh
./deploy_all_functions.sh
```

### الطريقة الثانية: رفع كل function على حدة

```bash
# 1. رفع function تسجيل الحضور
supabase functions deploy attendance-check-in --no-verify-jwt

# 2. رفع function تسجيل الانصراف
supabase functions deploy attendance-check-out --no-verify-jwt

# 3. رفع function رفع النبضات (مهم جداً!)
supabase functions deploy sync-pulses --no-verify-jwt

# 4. رفع function استراحات الموظفين
supabase functions deploy employee-break --no-verify-jwt

# 5. رفع function طلبات الفروع
supabase functions deploy branch-requests --no-verify-jwt

# 6. رفع function معالجة الطلبات
supabase functions deploy branch-request-action --no-verify-jwt

# 7. رفع function تقارير الحضور
supabase functions deploy branch-attendance-report --no-verify-jwt

# 8. رفع function ملخص النبضات
supabase functions deploy branch-pulse-summary --no-verify-jwt

# 9. رفع function حساب المرتبات
supabase functions deploy calculate-payroll --no-verify-jwt
```

## التحقق من الرفع

1. **من Supabase Dashboard:**
   - اذهب إلى: `Edge Functions` في القائمة الجانبية
   - يجب أن ترى جميع الـ functions المرفوعة

2. **من Terminal:**
   ```bash
   supabase functions list
   ```

## المتغيرات البيئية المطلوبة

تأكد من وجود هذه المتغيرات في Supabase Dashboard > Edge Functions > Settings:

- `SUPABASE_URL`: `https://bbxuyuaemigrqsvsnxkj.supabase.co`
- `SERVICE_ROLE_KEY`: (من Settings > API > service_role key)

## الـ Functions الأكثر أهمية

إذا كنت تريد رفع الأساسيات فقط:

1. ✅ **attendance-check-in** - ضروري لتسجيل الحضور
2. ✅ **attendance-check-out** - ضروري لتسجيل الانصراف  
3. ✅ **sync-pulses** - ضروري لرفع النبضات وتحديث الحضور والمرتب

## استكشاف الأخطاء

إذا فشل الرفع:

1. **تحقق من تسجيل الدخول:**
   ```bash
   supabase projects list
   ```

2. **تحقق من ربط المشروع:**
   ```bash
   supabase projects list
   ```

3. **تحقق من الـ logs:**
   ```bash
   supabase functions logs <function-name>
   ```

4. **تحقق من الصلاحيات:**
   - تأكد أن لديك صلاحيات Deploy على المشروع

## ملاحظات مهمة

- ⚠️ **لا تنسى رفع `sync-pulses`** - هذا الـ function مهم جداً لتحديث الحضور والمرتب
- ⚠️ بعد رفع أي function، انتظر دقيقة قبل اختباره
- ⚠️ تأكد من أن قاعدة البيانات تحتوي على جميع الجداول المطلوبة

## بعد الرفع

1. اختبر الـ functions من Supabase Dashboard
2. تحقق من الـ logs للتأكد من عدم وجود أخطاء
3. جرب تسجيل حضور/انصراف من التطبيق
4. تحقق من أن البيانات تُرفع بشكل صحيح

