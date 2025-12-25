# إصلاح مشكلة حذف الفروع

## المشكلة
كان النظام يمنع حذف الفرع إذا كان يحتوي على موظفين، مع أن الـ server code يتعامل مع فك ارتباط الموظفين تلقائياً.

## الحل

### 1. إزالة التحقق الذي يمنع الحذف
تم إزالة الكود الذي يمنع حذف الفرع إذا كان يحتوي على موظفين من `owner_branches_screen.dart`.

### 2. إنشاء RPC Function في Supabase
تم إنشاء function `delete_branch_with_unlink` في Supabase لحذف الفرع وفك ارتباط الموظفين تلقائياً.

**الملف:** `supabase/migrations/create_delete_branch_function.sql`

**الوظيفة:**
- تحذف BSSIDs المرتبطة بالفرع
- تفك ارتباط الموظفين (تضع `branch_id` و `branch` = null)
- تحذف روابط المديرين من `branch_managers`
- تحذف الفرع نفسه

### 3. تحديث Service
تم تحديث `SupabaseBranchService.deleteBranch` لاستخدام الـ RPC function.

### 4. تحديث رسائل التأكيد
تم تحديث رسالة التأكيد لتوضح أن الموظفين سيتم فك ارتباطهم تلقائياً.

## التطبيق

### 1. تطبيق Migration
```sql
-- في Supabase SQL Editor
-- قم بتشغيل محتوى ملف: supabase/migrations/create_delete_branch_function.sql
```

### 2. إعادة تشغيل التطبيق
```bash
flutter run
```

## النتيجة
- يمكن الآن حذف أي فرع حتى لو كان يحتوي على موظفين
- يتم فك ارتباط الموظفين تلقائياً عند الحذف
- رسالة تأكيد واضحة تخبر المستخدم بعدد الموظفين الذين سيتم فك ارتباطهم

