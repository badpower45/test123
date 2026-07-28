# 📝 Walkthrough: التحديث الشامل للمرتبات والسوبر موظف وقواعد الخصم

مستند يلخص التغييرات البرمجية والتحسينات التي تم إنجازها في هذا التحديث لضمان تلبية طلبات العمل بالكامل.

---

## 1. ما تم إنجازه (Accomplished Work)

### أ. إعداد وإدارة قواعد الحضور والتأخير (Shift Rules & Deductions)
1. **قاعدة البيانات:**
   - جدول `attendance_rules` يحمل تفاصيل قواعد الخصم لكل فرع أو بشكل عام (grace period, deduction type, deduction multiplier, fixed amount, tiered rules).
2. **سيرفر سوبابيس (Edge Function):**
   - تم تعديل دالة `calculate-payroll` لتجلب القواعد النشطة من جدول `attendance_rules` وتقوم بتطبيق الخصومات ديناميكياً بناءً على نوع الخصم المختار (hourly pro rata, fixed, tiered) دون الاعتماد على القيمة الافتراضية الثابتة (15 دقيقة).
3. **لوحة تحكم المالك (Owner Dashboard):**
   - إضافة أيقونة "قواعد الحضور والخصم" في شاشة إدارة الموظفين للمالك.
   - فتح شاشة جانبية تمكنه من استعراض كافة القواعد، وإنشاء قواعد مخصصة لكل فرع بشكل منفصل، وتعديل فترة السماح ونوع الخصم (عادي، ثابت، شرائح مخصصة) مع واجهة ديناميكية لإضافة وحذف الشرائح وحفظها في قاعدة البيانات.

### ب. موديول "سوبر موظف" (Super Employee)
1. **أجهزة الأندرويد والآيفون:**
   - تم تعديل فحص الـ Geofence والـ WiFi في Flutter (`GeofenceService`) وفي خدمة الخلفية بلغة Kotlin (`PersistentPulseService.kt`) للموظفين الحاملين لعلامة "سوبر موظف".
   - يتم التحقق من موقع الموظف السوبر ضد **كل الفروع المخزنة** محلياً وليس فرعاً واحداً، مما يتيح له البصمة واستلام نبضات الحضور بنجاح من أي فرع من فروع المؤسسة.
2. **لوحة التحكم:**
   - إضافة خيار "سوبر موظف" كـ Checkbox/Switch في واجهة إضافة الموظف الجديد وواجهة تعديل بيانات الموظف الحالي في لوحة تحكم المالك، مع إرسال القيمة المحدثة وحفظها في Supabase.

### ج. تصفية وتصدير الرواتب لـ Excel
1. **التصفية:**
   - إضافة قائمة منسدلة (Dropdown) في صفحة `owner_comprehensive_payroll_page.dart` لتصفية قائمة الرواتب حسب الفرع (مع خيار "الكل" افتراضياً).
   - تحديث بطاقات الإحصاءات الإجمالية (إجمالي الموظفين، إجمالي ساعات العمل، الصافي والراتب الأساسي) ديناميكياً بمجرد اختيار فرع محدد أو البحث بالاسم/الكود.
2. **تصدير Excel:**
   - إضافة زر "التصدير إلى Excel" في شريط العنوان (AppBar).
   - بناء نظام تصدير ذكي متوافق مع الويب (تنزيل فوري للملف بالمتصفح) ومع الهواتف الذكية (فتح نافذة المشاركة الأصلية Share Sheet لإرسال الملف عبر WhatsApp أو حفظه في الذاكرة).
   - الملف المصدّر يحتوي على كامل التفاصيل وبشكل منسق يدعم القراءة من اليمين إلى اليسار (RTL).

---

## 2. بنية الملفات المعدلة والمضافة (Modified Files & Structure)

- **قاعدة البيانات:**
  - [20260715020000_super_employee_and_rules.sql](file:///Users/abdelrahmanelezaby/work/test123/supabase/migrations/20260715020000_super_employee_and_rules.sql)
- **سيرفر سوبابيس (Edge Function):**
  - [calculate-payroll/index.ts](file:///Users/abdelrahmanelezaby/work/test123/supabase/functions/calculate-payroll/index.ts)
- **شاشات المالك والتحكم:**
  - [owner_main_screen.dart](file:///Users/abdelrahmanelezaby/work/test123/lib/screens/owner/owner_main_screen.dart)
  - [owner_comprehensive_payroll_page.dart](file:///Users/abdelrahmanelezaby/work/test123/lib/screens/owner/owner_comprehensive_payroll_page.dart)
- **شروط التحقق من الموقع:**
  - [geofence_service.dart](file:///Users/abdelrahmanelezaby/work/test123/lib/services/geofence_service.dart)
- **محرك حفظ الملفات المتعدد:**
  - [file_saver.dart](file:///Users/abdelrahmanelezaby/work/test123/lib/utils/file_saver.dart)
  - [file_saver_web.dart](file:///Users/abdelrahmanelezaby/work/test123/lib/utils/file_saver_web.dart)
  - [file_saver_mobile.dart](file:///Users/abdelrahmanelezaby/work/test123/lib/utils/file_saver_mobile.dart)
  - [file_saver_stub.dart](file:///Users/abdelrahmanelezaby/work/test123/lib/utils/file_saver_stub.dart)
