// Deployed server
const String apiBaseUrl = 'http://16.171.208.249:5000/api';
const String rootBaseUrl = 'http://16.171.208.249:5000';

// General
const String healthCheckEndpoint = '$rootBaseUrl/health';

// Auth
const String loginEndpoint = '$apiBaseUrl/auth/login';

// Attendance
const String checkInEndpoint = '$apiBaseUrl/attendance/check-in';
const String checkOutEndpoint = '$apiBaseUrl/attendance/check-out';
const String attendanceRequestCheckinEndpoint = '$apiBaseUrl/attendance/request-checkin';
const String attendanceRequestCheckoutEndpoint = '$apiBaseUrl/attendance/request-checkout';
const String attendanceRequestsEndpoint = '$apiBaseUrl/attendance/requests';
const String attendanceRequestReviewEndpoint = '$apiBaseUrl/attendance/requests/:requestId/review';

// Attendance reports
const String attendanceReportEndpoint = '$apiBaseUrl/reports/attendance/:employeeId';

// Pulses
const String pulseEndpoint = '$apiBaseUrl/pulses';

// Leave requests
const String leaveRequestEndpoint = '$apiBaseUrl/leave/request';
const String leaveRequestsEndpoint = '$apiBaseUrl/leave/requests';
const String leaveRequestReviewEndpoint = '$apiBaseUrl/leave/requests/:requestId/review';
const String leaveRequestsDeleteRejectedEndpoint =
	'$apiBaseUrl/leave/requests/delete-rejected';

// Advances
const String advanceRequestEndpoint = '$apiBaseUrl/advances/request';
const String advancesEndpoint = '$apiBaseUrl/advances';
const String advanceReviewEndpoint = '$apiBaseUrl/advances/:advanceId/review';
const String advancesDeleteRejectedEndpoint =
	'$apiBaseUrl/advances/delete-rejected';

// Absence & deductions
const String absenceNotifyEndpoint = '$apiBaseUrl/absence/notify';
const String absenceNotificationsEndpoint = '$apiBaseUrl/absence/notifications';
const String absenceApplyDeductionEndpoint = '$apiBaseUrl/absence/:notificationId/apply-deduction';

// Employees
const String employeesEndpoint = '$apiBaseUrl/employees';
const String currentEarningsEndpoint = '$apiBaseUrl/employees';
const String employeeDetailsEndpoint = '$apiBaseUrl/employees/:id';

// Branches
const String branchesEndpoint = '$apiBaseUrl/branches';
const String branchAssignManagerEndpoint =
	'$apiBaseUrl/branches/:branchId/assign-manager';
const String branchEmployeesEndpoint =
	'$apiBaseUrl/branches/:branchId/employees';

// Breaks
const String breaksEndpoint = '$apiBaseUrl/breaks';
const String breaksRequestEndpoint = '$apiBaseUrl/breaks/request';
const String breakReviewEndpoint = '$apiBaseUrl/breaks/:breakId/review';
const String breakStartEndpoint = '$apiBaseUrl/breaks/:breakId/start';
const String breakEndEndpoint = '$apiBaseUrl/breaks/:breakId/end';
const String shiftStatusEndpoint = '$apiBaseUrl/shifts/status';

// Manager profile
const String managerProfileEndpoint = '$apiBaseUrl/manager/profile';

// Owner dashboard
const String ownerDashboardEndpoint = '$apiBaseUrl/owner/dashboard';
const String ownerEmployeesOverviewEndpoint = '$apiBaseUrl/owner/employees';
const String ownerEmployeeHourlyRateEndpoint =
  '$apiBaseUrl/owner/employees/:employeeId/hourly-rate';
const String ownerPayrollSummaryEndpoint = '$apiBaseUrl/owner/payroll/summary';

// Manager dashboard
const String managerDashboardEndpoint = '$apiBaseUrl/manager/dashboard';

// Payroll
const String payrollCalculateEndpoint = '$apiBaseUrl/payroll/calculate';
