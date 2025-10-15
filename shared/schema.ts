import { pgTable, uuid, text, timestamp, boolean, numeric, index, doublePrecision, pgEnum, integer, date } from 'drizzle-orm/pg-core';
import { sql } from 'drizzle-orm';

// Employee role enum
export const employeeRoleEnum = pgEnum('employee_role', ['owner', 'admin', 'manager', 'hr', 'monitor', 'staff']);

// =============================================================================
// BRANCHES TABLE - Multi-branch management
// =============================================================================
export const branches = pgTable('branches', {
  id: uuid('id').primaryKey().defaultRandom(),
  name: text('name').notNull(),
  wifiBssid: text('wifi_bssid'),
  latitude: numeric('latitude'),
  longitude: numeric('longitude'),
  geofenceRadius: integer('geofence_radius').default(100),
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
  reviewedBy: uuid('reviewed_by').references(() => users.id),
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
  reviewedBy: uuid('reviewed_by').references(() => users.id),
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
  reviewedBy: uuid('reviewed_by').references(() => users.id),
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
  appliedBy: uuid('applied_by').references(() => users.id),
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
  reviewedBy: uuid('reviewed_by').references(() => users.id),
  reviewedAt: timestamp('reviewed_at', { withTimezone: true }),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => ({
  employeeIdIdx: index('idx_absence_notifications_employee_id').on(table.employeeId),
  statusIdx: index('idx_absence_notifications_status').on(table.status),
  dateIdx: index('idx_absence_notifications_date').on(table.absenceDate),
}));

// Pulses table - location tracking (from original schema)
export const pulses = pgTable('pulses', {
  id: uuid('id').primaryKey().defaultRandom(),
  employeeId: text('employee_id').notNull().references(() => employees.id, { onDelete: 'cascade' }),
  timestamp: timestamp('timestamp', { withTimezone: true }).defaultNow().notNull(),
  latitude: doublePrecision('latitude'),
  longitude: doublePrecision('longitude'),
  location: text('location'),
  isWithinGeofence: boolean('is_within_geofence').default(false),
  isFake: boolean('is_fake').default(false).notNull(),
  sentFromDevice: boolean('sent_from_device').default(true).notNull(),
  sentViaSupabase: boolean('sent_via_supabase').default(false).notNull(),
  offlineBatchId: uuid('offline_batch_id'),
  source: text('source'),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => ({
  employeeIdIdx: index('idx_pulses_employee_id').on(table.employeeId),
  timestampIdx: index('idx_pulses_timestamp').on(table.timestamp),
  latLonIdx: index('idx_pulses_latitude_longitude').on(table.latitude, table.longitude),
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
// ADMIN USERS AND PERMISSIONS
// =============================================================================

// Admin users table
export const users = pgTable('users', {
  id: uuid('id').primaryKey().defaultRandom(),
  email: text('email').unique().notNull(),
  passwordHash: text('password_hash').notNull(),
  fullName: text('full_name').notNull(),
  isActive: boolean('is_active').default(true),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow(),
}, (table) => ({
  emailIdx: index('idx_users_email').on(table.email),
  isActiveIdx: index('idx_users_is_active').on(table.isActive),
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

// Branch-Managers junction table
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
export const breakStatusEnum = pgEnum('break_status', ['PENDING', 'APPROVED', 'REJECTED', 'ACTIVE', 'COMPLETED']);

export const breaks = pgTable('breaks', {
  id: uuid('id').primaryKey().defaultRandom(),
  shiftId: uuid('shift_id').references(() => shifts.id, { onDelete: 'cascade' }),
  employeeId: text('employee_id').notNull().references(() => employees.id, { onDelete: 'cascade' }),
  requestedDurationMinutes: integer('requested_duration_minutes').notNull(),
  status: breakStatusEnum('status').default('PENDING').notNull(),
  startTime: timestamp('start_time', { withTimezone: true }),
  endTime: timestamp('end_time', { withTimezone: true }),
  approvedBy: text('approved_by').references(() => employees.id),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => ({
  shiftIdIdx: index('idx_breaks_shift_id').on(table.shiftId),
  employeeIdIdx: index('idx_breaks_employee_id').on(table.employeeId),
  statusIdx: index('idx_breaks_status').on(table.status),
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

export type Pulse = typeof pulses.$inferSelect;
export type NewPulse = typeof pulses.$inferInsert;

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

export type BranchManager = typeof branchManagers.$inferSelect;
export type NewBranchManager = typeof branchManagers.$inferInsert;

export type Break = typeof breaks.$inferSelect;
export type NewBreak = typeof breaks.$inferInsert;
