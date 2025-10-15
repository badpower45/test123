const String API_BASE_URL = 'https://[your-repl-name].repl.co/api';
const String ROOT_BASE_URL = 'https://[your-repl-name].repl.co';

// General
const String HEALTH_CHECK_ENDPOINT = '$ROOT_BASE_URL/health';

// Auth
const String LOGIN_ENDPOINT = '$API_BASE_URL/auth/login';

// Attendance
const String CHECK_IN_ENDPOINT = '$API_BASE_URL/attendance/check-in';
const String CHECK_OUT_ENDPOINT = '$API_BASE_URL/attendance/check-out';
const String ATTENDANCE_REQUEST_CHECKIN_ENDPOINT = '$API_BASE_URL/attendance/request-checkin';
const String ATTENDANCE_REQUEST_CHECKOUT_ENDPOINT = '$API_BASE_URL/attendance/request-checkout';
const String ATTENDANCE_REQUESTS_ENDPOINT = '$API_BASE_URL/attendance/requests';
const String ATTENDANCE_REQUEST_REVIEW_ENDPOINT = '$API_BASE_URL/attendance/requests/:requestId/review';

// Attendance reports
const String ATTENDANCE_REPORT_ENDPOINT = '$API_BASE_URL/reports/attendance/:employeeId';

// Pulses
const String PULSE_ENDPOINT = '$API_BASE_URL/pulses';

// Leave requests
const String LEAVE_REQUEST_ENDPOINT = '$API_BASE_URL/leave/request';
const String LEAVE_REQUESTS_ENDPOINT = '$API_BASE_URL/leave/requests';
const String LEAVE_REQUEST_REVIEW_ENDPOINT = '$API_BASE_URL/leave/requests/:requestId/review';

// Advances
const String ADVANCE_REQUEST_ENDPOINT = '$API_BASE_URL/advances/request';
const String ADVANCES_ENDPOINT = '$API_BASE_URL/advances';
const String ADVANCE_REVIEW_ENDPOINT = '$API_BASE_URL/advances/:advanceId/review';

// Absence & deductions
const String ABSENCE_NOTIFY_ENDPOINT = '$API_BASE_URL/absence/notify';
const String ABSENCE_NOTIFICATIONS_ENDPOINT = '$API_BASE_URL/absence/notifications';
const String ABSENCE_APPLY_DEDUCTION_ENDPOINT = '$API_BASE_URL/absence/:notificationId/apply-deduction';

// Employees
const String EMPLOYEES_ENDPOINT = '$API_BASE_URL/employees';
const String EMPLOYEE_DETAILS_ENDPOINT = '$API_BASE_URL/employees/:id';
const String EMPLOYEE_CURRENT_EARNINGS_ENDPOINT =
	'$API_BASE_URL/employees/:employeeId/current-earnings';

// Branches
const String BRANCHES_ENDPOINT = '$API_BASE_URL/branches';
const String BRANCH_ASSIGN_MANAGER_ENDPOINT =
	'$API_BASE_URL/branches/:branchId/assign-manager';
const String BRANCH_EMPLOYEES_ENDPOINT =
	'$API_BASE_URL/branches/:branchId/employees';

// Breaks
const String BREAKS_ENDPOINT = '$API_BASE_URL/breaks';
const String BREAK_REQUEST_ENDPOINT = '$API_BASE_URL/breaks/request';
const String BREAK_REVIEW_ENDPOINT = '$API_BASE_URL/breaks/:breakId/review';
const String BREAK_START_ENDPOINT = '$API_BASE_URL/breaks/:breakId/start';
const String BREAK_END_ENDPOINT = '$API_BASE_URL/breaks/:breakId/end';

// Manager dashboard
const String MANAGER_DASHBOARD_ENDPOINT = '$API_BASE_URL/manager/dashboard';

// Payroll
const String PAYROLL_CALCULATE_ENDPOINT = '$API_BASE_URL/payroll/calculate';
