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
  permissions: text('permissions').array().default(sql`'{}'`),
  branch: text('branch'),
  branchId: uuid('branch_id').references(() => branches.id),
  monthlySalary: numeric('monthly_salary'),
  hourlyRate: numeric('hourly_rate'),
  shiftStartTime: text('shift_start_time'), // e.g., '09:00' or '21:00'
  shiftEndTime: text('shift_end_time'), // e.g., '17:00' or '05:00'
  shiftType: text('shift_type'), // 'AM' or 'PM'
  // Personal Information Fields
  address: text('address'),
  birthDate: date('birth_date'),
  email: text('email'),
  phone: text('phone'),
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

// Pulses table - location tracking with BLV (Behavioral Location Verification)
export const pulses = pgTable('pulses', {
  id: uuid('id').primaryKey().defaultRandom(),
  employeeId: text('employee_id').notNull().references(() => employees.id, { onDelete: 'cascade' }),
  branchId: uuid('branch_id').references(() => branches.id, { onDelete: 'cascade' }),
  timestamp: timestamp('timestamp', { withTimezone: true }).defaultNow().notNull(),
  
  // Legacy location fields (kept for backward compatibility)
  latitude: doublePrecision('latitude'),
  longitude: doublePrecision('longitude'),
  location: text('location'),
  bssidAddress: text('bssid_address'),
  isWithinGeofence: boolean('is_within_geofence').default(false),
  
  // BLV Environmental Signals
  wifiCount: integer('wifi_count'), // Number of WiFi networks detected
  wifiSignalStrength: integer('wifi_signal_strength'), // Signal strength in dBm (-40 to -90)
  batteryLevel: doublePrecision('battery_level'), // 0.0 to 1.0
  isCharging: boolean('is_charging').default(false), // Charging status
  accelVariance: doublePrecision('accel_variance'), // Movement variance
  soundLevel: doublePrecision('sound_level'), // Ambient sound level (0.0 to 1.0)
  deviceOrientation: text('device_orientation'), // portrait/landscape/faceup/facedown
  
  // BLV Verification Scores
  presenceScore: doublePrecision('presence_score'), // 0.0 to 1.0 (similarity to branch baseline)
  trustScore: doublePrecision('trust_score'), // 0.0 to 1.0 (fraud detection score)
  verificationMethod: text('verification_method').default('BLV'), // BLV/WiFi/Hybrid/Manual
  
  // Status and flags
  isFake: boolean('is_fake').default(false).notNull(),
  isSynced: boolean('is_synced').default(true),
  sentFromDevice: boolean('sent_from_device').default(true).notNull(),
  sentViaSupabase: boolean('sent_via_supabase').default(false).notNull(),
  offlineBatchId: uuid('offline_batch_id'),
  source: text('source'),
  status: text('status').default('IN'), // IN/OUT/SUSPECT/REVIEW_REQUIRED
  
  // Device info for normalization
  deviceModel: text('device_model'),
  osVersion: text('os_version'),
  
  // Raw data for analysis
  rawEnvironmentData: text('raw_environment_data'), // JSON string of all collected data
  
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => ({
  employeeIdIdx: index('idx_pulses_employee_id').on(table.employeeId),
  branchIdIdx: index('idx_pulses_branch_id').on(table.branchId),
  timestampIdx: index('idx_pulses_timestamp').on(table.timestamp),
  latLonIdx: index('idx_pulses_latitude_longitude').on(table.latitude, table.longitude),
  geofenceIdx: index('idx_pulses_geofence').on(table.isWithinGeofence),
  presenceScoreIdx: index('idx_pulses_presence_score').on(table.presenceScore),
  trustScoreIdx: index('idx_pulses_trust_score').on(table.trustScore),
  statusIdx: index('idx_pulses_status').on(table.status),
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

// =============================================================================
// BLV SYSTEM - Behavioral Location Verification
// =============================================================================

// Branch Environment Baseline - البصمة البيئية لكل فرع
export const branchEnvironmentBaselines = pgTable('branch_environment_baselines', {
  id: uuid('id').primaryKey().defaultRandom(),
  branchId: uuid('branch_id').notNull().references(() => branches.id, { onDelete: 'cascade' }),
  
  // Time-based baselines (morning/afternoon/evening/night)
  timeSlot: text('time_slot').notNull(), // morning/afternoon/evening/night
  
  // WiFi baselines
  avgWifiCount: doublePrecision('avg_wifi_count'),
  wifiCountStdDev: doublePrecision('wifi_count_std_dev'),
  avgSignalStrength: doublePrecision('avg_signal_strength'),
  
  // Battery baselines
  avgBatteryLevel: doublePrecision('avg_battery_level'),
  chargingLikelihood: doublePrecision('charging_likelihood'), // 0.0 to 1.0
  
  // Motion baselines
  avgAccelVariance: doublePrecision('avg_accel_variance'),
  accelVarianceStdDev: doublePrecision('accel_variance_std_dev'),
  
  // Sound baselines
  avgSoundLevel: doublePrecision('avg_sound_level'),
  soundLevelStdDev: doublePrecision('sound_level_std_dev'),
  
  // Statistical info
  sampleCount: integer('sample_count').default(0), // Number of samples used
  lastUpdated: timestamp('last_updated', { withTimezone: true }).defaultNow(),
  confidence: doublePrecision('confidence').default(0), // 0.0 to 1.0
  
  // Metadata
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => ({
  branchIdIdx: index('idx_baseline_branch_id').on(table.branchId),
  timeSlotIdx: index('idx_baseline_time_slot').on(table.timeSlot),
  branchTimeIdx: index('idx_baseline_branch_time').on(table.branchId, table.timeSlot),
}));

// Device Calibration - معايرة الأجهزة المختلفة
export const deviceCalibrations = pgTable('device_calibrations', {
  id: uuid('id').primaryKey().defaultRandom(),
  deviceModel: text('device_model').notNull().unique(),
  osType: text('os_type').notNull(), // android/ios
  
  // Calibration factors
  accelCalibrationFactor: doublePrecision('accel_calibration_factor').default(1.0),
  soundCalibrationFactor: doublePrecision('sound_calibration_factor').default(1.0),
  wifiSignalCalibrationFactor: doublePrecision('wifi_signal_calibration_factor').default(1.0),
  
  // Sample statistics
  sampleCount: integer('sample_count').default(0),
  avgReadingDrift: doublePrecision('avg_reading_drift'),
  
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => ({
  deviceModelIdx: index('idx_calibration_device_model').on(table.deviceModel),
}));

// Employee-Device Baseline - البصمة الشخصية لكل موظف + جهاز
export const employeeDeviceBaselines = pgTable('employee_device_baselines', {
  id: uuid('id').primaryKey().defaultRandom(),
  employeeId: text('employee_id').notNull().references(() => employees.id, { onDelete: 'cascade' }),
  deviceId: text('device_id').notNull(),
  deviceModel: text('device_model'),
  
  // Personal behavioral patterns
  personalAccelVariance: doublePrecision('personal_accel_variance'),
  personalSoundSensitivity: doublePrecision('personal_sound_sensitivity'),
  typicalChargingPattern: text('typical_charging_pattern'), // JSON string
  
  // Usage statistics
  totalPulses: integer('total_pulses').default(0),
  avgPresenceScore: doublePrecision('avg_presence_score'),
  
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => ({
  employeeIdIdx: index('idx_emp_baseline_employee_id').on(table.employeeId),
  deviceIdIdx: index('idx_emp_baseline_device_id').on(table.deviceId),
  empDeviceIdx: index('idx_emp_baseline_emp_device').on(table.employeeId, table.deviceId),
}));

// Pulse Flags - علامات الشك والتنبيهات
export const pulseFlags = pgTable('pulse_flags', {
  id: uuid('id').primaryKey().defaultRandom(),
  pulseId: uuid('pulse_id').notNull().references(() => pulses.id, { onDelete: 'cascade' }),
  employeeId: text('employee_id').notNull().references(() => employees.id, { onDelete: 'cascade' }),
  
  // Flag details
  flagType: text('flag_type').notNull(), // NoMotion/PassiveAudio/HeartbeatMiss/AnomalousPattern/etc
  severity: text('severity').default('medium'), // low/medium/high/critical
  description: text('description'),
  details: text('details'), // JSON string with flag-specific data
  
  // Resolution
  isResolved: boolean('is_resolved').default(false),
  resolvedBy: text('resolved_by').references(() => employees.id),
  resolvedAt: timestamp('resolved_at', { withTimezone: true }),
  resolutionNote: text('resolution_note'),
  resolutionAction: text('resolution_action'), // approved/rejected/manual_override
  
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => ({
  pulseIdIdx: index('idx_flags_pulse_id').on(table.pulseId),
  employeeIdIdx: index('idx_flags_employee_id').on(table.employeeId),
  flagTypeIdx: index('idx_flags_type').on(table.flagType),
  isResolvedIdx: index('idx_flags_resolved').on(table.isResolved),
  severityIdx: index('idx_flags_severity').on(table.severity),
}));

// Active Interaction Logs - سجل التفاعلات النشطة
export const activeInteractionLogs = pgTable('active_interaction_logs', {
  id: uuid('id').primaryKey().defaultRandom(),
  employeeId: text('employee_id').notNull().references(() => employees.id, { onDelete: 'cascade' }),
  branchId: uuid('branch_id').references(() => branches.id),
  
  // Interaction details
  interactionType: text('interaction_type').notNull(), // heartbeat/pin_entry/page_view/button_click
  interactionData: text('interaction_data'), // JSON string
  
  // Context
  attendanceId: uuid('attendance_id').references(() => attendance.id),
  shiftDurationMinutes: integer('shift_duration_minutes'), // How long into shift
  
  timestamp: timestamp('timestamp', { withTimezone: true }).defaultNow().notNull(),
}, (table) => ({
  employeeIdIdx: index('idx_interaction_employee_id').on(table.employeeId),
  timestampIdx: index('idx_interaction_timestamp').on(table.timestamp),
  typeIdx: index('idx_interaction_type').on(table.interactionType),
}));

// Attendance Exemptions - استثناءات الحضور
export const attendanceExemptions = pgTable('attendance_exemptions', {
  id: uuid('id').primaryKey().defaultRandom(),
  employeeId: text('employee_id').notNull().references(() => employees.id, { onDelete: 'cascade' }),
  branchId: uuid('branch_id').references(() => branches.id),
  
  // Exemption details
  exemptionType: text('exemption_type').notNull(), // sick/mission/power_outage/network_issue/device_issue
  startTime: timestamp('start_time', { withTimezone: true }).notNull(),
  endTime: timestamp('end_time', { withTimezone: true }).notNull(),
  reason: text('reason').notNull(),
  
  // Approval
  status: requestStatusEnum('status').default('pending').notNull(),
  requestedBy: text('requested_by').references(() => employees.id),
  approvedBy: text('approved_by').references(() => employees.id),
  approvedAt: timestamp('approved_at', { withTimezone: true }),
  
  // Evidence
  evidenceUrls: text('evidence_urls').array(), // Photos/documents
  notes: text('notes'),
  
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => ({
  employeeIdIdx: index('idx_exemption_employee_id').on(table.employeeId),
  statusIdx: index('idx_exemption_status').on(table.status),
  typeIdx: index('idx_exemption_type').on(table.exemptionType),
  timeRangeIdx: index('idx_exemption_time_range').on(table.startTime, table.endTime),
}));

// Manual Overrides - التعديلات اليدوية
export const manualOverrides = pgTable('manual_overrides', {
  id: uuid('id').primaryKey().defaultRandom(),
  pulseId: uuid('pulse_id').references(() => pulses.id, { onDelete: 'cascade' }),
  employeeId: text('employee_id').notNull().references(() => employees.id, { onDelete: 'cascade' }),
  
  // Override details
  originalPresenceScore: doublePrecision('original_presence_score'),
  originalTrustScore: doublePrecision('original_trust_score'),
  originalStatus: text('original_status'),
  
  newPresenceScore: doublePrecision('new_presence_score'),
  newTrustScore: doublePrecision('new_trust_score'),
  newStatus: text('new_status'),
  
  // Authorization
  overrideBy: text('override_by').notNull().references(() => employees.id),
  overrideReason: text('override_reason').notNull(),
  overrideCategory: text('override_category'), // technical_issue/false_positive/manager_discretion
  
  // Audit
  managerApproval: boolean('manager_approval').default(false),
  hrApproval: boolean('hr_approval').default(false),
  
  timestamp: timestamp('timestamp', { withTimezone: true }).defaultNow().notNull(),
}, (table) => ({
  pulseIdIdx: index('idx_override_pulse_id').on(table.pulseId),
  employeeIdIdx: index('idx_override_employee_id').on(table.employeeId),
  overrideByIdx: index('idx_override_by').on(table.overrideBy),
  timestampIdx: index('idx_override_timestamp').on(table.timestamp),
}));

// BLV System Configuration - إعدادات النظام
export const blvSystemConfig = pgTable('blv_system_config', {
  id: uuid('id').primaryKey().defaultRandom(),
  branchId: uuid('branch_id').references(() => branches.id), // null = global config
  
  // Verification thresholds
  minPresenceScore: doublePrecision('min_presence_score').default(0.7),
  minTrustScore: doublePrecision('min_trust_score').default(0.6),
  
  // Feature weights
  wifiWeight: doublePrecision('wifi_weight').default(0.4),
  motionWeight: doublePrecision('motion_weight').default(0.2),
  soundWeight: doublePrecision('sound_weight').default(0.2),
  batteryWeight: doublePrecision('battery_weight').default(0.2),
  
  // Interaction requirements
  activeInteractionIntervalMinutes: integer('active_interaction_interval_minutes').default(120),
  maxContinuousHoursWithoutInteraction: integer('max_continuous_hours_without_interaction').default(6),
  
  // Learning settings
  baselineLearningPeriodDays: integer('baseline_learning_period_days').default(14),
  baselineUpdateFrequencyDays: integer('baseline_update_frequency_days').default(7),
  minSamplesForBaseline: integer('min_samples_for_baseline').default(50),
  
  // Flags and alerts
  enableNoMotionFlag: boolean('enable_no_motion_flag').default(true),
  noMotionThresholdMinutes: integer('no_motion_threshold_minutes').default(120),
  enableHeartbeatCheck: boolean('enable_heartbeat_check').default(true),
  
  // Fallback options
  fallbackToWifiOnly: boolean('fallback_to_wifi_only').default(true),
  allowManualOverride: boolean('allow_manual_override').default(true),
  
  isActive: boolean('is_active').default(true),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => ({
  branchIdIdx: index('idx_config_branch_id').on(table.branchId),
  isActiveIdx: index('idx_config_is_active').on(table.isActive),
}));

// Type exports for TypeScript
export type Employee = typeof employees.$inferSelect;
export type NewEmployee = typeof employees.$inferInsert;

export type Attendance = typeof attendance.$inferSelect;
export type NewAttendance = typeof attendance.$inferInsert;

export type AttendanceRequest = typeof attendanceRequests.$inferSelect;
export type NewAttendanceRequest = typeof attendanceRequests.$inferInsert;

export type LeaveRequest = typeof leaveRequests.$inferSelect;
export type NewLeaveRequest = typeof leaveRequests.$inferInsert;

export type Advance = typeof advances.$inferSelect;
export type NewAdvance = typeof advances.$inferInsert;

export type Deduction = typeof deductions.$inferSelect;
export type NewDeduction = typeof deductions.$inferInsert;

export type AbsenceNotification = typeof absenceNotifications.$inferSelect;
export type NewAbsenceNotification = typeof absenceNotifications.$inferInsert;

export type Profile = typeof profiles.$inferSelect;
export type NewProfile = typeof profiles.$inferInsert;

export type Shift = typeof shifts.$inferSelect;
export type NewShift = typeof shifts.$inferInsert;

export type User = typeof users.$inferSelect;
export type NewUser = typeof users.$inferInsert;

export type Role = typeof roles.$inferSelect;
export type NewRole = typeof roles.$inferInsert;

export type Permission = typeof permissions.$inferSelect;
export type NewPermission = typeof permissions.$inferInsert;

export type RolePermission = typeof rolePermissions.$inferSelect;
export type NewRolePermission = typeof rolePermissions.$inferInsert;

export type UserRole = typeof userRoles.$inferSelect;
export type NewUserRole = typeof userRoles.$inferInsert;

export type Branch = typeof branches.$inferSelect;
export type NewBranch = typeof branches.$inferInsert;

export type BranchBssid = typeof branchBssids.$inferSelect;
export type NewBranchBssid = typeof branchBssids.$inferInsert;

export type Pulse = typeof pulses.$inferSelect;
export type NewPulse = typeof pulses.$inferInsert;

export type BranchManager = typeof branchManagers.$inferSelect;
export type NewBranchManager = typeof branchManagers.$inferInsert;

export type Break = typeof breaks.$inferSelect;
export type NewBreak = typeof breaks.$inferInsert;

export type DeviceSession = typeof deviceSessions.$inferSelect;
export type NewDeviceSession = typeof deviceSessions.$inferInsert;

export type Notification = typeof notifications.$inferSelect;
export type NewNotification = typeof notifications.$inferInsert;

export type SalaryCalculation = typeof salaryCalculations.$inferSelect;
export type NewSalaryCalculation = typeof salaryCalculations.$inferInsert;

// BLV System Types
export type BranchEnvironmentBaseline = typeof branchEnvironmentBaselines.$inferSelect;
export type NewBranchEnvironmentBaseline = typeof branchEnvironmentBaselines.$inferInsert;

export type DeviceCalibration = typeof deviceCalibrations.$inferSelect;
export type NewDeviceCalibration = typeof deviceCalibrations.$inferInsert;

export type EmployeeDeviceBaseline = typeof employeeDeviceBaselines.$inferSelect;
export type NewEmployeeDeviceBaseline = typeof employeeDeviceBaselines.$inferInsert;

export type PulseFlag = typeof pulseFlags.$inferSelect;
export type NewPulseFlag = typeof pulseFlags.$inferInsert;

export type ActiveInteractionLog = typeof activeInteractionLogs.$inferSelect;
export type NewActiveInteractionLog = typeof activeInteractionLogs.$inferInsert;

export type AttendanceExemption = typeof attendanceExemptions.$inferSelect;
export type NewAttendanceExemption = typeof attendanceExemptions.$inferInsert;

export type ManualOverride = typeof manualOverrides.$inferSelect;
export type NewManualOverride = typeof manualOverrides.$inferInsert;

export type BLVSystemConfig = typeof blvSystemConfig.$inferSelect;
export type NewBLVSystemConfig = typeof blvSystemConfig.$inferInsert;

// =============================================================================
// BLV VALIDATION LOGS - Detailed validation event logs
// =============================================================================
export const blvValidationLogs = pgTable('blv_validation_logs', {
  id: uuid('id').primaryKey().defaultRandom(),
  employeeId: text('employee_id').notNull().references(() => employees.id, { onDelete: 'cascade' }),
  branchId: uuid('branch_id').references(() => branches.id, { onDelete: 'set null' }),
  validationType: text('validation_type'), // 'check-in', 'pulse', 'check-out'

  // Individual component scores (0-100)
  wifiScore: integer('wifi_score'),
  gpsScore: integer('gps_score'),
  cellScore: integer('cell_score'),
  soundScore: integer('sound_score'),
  motionScore: integer('motion_score'),
  bluetoothScore: integer('bluetooth_score'),
  lightScore: integer('light_score'),
  batteryScore: integer('battery_score'),

  // Total weighted score
  totalScore: integer('total_score'),
  threshold: integer('threshold').default(70),
  isApproved: boolean('is_approved').default(true).notNull(),

  // Raw sensor data for audit
  sensorSnapshot: text('sensor_snapshot'), // JSONB as text

  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => ({
  employeeIdIdx: index('idx_blv_logs_employee').on(table.employeeId, table.createdAt),
  branchIdIdx: index('idx_blv_logs_branch').on(table.branchId, table.createdAt),
  approvedIdx: index('idx_blv_logs_approved').on(table.isApproved),
  typeIdx: index('idx_blv_logs_type').on(table.validationType),
}));

// =============================================================================
// PAYROLL - Automated payroll calculation based on BLV-verified hours
// =============================================================================
export const payroll = pgTable('payroll', {
  id: uuid('id').primaryKey().defaultRandom(),
  employeeId: text('employee_id').notNull().references(() => employees.id, { onDelete: 'cascade' }),
  branchId: uuid('branch_id').references(() => branches.id, { onDelete: 'set null' }),

  // Pay period
  periodStart: date('period_start').notNull(),
  periodEnd: date('period_end').notNull(),

  // Hours breakdown
  totalHours: numeric('total_hours').default('0').notNull(),
  pauseDurationMinutes: integer('pause_duration_minutes').default(0).notNull(),
  blvVerifiedHours: numeric('blv_verified_hours').default('0').notNull(),

  // Work days and shifts
  workDays: integer('work_days').default(0).notNull(),
  totalShifts: integer('total_shifts').default(0).notNull(),

  // Pay calculation
  hourlyRate: numeric('hourly_rate').notNull(),
  baseSalary: numeric('base_salary'),
  grossPay: numeric('gross_pay').default('0').notNull(),

  // Deductions
  advancesTotal: numeric('advances_total').default('0').notNull(),
  deductionsTotal: numeric('deductions_total').default('0').notNull(),
  absenceDeductions: numeric('absence_deductions').default('0').notNull(),
  lateDeductions: numeric('late_deductions').default('0').notNull(),

  // Final amount
  netPay: numeric('net_pay').default('0').notNull(),

  // Payment status
  isCalculated: boolean('is_calculated').default(true).notNull(),
  isApproved: boolean('is_approved').default(false).notNull(),
  isPaid: boolean('is_paid').default(false).notNull(),

  // Timestamps
  calculatedAt: timestamp('calculated_at', { withTimezone: true }).defaultNow().notNull(),
  approvedAt: timestamp('approved_at', { withTimezone: true }),
  approvedBy: text('approved_by').references(() => employees.id),
  paidAt: timestamp('paid_at', { withTimezone: true }),
  paidBy: text('paid_by').references(() => employees.id),

  // Audit and notes
  calculationDetails: text('calculation_details'), // JSONB as text
  notes: text('notes'),
  paymentMethod: text('payment_method'),
  paymentReference: text('payment_reference'),

  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => ({
  employeeIdIdx: index('idx_payroll_employee').on(table.employeeId, table.periodStart),
  branchIdIdx: index('idx_payroll_branch').on(table.branchId, table.periodStart),
  periodIdx: index('idx_payroll_period').on(table.periodStart, table.periodEnd),
  unpaidIdx: index('idx_payroll_unpaid').on(table.isPaid, table.periodEnd),
  unapprovedIdx: index('idx_payroll_unapproved').on(table.isApproved, table.calculatedAt),
  statusIdx: index('idx_payroll_status').on(table.isCalculated, table.isApproved, table.isPaid),
}));

// =============================================================================
// PAYROLL HISTORY - Audit trail for payroll changes
// =============================================================================
export const payrollHistory = pgTable('payroll_history', {
  id: uuid('id').primaryKey().defaultRandom(),
  payrollId: uuid('payroll_id').notNull().references(() => payroll.id, { onDelete: 'cascade' }),

  // Track changes
  action: text('action').notNull(), // 'CALCULATED', 'APPROVED', 'PAID', 'MODIFIED', 'CANCELLED'
  fieldChanged: text('field_changed'),
  oldValue: text('old_value'),
  newValue: text('new_value'),

  // Who made the change
  changedBy: text('changed_by').references(() => employees.id),
  changeReason: text('change_reason'),

  // When
  changedAt: timestamp('changed_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => ({
  payrollIdIdx: index('idx_payroll_history_payroll').on(table.payrollId, table.changedAt),
  actionIdx: index('idx_payroll_history_action').on(table.action, table.changedAt),
}));

// Type exports for new tables
export type BLVValidationLog = typeof blvValidationLogs.$inferSelect;
export type NewBLVValidationLog = typeof blvValidationLogs.$inferInsert;

export type Payroll = typeof payroll.$inferSelect;
export type NewPayroll = typeof payroll.$inferInsert;

export type PayrollHistory = typeof payrollHistory.$inferSelect;
export type NewPayrollHistory = typeof payrollHistory.$inferInsert;
