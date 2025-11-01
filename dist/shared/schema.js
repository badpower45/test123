import { pgTable, uuid, text, timestamp, boolean, numeric, index, doublePrecision, pgEnum, integer, date } from 'drizzle-orm/pg-core';
import { sql } from 'drizzle-orm';
// User role enum for multi-branch
export const userRoleEnum = pgEnum('user_role', ['OWNER', 'MANAGER', 'EMPLOYEE']);
// Legacy employee role enum (kept for compatibility)
export const employeeRoleEnum = pgEnum('employee_role', ['owner', 'admin', 'manager', 'hr', 'monitor', 'staff']);
// =============================================================================
// BRANCHES TABLE - Multi-branch management
// =============================================================================
export const branches = pgTable('branches', {
    id: uuid('id').primaryKey().defaultRandom(),
    name: text('name').notNull(),
    managerId: text('manager_id'), // Use string reference to avoid circular dependency
    latitude: numeric('latitude'),
    longitude: numeric('longitude'),
    geofenceRadius: integer('geofence_radius').default(100),
    bssid_1: text('bssid_1'),
    bssid_2: text('bssid_2').default(null),
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => ({
    nameIdx: index('idx_branches_name').on(table.name),
}));
// Request status enum
export const requestStatusEnum = pgEnum('request_status', ['pending', 'approved', 'rejected']);
// Leave type enum
export const leaveTypeEnum = pgEnum('leave_type', ['regular', 'emergency']);
// Employees table - directory of restaurant employees
export const employees = pgTable('employees', {
    id: text('id').primaryKey(),
    fullName: text('full_name').notNull(),
    pinHash: text('pin_hash').notNull(),
    role: employeeRoleEnum('role').default('staff').notNull(),
    permissions: text('permissions').array().default(sql `'{}'`),
    branch: text('branch'),
    branchId: uuid('branch_id').references(() => branches.id),
    monthlySalary: numeric('monthly_salary'),
    hourlyRate: numeric('hourly_rate'),
    shiftStartTime: text('shift_start_time'), // e.g., '09:00' or '21:00'
    shiftEndTime: text('shift_end_time'), // e.g., '17:00' or '05:00'
    shiftType: text('shift_type'), // 'AM' or 'PM'
    active: boolean('active').default(true).notNull(),
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => ({
    branchIdIdx: index('idx_employees_branch_id').on(table.branchId),
}));
// Attendance table - daily check-in/check-out records
export const attendance = pgTable('attendance', {
    id: uuid('id').primaryKey().defaultRandom(),
    employeeId: text('employee_id').notNull().references(() => employees.id, { onDelete: 'cascade' }),
    checkInTime: timestamp('check_in_time', { withTimezone: true }),
    checkOutTime: timestamp('check_out_time', { withTimezone: true }),
    actualCheckInTime: timestamp('actual_check_in_time', { withTimezone: true }), // الوقت الفعلي للحضور
    modifiedCheckInTime: timestamp('modified_check_in_time', { withTimezone: true }), // الوقت المعدل
    modifiedBy: text('modified_by'), // Can be employee ID or role string
    modifiedAt: timestamp('modified_at', { withTimezone: true }),
    modificationReason: text('modification_reason'),
    workHours: numeric('work_hours'),
    date: date('date').notNull(),
    status: text('status').default('active').notNull(),
    isAutoCheckout: boolean('is_auto_checkout').default(false),
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => ({
    employeeIdIdx: index('idx_attendance_employee_id').on(table.employeeId),
    dateIdx: index('idx_attendance_date').on(table.date),
}));
// Attendance requests - for forgotten check-in/out
export const attendanceRequests = pgTable('attendance_requests', {
    id: uuid('id').primaryKey().defaultRandom(),
    employeeId: text('employee_id').notNull().references(() => employees.id, { onDelete: 'cascade' }),
    requestType: text('request_type').notNull(),
    requestedTime: timestamp('requested_time', { withTimezone: true }).notNull(),
    reason: text('reason').notNull(),
    status: requestStatusEnum('status').default('pending').notNull(),
    reviewedBy: text('reviewed_by'), // Can be employee ID or user ID
    reviewedAt: timestamp('reviewed_at', { withTimezone: true }),
    reviewNotes: text('review_notes'),
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => ({
    employeeIdIdx: index('idx_attendance_requests_employee_id').on(table.employeeId),
    statusIdx: index('idx_attendance_requests_status').on(table.status),
}));
// Leave requests table
export const leaveRequests = pgTable('leave_requests', {
    id: uuid('id').primaryKey().defaultRandom(),
    employeeId: text('employee_id').notNull().references(() => employees.id, { onDelete: 'cascade' }),
    startDate: date('start_date').notNull(),
    endDate: date('end_date').notNull(),
    leaveType: leaveTypeEnum('leave_type').notNull(),
    reason: text('reason'),
    daysCount: integer('days_count').notNull(),
    allowanceAmount: numeric('allowance_amount').default('0'),
    status: requestStatusEnum('status').default('pending').notNull(),
    reviewedBy: text('reviewed_by'), // Can be employee ID or user ID
    reviewedAt: timestamp('reviewed_at', { withTimezone: true }),
    reviewNotes: text('review_notes'),
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => ({
    employeeIdIdx: index('idx_leave_requests_employee_id').on(table.employeeId),
    statusIdx: index('idx_leave_requests_status').on(table.status),
    startDateIdx: index('idx_leave_requests_start_date').on(table.startDate),
}));
// Advances (salary advance) table
export const advances = pgTable('advances', {
    id: uuid('id').primaryKey().defaultRandom(),
    employeeId: text('employee_id').notNull().references(() => employees.id, { onDelete: 'cascade' }),
    amount: numeric('amount').notNull(),
    requestDate: timestamp('request_date', { withTimezone: true }).defaultNow().notNull(),
    eligibleAmount: numeric('eligible_amount').notNull(),
    currentSalary: numeric('current_salary').notNull(),
    status: requestStatusEnum('status').default('pending').notNull(),
    reviewedBy: text('reviewed_by'), // Can be employee ID or user ID
    reviewedAt: timestamp('reviewed_at', { withTimezone: true }),
    paidAt: timestamp('paid_at', { withTimezone: true }),
    deductedAt: timestamp('deducted_at', { withTimezone: true }),
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => ({
    employeeIdIdx: index('idx_advances_employee_id').on(table.employeeId),
    statusIdx: index('idx_advances_status').on(table.status),
    requestDateIdx: index('idx_advances_request_date').on(table.requestDate),
}));
// Deductions table
export const deductions = pgTable('deductions', {
    id: uuid('id').primaryKey().defaultRandom(),
    employeeId: text('employee_id').notNull().references(() => employees.id, { onDelete: 'cascade' }),
    amount: numeric('amount').notNull(),
    reason: text('reason').notNull(),
    deductionDate: date('deduction_date').notNull(),
    deductionType: text('deduction_type').notNull(),
    appliedBy: text('applied_by'), // Can be employee ID or user ID
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => ({
    employeeIdIdx: index('idx_deductions_employee_id').on(table.employeeId),
    dateIdx: index('idx_deductions_date').on(table.deductionDate),
}));
// Absence notifications table
export const absenceNotifications = pgTable('absence_notifications', {
    id: uuid('id').primaryKey().defaultRandom(),
    employeeId: text('employee_id').notNull().references(() => employees.id, { onDelete: 'cascade' }),
    absenceDate: date('absence_date').notNull(),
    notifiedAt: timestamp('notified_at', { withTimezone: true }).defaultNow().notNull(),
    status: requestStatusEnum('status').default('pending').notNull(),
    deductionApplied: boolean('deduction_applied').default(false),
    deductionAmount: numeric('deduction_amount'),
    reviewedBy: text('reviewed_by'), // Can be employee ID or user ID
    reviewedAt: timestamp('reviewed_at', { withTimezone: true }),
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => ({
    employeeIdIdx: index('idx_absence_notifications_employee_id').on(table.employeeId),
    statusIdx: index('idx_absence_notifications_status').on(table.status),
    dateIdx: index('idx_absence_notifications_date').on(table.absenceDate),
}));
// =============================================================================
// GEOFENCE VIOLATIONS - مخالفات النطاق الجغرافي
// =============================================================================
export const geofenceViolations = pgTable('geofence_violations', {
    id: uuid('id').primaryKey().defaultRandom(),
    employeeId: text('employee_id').notNull().references(() => employees.id, { onDelete: 'cascade' }),
    branchId: uuid('branch_id').references(() => branches.id, { onDelete: 'set null' }),
    exitTime: timestamp('exit_time', { withTimezone: true }).notNull(),
    enterTime: timestamp('enter_time', { withTimezone: true }),
    durationSeconds: integer('duration_seconds'),
    latitude: doublePrecision('latitude'),
    longitude: doublePrecision('longitude'),
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => ({
    employeeIdIdx: index('idx_geofence_violations_employee_id').on(table.employeeId),
    exitTimeIdx: index('idx_geofence_violations_exit_time').on(table.exitTime),
}));
// Pulses table - location tracking (updated for multi-branch)
export const pulses = pgTable('pulses', {
    id: uuid('id').primaryKey().defaultRandom(),
    employeeId: text('employee_id').notNull().references(() => employees.id, { onDelete: 'cascade' }),
    branchId: uuid('branch_id').references(() => branches.id, { onDelete: 'cascade' }),
    timestamp: timestamp('timestamp', { withTimezone: true }).defaultNow().notNull(),
    latitude: doublePrecision('latitude'),
    longitude: doublePrecision('longitude'),
    location: text('location'),
    bssidAddress: text('bssid_address'),
    isWithinGeofence: boolean('is_within_geofence').default(false),
    isFake: boolean('is_fake').default(false).notNull(),
    isSynced: boolean('is_synced').default(true),
    sentFromDevice: boolean('sent_from_device').default(true).notNull(),
    sentViaSupabase: boolean('sent_via_supabase').default(false).notNull(),
    offlineBatchId: uuid('offline_batch_id'),
    source: text('source'),
    status: text('status').default('IN'),
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => ({
    employeeIdIdx: index('idx_pulses_employee_id').on(table.employeeId),
    branchIdIdx: index('idx_pulses_branch_id').on(table.branchId),
    timestampIdx: index('idx_pulses_timestamp').on(table.timestamp),
    latLonIdx: index('idx_pulses_latitude_longitude').on(table.latitude, table.longitude),
    geofenceIdx: index('idx_pulses_geofence').on(table.isWithinGeofence),
    createdAtIdx: index('idx_pulses_created_at').on(table.createdAt),
}));
// Legacy profiles table (kept for compatibility)
export const profiles = pgTable('profiles', {
    id: uuid('id').primaryKey(),
    fullName: text('full_name').notNull(),
    employeeId: text('employee_id').unique().notNull(),
    role: text('role').default('employee').notNull(),
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow(),
}, (table) => ({
    employeeIdIdx: index('idx_profiles_employee_id').on(table.employeeId),
    roleIdx: index('idx_profiles_role').on(table.role),
}));
// Legacy shifts table (kept for compatibility)
export const shifts = pgTable('shifts', {
    id: uuid('id').primaryKey().defaultRandom(),
    userId: uuid('user_id').notNull().references(() => profiles.id, { onDelete: 'cascade' }),
    checkInTime: timestamp('check_in_time', { withTimezone: true }).defaultNow(),
    checkOutTime: timestamp('check_out_time', { withTimezone: true }),
    status: text('status').default('active').notNull(),
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow(),
}, (table) => ({
    userIdIdx: index('idx_shifts_user_id').on(table.userId),
    statusIdx: index('idx_shifts_status').on(table.status),
    checkInTimeIdx: index('idx_shifts_check_in_time').on(table.checkInTime),
}));
// =============================================================================
// USERS TABLE - Multi-branch users
// =============================================================================
export const users = pgTable('users', {
    id: uuid('id').primaryKey().defaultRandom(),
    username: text('username').unique().notNull(),
    passwordHash: text('password_hash').notNull(),
    role: userRoleEnum('role').notNull(),
    branchId: uuid('branch_id').references(() => branches.id),
    fullName: text('full_name').notNull(),
    email: text('email').unique(),
    isActive: boolean('is_active').default(true),
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow(),
}, (table) => ({
    usernameIdx: index('idx_users_username').on(table.username),
    roleIdx: index('idx_users_role').on(table.role),
    branchIdIdx: index('idx_users_branch_id').on(table.branchId),
}));
// =============================================================================
// ADMIN USERS AND PERMISSIONS (Legacy - kept for compatibility)
// =============================================================================
// Legacy admin users table
export const adminUsers = pgTable('admin_users', {
    id: uuid('id').primaryKey().defaultRandom(),
    email: text('email').unique().notNull(),
    passwordHash: text('password_hash').notNull(),
    fullName: text('full_name').notNull(),
    isActive: boolean('is_active').default(true),
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow(),
}, (table) => ({
    emailIdx: index('idx_admin_users_email').on(table.email),
    isActiveIdx: index('idx_admin_users_is_active').on(table.isActive),
}));
// Roles table
export const roles = pgTable('roles', {
    id: uuid('id').primaryKey().defaultRandom(),
    name: text('name').unique().notNull(),
    nameAr: text('name_ar').notNull(),
    description: text('description'),
    isSystemRole: boolean('is_system_role').default(false),
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow(),
}, (table) => ({
    nameIdx: index('idx_roles_name').on(table.name),
}));
// Permissions table
export const permissions = pgTable('permissions', {
    id: uuid('id').primaryKey().defaultRandom(),
    name: text('name').unique().notNull(),
    nameAr: text('name_ar').notNull(),
    description: text('description'),
    category: text('category').notNull(),
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
}, (table) => ({
    nameIdx: index('idx_permissions_name').on(table.name),
    categoryIdx: index('idx_permissions_category').on(table.category),
}));
// Role-Permissions junction table
export const rolePermissions = pgTable('role_permissions', {
    id: uuid('id').primaryKey().defaultRandom(),
    roleId: uuid('role_id').notNull().references(() => roles.id, { onDelete: 'cascade' }),
    permissionId: uuid('permission_id').notNull().references(() => permissions.id, { onDelete: 'cascade' }),
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
}, (table) => ({
    roleIdIdx: index('idx_role_permissions_role_id').on(table.roleId),
    permissionIdIdx: index('idx_role_permissions_permission_id').on(table.permissionId),
}));
// User-Roles junction table
export const userRoles = pgTable('user_roles', {
    id: uuid('id').primaryKey().defaultRandom(),
    userId: uuid('user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
    roleId: uuid('role_id').notNull().references(() => roles.id, { onDelete: 'cascade' }),
    assignedAt: timestamp('assigned_at', { withTimezone: true }).defaultNow(),
    assignedBy: uuid('assigned_by').references(() => users.id),
}, (table) => ({
    userIdIdx: index('idx_user_roles_user_id').on(table.userId),
    roleIdIdx: index('idx_user_roles_role_id').on(table.roleId),
}));
// Branch_BSSIDs table - Multiple BSSIDs per branch
export const branchBssids = pgTable('branch_bssids', {
    id: uuid('id').primaryKey().defaultRandom(),
    branchId: uuid('branch_id').notNull().references(() => branches.id, { onDelete: 'cascade' }),
    bssidAddress: text('bssid_address').notNull(),
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
}, (table) => ({
    branchIdIdx: index('idx_branch_bssids_branch_id').on(table.branchId),
    bssidAddressIdx: index('idx_branch_bssids_bssid_address').on(table.bssidAddress),
}));
// Legacy Branch-Managers junction table (kept for compatibility)
export const branchManagers = pgTable('branch_managers', {
    id: uuid('id').primaryKey().defaultRandom(),
    employeeId: text('employee_id').notNull().references(() => employees.id, { onDelete: 'cascade' }),
    branchId: uuid('branch_id').notNull().references(() => branches.id, { onDelete: 'cascade' }),
    assignedAt: timestamp('assigned_at', { withTimezone: true }).defaultNow(),
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => ({
    employeeIdIdx: index('idx_branch_managers_employee_id').on(table.employeeId),
    branchIdIdx: index('idx_branch_managers_branch_id').on(table.branchId),
}));
// =============================================================================
// BREAKS TABLE - Break Management System
// =============================================================================
export const breakStatusEnum = pgEnum('break_status', ['PENDING', 'APPROVED', 'REJECTED', 'ACTIVE', 'COMPLETED', 'POSTPONED']);
export const breaks = pgTable('breaks', {
    id: uuid('id').primaryKey().defaultRandom(),
    shiftId: uuid('shift_id').references(() => shifts.id, { onDelete: 'cascade' }),
    employeeId: text('employee_id').notNull().references(() => employees.id, { onDelete: 'cascade' }),
    requestedDurationMinutes: integer('requested_duration_minutes').notNull(),
    status: breakStatusEnum('status').default('PENDING').notNull(),
    startTime: timestamp('start_time', { withTimezone: true }),
    endTime: timestamp('end_time', { withTimezone: true }),
    approvedBy: text('approved_by').references(() => employees.id),
    // Payout fields for postponed breaks
    payoutEligible: boolean('payout_eligible').default(false).notNull(),
    payoutApplied: boolean('payout_applied').default(false).notNull(),
    payoutAppliedAt: timestamp('payout_applied_at', { withTimezone: true }),
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => ({
    shiftIdIdx: index('idx_breaks_shift_id').on(table.shiftId),
    employeeIdIdx: index('idx_breaks_employee_id').on(table.employeeId),
    statusIdx: index('idx_breaks_status').on(table.status),
}));
// =============================================================================
// DEVICE SESSIONS - Single Device Login Management
// =============================================================================
export const deviceSessions = pgTable('device_sessions', {
    id: uuid('id').primaryKey().defaultRandom(),
    employeeId: text('employee_id').notNull().references(() => employees.id, { onDelete: 'cascade' }),
    deviceId: text('device_id').notNull(),
    deviceName: text('device_name'),
    deviceModel: text('device_model'),
    osVersion: text('os_version'),
    appVersion: text('app_version'),
    lastActiveAt: timestamp('last_active_at', { withTimezone: true }).defaultNow().notNull(),
    isActive: boolean('is_active').default(true).notNull(),
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => ({
    employeeIdIdx: index('idx_device_sessions_employee_id').on(table.employeeId),
    deviceIdIdx: index('idx_device_sessions_device_id').on(table.deviceId),
    isActiveIdx: index('idx_device_sessions_is_active').on(table.isActive),
}));
// =============================================================================
// NOTIFICATIONS - Real-time notifications system
// =============================================================================
export const notificationTypeEnum = pgEnum('notification_type', [
    'CHECK_IN',
    'CHECK_OUT',
    'LEAVE_REQUEST',
    'ADVANCE_REQUEST',
    'ATTENDANCE_REQUEST',
    'ABSENCE_ALERT',
    'SALARY_PAID',
    'GENERAL'
]);
export const notifications = pgTable('notifications', {
    id: uuid('id').primaryKey().defaultRandom(),
    recipientId: text('recipient_id').notNull().references(() => employees.id, { onDelete: 'cascade' }),
    senderId: text('sender_id').references(() => employees.id, { onDelete: 'set null' }),
    type: notificationTypeEnum('type').notNull(),
    title: text('title').notNull(),
    message: text('message').notNull(),
    relatedId: text('related_id'), // ID of related record (can be text or UUID string)
    isRead: boolean('is_read').default(false).notNull(),
    readAt: timestamp('read_at', { withTimezone: true }),
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => ({
    recipientIdIdx: index('idx_notifications_recipient_id').on(table.recipientId),
    typeIdx: index('idx_notifications_type').on(table.type),
    isReadIdx: index('idx_notifications_is_read').on(table.isRead),
    createdAtIdx: index('idx_notifications_created_at').on(table.createdAt),
}));
// =============================================================================
// SALARY CALCULATIONS - Salary computation and tracking
// =============================================================================
export const salaryCalculations = pgTable('salary_calculations', {
    id: uuid('id').primaryKey().defaultRandom(),
    employeeId: text('employee_id').notNull().references(() => employees.id, { onDelete: 'cascade' }),
    periodStart: date('period_start').notNull(),
    periodEnd: date('period_end').notNull(),
    baseSalary: numeric('base_salary').notNull(),
    totalWorkHours: numeric('total_work_hours').default('0').notNull(),
    totalWorkDays: integer('total_work_days').default(0).notNull(),
    overtimeHours: numeric('overtime_hours').default('0'),
    overtimeAmount: numeric('overtime_amount').default('0'),
    advancesTotal: numeric('advances_total').default('0'),
    deductionsTotal: numeric('deductions_total').default('0'),
    absenceDeductions: numeric('absence_deductions').default('0'),
    netSalary: numeric('net_salary').notNull(),
    isPaid: boolean('is_paid').default(false).notNull(),
    paidAt: timestamp('paid_at', { withTimezone: true }),
    notes: text('notes'),
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => ({
    employeeIdIdx: index('idx_salary_calculations_employee_id').on(table.employeeId),
    periodStartIdx: index('idx_salary_calculations_period_start').on(table.periodStart),
    isPaidIdx: index('idx_salary_calculations_is_paid').on(table.isPaid),
}));
