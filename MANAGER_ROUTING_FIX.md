# Manager Branch Routing & Request Assignment Fix

## Overview
Fixed two critical issues in the manager workflow:
1. **Manager loads wrong branch** when navigating from employee_main_screen to dashboard
2. **Leave, Advance, and Attendance requests** not routing to managers despite working break requests

## Root Causes

### Issue 1: Manager Dashboard Wrong Branch
**Problem:** When a manager user navigated to their dashboard, the system would query `employees.branch` instead of querying the `branches.manager_id` relationship.

**Root Cause:** `_resolveManagerBranch()` in `employee_main_screen.dart` was using:
```dart
await SupabaseAttendanceService.getEmployeeStatus(widget.employeeId)
```
This returns the manager's personal employee data (which may have a generic branch), not their assigned manager branch.

**Solution:** 
- Changed to query `branches` table directly with `WHERE manager_id = widget.employeeId`
- Falls back to employee data if no branch found via manager_id
- Now correctly resolves to the branch the manager actually manages

### Issue 2: Request Routing Not Working
**Problem:** 
- Break requests correctly assigned to `assigned_manager_id` ✅
- Leave requests assigned but manager couldn't see them ❌
- Advance requests assigned but manager couldn't see them ❌
- Attendance requests assigned but manager couldn't see them ❌

**Root Causes:**
1. `submitAdvanceRequest()` was using old HTTP endpoint (with empty `apiBaseUrl`) instead of `SupabaseRequestsService`
2. `fetchAdvanceRequests()` was also using old HTTP endpoints
3. Manager UI screens were filtering by `branchName` instead of `assigned_manager_id`

**Solution:**
- Migrated `submitAdvanceRequest()` to use `SupabaseRequestsService.createSalaryAdvanceRequest()` 
- Migrated `fetchAdvanceRequests()` to use `SupabaseRequestsService.getSalaryAdvanceRequests()`
- Updated all manager request tabs to filter by `managerId` instead of `branchName`:
  - `ManagerLeaveRequestsTab` - now uses `managerId` filter
  - `ManagerAdvanceRequestsTab` - now uses `managerId` filter
  - `ManagerAttendanceRequestsTab` - now uses `managerId` filter

## Files Changed

### Backend Services
**File:** [lib/services/supabase_attendance_service.dart](lib/services/supabase_attendance_service.dart)
- Added public getter `static SupabaseClient get client => _supabase;` for manager branch resolution

**File:** [lib/services/requests_api_service.dart](lib/services/requests_api_service.dart)
- Changed `submitAdvanceRequest()` to use `SupabaseRequestsService.createSalaryAdvanceRequest()`
- Changed `fetchAdvanceRequests()` to use `SupabaseRequestsService.getSalaryAdvanceRequests()`

### Manager UI Screens
**File:** [lib/screens/employee/employee_main_screen.dart](lib/screens/employee/employee_main_screen.dart)
- Rewrote `_resolveManagerBranch()` to:
  1. Query `branches` table directly: `WHERE manager_id = widget.employeeId`
  2. Fall back to employee.branch if no branch found
  3. Correctly resolves manager's assigned branch on first load

**File:** [lib/screens/manager/manager_leave_requests_tab.dart](lib/screens/manager/manager_leave_requests_tab.dart)
- Changed `_loadRequests()` to filter by `managerId` instead of `branchName`
- Removed unnecessary employee status query

**File:** [lib/screens/manager/manager_advance_requests_tab.dart](lib/screens/manager/manager_advance_requests_tab.dart)
- Changed `_loadRequests()` to filter by `managerId` instead of `branchName`
- Removed unnecessary employee status query

**File:** [lib/screens/manager/manager_attendance_requests_tab.dart](lib/screens/manager/manager_attendance_requests_tab.dart)
- Changed `_loadRequests()` to filter by `managerId` instead of `branchName`
- Removed unnecessary employee status query

## Request Routing Architecture

Now all request types follow the same pattern:

```
Employee submits request
    ↓
Service resolves assigned_manager_id using _resolveManagerId()
    ├─ Priority 1: branches.manager_id (official branch manager)
    ├─ Priority 2: Active manager in same branch_id
    └─ Priority 3: Any active manager
    ↓
Request stored with assigned_manager_id field
    ↓
Manager dashboard queries with WHERE assigned_manager_id = ?
    ↓
Manager sees request in their queue
```

Supported request types with `assigned_manager_id`:
- ✅ Break requests (breaks table) 
- ✅ Leave requests (leave_requests table)
- ✅ Salary advances (salary_advances table)
- ✅ Attendance requests (attendance_requests table)

## Testing Checklist

- [ ] Manager navigates from employee_main_screen → loanches ManagerDashboardSimple with correct branch
- [ ] Print logs show "Found branch via manager_id: [branchName]"
- [ ] Employee submits leave request → assigned_manager_id populated
- [ ] Employee submits advance request → assigned_manager_id populated
- [ ] Employee submits attendance request → assigned_manager_id populated
- [ ] Manager sees all 4 request types in their dashboard:
  - [ ] Pending leave requests
  - [ ] Pending advance requests
  - [ ] Pending attendance requests
  - [ ] Pending break requests
- [ ] Manager can approve/reject each request type
- [ ] No "Branch is empty" errors in manager screens

## Deployment Steps

1. **Rebuild Flutter app:**
   ```bash
   flutter clean
   flutter pub get
   flutter build apk --flavor full
   ```

2. **No backend changes needed** - All edge functions already support this pattern

3. **Deploy to device:**
   ```bash
   flutter install -d [device_id]
   ```

## Backward Compatibility

- Existing requests without `assigned_manager_id` are handled by edge function backfill
- Break requests in `manager-pending-requests` auto-assign if missing assignment
- Manager queries use direct assignment rather than branch name (more reliable)

## Related Issues Fixed

- ✅ [Phase 4] Manager dashboard navigation loads wrong branch
- ✅ [Phase 4] Leave requests not reaching manager
- ✅ [Phase 4] Advance requests not reaching manager  
- ✅ [Phase 4] Attendance requests not reaching manager
- ✅ [Legacy] HTTP endpoints for advances disabled (empty `apiBaseUrl`)

## Performance Notes

- Branch resolution on manager login: 1 DB query (direct index lookup on `manager_id`)
- Request loading: Uses existing `assigned_manager_id` index (no N+1 queries)
- Client-side filtering by `managerId` (exact match, not branch name string matching)
