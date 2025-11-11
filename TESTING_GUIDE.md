# 🧪 OWNER SCREENS TESTING GUIDE

## Quick Start Testing

### Login Credentials
```
Owner Account:
ID: OWNER001
PIN: 1234

Manager Account (for comparison):
ID: MGR001
PIN: 1111

Employee Accounts:
ID: EMP001, PIN: 2222
ID: EMP002, PIN: 3333
ID: EMP003, PIN: 4444
```

---

## Test Scenarios

### 1. Owner Login & Navigation (2 minutes)

**Steps**:
1. Open app
2. Enter: OWNER001 / 1234
3. Click "تسجيل الدخول"
4. ✅ Should navigate to Owner Dashboard

**Verify**:
- Top AppBar shows owner name
- Drawer button visible
- Dashboard content loads
- Bottom nav bar shows (لوحة التحكم, الموظفون)

---

### 2. Dashboard Overview (3 minutes)

**Steps**:
1. Wait for dashboard to load
2. View stat cards
3. Check currently present employees
4. Click on request cards

**Verify**:
- ✅ Total Employees: 6
- ✅ Today Attendance: 0+ (depends on test data)
- ✅ Currently Present: Shows employees who checked in but not out
- ✅ Pending Requests: Count of all pending requests
- ✅ Leave Requests card: Shows count, click navigates to Leave Requests screen
- ✅ Attendance Requests card: Shows count
- ✅ Salary Advance card: Shows count
- ✅ Currently present list: Shows employee names and check-in times

---

### 3. Employee Management (10 minutes)

#### 3.1 View Employees
**Steps**:
1. Open drawer
2. Click "الموظفون"
3. View employee list

**Verify**:
- ✅ Shows all 6 employees (OWNER001, MGR001, EMP001-003, HR001)
- ✅ Each card shows: Avatar, Name, Role badge, Branch, ID, PIN
- ✅ Role badges have different colors (Purple=Owner, Blue=Manager, Green=HR, Orange=Staff)

#### 3.2 Filter Employees
**Steps**:
1. Select "الفرع" → Choose a branch (e.g., "Cairo Main")
2. Observe filtered results
3. Select "الدور" → Choose "موظف"
4. Click filter icon to clear filters

**Verify**:
- ✅ Filtering by branch works
- ✅ Filtering by role works
- ✅ Both filters work together
- ✅ Clear filters button resets everything

#### 3.3 Add New Employee
**Steps**:
1. Click floating "+" button (إضافة موظف)
2. Fill form:
   - ID: TEST001
   - Name: Test Employee
   - PIN: 9999
   - Branch: Select from dropdown
   - Role: Select "موظف"
   - Salary: 5000
3. Keep "نشط" enabled
4. Click "إضافة"

**Verify**:
- ✅ Dialog opens
- ✅ All fields editable
- ✅ Branch dropdown populated from Supabase
- ✅ PIN validation (must be 4 digits)
- ✅ Success message: "✓ تم إضافة الموظف بنجاح"
- ✅ New employee appears in list
- ✅ Can login with TEST001/9999

#### 3.4 Edit Employee
**Steps**:
1. Find TEST001 in list
2. Click ⋮ menu → "تعديل"
3. Change name to "Updated Test"
4. Change salary to 6000
5. Click "تحديث"

**Verify**:
- ✅ Edit dialog opens with pre-filled data
- ✅ Employee ID field disabled (can't change)
- ✅ All other fields editable
- ✅ Success message: "✓ تم تحديث الموظف بنجاح"
- ✅ Changes reflected in list

#### 3.5 Delete Employee
**Steps**:
1. Find TEST001
2. Click ⋮ menu → "حذف"
3. Confirm deletion
4. Verify removed from list

**Verify**:
- ✅ Confirmation dialog appears
- ✅ Success message: "✓ تم حذف الموظف بنجاح"
- ✅ Employee removed from list
- ✅ Cannot login with TEST001 anymore

---

### 4. Leave Requests Management (5 minutes)

#### 4.1 Create Leave Request (as Employee)
**Steps**:
1. Logout from Owner
2. Login as EMP001 / 2222
3. Navigate to "الطلبات" tab
4. Go to "إجازات" tab
5. Click "طلب إجازة جديد"
6. Fill:
   - Start Date: Tomorrow
   - End Date: 3 days later
   - Leave Type: "مرضي"
   - Reason: "اجازة مرضيه"
7. Submit

**Verify**:
- ✅ Request created successfully
- ✅ Shows in pending list
- ✅ Status: "قيد الانتظار" (yellow)

#### 4.2 Approve Leave Request (as Owner)
**Steps**:
1. Logout from EMP001
2. Login as OWNER001 / 1234
3. Open drawer → "طلبات الإجازات"
4. Find EMP001's request
5. Click "موافقة"

**Verify**:
- ✅ Request card shows employee name, branch, dates
- ✅ Leave type displayed
- ✅ Reason displayed
- ✅ Approve button changes to "تمت الموافقة" (green)
- ✅ Request disappears from pending filter
- ✅ Employee sees request with green "موافق عليه" status

#### 4.3 Reject Leave Request
**Steps**:
1. Create another leave request as EMP001
2. Login as OWNER001
3. Navigate to Leave Requests
4. Click "رفض"
5. Enter rejection reason: "تعارض مع الجدول"
6. Submit

**Verify**:
- ✅ Rejection dialog appears
- ✅ Can enter rejection notes
- ✅ Success message appears
- ✅ Request shows "مرفوض" (red) status
- ✅ Employee sees rejection with notes

#### 4.4 Filter Leave Requests
**Steps**:
1. Create multiple requests with different statuses
2. Use filter dropdown:
   - Select "قيد الانتظار"
   - Select "موافق عليه"
   - Select "مرفوض"
   - Select "الكل"

**Verify**:
- ✅ Pending filter shows only pending
- ✅ Approved filter shows only approved
- ✅ Rejected filter shows only rejected
- ✅ All filter shows everything

---

### 5. Attendance Requests (3 minutes)

**Steps**:
1. Create attendance request as EMP002
   - Request Date: Yesterday
   - Reason: "forgot to check in"
2. Login as OWNER001
3. Navigate to "طلبات الحضور"
4. Approve or Reject

**Verify**:
- ✅ Shows employee name, branch
- ✅ Shows request date and reason
- ✅ Filter works
- ✅ Approve/Reject updates status
- ✅ Employee sees updated status

---

### 6. Salary Advance Requests (8 minutes)

#### 6.1 Valid Salary Advance (≤ 30%)
**Steps**:
1. Login as EMP001 / 2222
2. Navigate to Requests → "سلف"
3. Click "طلب سلفة جديد"
4. Check current salary info (should show: "الراتب الشهري: 5000 ج.م" and "الحد الأقصى للسلفة: 1500 ج.م")
5. Enter amount: 1000 (20% of 5000)
6. Enter reason: "حاجة طارئة"
7. Submit

**Verify**:
- ✅ Shows current salary and max advance (30%)
- ✅ Request created successfully
- ✅ Shows "قيد الانتظار" status

#### 6.2 Invalid Salary Advance (> 30%)
**Steps**:
1. Try to request 2000 (40% of 5000)
2. Submit

**Verify**:
- ✅ Error message: "لا يمكن طلب أكثر من 30% من الراتب الشهري"
- ✅ Request not created
- ✅ Shows max allowed amount

#### 6.3 Approve Salary Advance (as Owner)
**Steps**:
1. Login as OWNER001
2. Navigate to "طلبات السلف"
3. Find EMP001's request for 1000
4. Observe:
   - Employee name: Employee One
   - Monthly Salary: 5000 ج.م
   - Amount: 1000 ج.م
   - Percentage: 20% (green background)
5. Click "موافقة"

**Verify**:
- ✅ Card shows all employee info
- ✅ Monthly salary displayed
- ✅ Amount and percentage calculated correctly
- ✅ Percentage < 30% has green background
- ✅ Percentage > 30% has red background
- ✅ Approve button works
- ✅ Status updates to approved

#### 6.4 5-Day Rule Test
**Steps**:
1. Approve first request
2. Immediately create another request as EMP001
3. Try to submit

**Verify**:
- ✅ Error: "يمكن طلب سلفة مرة واحدة كل 5 أيام"
- ✅ Request blocked
- ✅ Must wait 5 days

---

### 7. Attendance Table (5 minutes)

**Steps**:
1. Navigate to "جدول الحضور"
2. View default data (current month)
3. Click date range picker
4. Select: Last month (full month)
5. Click "Branch" dropdown
6. Select a specific branch
7. View updated table
8. Click "مسح التصفية" to clear

**Verify**:
- ✅ DataTable displays with columns: Date, Employee, Branch, Check-in, Check-out, Total Hours, Status
- ✅ Default shows current month
- ✅ Date range picker changes data
- ✅ Branch filter works
- ✅ Summary shows:
  * Total records count
  * Currently present count
  * Average hours calculation
- ✅ Table scrolls horizontally and vertically
- ✅ Clear filters resets everything
- ✅ Pull to refresh reloads data

---

### 8. Navigation & UI (2 minutes)

**Steps**:
1. Open drawer
2. Navigate to each screen
3. Verify back button/drawer works
4. Check logout

**Verify**:
- ✅ Drawer shows all 6 screens
- ✅ Current screen highlighted
- ✅ Navigation works smoothly
- ✅ AppBar title updates
- ✅ Logout confirmation dialog appears
- ✅ Logout works, returns to login screen

---

## Error Handling Tests

### 1. Network Error
**Steps**:
1. Disable internet
2. Try to load any screen
3. Enable internet
4. Pull to refresh

**Verify**:
- ✅ Shows error message with icon
- ✅ "إعادة المحاولة" button appears
- ✅ Retry button works when internet restored

### 2. Invalid Data
**Steps**:
1. Try to add employee with empty fields
2. Try to add employee with 3-digit PIN

**Verify**:
- ✅ Form validation prevents submission
- ✅ Shows red error text under fields
- ✅ User-friendly error messages

---

## Performance Tests

### 1. Large Dataset
**Steps**:
1. Create 50+ employees
2. Create 100+ attendance records
3. Navigate between screens
4. Apply filters

**Verify**:
- ✅ Screens load within 2 seconds
- ✅ Filters apply instantly
- ✅ No lag when scrolling
- ✅ No memory leaks

### 2. Concurrent Operations
**Steps**:
1. Create multiple requests simultaneously
2. Approve/reject multiple requests quickly
3. Switch between screens rapidly

**Verify**:
- ✅ No race conditions
- ✅ All operations complete successfully
- ✅ UI updates correctly

---

## Edge Cases

### 1. Empty States
**Test**: View screens with no data
- ✅ Dashboard: Shows 0 counts gracefully
- ✅ Employees: Shows "لا يوجد موظفون" message
- ✅ Requests: Shows "لا توجد طلبات" message
- ✅ Attendance Table: Shows "لا توجد سجلات" message

### 2. Very Long Names
**Test**: Add employee with 50-character name
- ✅ UI handles long text
- ✅ Text wraps or ellipsis
- ✅ No layout breaks

### 3. Special Characters
**Test**: Add employee with Arabic/English mixed name
- ✅ Supports both languages
- ✅ Text displays correctly
- ✅ Search works

---

## Regression Tests

After each update, verify:
- [ ] Login still works for all roles
- [ ] Employee can check in/out
- [ ] Requests can be created
- [ ] Owner can approve/reject
- [ ] Filters work
- [ ] Data persists after logout
- [ ] No console errors

---

## Test Results Template

```
Date: _______________
Tester: _______________

Dashboard: ☐ Pass ☐ Fail
Notes: _______________

Employee Management: ☐ Pass ☐ Fail
Notes: _______________

Leave Requests: ☐ Pass ☐ Fail
Notes: _______________

Attendance Requests: ☐ Pass ☐ Fail
Notes: _______________

Salary Advances: ☐ Pass ☐ Fail
Notes: _______________

Attendance Table: ☐ Pass ☐ Fail
Notes: _______________

Overall Status: ☐ Ready for Production ☐ Needs Fixes
```

---

## Automated Testing (Future)

Consider adding:
- Unit tests for services
- Widget tests for screens
- Integration tests for flows
- E2E tests with test data

---

**Total Testing Time**: ~40 minutes  
**Coverage**: All major features + edge cases  
**Tools Needed**: Flutter app, Supabase access, Test accounts  

Happy Testing! 🎉
