import { pgTable, uuid, text, timestamp, boolean, point, index } from "drizzle-orm/pg-core";
import { sql } from "drizzle-orm";

export const profiles = pgTable("profiles", {
  id: uuid("id").primaryKey(),
  fullName: text("full_name").notNull(),
  employeeId: text("employee_id").notNull().unique(),
  role: text("role").notNull().default("employee"),
  createdAt: timestamp("created_at", { withTimezone: true }).defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).defaultNow(),
}, (table) => ({
  employeeIdIdx: index("idx_profiles_employee_id").on(table.employeeId),
  roleIdx: index("idx_profiles_role").on(table.role),
}));

export const shifts = pgTable("shifts", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id").notNull().references(() => profiles.id, { onDelete: "cascade" }),
  checkInTime: timestamp("check_in_time", { withTimezone: true }).defaultNow(),
  checkOutTime: timestamp("check_out_time", { withTimezone: true }),
  status: text("status").notNull().default("active"),
  createdAt: timestamp("created_at", { withTimezone: true }).defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).defaultNow(),
}, (table) => ({
  userIdIdx: index("idx_shifts_user_id").on(table.userId),
  statusIdx: index("idx_shifts_status").on(table.status),
  checkInTimeIdx: index("idx_shifts_check_in_time").on(table.checkInTime),
}));

export const pulses = pgTable("pulses", {
  id: uuid("id").primaryKey().defaultRandom(),
  shiftId: uuid("shift_id").notNull().references(() => shifts.id, { onDelete: "cascade" }),
  latitude: text("latitude").notNull(),
  longitude: text("longitude").notNull(),
  isWithinGeofence: boolean("is_within_geofence").default(false),
  createdAt: timestamp("created_at", { withTimezone: true }).defaultNow(),
}, (table) => ({
  shiftIdIdx: index("idx_pulses_shift_id").on(table.shiftId),
  geofenceIdx: index("idx_pulses_geofence").on(table.isWithinGeofence),
  createdAtIdx: index("idx_pulses_created_at").on(table.createdAt),
}));

export type Profile = typeof profiles.$inferSelect;
export type NewProfile = typeof profiles.$inferInsert;

export type Shift = typeof shifts.$inferSelect;
export type NewShift = typeof shifts.$inferInsert;

export type Pulse = typeof pulses.$inferSelect;
export type NewPulse = typeof pulses.$inferInsert;
