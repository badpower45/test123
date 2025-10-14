import { pgTable, uuid, text, timestamp, boolean, numeric, index, customType } from 'drizzle-orm/pg-core';
import { sql } from 'drizzle-orm';

// Custom type for PostGIS geography
const geography = customType<{ data: string }>({
  dataType() {
    return 'geography(Point, 4326)';
  },
});

// Profiles table - employee information (no auth.users dependency)
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

// Shifts table - records each work shift
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

// Pulses table - stores periodic location updates with geofencing
export const pulses = pgTable('pulses', {
  id: uuid('id').primaryKey().defaultRandom(),
  shiftId: uuid('shift_id').notNull().references(() => shifts.id, { onDelete: 'cascade' }),
  latitude: numeric('latitude'),
  longitude: numeric('longitude'),
  location: geography('location'),
  isWithinGeofence: boolean('is_within_geofence').default(false),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
}, (table) => ({
  shiftIdIdx: index('idx_pulses_shift_id').on(table.shiftId),
  latLonIdx: index('idx_pulses_lat_lon').on(table.latitude, table.longitude),
  geofenceIdx: index('idx_pulses_geofence').on(table.isWithinGeofence),
  createdAtIdx: index('idx_pulses_created_at').on(table.createdAt),
}));

// =============================================================================
// ROLES AND PERMISSIONS TABLES
// جداول الأدوار والصلاحيات
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

// Type exports for TypeScript
export type Profile = typeof profiles.$inferSelect;
export type NewProfile = typeof profiles.$inferInsert;

export type Shift = typeof shifts.$inferSelect;
export type NewShift = typeof shifts.$inferInsert;

export type Pulse = typeof pulses.$inferSelect;
export type NewPulse = typeof pulses.$inferInsert;

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
