const String API_BASE_URL = 'https://[your-repl-name].repl.co/api';

// Auth
const String LOGIN_ENDPOINT = '$API_BASE_URL/auth/login';

// Attendance
const String CHECK_IN_ENDPOINT = '$API_BASE_URL/attendance/check-in';
const String CHECK_OUT_ENDPOINT = '$API_BASE_URL/attendance/check-out';
const String ATTENDANCE_REQUEST_CHECKIN_ENDPOINT =
	'$API_BASE_URL/attendance/request-checkin';
const String ATTENDANCE_REQUEST_CHECKOUT_ENDPOINT =
	'$API_BASE_URL/attendance/request-checkout';
const String ATTENDANCE_REQUESTS_ENDPOINT =
	'$API_BASE_URL/attendance/requests';
const String ATTENDANCE_REPORT_ENDPOINT =
	'$API_BASE_URL/reports/attendance';

// Pulses
const String PULSE_ENDPOINT = '$API_BASE_URL/pulses';

// Leave & Advances
const String LEAVE_REQUEST_ENDPOINT = '$API_BASE_URL/leave/request';
const String LEAVE_REQUESTS_ENDPOINT = '$API_BASE_URL/leave/requests';
const String ADVANCE_REQUEST_ENDPOINT = '$API_BASE_URL/advances/request';
const String ADVANCES_ENDPOINT = '$API_BASE_URL/advances';

// Employees & dashboard
const String EMPLOYEES_ENDPOINT = '$API_BASE_URL/employees';
const String MANAGER_DASHBOARD_ENDPOINT = '$API_BASE_URL/manager/dashboard';
const String PAYROLL_CALCULATE_ENDPOINT = '$API_BASE_URL/payroll/calculate';
