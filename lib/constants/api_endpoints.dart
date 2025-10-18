// استخدم عنوان خادم AWS في هذا الوضع
// Production AWS EC2 Server
const String API_BASE_URL = 'http://16.171.208.249:5000/api';
const String ROOT_BASE_URL = 'http://16.171.208.249:5000';

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
const String LEAVE_REQUESTS_DELETE_REJECTED_ENDPOINT =
	'$API_BASE_URL/leave/requests/delete-rejected';

// Advances
const String ADVANCE_REQUEST_ENDPOINT = '$API_BASE_URL/advances/request';
const String ADVANCES_ENDPOINT = '$API_BASE_URL/advances';
const String ADVANCE_REVIEW_ENDPOINT = '$API_BASE_URL/advances/:advanceId/review';
const String ADVANCES_DELETE_REJECTED_ENDPOINT =
	'$API_BASE_URL/advances/delete-rejected';

// Absence & deductions
const String ABSENCE_NOTIFY_ENDPOINT = '$API_BASE_URL/absence/notify';
const String ABSENCE_NOTIFICATIONS_ENDPOINT = '$API_BASE_URL/absence/notifications';
const String ABSENCE_APPLY_DEDUCTION_ENDPOINT = '$API_BASE_URL/absence/:notificationId/apply-deduction';

// Employees
const String EMPLOYEES_ENDPOINT = '$API_BASE_URL/employees';
const String CURRENT_EARNINGS_ENDPOINT = '$API_BASE_URL/employees';
const String EMPLOYEE_DETAILS_ENDPOINT = '$API_BASE_URL/employees/:id';

// Branches
const String BRANCHES_ENDPOINT = '$API_BASE_URL/branches';
const String BRANCH_ASSIGN_MANAGER_ENDPOINT =
	'$API_BASE_URL/branches/:branchId/assign-manager';
const String BRANCH_EMPLOYEES_ENDPOINT =
	'$API_BASE_URL/branches/:branchId/employees';

// Breaks
const String BREAKS_ENDPOINT = '$API_BASE_URL/breaks';
const String BREAKS_REQUEST_ENDPOINT = '$API_BASE_URL/breaks/request';
const String BREAK_REVIEW_ENDPOINT = '$API_BASE_URL/breaks/:breakId/review';
const String BREAK_START_ENDPOINT = '$API_BASE_URL/breaks/:breakId/start';
const String BREAK_END_ENDPOINT = '$API_BASE_URL/breaks/:breakId/end';
const String SHIFT_STATUS_ENDPOINT = '$API_BASE_URL/shifts/status';

// Manager profile
const String MANAGER_PROFILE_ENDPOINT = '$API_BASE_URL/manager/profile';

// Owner dashboard
const String OWNER_MANAGER_REQUESTS_ENDPOINT =
	'$API_BASE_URL/owner/manager-requests';
const String OWNER_MANAGER_REQUEST_REVIEW_ENDPOINT =
	'$API_BASE_URL/owner/manager-requests/:requestId/review';
const String OWNER_HOURLY_RATES_ENDPOINT = '$API_BASE_URL/owner/hourly-rates';
const String OWNER_EMPLOYEE_HOURLY_RATE_ENDPOINT =
	'$API_BASE_URL/owner/employees/:employeeId/hourly-rate';
const String OWNER_PEOPLE_DIRECTORY_ENDPOINT = '$API_BASE_URL/owner/people';
const String OWNER_PERSON_PROFILE_ENDPOINT = '$API_BASE_URL/owner/people/:personId';
const String OWNER_FINANCIAL_REPORT_ENDPOINT = '$API_BASE_URL/owner/financial-report';

// Manager dashboard
const String MANAGER_DASHBOARD_ENDPOINT = '$API_BASE_URL/manager/dashboard';

// Payroll
const String PAYROLL_CALCULATE_ENDPOINT = '$API_BASE_URL/payroll/calculate';
