# نظام المرتبات - ملخص التطوير الكامل
## Complete Payroll System Development Summary

---

## 📋 المتطلبات الأصلية

طلب المستخدم نظام مرتبات كامل يتضمن:

### 1. صفحة المرتبات الرئيسية (Owner):
- عرض كل الفروع
- إجمالي المرتبات لكل فرع
- زر "تم الدفع" لكل فرع مع تأكيد

### 2. تفاصيل الفرع:
- قائمة الموظفين في الفرع
- المرتب المستحق لكل موظف
- زر "دفع" لكل موظف

### 3. التقرير التفصيلي للموظف (شيت كبير):
| التاريخ | وقت الحضور | وقت الانصراف | الساعات | السلف | بدل الإجازة | الخصومات | الإجمالي |
|---------|-----------|--------------|---------|-------|-------------|----------|----------|

### 4. قواعد خاصة:
- **بدل الإجازة**: 100 جنيه إذا غاب أقل من 3 أيام
- **الخصومات**: من نظام الغياب (2 يوم × ساعات الشيفت × سعر الساعة)
- **دفع فردي**: يمكن دفع موظف واحد (ينخصم من إجمالي الفرع)
- **دفع جماعي**: يمكن دفع الفرع كامل

---

## 🎯 ما تم تنفيذه

### ✅ 1. قاعدة البيانات (3 ملفات SQL):

#### **add_hourly_rate_and_shifts.sql**
```sql
-- إضافة حقول جديدة لجدول employees:
ALTER TABLE employees ADD COLUMN hourly_rate DECIMAL(10,2);
ALTER TABLE employees ADD COLUMN shift_start_time TIME;
ALTER TABLE employees ADD COLUMN shift_end_time TIME;

-- تحويل المرتبات القديمة (اختياري):
UPDATE employees SET hourly_rate = ROUND(monthly_salary / 208.0, 2);
```

#### **add_absences_and_deductions.sql**
```sql
-- جدول الغيابات:
CREATE TABLE absences (
  employee_id, branch_id, manager_id,
  absence_date, shift_start_time, shift_end_time,
  status (pending/approved/rejected),
  deduction_amount
);

-- جدول الخصومات:
CREATE TABLE deductions (
  employee_id, absence_id,
  amount (negative value),
  reason, deduction_date
);

-- RLS Policies للمديرين
```

#### **add_payroll_system.sql** (الجديد)
```sql
-- جدول دورات المرتبات:
CREATE TABLE payroll_cycles (
  branch_id, start_date, end_date,
  total_amount, status (pending/paid),
  paid_at, paid_by
);

-- جدول مرتبات الموظفين:
CREATE TABLE employee_payrolls (
  payroll_cycle_id, employee_id,
  total_hours, hourly_rate, base_salary,
  leave_allowance (100 EGP if < 3 days),
  total_advances, absence_days,
  total_deductions, net_salary,
  status, paid_at
);

-- جدول ملخص الحضور اليومي:
CREATE TABLE daily_attendance_summary (
  employee_id, attendance_date,
  check_in_time, check_out_time, total_hours,
  hourly_rate, daily_salary,
  advance_amount, leave_allowance,
  deduction_amount,
  is_absent, is_on_leave
);

-- Database Functions:
-- 1. calculate_leave_allowance() - حساب بدل الإجازة
-- 2. calculate_employee_payroll() - حساب مرتب موظف لدورة معينة
```

---

### ✅ 2. الخدمات (Services):

#### **PayrollService** (lib/services/payroll_service.dart) - 300 سطر
```dart
class PayrollService {
  // 1. Get all branches with pending payrolls
  Future<List> getBranchPayrollSummary()
  
  // 2. Get employees payroll for a specific branch cycle
  Future<List> getBranchEmployeesPayroll(cycleId)
  
  // 3. Get employee attendance details for report
  Future<List> getEmployeeAttendanceReport(employeeId, startDate, endDate)
  
  // 4. Create or update payroll cycle for a branch
  Future<String?> createOrUpdatePayrollCycle(branchId, startDate, endDate)
  
  // 5. Calculate payroll for all employees in a branch
  Future<bool> calculateBranchPayroll(cycleId, employeeIds)
  
  // 6. Mark branch payroll as paid
  Future<bool> markBranchPayrollPaid(cycleId, paidBy)
  
  // 7. Mark individual employee payroll as paid
  Future<bool> markEmployeePayrollPaid(payrollId, cycleId)
  
  // 8. Sync daily attendance (called after check-in/check-out)
  Future<bool> syncDailyAttendance(employeeId, date, checkIn, checkOut, hourlyRate)
  
  // 9. Mark day as absent
  Future<bool> markDayAbsent(employeeId, date)
}
```

---

### ✅ 3. الشاشات (Screens):

#### **OwnerPayrollPage** (lib/screens/owner/owner_payroll_page.dart) - 350 سطر
```dart
// الصفحة الرئيسية للمرتبات:
- عرض جميع الفروع
- Card لكل فرع يحتوي على:
  * اسم الفرع والموقع
  * الفترة (من - إلى)
  * إجمالي المرتبات
  * حالة الدفع (معلق/مدفوع)
  * زر "تم الدفع" (إذا كان معلق)
  * تاريخ الدفع (إذا كان مدفوع)
  
- عند الضغط على فرع → الانتقال لتفاصيل الفرع
- عند الضغط على "تم الدفع" → تأكيد → تحديث الحالة
```

#### **OwnerBranchPayrollDetailsPage** (lib/screens/owner/owner_branch_payroll_details_page.dart) - 380 سطر
```dart
// تفاصيل مرتبات فرع:
- Summary Card:
  * إجمالي المرتبات المعلقة
  * عدد الموظفين
  
- قائمة الموظفين:
  * اسم الموظف
  * عدد الساعات × سعر الساعة
  * بدل الإجازة
  * السلف
  * الخصومات
  * صافي المرتب
  * حالة الدفع (معلق/مدفوع)
  * زر "دفع" (إذا معلق)
  * تاريخ الدفع (إذا مدفوع)
  
- عند الضغط على موظف → التقرير التفصيلي
- عند الضغط على "دفع" → تأكيد → تحديث + إعادة حساب إجمالي الفرع
```

#### **OwnerEmployeePayrollReportPage** (lib/screens/owner/owner_employee_payroll_report_page.dart) - 450 سطر
```dart
// التقرير التفصيلي للموظف:
- Summary Header:
  * الفترة
  * إجمالي الساعات
  * أيام الغياب
  * المرتب الأساسي
  * صافي المرتب النهائي
  
- Breakdown Cards:
  * بدل الإجازة (أخضر)
  * السلف (برتقالي)
  * الخصومات (أحمر)
  
- جدول تفصيلي لكل يوم:
  | التاريخ | الحضور | الانصراف | ساعات | المرتب | سلف | بدل | خصم |
  - صفوف ملونة (أبيض/رمادي)
  - صفوف الغياب بخلفية حمراء
  - عرض "غياب" أو "إجازة" بدلاً من الأوقات
  
- Footer بالحساب النهائي:
  * المرتب الأساسي
  * + بدل الإجازة
  * - السلف
  * - الخصومات
  * = صافي المرتب النهائي
```

---

### ✅ 4. التكامل مع Check-in/Check-out:

#### **employee_home_page.dart** (تعديلات):
```dart
// في _handleCheckIn():
// بعد تسجيل الحضور بنجاح:
await PayrollService().syncDailyAttendance(
  employeeId: widget.employeeId,
  date: DateTime.now(),
  checkInTime: checkInTimeStr,
  checkOutTime: null,
  hourlyRate: hourlyRate,
);

// في _handleCheckOut():
// بعد تسجيل الانصراف بنجاح:
await PayrollService().syncDailyAttendance(
  employeeId: widget.employeeId,
  date: DateTime.now(),
  checkInTime: checkInTimeStr,
  checkOutTime: checkOutTimeStr,
  hourlyRate: hourlyRate,
);
```

---

### ✅ 5. التكامل مع Owner Screen:

#### **owner_main_screen.dart** (تعديلات):
```dart
// استبدال _OwnerPayrollTab القديم بـ OwnerPayrollPage الجديد:
_tabs = [
  _OwnerDashboardTab(...),
  _OwnerEmployeesTab(...),
  _OwnerBranchesTab(...),
  _OwnerPresenceTab(...),
  const OwnerPayrollPage(), // ← النظام الجديد
];
```

---

## 🔄 سير العمل (Workflow)

### 1️⃣ تسجيل الحضور اليومي:
```
الموظف يسجل حضور
    ↓
تسجيل في جدول attendance (الحضور الأساسي)
    ↓
تسجيل في daily_attendance_summary:
  - employee_id
  - attendance_date
  - check_in_time
  - hourly_rate (من بيانات الموظف)
    ↓
فحص التأخير (نظام الغياب)
    ↓
إنشاء absence إذا لزم الأمر
```

### 2️⃣ تسجيل الانصراف:
```
الموظف يسجل انصراف
    ↓
تحديث جدول attendance
    ↓
تحديث daily_attendance_summary:
  - check_out_time
  - total_hours = (check_out - check_in) / 60
  - daily_salary = total_hours × hourly_rate
```

### 3️⃣ حساب المرتب الشهري:
```
Owner يفتح صفحة المرتبات
    ↓
النظام يحسب تلقائياً لكل موظف:
  - إجمالي الساعات (من daily_attendance_summary)
  - المرتب الأساسي = ساعات × hourly_rate
  - بدل الإجازة = 100 (إذا غاب < 3 أيام)
  - السلف = SUM(advance_amount)
  - الخصومات = SUM(deductions.amount)
  - صافي المرتب = أساسي + بدل - سلف - خصومات
    ↓
حفظ في employee_payrolls
    ↓
حساب إجمالي الفرع = SUM(net_salary)
    ↓
حفظ في payroll_cycles
```

### 4️⃣ دفع المرتب:
```
Owner يضغط "دفع" على موظف
    ↓
تأكيد الدفع
    ↓
تحديث employee_payrolls:
  - status = 'paid'
  - paid_at = NOW()
    ↓
إعادة حساب إجمالي الفرع (فقط المعلق)
    ↓
تحديث payroll_cycles.total_amount
```

### 5️⃣ دفع الفرع كامل:
```
Owner يضغط "تم الدفع" على فرع
    ↓
تأكيد الدفع
    ↓
تحديث payroll_cycles:
  - status = 'paid'
  - paid_at = NOW()
  - paid_by = owner_id
```

---

## 📊 الحسابات التفصيلية

### المرتب الأساسي:
```dart
double calculateBaseSalary(List<DailyAttendance> days, double hourlyRate) {
  double totalHours = 0;
  for (var day in days) {
    if (!day.isAbsent) {
      totalHours += day.totalHours;
    }
  }
  return totalHours * hourlyRate;
}
```

### بدل الإجازة:
```dart
double calculateLeaveAllowance(List<DailyAttendance> days) {
  int absenceDays = days.where((d) => d.isAbsent || d.isOnLeave).length;
  
  if (absenceDays > 0 && absenceDays < 3) {
    return 100.0; // 100 جنيه
  }
  return 0.0;
}
```

### إجمالي السلف:
```dart
double calculateTotalAdvances(List<DailyAttendance> days) {
  return days.fold(0.0, (sum, day) => sum + day.advanceAmount);
}
```

### إجمالي الخصومات:
```dart
double calculateTotalDeductions(String employeeId, DateTime start, DateTime end) {
  // من جدول deductions
  var deductions = getDeductions(employeeId, start, end);
  return deductions.fold(0.0, (sum, d) => sum + d.amount.abs());
}
```

### صافي المرتب:
```dart
double calculateNetSalary(
  double baseSalary,
  double leaveAllowance,
  double totalAdvances,
  double totalDeductions,
) {
  return baseSalary + leaveAllowance - totalAdvances - totalDeductions;
}
```

---

## 🎨 واجهة المستخدم (UI)

### الألوان:
- **معلق**: برتقالي (Orange)
- **مدفوع**: أخضر (Green)
- **بدل الإجازة**: أخضر فاتح
- **السلف**: برتقالي
- **الخصومات**: أحمر
- **المرتب النهائي**: بنفسجي (Deep Purple)

### الأيقونات:
- المرتبات: `Icons.attach_money`
- الحضور: `Icons.access_time`
- الغياب: `Icons.event_busy`
- الدفع: `Icons.payment`
- تم الدفع: `Icons.check_circle`
- بدل الإجازة: `Icons.card_giftcard`
- السلف: `Icons.money_off`
- الخصومات: `Icons.remove_circle`

---

## ✅ الملفات المنشأة/المعدلة

### ملفات SQL (3):
1. ✅ `add_hourly_rate_and_shifts.sql` (28 lines)
2. ✅ `add_absences_and_deductions.sql` (90 lines)
3. ✅ `add_payroll_system.sql` (250 lines)

### ملفات Dart جديدة (4):
1. ✅ `lib/services/payroll_service.dart` (300 lines)
2. ✅ `lib/screens/owner/owner_payroll_page.dart` (350 lines)
3. ✅ `lib/screens/owner/owner_branch_payroll_details_page.dart` (380 lines)
4. ✅ `lib/screens/owner/owner_employee_payroll_report_page.dart` (450 lines)

### ملفات Dart معدلة (2):
1. ✅ `lib/screens/employee/employee_home_page.dart` (إضافة تكامل PayrollService)
2. ✅ `lib/screens/owner/owner_main_screen.dart` (استبدال تبويب المرتبات)

### ملفات توثيق (2):
1. ✅ `PAYROLL_SYSTEM_GUIDE.md` (دليل التنفيذ الكامل)
2. ✅ `PAYROLL_DEVELOPMENT_SUMMARY.md` (هذا الملف)

---

## 📈 إحصائيات التطوير

- **إجمالي الأسطر**: ~2000 سطر
- **عدد الملفات الجديدة**: 9 ملفات
- **عدد الملفات المعدلة**: 2 ملفات
- **عدد الجداول الجديدة**: 5 جداول
- **عدد الـFunctions**: 2 functions
- **عدد الشاشات الجديدة**: 3 شاشات
- **عدد الخدمات الجديدة**: 1 خدمة (9 methods)

---

## 🔐 الأمان (Security)

### Row Level Security (RLS):
```sql
-- Owner can view all payrolls
CREATE POLICY "Owners can view all payrolls"
ON payroll_cycles FOR SELECT
USING (auth.uid() IN (SELECT id FROM employees WHERE role = 'owner'));

-- Owner can update payrolls
CREATE POLICY "Owners can update payrolls"
ON payroll_cycles FOR UPDATE
USING (auth.uid() IN (SELECT id FROM employees WHERE role = 'owner'));

-- Employees can view their own payroll
CREATE POLICY "Employees view own payroll"
ON employee_payrolls FOR SELECT
USING (employee_id = auth.uid());
```

---

## 🧪 سيناريوهات الاختبار

### ✅ Test Case 1: إضافة موظف بساعة
```
Input:
  - Name: "أحمد محمد"
  - Hourly Rate: 50 EGP
  - Shift: 09:00 - 17:00

Expected:
  - Employee saved with hourly_rate = 50
  - shift_start_time = 09:00
  - shift_end_time = 17:00
```

### ✅ Test Case 2: تسجيل حضور وانصراف
```
Input:
  - Check-in: 09:00
  - Check-out: 17:00

Expected in daily_attendance_summary:
  - check_in_time = "09:00"
  - check_out_time = "17:00"
  - total_hours = 8.0
  - daily_salary = 8 × 50 = 400 EGP
```

### ✅ Test Case 3: غياب يومين (بدل إجازة)
```
Input:
  - 28 days present
  - 2 days absent

Expected:
  - absence_days = 2
  - leave_allowance = 100 EGP (because < 3 days)
  - net_salary includes +100 EGP
```

### ✅ Test Case 4: غياب 3 أيام (بدون بدل)
```
Input:
  - 27 days present
  - 3 days absent

Expected:
  - absence_days = 3
  - leave_allowance = 0 EGP (because >= 3 days)
```

### ✅ Test Case 5: خصم غياب
```
Input:
  - Manager rejected absence
  - Shift: 8 hours
  - Hourly Rate: 50 EGP

Expected in deductions:
  - amount = -(2 × 8 × 50) = -800 EGP
  - total_deductions in payroll = 800 EGP
  - net_salary reduced by 800 EGP
```

### ✅ Test Case 6: دفع موظف واحد
```
Input:
  - Branch total = 10,000 EGP
  - Employee 1 salary = 3,000 EGP
  - Mark Employee 1 as paid

Expected:
  - employee_payrolls.status = 'paid'
  - employee_payrolls.paid_at = NOW()
  - Branch total updated = 7,000 EGP
```

### ✅ Test Case 7: دفع فرع كامل
```
Input:
  - Branch has 5 employees
  - Total = 15,000 EGP
  - Mark branch as paid

Expected:
  - payroll_cycles.status = 'paid'
  - payroll_cycles.paid_at = NOW()
  - payroll_cycles.paid_by = owner_id
  - Branch total = 15,000 EGP (unchanged)
```

---

## 🚀 خطوات النشر

### 1. Database Migration:
```bash
# في Supabase SQL Editor:
1. افتح add_hourly_rate_and_shifts.sql
2. نفذ السكريبت
3. تأكد من النجاح

4. افتح add_absences_and_deductions.sql
5. نفذ السكريبت
6. تأكد من النجاح

7. افتح add_payroll_system.sql
8. نفذ السكريبت
9. تأكد من النجاح
```

### 2. Flutter Build:
```bash
flutter clean
flutter pub get
flutter build apk --release
```

### 3. Testing:
```bash
# اختبار شامل:
- تسجيل حضور وانصراف
- عرض المرتبات
- دفع موظف
- دفع فرع
- التقرير التفصيلي
```

---

## 📝 ملاحظات مهمة

### ⚠️ تحذيرات:
1. **لا تحذف جدول `attendance`** - النظام الجديد يعمل بجانبه
2. **الترتيب مهم** - يجب تنفيذ SQL بالترتيب المذكور
3. **RLS** - تأكد من تفعيل RLS Policies
4. **hourly_rate** - يجب تحديثه لكل موظف

### ✅ مميزات:
1. **تكامل كامل** - مع نظام الحضور والغياب
2. **حسابات تلقائية** - لا حاجة لحساب يدوي
3. **تقارير تفصيلية** - جدول كبير لكل يوم
4. **دفع مرن** - فردي أو جماعي
5. **أمان عالي** - RLS Policies محكمة

---

## 🎯 النتيجة النهائية

تم بناء نظام مرتبات كامل ومتكامل يتضمن:

✅ **3 مستويات من العرض**:
1. عرض الفروع
2. عرض الموظفين في كل فرع
3. التقرير التفصيلي لكل موظف

✅ **حسابات دقيقة**:
- المرتب الأساسي (ساعات × سعر الساعة)
- بدل الإجازة (100 جنيه إذا < 3 أيام غياب)
- السلف (مجموع السلف اليومية)
- الخصومات (من نظام الغياب)
- صافي المرتب (النهائي)

✅ **دفع مرن**:
- دفع موظف واحد (ينخصم من إجمالي الفرع)
- دفع الفرع كامل

✅ **تكامل تلقائي**:
- مع نظام الحضور (check-in/out)
- مع نظام الغياب (deductions)
- مع نظام السلف

✅ **تقارير شاملة**:
- جدول تفصيلي لكل يوم
- ملخص شهري
- حسابات نهائية

---

**النظام جاهز للعمل! 🎉**
