import express from 'express';
import cors from 'cors';
import path from 'path';
import { fileURLToPath } from 'url';
import bcrypt from 'bcrypt';
import { db } from './db.js';
import {
  employees, attendance, attendanceRequests, leaveRequests, advances,
  deductions, absenceNotifications, pulses, users, roles, permissions,
  rolePermissions, userRoles, branches, branchBssids, branchManagers, breaks
} from '../shared/schema.js';
import { eq, and, gte, lte, lt, desc, sql, between, inArray } from 'drizzle-orm';
import { requirePermission, getUserPermissions, checkUserPermission } from './auth.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const PORT = Number(process.env.PORT) || 5000;

// Debug logs for environment
console.log('[DEBUG] Server starting...');
console.log('[DEBUG] PORT:', PORT);
console.log('[DEBUG] NODE_ENV:', process.env.NODE_ENV);
console.log('[DEBUG] DATABASE_URL present:', !!process.env.DATABASE_URL);

app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(express.static(path.join(__dirname, '../public')));

// =============================================================================
// UTILITY FUNCTIONS
// =============================================================================

/**
 * Convert string numbers to actual numbers in objects
 * This fixes PostgreSQL returning numeric fields as strings
 */
function normalizeNumericFields(obj: any, fields: string[]): any {
  if (!obj) return obj;
  
  const normalized = { ...obj };
  for (const field of fields) {
    if (field in normalized && normalized[field] !== null && normalized[field] !== undefined) {
      const value = normalized[field];
      if (typeof value === 'string') {
        const num = parseFloat(value);
        normalized[field] = isNaN(num) ? value : num;
      }
    }
  }
  return normalized;
}

function extractRows<T>(result: any): T[] {
  if (Array.isArray(result)) {
    return result;
  }
  return [];
}

function extractFirstRow<T>(result: any): T | undefined {
  const rows = extractRows<T>(result);
  return rows.length > 0 ? rows[0] : undefined;
}

async function getOwnerRecord(ownerId?: string) {
  if (!ownerId) {
    return null;
  }

  const [owner] = await db
    .select()
    .from(employees)
    .where(eq(employees.id, ownerId))
    .limit(1);

  if (!owner) {
    return null;
  }

  const role = owner.role as string;
  if (role !== 'owner' && role !== 'admin') {
    return null;
  }

  return owner;
}

// Force JSON-only API errors (avoid HTML bodies that cause Flutter FormatException)
// Set JSON content-type for API routes only
app.use((req, res, next) => {
  if (req.path.startsWith('/api') || req.path === '/health' || req.path.startsWith('/api/branch')) {
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
  }
  next();
});

// =============================================================================
// BRANCH MANAGER ENDPOINTS
// =============================================================================

// Get all requests for a branch (leave, advance, attendance, absence)
app.get('/api/branch/:branch/requests', async (req, res) => {
  try {
    const branch = req.params.branch;
    // Get all employees in branch
    const employeesInBranch = await db.select().from(employees).where(eq(employees.branch, branch));
    const employeeIds = employeesInBranch.map(e => e.id);

    if (employeeIds.length === 0) {
      return res.json({
        success: true,
        leaveRequests: [],
        advanceRequests: [],
        attendanceRequests: [],
        absenceNotifications: [],
      });
    }

    // Leave requests
    const leaveReqs = await db
      .select()
      .from(leaveRequests)
      .where(and(inArray(leaveRequests.employeeId, employeeIds), eq(leaveRequests.status, 'pending')));
    // Advances
    const advanceReqs = await db
      .select()
      .from(advances)
      .where(and(inArray(advances.employeeId, employeeIds), eq(advances.status, 'pending')));
    // Attendance requests
    const attReqs = await db
      .select()
      .from(attendanceRequests)
      .where(and(inArray(attendanceRequests.employeeId, employeeIds), eq(attendanceRequests.status, 'pending')));
    // Absence notifications
    const absenceAlerts = await db
      .select()
      .from(absenceNotifications)
      .where(and(inArray(absenceNotifications.employeeId, employeeIds), eq(absenceNotifications.status, 'pending')));
    // Break requests
    const breakReqs = await db
      .select()
      .from(breaks)
      .where(and(inArray(breaks.employeeId, employeeIds), eq(breaks.status, 'PENDING')));

    res.json({
      success: true,
      leaveRequests: leaveReqs.map(r => normalizeNumericFields(r, ['daysCount', 'allowanceAmount'])),
      advanceRequests: advanceReqs.map(r => normalizeNumericFields(r, ['amount', 'eligibleAmount', 'currentSalary'])),
      attendanceRequests: attReqs,
      absenceNotifications: absenceAlerts,
      breakRequests: breakReqs.map(r => normalizeNumericFields(r, ['requestedDurationMinutes'])),
    });
  } catch (err) {
    res.status(500).json({ error: 'Internal server error', message: err?.message });
  }
});

// Approve/reject a request (leave, advance, attendance, absence)
app.post('/api/branch/request/:type/:id/:action', async (req, res) => {
  try {
  let { type, id, action } = req.params as { type: string; id: string; action: 'approve' | 'reject' | 'postpone' };
    const validTypes = ['leave', 'advance', 'attendance', 'absence', 'break'];
    // Normalize common plural aliases
    const typeMap: Record<string, typeof validTypes[number]> = {
      leaves: 'leave',
      advances: 'advance',
      attendances: 'attendance',
      absences: 'absence',
      breaks: 'break',
    } as const;
    type = (typeMap[type] || type) as any;
  const validActions = ['approve', 'reject', 'postpone'];
    if (!validTypes.includes(type) || !validActions.includes(action)) {
      return res.status(400).json({ error: 'Invalid type or action' });
    }
    if (type === 'break') {
      const statusUpdate = action === 'approve' ? 'APPROVED' : action === 'reject' ? 'REJECTED' : 'POSTPONED';
      const payoutEligible = action === 'postpone';
      const updateResult = await db
        .update(breaks)
        .set({
          status: statusUpdate,
          payoutEligible,
          approvedBy: (req.body?.reviewer_id || req.body?.manager_id) ?? null,
          updatedAt: new Date(),
        })
        .where(eq(breaks.id, id))
        .returning();
      const updated = extractFirstRow(updateResult);
      return res.json({ success: true, updated });
    } else {
      let table;
      switch (type) {
        case 'leave': table = leaveRequests; break;
        case 'advance': table = advances; break;
        case 'attendance': table = attendanceRequests; break;
        case 'absence': table = absenceNotifications; break;
      }
      const status = action === 'approve' ? 'approved' : 'rejected';
        const updateResult = await db
          .update(table)
          .set({ status, reviewedAt: new Date() })
          .where(eq(table.id, id))
          .returning();
        const updated = extractFirstRow(updateResult);
        return res.json({ success: true, updated });
    }
  } catch (err) {
    res.status(500).json({ error: 'Internal server error', message: err?.message });
  }
});

// Get daily attendance report for a branch
app.get('/api/branch/:branch/attendance-report', async (req, res) => {
  try {
    const branch = req.params.branch;
    const today = new Date().toISOString().split('T')[0];
    // Get all employees in branch
    const employeesInBranch = await db.select().from(employees).where(eq(employees.branch, branch));
    const employeeIds = employeesInBranch.map(e => e.id);
    if (employeeIds.length === 0) {
      return res.json({ success: true, report: [] });
    }
    // Get today's attendance
    const report = await db
      .select()
      .from(attendance)
      .where(and(inArray(attendance.employeeId, employeeIds), eq(attendance.date, today)));
    res.json({ success: true, report });
  } catch (err) {
    res.status(500).json({ error: 'Internal server error', message: err?.message });
  }
});

// Manager: Create or update attendance for an employee (check-in/check-out)
app.post('/api/branch/attendance/edit', async (req, res) => {
  try {
    const { employee_id, date, check_in_time, check_out_time } = req.body;

    if (!employee_id || !date) {
      return res.status(400).json({ error: 'employee_id and date are required' });
    }

    // Check if attendance exists
    const [existing] = await db
      .select()
      .from(attendance)
      .where(and(eq(attendance.employeeId, employee_id), eq(attendance.date, date)))
      .limit(1);

    if (existing) {
      // Update existing attendance
      const updateData: any = { updatedAt: new Date() };
      if (check_in_time !== undefined) updateData.checkInTime = check_in_time;
      if (check_out_time !== undefined) updateData.checkOutTime = check_out_time;

      // Calculate work hours if both times are available
      if ((check_in_time || existing.checkInTime) && (check_out_time || existing.checkOutTime)) {
        const inTime = check_in_time || existing.checkInTime;
        const outTime = check_out_time || existing.checkOutTime;
        const diffMs = new Date(`1970-01-01T${outTime}`).getTime() - new Date(`1970-01-01T${inTime}`).getTime();
        const hours = Math.max(0, diffMs / (1000 * 60 * 60));
        updateData.workHours = hours.toFixed(2);
      }

      const updateResult = await db
        .update(attendance)
        .set(updateData)
        .where(eq(attendance.id, existing.id))
        .returning();
      const updated = extractFirstRow(updateResult);

      return res.json({ success: true, message: 'تم تحديث الحضور بنجاح', attendance: updated });
    } else {
      // Create new attendance
      const insertData: any = {
        employeeId: employee_id,
        date,
        checkInTime: check_in_time || null,
        checkOutTime: check_out_time || null,
        workHours: '0',
      };

      // Calculate work hours if both times are provided
      if (check_in_time && check_out_time) {
        const diffMs = new Date(`1970-01-01T${check_out_time}`).getTime() - new Date(`1970-01-01T${check_in_time}`).getTime();
        const hours = Math.max(0, diffMs / (1000 * 60 * 60));
        insertData.workHours = hours.toFixed(2);
      }

      const insertResult = await db
        .insert(attendance)
        .values(insertData)
        .returning();
      const newAttendance = extractFirstRow(insertResult);

      return res.json({ success: true, message: 'تم إنشاء سجل الحضور بنجاح', attendance: newAttendance });
    }
  } catch (err) {
    console.error('Edit attendance error:', err);
    res.status(500).json({ error: 'Internal server error', message: err?.message });
  }
});

process.on('uncaughtException', (error) => {
  console.error('[FATAL] Uncaught Exception:', error);
  process.exit(1);
});

process.on('unhandledRejection', (reason, promise) => {
  console.error('[FATAL] Unhandled Rejection at:', promise, 'reason:', reason);
  process.exit(1);
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'ok', message: 'Oldies Workers API is running' });
});

// =============================================================================
// AUTHENTICATION & LOGIN
// نظام تسجيل الدخول
// =============================================================================

// Login with PIN
app.post('/api/auth/login', async (req, res) => {
  try {
    const { employee_id, pin } = req.body;

    const normalizedEmployeeId = typeof employee_id === 'string' ? employee_id.trim() : String(employee_id ?? '').trim();
    const normalizedPin = typeof pin === 'string' ? pin.trim() : String(pin ?? '').trim();

    if (!normalizedEmployeeId || !normalizedPin) {
      return res.status(400).json({ error: 'Employee ID and PIN are required' });
    }

    // Find employee
    const [employee] = await db
      .select()
      .from(employees)
      .where(and(
        eq(employees.id, normalizedEmployeeId),
        eq(employees.active, true)
      ))
      .limit(1);

    if (!employee) {
      console.warn('[auth/login] Invalid ID - employee not found or inactive', {
        employeeId: normalizedEmployeeId,
      });
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    // Verify PIN using bcrypt
    const providedPin = normalizedPin;
    const storedPinHash = employee.pinHash;
    if (!storedPinHash) {
      console.warn('[auth/login] No PIN hash found for employee', {
        employeeId: normalizedEmployeeId,
      });
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    // Check if PIN is valid (handle both bcrypt hashes and plain text PINs)
    let isValidPin = false;
    if (storedPinHash.startsWith('$2b$') || storedPinHash.startsWith('$2a$')) {
      // It's a bcrypt hash, use bcrypt comparison
      isValidPin = await bcrypt.compare(providedPin, storedPinHash);
    } else {
      // It's plain text, do direct comparison
      isValidPin = providedPin === storedPinHash;
    }

    if (!isValidPin) {
      console.warn('[auth/login] Invalid PIN attempt', {
        employeeId: normalizedEmployeeId,
      });
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    console.log('[auth/login] Login successful', {
      employeeId: employee.id,
      role: employee.role,
    });

    res.json({
      success: true,
      employee: {
        id: employee.id,
        fullName: employee.fullName,
        role: employee.role,
        branch: employee.branch,
      }
    });
  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// =============================================================================
// ATTENDANCE - Check In / Check Out
// الحضور والانصراف
// =============================================================================

// Check In
app.post('/api/attendance/check-in', async (req, res) => {
  try {
    const { employee_id, latitude, longitude } = req.body;

    if (!employee_id) {
      return res.status(400).json({ error: 'Employee ID is required' });
    }

    const today = new Date().toISOString().split('T')[0];

    // Check if already checked in today
    const [existing] = await db
      .select()
      .from(attendance)
      .where(and(
        eq(attendance.employeeId, employee_id),
        eq(attendance.date, today),
        eq(attendance.status, 'active')
      ))
      .limit(1);

    if (existing) {
      return res.status(400).json({ 
        error: 'Already checked in today',
        attendance: existing 
      });
    }

    // Create new attendance record
    const insertResult = await db
      .insert(attendance)
      .values({
        employeeId: employee_id,
        checkInTime: new Date(),
        date: today,
        status: 'active',
      })
      .returning();
    const newAttendance = extractFirstRow(insertResult);

    // Create pulse for location tracking
    if (latitude && longitude) {
      // Note: pulses table requires userId and branchId
      // Need employee record for branchId
      const [employee] = await db
        .select()
        .from(employees)
        .where(eq(employees.id, employee_id))
        .limit(1);

      if (employee && employee.branchId) {
        await db.insert(pulses).values({
          employeeId: employee_id,
          branchId: employee.branchId,
          latitude,
          longitude,
          isWithinGeofence: true,
        });
      }
    }

    res.json({
      success: true,
      message: 'تم تسجيل الحضور بنجاح',
      attendance: newAttendance,
    });
  } catch (error) {
    console.error('Check-in error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Check Out
app.post('/api/attendance/check-out', async (req, res) => {
  try {
    const { employee_id, latitude, longitude } = req.body;

    if (!employee_id) {
      return res.status(400).json({ error: 'Employee ID is required' });
    }

    const today = new Date().toISOString().split('T')[0];

    // Find active attendance record
    const [activeAttendance] = await db
      .select()
      .from(attendance)
      .where(and(
        eq(attendance.employeeId, employee_id),
        eq(attendance.date, today),
        eq(attendance.status, 'active')
      ))
      .limit(1);

    if (!activeAttendance) {
      return res.status(400).json({ error: 'No active check-in found for today' });
    }

    // Calculate work hours
    const checkOutTime = new Date();
    const checkInTime = new Date(activeAttendance.checkInTime!);
    const workHours = (checkOutTime.getTime() - checkInTime.getTime()) / (1000 * 60 * 60);

    // Update attendance record
    const updateResult = await db
      .update(attendance)
      .set({
        checkOutTime,
        workHours: workHours.toFixed(2),
        status: 'completed',
        updatedAt: new Date(),
      })
      .where(eq(attendance.id, activeAttendance.id))
      .returning();
    const updated = extractFirstRow(updateResult);

    // Create pulse for location tracking
    if (latitude && longitude) {
      const [employee] = await db
        .select()
        .from(employees)
        .where(eq(employees.id, employee_id))
        .limit(1);

      if (employee) {
        await db.insert(pulses).values({
          employeeId: employee_id,
          branchId: employee.branchId,
          latitude,
          longitude,
          status: 'IN',
          createdAt: new Date(),
        });
      }
    }

    res.json({
      success: true,
      message: 'تم تسجيل الانصراف بنجاح',
      attendance: updated,
      workHours: parseFloat(workHours.toFixed(2)),
    });
  } catch (error) {
    console.error('Check-out error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// =============================================================================
// PULSES - عدد النبضات والأرباح اللحظية
// =============================================================================

// Get active employee pulse count for today (shift-based if active, else 0)
app.get('/api/pulses/active/:employeeId', async (req, res) => {
  try {
    const { employeeId } = req.params;
    const today = new Date().toISOString().split('T')[0];

    const [todayAttendance] = await db
      .select()
      .from(attendance)
      .where(and(eq(attendance.employeeId, employeeId), eq(attendance.date, today)))
      .limit(1);

    if (!todayAttendance || todayAttendance.status !== 'active') {
      return res.json({ success: true, active: false, validPulseCount: 0, earnings: 0 });
    }

    const startTs = new Date(todayAttendance.checkInTime!);
    const now = new Date();

    const result = await db
      .select({ count: sql<number>`count(*)` })
      .from(pulses)
      .where(and(
        eq(pulses.employeeId, employeeId),
        eq(pulses.isWithinGeofence, true),
        gte(pulses.createdAt, startTs),
        lte(pulses.createdAt, now)
      ));

    const validPulseCount = Number(result[0]?.count) || 0;
    const HOURLY_RATE = 40;
    const pulseValue = (HOURLY_RATE / 3600) * 30; // قيمة كل نبضة
    const earnings = validPulseCount * pulseValue;

    res.json({
      success: true,
      active: true,
      validPulseCount,
      earnings: parseFloat(earnings.toFixed(2)),
      checkInTime: todayAttendance.checkInTime,
    });
  } catch (error) {
    console.error('Get active pulses error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Get pulse count for a custom period
app.get('/api/pulses/period/:employeeId', async (req, res) => {
  try {
    const { employeeId } = req.params;
    const { start, end } = req.query;

    if (!start || !end) {
      return res.status(400).json({ error: 'start and end query params are required (ISO date/time)' });
    }

    const startTs = new Date(String(start));
    const endTs = new Date(String(end));

    const result = await db
      .select({ count: sql<number>`count(*)` })
      .from(pulses)
      .where(and(
        eq(pulses.employeeId, employeeId),
        eq(pulses.isWithinGeofence, true),
        gte(pulses.createdAt, startTs),
        lte(pulses.createdAt, endTs)
      ));

    const validPulseCount = Number(result[0]?.count) || 0;
    const HOURLY_RATE = 40;
    const pulseValue = (HOURLY_RATE / 3600) * 30;
    const earnings = validPulseCount * pulseValue;

    res.json({
      success: true,
      validPulseCount,
      earnings: parseFloat(earnings.toFixed(2)),
      period: { start: startTs.toISOString(), end: endTs.toISOString() },
    });
  } catch (error) {
    console.error('Get period pulses error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// =============================================================================
// ATTENDANCE REQUESTS - طلبات الحضور/الانصراف
// =============================================================================

// Request forgotten check-in
app.post('/api/attendance/request-checkin', async (req, res) => {
  try {
    const { employee_id, requested_time, reason } = req.body;

    if (!employee_id || !requested_time || !reason) {
      return res.status(400).json({ 
        error: 'Employee ID, requested time, and reason are required' 
      });
    }

    // تحقق من وجود طلب لنفس اليوم ولنفس الموظف
    const reqDate = new Date(requested_time);
    const reqDay = reqDate.toISOString().split('T')[0];
    const [existing] = await db
      .select()
      .from(attendanceRequests)
      .where(and(
        eq(attendanceRequests.employeeId, employee_id),
        eq(attendanceRequests.requestType, 'check-in'),
        eq(attendanceRequests.status, 'pending'),
        sql`DATE(${attendanceRequests.requestedTime}) = ${reqDay}`
      ))
      .limit(1);
    if (existing) {
      return res.status(400).json({ error: 'يوجد بالفعل طلب حضور معلق لهذا اليوم' });
    }

    const insertResult = await db
      .insert(attendanceRequests)
      .values({
        employeeId: employee_id,
        requestType: 'check-in',
        requestedTime: reqDate,
        reason,
        status: 'pending',
      })
      .returning();
    const request = extractFirstRow(insertResult);

    res.json({
      success: true,
      message: 'تم إرسال طلب الحضور للمراجعة',
      request,
    });
  } catch (error) {
    console.error('Check-in request error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Request forgotten check-out
app.post('/api/attendance/request-checkout', async (req, res) => {
  try {
    const { employee_id, requested_time, reason } = req.body;

    if (!employee_id || !requested_time || !reason) {
      return res.status(400).json({ 
        error: 'Employee ID, requested time, and reason are required' 
      });
    }

    const insertResult = await db
      .insert(attendanceRequests)
      .values({
        employeeId: employee_id,
        requestType: 'check-out',
        requestedTime: new Date(requested_time),
        reason,
        status: 'pending',
      })
      .returning();
    const request = extractFirstRow(insertResult);

    res.json({
      success: true,
      message: 'تم إرسال طلب الانصراف للمراجعة',
      request,
    });
  } catch (error) {
    console.error('Check-out request error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Get pending requests (for manager)
app.get('/api/attendance/requests', async (req, res) => {
  try {
    const { status = 'pending' } = req.query;

    const requests = await db
      .select({
        id: attendanceRequests.id,
        employeeId: attendanceRequests.employeeId,
        employeeName: employees.fullName,
        requestType: attendanceRequests.requestType,
        requestedTime: attendanceRequests.requestedTime,
        reason: attendanceRequests.reason,
        status: attendanceRequests.status,
        createdAt: attendanceRequests.createdAt,
      })
      .from(attendanceRequests)
      .innerJoin(employees, eq(attendanceRequests.employeeId, employees.id))
      .where(eq(attendanceRequests.status, status as 'pending' | 'approved' | 'rejected'))
      .orderBy(desc(attendanceRequests.createdAt));

    res.json({ requests });
  } catch (error) {
    console.error('Get requests error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Approve/reject attendance request
app.post('/api/attendance/requests/:requestId/review', async (req, res) => {
  try {
    const { requestId } = req.params;
    const { action, reviewer_id, notes } = req.body;

    if (!action || !['approve', 'reject'].includes(action)) {
      return res.status(400).json({ error: 'Action must be approve or reject' });
    }

    // Get request details
    const [request] = await db
      .select()
      .from(attendanceRequests)
      .where(eq(attendanceRequests.id, requestId))
      .limit(1);

    if (!request) {
      return res.status(404).json({ error: 'Request not found' });
    }

    // Update request status
    const updateResult = await db
      .update(attendanceRequests)
      .set({
        status: action === 'approve' ? 'approved' : 'rejected',
        reviewedBy: reviewer_id,
        reviewedAt: new Date(),
        reviewNotes: notes,
      })
      .where(eq(attendanceRequests.id, requestId))
      .returning();
    const updated = extractFirstRow(updateResult);

    // If approved, create/update attendance record
    if (action === 'approve') {
      const requestedDateTime = new Date(request.requestedTime);
      const requestDate = requestedDateTime.toISOString().split('T')[0];

      if (request.requestType === 'check-in') {
        // Check if attendance already exists for this date
        const [existing] = await db
          .select()
          .from(attendance)
          .where(and(
            eq(attendance.employeeId, request.employeeId),
            eq(attendance.date, requestDate)
          ))
          .limit(1);

        if (!existing) {
          await db.insert(attendance).values({
            employeeId: request.employeeId,
            checkInTime: requestedDateTime,
            date: requestDate,
            status: 'active',
          });
        } else {
          // Update existing record with the new check-in time
          await db
            .update(attendance)
            .set({
              checkInTime: requestedDateTime,
              status: 'active',
            })
            .where(eq(attendance.id, existing.id));
        }
      } else if (request.requestType === 'check-out') {
        const [activeAttendance] = await db
          .select()
          .from(attendance)
          .where(and(
            eq(attendance.employeeId, request.employeeId),
            eq(attendance.date, requestDate),
            eq(attendance.status, 'active')
          ))
          .limit(1);

        if (activeAttendance) {
          const checkOutTime = requestedDateTime;
          const checkInTime = new Date(activeAttendance.checkInTime!);
          const workHours = (checkOutTime.getTime() - checkInTime.getTime()) / (1000 * 60 * 60);

          await db
            .update(attendance)
            .set({
              checkOutTime,
              workHours: workHours.toFixed(2),
              status: 'completed',
            })
            .where(eq(attendance.id, activeAttendance.id));
        }
      }
    }

    res.json({
      success: true,
      message: action === 'approve' ? 'تم الموافقة على الطلب' : 'تم رفض الطلب',
      request: updated,
    });
  } catch (error) {
    console.error('Review request error:', error);
    console.error('Error stack:', error?.stack);
    console.error('Error message:', error?.message);
    res.status(500).json({ error: 'Internal server error', details: error?.message });
  }
});

// =============================================================================
// LEAVE REQUESTS - طلبات الإجازات
// =============================================================================

// Create leave request
app.post('/api/leave/request', async (req, res) => {
  try {
    const { employee_id, start_date, end_date, reason } = req.body;

    if (!employee_id || !start_date || !end_date) {
      return res.status(400).json({ 
        error: 'Employee ID, start date, and end date are required' 
      });
    }

    const startDate = new Date(start_date);
    const endDate = new Date(end_date);
    const now = new Date();

    // Calculate hours until leave starts
    const hoursUntilLeave = (startDate.getTime() - now.getTime()) / (1000 * 60 * 60);

    // Determine leave type
    let leaveType: 'regular' | 'emergency' = 'regular';
    if (hoursUntilLeave < 48) {
      leaveType = 'emergency';
      if (!reason) {
        return res.status(400).json({ 
          error: 'السبب مطلوب للإجازة الطارئة (أقل من 48 ساعة)' 
        });
      }
    }

    // Calculate days
    const daysCount = Math.ceil((endDate.getTime() - startDate.getTime()) / (1000 * 60 * 60 * 24)) + 1;

    // Calculate allowance (100 EGP fixed for <= 2 days, 0 for more than 2 days)
    let allowanceAmount = 0;
    if (daysCount <= 2) {
      allowanceAmount = 100; // حافز ثابت 100 جنيه
    }

    const insertResult = await db
      .insert(leaveRequests)
      .values({
        employeeId: employee_id,
        startDate: start_date,
        endDate: end_date,
        leaveType,
        reason,
        daysCount,
        allowanceAmount: allowanceAmount > 0 ? allowanceAmount.toString() : '0',
        status: 'pending',
      })
      .returning();
    const leaveRequest = extractFirstRow(insertResult);

    res.json({
      success: true,
      message: 'تم إرسال طلب الإجازة للمراجعة',
      request: normalizeNumericFields(leaveRequest, ['daysCount', 'allowanceAmount']),
      leaveRequest: normalizeNumericFields(leaveRequest, ['daysCount', 'allowanceAmount']),
      allowanceAmount,
    });
  } catch (error) {
    console.error('Leave request error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Get leave requests
app.get('/api/leave/requests', async (req, res) => {
  try {
    const { employee_id, status } = req.query;

    let query = db
      .select({
        id: leaveRequests.id,
        employeeId: leaveRequests.employeeId,
        employeeName: employees.fullName,
        startDate: leaveRequests.startDate,
        endDate: leaveRequests.endDate,
        leaveType: leaveRequests.leaveType,
        reason: leaveRequests.reason,
        daysCount: leaveRequests.daysCount,
        allowanceAmount: leaveRequests.allowanceAmount,
        status: leaveRequests.status,
        createdAt: leaveRequests.createdAt,
      })
      .from(leaveRequests)
      .innerJoin(employees, eq(leaveRequests.employeeId, employees.id))
      .$dynamic();

    if (employee_id) {
      query = query.where(eq(leaveRequests.employeeId, employee_id as string));
    }

    if (status) {
      query = query.where(eq(leaveRequests.status, status as 'pending' | 'approved' | 'rejected'));
    }

    const requests = await query.orderBy(desc(leaveRequests.createdAt));

    res.json({ 
      requests: requests.map(r => normalizeNumericFields(r, ['daysCount', 'allowanceAmount']))
    });
  } catch (error) {
    console.error('Get leave requests error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Approve/reject leave request
app.post('/api/leave/requests/:requestId/review', async (req, res) => {
  try {
    const { requestId } = req.params;
    const { action, reviewer_id, notes } = req.body;

    if (!action || !['approve', 'reject'].includes(action)) {
      return res.status(400).json({ error: 'Action must be approve or reject' });
    }

    const updateResult = await db
      .update(leaveRequests)
      .set({
        status: action === 'approve' ? 'approved' : 'rejected',
        reviewedBy: req.body.reviewer_id,
        reviewedAt: new Date(),
        reviewNotes: req.body.notes,
      })
      .where(eq(leaveRequests.id, req.params.requestId))
      .returning();
    const updated = extractFirstRow(updateResult);

    res.json({
      success: true,
      message: action === 'approve' ? 'تم الموافقة على الإجازة' : 'تم رفض الإجازة',
      request: normalizeNumericFields(updated, ['daysCount', 'allowanceAmount']),
    });
  } catch (error) {
    console.error('Review leave request error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// =============================================================================
// SALARY ADVANCES - السلف
// =============================================================================

// Request salary advance
app.post('/api/advances/request', async (req, res) => {
  try {
    const { employee_id, amount } = req.body;

    if (!employee_id || !amount) {
      return res.status(400).json({ error: 'Employee ID and amount are required' });
    }

    // Get employee info
    const [employee] = await db
      .select()
      .from(employees)
      .where(eq(employees.id, employee_id))
      .limit(1);

    if (!employee) {
      return res.status(404).json({ error: 'Employee not found' });
    }

    // Check if requested in last 5 days
    const fiveDaysAgo = new Date();
    fiveDaysAgo.setDate(fiveDaysAgo.getDate() - 5);

    const [recentAdvance] = await db
      .select()
      .from(advances)
      .where(and(
        eq(advances.employeeId, employee_id),
        gte(advances.requestDate, fiveDaysAgo)
      ))
      .limit(1);

    if (recentAdvance) {
      return res.status(400).json({ 
        error: 'يمكن طلب سلفة كل 5 أيام فقط' 
      });
    }

    // Calculate real-time earnings based on pulses
    // Get start of current pay period (1st of current month)
    const now = new Date();
    const periodStart = new Date(now.getFullYear(), now.getMonth(), 1);
    
    // Count valid pulses in current period
    const validPulsesResult = await db
      .select({ count: sql<number>`count(*)` })
      .from(pulses)
      .where(and(
        eq(pulses.employeeId, employee_id),
        eq(pulses.isWithinGeofence, true),
        gte(pulses.createdAt, periodStart),
        lte(pulses.createdAt, now)
      ));

    const validPulseCount = validPulsesResult[0]?.count || 0;
    
    // Calculate earnings (40 EGP/hour, pulse every 30 seconds = 0.333 EGP per pulse)
    const HOURLY_RATE = 40;
    const pulseValue = (HOURLY_RATE / 3600) * 30;
    const totalRealTimeEarnings = validPulseCount * pulseValue;
    
    // Eligible amount is 30% of real-time earnings
    const eligibleAmount = totalRealTimeEarnings * 0.3;

    if (parseFloat(amount) > eligibleAmount) {
      return res.status(400).json({ 
        error: `الحد الأقصى للسلفة هو ${Math.round(eligibleAmount * 100) / 100} جنيه (30% من الأرباح الحالية ${Math.round(totalRealTimeEarnings * 100) / 100} جنيه)` 
      });
    }

    const insertResult = await db
      .insert(advances)
      .values({
        employeeId: employee_id,
        amount,
        eligibleAmount: eligibleAmount.toString(),
        currentSalary: totalRealTimeEarnings.toString(),
        status: 'pending',
      })
      .returning();
    const advance = extractFirstRow(insertResult);

    res.json({
      success: true,
      message: 'تم إرسال طلب السلفة للمراجعة',
      advance: normalizeNumericFields(advance, ['amount', 'eligibleAmount', 'currentSalary']),
      request: normalizeNumericFields(advance, ['amount', 'eligibleAmount', 'currentSalary']),
    });
  } catch (error) {
    console.error('Advance request error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Get advances
app.get('/api/advances', async (req, res) => {
  try {
    const { employee_id, status } = req.query;

    let query = db
      .select({
        id: advances.id,
        employeeId: advances.employeeId,
        employeeName: employees.fullName,
        amount: advances.amount,
        eligibleAmount: advances.eligibleAmount,
        status: advances.status,
        requestDate: advances.requestDate,
      })
      .from(advances)
      .innerJoin(employees, eq(advances.employeeId, employees.id))
      .$dynamic();

    if (employee_id) {
      query = query.where(eq(advances.employeeId, employee_id as string));
    }

    if (status) {
      query = query.where(eq(advances.status, status as 'pending' | 'approved' | 'rejected'));
    }

    const advancesList = await query.orderBy(desc(advances.requestDate));

    res.json({ 
      advances: advancesList.map(a => normalizeNumericFields(a, ['amount', 'eligibleAmount']))
    });
  } catch (error) {
    console.error('Get advances error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Approve/reject advance
app.post('/api/advances/:advanceId/review', async (req, res) => {
  try {
    const { advanceId } = req.params;
    const { action, reviewer_id } = req.body;

    if (!action || !['approve', 'reject'].includes(action)) {
      return res.status(400).json({ error: 'Action must be approve or reject' });
    }

    // Update advance status
    const updateResult = await db
      .update(advances)
      .set({
        status: action === 'approve' ? 'approved' : 'rejected',
        reviewedBy: reviewer_id,
        reviewedAt: new Date(),
      })
      .where(eq(advances.id, advanceId))
      .returning({ id: advances.id, employeeId: advances.employeeId, amount: advances.amount, eligibleAmount: advances.eligibleAmount, currentSalary: advances.currentSalary, status: advances.status, reviewedBy: advances.reviewedBy, reviewedAt: advances.reviewedAt });
    const updated = extractFirstRow(updateResult) as any;

    // If approved, deduct the advance amount from salary by creating a deduction record
    if (action === 'approve' && updated) {
      await db.insert(deductions).values({
        employeeId: updated.employeeId,
        amount: String(updated.amount),
        reason: 'سلفة معتمدة من المدير',
        deductionDate: new Date().toISOString().split('T')[0],
        deductionType: 'advance',
        appliedBy: reviewer_id,
      });
    }

    res.json({
      success: true,
      message: action === 'approve' ? 'تم الموافقة على السلفة وخصمها من الراتب' : 'تم رفض السلفة',
      advance: updated,
    });
  } catch (error) {
    console.error('Absence notification error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Get absence notifications (for manager)
app.get('/api/absence/notifications', async (req, res) => {
  try {
    const { status = 'pending' } = req.query;

    const notifications = await db
      .select({
        id: absenceNotifications.id,
        employeeId: absenceNotifications.employeeId,
        employeeName: employees.fullName,
        absenceDate: absenceNotifications.absenceDate,
        status: absenceNotifications.status,
        deductionApplied: absenceNotifications.deductionApplied,
        notifiedAt: absenceNotifications.notifiedAt,
      })
      .from(absenceNotifications)
      .innerJoin(employees, eq(absenceNotifications.employeeId, employees.id))
      .where(eq(absenceNotifications.status, status as 'pending' | 'approved' | 'rejected'))
      .orderBy(desc(absenceNotifications.notifiedAt));

    res.json({ notifications });
  } catch (error) {
    console.error('Get absence notifications error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Review absence notification (approve/reject with smart deduction logic)
app.post('/api/absence/:notificationId/review', async (req, res) => {
  try {
    const { notificationId } = req.params;
    const { action, reviewer_id, notes } = req.body;

    if (!action || !['approve', 'reject'].includes(action)) {
      return res.status(400).json({ error: 'Action must be approve or reject' });
    }

    // Get notification
    const [notification] = await db
      .select()
      .from(absenceNotifications)
      .where(eq(absenceNotifications.id, notificationId))
      .limit(1);

    if (!notification) {
      return res.status(404).json({ error: 'Notification not found' });
    }

    let deductionAmount = '0';

    // If rejected → apply 2 days deduction (غياب بدون إذن)
    // حسب السيستم الإداري: الغياب مرة واحدة بدون إذن = خصم يومين كاملين
    if (action === 'reject') {
      deductionAmount = '400'; // 2 days * 200 EGP/day (خصم يومين)

      // Create deduction record
      await db.insert(deductions).values({
        employeeId: notification.employeeId,
        amount: deductionAmount,
        reason: notes || 'غياب بدون إذن - خصم يومين كاملين',
        deductionDate: notification.absenceDate,
        deductionType: 'absence',
        appliedBy: reviewer_id,
      });
    }

    // Update notification
    const updateResult = await db
      .update(absenceNotifications)
      .set({
        status: action === 'approve' ? 'approved' : 'rejected',
        deductionApplied: action === 'reject',
        deductionAmount: action === 'reject' ? deductionAmount : null,
        reviewedBy: reviewer_id,
        reviewedAt: new Date(),
      })
      .where(eq(absenceNotifications.id, notificationId))
      .returning();
    const updated = extractFirstRow(updateResult);

    res.json({
      success: true,
      message: action === 'approve' 
        ? 'تم الموافقة على الغياب - غياب بإذن' 
        : 'تم رفض الغياب - تم تطبيق خصم يومين',
      notification: updated,
      deductionAmount: action === 'reject' ? deductionAmount : '0',
    });
  } catch (error) {
    console.error('Review absence error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Apply deduction for absence (legacy - kept for backward compatibility)
app.post('/api/absence/:notificationId/apply-deduction', async (req, res) => {
  try {
    const { notificationId } = req.params;
    const { reviewer_id, amount } = req.body;

    // Get notification
    const [notification] = await db
      .select()
      .from(absenceNotifications)
      .where(eq(absenceNotifications.id, notificationId))
      .limit(1);

    if (!notification) {
      return res.status(404).json({ error: 'Notification not found' });
    }

    // Default deduction: 2 days work (assuming 8 hours/day * hourly rate)
    const deductionAmount = amount || '400'; // 2 days * 200 EGP/day

    // Create deduction record
    await db.insert(deductions).values({
      employeeId: notification.employeeId,
      amount: deductionAmount,
      reason: 'غياب بدون إذن',
      deductionDate: notification.absenceDate,
      deductionType: 'absence',
      appliedBy: reviewer_id,
    });

    // Update notification
    const updateResult = await db
      .update(absenceNotifications)
      .set({
        status: 'approved',
        deductionApplied: true,
        deductionAmount: deductionAmount,
        reviewedBy: reviewer_id,
        reviewedAt: new Date(),
      })
      .where(eq(absenceNotifications.id, notificationId))
      .returning();
    const updated = extractFirstRow(updateResult);

    res.json({
      success: true,
      message: 'تم تطبيق الخصم',
      notification: updated,
      deductionAmount,
    });
  } catch (error) {
    console.error('Apply deduction error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// =============================================================================
// ATTENDANCE REPORTS - تقارير الحضور
// =============================================================================

// Get comprehensive employee report (يوم 1 و 16 من كل شهر)
// يتم حساب حافز الغياب وجميع الخصومات والحوافز في هذا التقرير
// حافز الغياب = 100 جنيه ثابت إذا لم يتجاوز عدد أيام الإجازة يومين
// يتجدد الحافز كل 15 يوم (من 1-15 ومن 16-نهاية الشهر)
app.get('/api/reports/comprehensive/:employeeId', async (req, res) => {
  try {
    const { employeeId } = req.params;
    const { start_date, end_date, skip_date_check } = req.query;

    // Check if it's 1st or 16th (skip for managers/admins)
    // التقارير متاحة فقط يوم 1 (للفترة من 16-31) ويوم 16 (للفترة من 1-15)
    if (!skip_date_check) {
      const today = new Date().getDate();
      if (today !== 1 && today !== 16) {
        return res.status(403).json({ 
          error: 'التقارير متاحة فقط يوم 1 و 16 من كل شهر - يتجدد حافز الغياب كل 15 يوم' 
        });
      }
    }

    // Get employee info
    const [employee] = await db
      .select()
      .from(employees)
      .where(eq(employees.id, employeeId))
      .limit(1);

    if (!employee) {
      return res.status(404).json({ error: 'Employee not found' });
    }

    // Get attendance records
    const attendanceRecords = await db
      .select()
      .from(attendance)
      .where(and(
        eq(attendance.employeeId, employeeId),
        gte(attendance.date, start_date as string),
        lte(attendance.date, end_date as string)
      ))
      .orderBy(attendance.date);

    // Get valid pulses count for salary calculation
    const validPulsesResult = await db
      .select({ count: sql<number>`count(*)` })
      .from(pulses)
      .where(and(
        eq(pulses.employeeId, employeeId),
        eq(pulses.isWithinGeofence, true),
        gte(pulses.createdAt, new Date(start_date as string)),
        lte(pulses.createdAt, new Date(end_date as string))
      ));

    const validPulseCount = validPulsesResult[0]?.count || 0;
    
    // Calculate salary from pulses (40 EGP/hour, pulse every 30 seconds)
    const HOURLY_RATE = 40;
    const pulseValue = (HOURLY_RATE / 3600) * 30; // 0.333 EGP per pulse
    const grossSalary = validPulseCount * pulseValue;

    // Get advances
    const advancesList = await db
      .select()
      .from(advances)
      .where(and(
        eq(advances.employeeId, employeeId),
        eq(advances.status, 'approved'),
        gte(advances.requestDate, new Date(start_date as string)),
        lte(advances.requestDate, new Date(end_date as string))
      ));

    // Get leaves
    const leaves = await db
      .select()
      .from(leaveRequests)
      .where(and(
        eq(leaveRequests.employeeId, employeeId),
        eq(leaveRequests.status, 'approved'),
        gte(leaveRequests.startDate, start_date as string),
        lte(leaveRequests.endDate, end_date as string)
      ));

    // Get deductions
    const deductionsList = await db
      .select()
      .from(deductions)
      .where(and(
        eq(deductions.employeeId, employeeId),
        gte(deductions.deductionDate, start_date as string),
        lte(deductions.deductionDate, end_date as string)
      ));

    // Calculate totals
    const totalWorkHours = attendanceRecords.reduce((sum, record) => 
      sum + parseFloat(record.workHours || '0'), 0
    );

    const totalAdvances = advancesList.reduce((sum, advance) => 
      sum + parseFloat(advance.amount || '0'), 0
    );

    const totalDeductions = deductionsList.reduce((sum, deduction) => 
      sum + parseFloat(deduction.amount || '0'), 0
    );

    const totalLeaveAllowance = leaves.reduce((sum, leave) => 
      sum + parseFloat(leave.allowanceAmount || '0'), 0
    );

    // Calculate attendance allowance (حافز الغياب)
    // يُمنح 100 جنيه إذا لم يتجاوز عدد أيام الإجازة المعتمدة يومين
    let attendanceAllowance = 0;
    const totalLeaveDays = leaves.reduce((sum, leave) => sum + (leave.daysCount || 0), 0);
    
    if (totalLeaveDays <= 2) {
      attendanceAllowance = 100; // حافز الغياب 100 جنيه ثابت
    }
    // إذا أخذ إجازة أكثر من يومين → يخسر حافز الغياب

  // Calculate net salary (خصومات الراتب تشمل السلف المعتمدة تلقائياً)
  const netSalary = grossSalary - totalDeductions + totalLeaveAllowance + attendanceAllowance;

    res.json({
      employee: {
        id: employee.id,
        fullName: employee.fullName,
        role: employee.role,
        branch: employee.branch,
      },
      period: { 
        start: start_date, 
        end: end_date,
        reportDate: new Date().toISOString()
      },
      attendance: attendanceRecords,
      advances: advancesList,
      leaves,
      deductions: deductionsList,
      salary: {
        validPulses: validPulseCount,
        grossSalary: parseFloat(grossSalary.toFixed(2)),
        totalAdvances: parseFloat(totalAdvances.toFixed(2)),
        totalDeductions: parseFloat(totalDeductions.toFixed(2)),
        totalLeaveAllowance: parseFloat(totalLeaveAllowance.toFixed(2)),
        attendanceAllowance: parseFloat(attendanceAllowance.toFixed(2)),
        netSalary: parseFloat(netSalary.toFixed(2)),
      },
      summary: {
        totalWorkHours: parseFloat(totalWorkHours.toFixed(2)),
        totalWorkDays: attendanceRecords.length,
        totalLeaveDays: leaves.reduce((sum, leave) => sum + (leave.daysCount || 0), 0),
      }
    });
  } catch (error) {
    console.error('Get comprehensive report error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Get employee attendance report (legacy - kept for backward compatibility)
app.get('/api/reports/attendance/:employeeId', async (req, res) => {
  try {
    const { employeeId } = req.params;
    const { start_date, end_date } = req.query;

    // Get attendance records
    const attendanceRecords = await db
      .select()
      .from(attendance)
      .where(and(
        eq(attendance.employeeId, employeeId),
        gte(attendance.date, start_date as string),
        lte(attendance.date, end_date as string)
      ))
      .orderBy(attendance.date);

    // Get advances
    const advancesList = await db
      .select()
      .from(advances)
      .where(and(
        eq(advances.employeeId, employeeId),
        eq(advances.status, 'approved'),
        gte(advances.requestDate, new Date(start_date as string)),
        lte(advances.requestDate, new Date(end_date as string))
      ));

    // Get leaves
    const leaves = await db
      .select()
      .from(leaveRequests)
      .where(and(
        eq(leaveRequests.employeeId, employeeId),
        eq(leaveRequests.status, 'approved'),
        gte(leaveRequests.startDate, start_date as string),
        lte(leaveRequests.endDate, end_date as string)
      ));

    // Get deductions
    const deductionsList = await db
      .select()
      .from(deductions)
      .where(and(
        eq(deductions.employeeId, employeeId),
        gte(deductions.deductionDate, start_date as string),
        lte(deductions.deductionDate, end_date as string)
      ));

    // Calculate totals
    const totalWorkHours = attendanceRecords.reduce((sum, record) => 
      sum + parseFloat(record.workHours || '0'), 0
    );

    const totalAdvances = advancesList.reduce((sum, advance) => 
      sum + parseFloat(advance.amount || '0'), 0
    );

    const totalDeductions = deductionsList.reduce((sum, deduction) => 
      sum + parseFloat(deduction.amount || '0'), 0
    );

    const totalLeaveAllowance = leaves.reduce((sum, leave) => 
      sum + parseFloat(leave.allowanceAmount || '0'), 0
    );

    // Calculate attendance allowance (حافز الغياب)
    let attendanceAllowance = 0;
    const totalLeaveDays = leaves.reduce((sum, leave) => sum + (leave.daysCount || 0), 0);
    
    if (totalLeaveDays <= 2) {
      attendanceAllowance = 100; // حافز الغياب 100 جنيه ثابت
    }

    res.json({
      employeeId,
      period: { start: start_date, end: end_date },
      attendance: attendanceRecords,
      advances: advancesList,
      leaves,
      deductions: deductionsList,
      summary: {
        totalWorkHours: parseFloat(totalWorkHours.toFixed(2)),
        totalAdvances: parseFloat(totalAdvances.toFixed(2)),
        totalDeductions: parseFloat(totalDeductions.toFixed(2)),
        totalLeaveAllowance: parseFloat(totalLeaveAllowance.toFixed(2)),
        attendanceAllowance: parseFloat(attendanceAllowance.toFixed(2)),
      }
    });
  } catch (error) {
    console.error('Get report error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// =============================================================================
// EMPLOYEE MANAGEMENT - إدارة الموظفين
// =============================================================================

// Get all employees
app.get('/api/employees', async (req, res) => {
  try {
    const employeesList = await db
      .select()
      .from(employees)
      .where(eq(employees.active, true));

    res.json({ employees: employeesList });
  } catch (error) {
    console.error('Get employees error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Get single employee
app.get('/api/employees/:id', async (req, res) => {
  try {
    const { id } = req.params;

    const [employee] = await db
      .select()
      .from(employees)
      .where(eq(employees.id, id))
      .limit(1);

    if (!employee) {
      return res.status(404).json({ error: 'Employee not found' });
    }

    res.json({ employee });
  } catch (error) {
    console.error('Get employee error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Get employee current earnings
app.get('/api/employees/:id/current-earnings', async (req, res) => {
  try {
    const { id } = req.params;

    // Get employee
    const [employee] = await db
      .select()
      .from(employees)
      .where(eq(employees.id, id))
      .limit(1);

    if (!employee) {
      return res.status(404).json({ error: 'Employee not found' });
    }

    // Calculate real-time earnings based on pulses
    const now = new Date();
    const periodStart = new Date(now.getFullYear(), now.getMonth(), 1);
    
    // Count valid pulses in current period
    const validPulsesResult = await db
      .select({ count: sql<number>`count(*)` })
      .from(pulses)
      .where(and(
        eq(pulses.employeeId, id),
        eq(pulses.isWithinGeofence, true),
        gte(pulses.createdAt, periodStart),
        lte(pulses.createdAt, now)
      ));

    const validPulseCount = Number(validPulsesResult[0]?.count) || 0;
    
    // Calculate earnings (40 EGP/hour, pulse every 30 seconds = 0.333 EGP per pulse)
    const HOURLY_RATE = 40;
    const pulseValue = (HOURLY_RATE / 3600) * 30;
    const totalEarnings = validPulseCount * pulseValue;
    const maxAdvanceAmount = totalEarnings * 0.3;

    res.json({
      success: true,
      totalEarnings,
      total_earnings: totalEarnings,
      maxAdvanceAmount,
      max_advance_amount: maxAdvanceAmount,
      eligibleAdvance: maxAdvanceAmount,
      eligible_advance: maxAdvanceAmount,
      validPulseCount,
      periodStart: periodStart.toISOString(),
    });
  } catch (error) {
    console.error('Get current earnings error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Create employee
app.post('/api/employees', async (req, res) => {
  try {
    const rawId = typeof req.body.id === 'string' && req.body.id.trim() ? req.body.id : req.body.employeeId;
    const id = typeof rawId === 'string' ? rawId.trim() : '';

    const nameSource = typeof req.body.fullName === 'string' && req.body.fullName.trim()
      ? req.body.fullName
      : req.body.name;
    const fullName = typeof nameSource === 'string' ? nameSource.trim() : '';

    const pinSource = typeof req.body.pin === 'string' && req.body.pin.trim()
      ? req.body.pin
      : req.body.pinCode;
    const pin = typeof pinSource === 'string' ? pinSource.trim() : '';

    const branchInput = typeof req.body.branch === 'string' ? req.body.branch.trim() : undefined;
    const branch = branchInput ? branchInput : null;

    const roleInput = typeof req.body.role === 'string' ? req.body.role.trim().toLowerCase() : undefined;
    const allowedRoles = new Set(['owner', 'admin', 'manager', 'hr', 'monitor', 'staff']);
    const role = roleInput && allowedRoles.has(roleInput) ? roleInput : 'staff';

    const activeRaw = req.body.active;
    const active = typeof activeRaw === 'string'
      ? activeRaw.toLowerCase() !== 'false'
      : activeRaw === undefined
        ? true
        : Boolean(activeRaw);

    const hourlyRateRaw = req.body.hourlyRate ?? req.body.hourly_rate;
    let hourlyRate: number | undefined;
    if (hourlyRateRaw !== undefined && hourlyRateRaw !== null && String(hourlyRateRaw).trim() !== '') {
      const parsed = Number(hourlyRateRaw);
      if (!Number.isFinite(parsed) || parsed < 0) {
        return res.status(400).json({ error: 'hourlyRate must be a positive number' });
      }
      hourlyRate = parsed;
    }

    if (!id || !fullName || !pin) {
      return res.status(400).json({ error: 'id, fullName, and pin are required' });
    }

    const pinHash = await bcrypt.hash(pin, 10);

    const insertData: any = {
      id,
      fullName,
      pinHash,
      role,
      branch,
      active,
    };

    if (hourlyRate !== undefined) {
      insertData.hourlyRate = hourlyRate;
    }

    const [newEmployee] = await db
      .insert(employees)
      .values(insertData)
      .returning({
        id: employees.id,
        fullName: employees.fullName,
        role: employees.role,
        branch: employees.branch,
        hourlyRate: employees.hourlyRate,
        active: employees.active,
        createdAt: employees.createdAt,
        updatedAt: employees.updatedAt,
      });

    if (!newEmployee) {
      return res.status(500).json({ error: 'فشل إنشاء الموظف: استجابة غير متوقعة من قاعدة البيانات' });
    }

    res.status(201).json({
      success: true,
      message: 'تم إضافة الموظف بنجاح',
      employee: normalizeNumericFields(newEmployee, ['hourlyRate']),
    });
  } catch (error: any) {
    if (error?.code === '23505') {
      return res.status(409).json({ error: 'يوجد موظف بنفس المعرف بالفعل' });
    }
    console.error('Create employee error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// =============================================================================
// SHIFT MANAGEMENT - إدارة الشيفتات
// =============================================================================

// Get active shifts (employees currently working)
app.get('/api/shifts/active', async (req, res) => {
  try {
    const { branch_id } = req.query;
    const today = new Date().toISOString().split('T')[0];

    let query = db
      .select({
        attendanceId: attendance.id,
        employeeId: attendance.employeeId,
        employeeName: employees.fullName,
        employeeRole: employees.role,
        branch: employees.branch,
        checkInTime: attendance.checkInTime,
        workHours: attendance.workHours,
        status: attendance.status,
      })
      .from(attendance)
      .innerJoin(employees, eq(attendance.employeeId, employees.id))
      .where(and(
        eq(attendance.date, today),
        eq(attendance.status, 'active')
      ))
      .$dynamic();

    if (branch_id) {
      query = query.where(eq(employees.branchId, branch_id as string));
    }

    const activeShifts = await query.orderBy(attendance.checkInTime);

    res.json({
      success: true,
      activeShifts,
      count: activeShifts.length,
      date: today,
    });
  } catch (error) {
    console.error('Get active shifts error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Auto checkout (force checkout for active shifts)
app.post('/api/shifts/auto-checkout', async (req, res) => {
  try {
    const { employee_id, reason } = req.body;

    if (!employee_id) {
      return res.status(400).json({ error: 'Employee ID is required' });
    }

    const today = new Date().toISOString().split('T')[0];

    // Find active attendance record
    const [activeAttendance] = await db
      .select()
      .from(attendance)
      .where(and(
        eq(attendance.employeeId, employee_id),
        eq(attendance.date, today),
        eq(attendance.status, 'active')
      ))
      .limit(1);

    if (!activeAttendance) {
      return res.status(404).json({ error: 'No active shift found for this employee' });
    }

    const checkOutTime = new Date();
    const checkInTime = new Date(activeAttendance.checkInTime!);
    const workHours = (checkOutTime.getTime() - checkInTime.getTime()) / (1000 * 60 * 60);

    const updateResult = await db
      .update(attendance)
      .set({
        checkOutTime,
        workHours: workHours.toFixed(2),
        status: 'completed',
        isAutoCheckout: true,
      })
      .where(eq(attendance.id, activeAttendance.id))
      .returning();
    const updated = extractFirstRow(updateResult);

    res.json({
      success: true,
      message: 'تم تسجيل الانصراف التلقائي',
      attendance: updated,
      workHours: parseFloat(workHours.toFixed(2)),
      reason: reason || 'Auto checkout',
    });
  } catch (error) {
    console.error('Auto checkout error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Get employee current shift status
app.get('/api/shifts/status/:employeeId', async (req, res) => {
  try {
    const { employeeId } = req.params;
    const today = new Date().toISOString().split('T')[0];

    const [todayAttendance] = await db
      .select()
      .from(attendance)
      .where(and(
        eq(attendance.employeeId, employeeId),
        eq(attendance.date, today)
      ))
      .limit(1);

    if (!todayAttendance) {
      return res.json({
        hasShift: false,
        status: 'not_checked_in',
        message: 'لم يتم تسجيل الحضور اليوم',
      });
    }

    const isActive = todayAttendance.status === 'active';

    res.json({
      hasShift: true,
      status: todayAttendance.status,
      isActive,
      checkInTime: todayAttendance.checkInTime,
      checkOutTime: todayAttendance.checkOutTime,
      workHours: todayAttendance.workHours,
      message: isActive ? 'الموظف موجود حالياً في الشيفت' : 'تم تسجيل الانصراف',
    });
  } catch (error) {
    console.error('Get shift status error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Get daily attendance sheet (for managers)
app.get('/api/attendance/daily-sheet', async (req, res) => {
  try {
    const { date, branch_id } = req.query;
    const targetDate = date ? date as string : new Date().toISOString().split('T')[0];

    // Get all active employees
    let employeesQuery = db
      .select()
      .from(employees)
      .where(eq(employees.active, true))
      .$dynamic();

    if (branch_id) {
      employeesQuery = employeesQuery.where(eq(employees.branchId, branch_id as string));
    }

    const allEmployees = await employeesQuery;

    // Get attendance records for the date
    const attendanceRecords = await db
      .select()
      .from(attendance)
      .where(eq(attendance.date, targetDate));

    // Create attendance map
    const attendanceMap = new Map();
    attendanceRecords.forEach(record => {
      attendanceMap.set(record.employeeId, record);
    });

    // Build daily sheet
    const dailySheet = allEmployees.map(employee => {
      const attendanceRecord = attendanceMap.get(employee.id);

      if (!attendanceRecord) {
        return {
          employeeId: employee.id,
          employeeName: employee.fullName,
          role: employee.role,
          branch: employee.branch,
          status: 'غائب',
          checkInTime: null,
          checkOutTime: null,
          workHours: 0,
          isActive: false,
        };
      }

      return {
        employeeId: employee.id,
        employeeName: employee.fullName,
        role: employee.role,
        branch: employee.branch,
        status: attendanceRecord.status === 'active' ? 'موجود حالياً' : 'انصرف',
        checkInTime: attendanceRecord.checkInTime,
        checkOutTime: attendanceRecord.checkOutTime,
        workHours: parseFloat(attendanceRecord.workHours || '0'),
        isActive: attendanceRecord.status === 'active',
        isAutoCheckout: attendanceRecord.isAutoCheckout || false,
      };
    });

    // Calculate summary
    const present = dailySheet.filter(emp => emp.status !== 'غائب').length;
    const absent = dailySheet.filter(emp => emp.status === 'غائب').length;
    const currentlyWorking = dailySheet.filter(emp => emp.isActive).length;
    const totalWorkHours = dailySheet.reduce((sum, emp) => sum + emp.workHours, 0);

    res.json({
      success: true,
      date: targetDate,
      dailySheet,
      summary: {
        totalEmployees: allEmployees.length,
        present,
        absent,
        currentlyWorking,
        totalWorkHours: parseFloat(totalWorkHours.toFixed(2)),
      }
    });
  } catch (error) {
    console.error('Get daily attendance sheet error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// =============================================================================
// MANAGER DASHBOARD - لوحة تحكم المدير
// =============================================================================

app.get('/api/manager/dashboard', async (req, res) => {
  try {
    const pendingAttendanceRequests = await db
      .select({
        id: attendanceRequests.id,
        employeeId: attendanceRequests.employeeId,
        employeeName: employees.fullName,
        requestType: attendanceRequests.requestType,
        requestedTime: attendanceRequests.requestedTime,
        reason: attendanceRequests.reason,
        status: attendanceRequests.status,
        createdAt: attendanceRequests.createdAt,
      })
      .from(attendanceRequests)
      .innerJoin(employees, eq(attendanceRequests.employeeId, employees.id))
      .where(eq(attendanceRequests.status, 'pending'))
      .orderBy(desc(attendanceRequests.createdAt));

    // Ensure status and requestType are sent as strings
    const normalizedAttendanceRequests = pendingAttendanceRequests.map(a => ({
      ...a,
      status: String(a.status),
      requestType: String(a.requestType)
    }));

    const pendingLeaveRequests = await db
      .select({
        id: leaveRequests.id,
        employeeId: leaveRequests.employeeId,
        employeeName: employees.fullName,
        startDate: leaveRequests.startDate,
        endDate: leaveRequests.endDate,
        leaveType: leaveRequests.leaveType,
        reason: leaveRequests.reason,
        daysCount: leaveRequests.daysCount,
        allowanceAmount: leaveRequests.allowanceAmount,
        status: leaveRequests.status,
        createdAt: leaveRequests.createdAt,
      })
      .from(leaveRequests)
      .innerJoin(employees, eq(leaveRequests.employeeId, employees.id))
      .where(eq(leaveRequests.status, 'pending'))
      .orderBy(desc(leaveRequests.createdAt));

    const pendingAdvances = await db
      .select({
        id: advances.id,
        employeeId: advances.employeeId,
        employeeName: employees.fullName,
        amount: advances.amount,
        eligibleAmount: advances.eligibleAmount,
        currentSalary: advances.currentSalary,
        status: advances.status,
        requestDate: advances.requestDate,
      })
      .from(advances)
      .innerJoin(employees, eq(advances.employeeId, employees.id))
      .where(eq(advances.status, 'pending'))
      .orderBy(desc(advances.requestDate));

    const pendingAbsences = await db
      .select({
        id: absenceNotifications.id,
        employeeId: absenceNotifications.employeeId,
        employeeName: employees.fullName,
        absenceDate: absenceNotifications.absenceDate,
        status: absenceNotifications.status,
        deductionApplied: absenceNotifications.deductionApplied,
        notifiedAt: absenceNotifications.notifiedAt,
      })
      .from(absenceNotifications)
      .innerJoin(employees, eq(absenceNotifications.employeeId, employees.id))
      .where(eq(absenceNotifications.status, 'pending'))
      .orderBy(desc(absenceNotifications.notifiedAt));

    const pendingBreaks = await db
      .select({
        id: breaks.id,
        employeeId: breaks.employeeId,
        employeeName: employees.fullName,
        requestedDurationMinutes: breaks.requestedDurationMinutes,
        status: breaks.status,
        createdAt: breaks.createdAt,
      })
      .from(breaks)
      .innerJoin(employees, eq(breaks.employeeId, employees.id))
      .where(eq(breaks.status, 'PENDING'))
      .orderBy(desc(breaks.createdAt));

    // Ensure status is sent as string
    const normalizedBreaks = pendingBreaks.map(b => ({
      ...normalizeNumericFields(b, ['requestedDurationMinutes']),
      status: String(b.status)
    }));

    res.json({
      success: true,
      dashboard: {
        attendanceRequests: normalizedAttendanceRequests,
        leaveRequests: pendingLeaveRequests,
        advances: pendingAdvances,
        absences: pendingAbsences,
        breakRequests: normalizedBreaks,
        summary: {
          totalPendingRequests: pendingAttendanceRequests.length + pendingLeaveRequests.length + pendingAdvances.length + pendingAbsences.length + pendingBreaks.length,
          attendanceRequestsCount: pendingAttendanceRequests.length,
          leaveRequestsCount: pendingLeaveRequests.length,
          advancesCount: pendingAdvances.length,
          absencesCount: pendingAbsences.length,
          breakRequestsCount: pendingBreaks.length,
        }
      }
    });
  } catch (error) {
    console.error('Dashboard error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// =============================================================================
// OWNER DASHBOARD - لوحة تحكم المالك
// =============================================================================

app.get('/api/owner/dashboard', async (req, res) => {
  try {
    const ownerId = req.query.owner_id as string | undefined;

    if (!ownerId) {
      return res.status(400).json({ error: 'owner_id is required' });
    }

    const ownerRecord = await getOwnerRecord(ownerId);
    if (!ownerRecord) {
      return res.status(403).json({ error: 'لا توجد صلاحيات للوصول إلى لوحة المالك' });
    }

    const pendingAttendanceRequests = await db
      .select({
        id: attendanceRequests.id,
        employeeId: attendanceRequests.employeeId,
        employeeName: employees.fullName,
        employeeRole: employees.role,
        employeeBranch: employees.branch,
        requestType: attendanceRequests.requestType,
        requestedTime: attendanceRequests.requestedTime,
        reason: attendanceRequests.reason,
        status: attendanceRequests.status,
        createdAt: attendanceRequests.createdAt,
      })
      .from(attendanceRequests)
      .innerJoin(employees, eq(attendanceRequests.employeeId, employees.id))
      .where(and(
        eq(attendanceRequests.status, 'pending'),
        eq(employees.role, 'manager')
      ))
      .orderBy(desc(attendanceRequests.createdAt));

    const normalizedAttendance = pendingAttendanceRequests.map(request => ({
      ...request,
      status: String(request.status),
      requestType: String(request.requestType),
    }));

    const pendingLeaveRequests = await db
      .select({
        id: leaveRequests.id,
        employeeId: leaveRequests.employeeId,
        employeeName: employees.fullName,
        employeeRole: employees.role,
        employeeBranch: employees.branch,
        startDate: leaveRequests.startDate,
        endDate: leaveRequests.endDate,
        leaveType: leaveRequests.leaveType,
        reason: leaveRequests.reason,
        daysCount: leaveRequests.daysCount,
        allowanceAmount: leaveRequests.allowanceAmount,
        status: leaveRequests.status,
        createdAt: leaveRequests.createdAt,
      })
      .from(leaveRequests)
      .innerJoin(employees, eq(leaveRequests.employeeId, employees.id))
      .where(and(
        eq(leaveRequests.status, 'pending'),
        eq(employees.role, 'manager')
      ))
      .orderBy(desc(leaveRequests.createdAt));

    const normalizedLeaveRequests = pendingLeaveRequests.map(request =>
      normalizeNumericFields(request, ['allowanceAmount'])
    );

    const pendingAdvances = await db
      .select({
        id: advances.id,
        employeeId: advances.employeeId,
        employeeName: employees.fullName,
        employeeRole: employees.role,
        employeeBranch: employees.branch,
        amount: advances.amount,
        eligibleAmount: advances.eligibleAmount,
        currentSalary: advances.currentSalary,
        status: advances.status,
        requestDate: advances.requestDate,
      })
      .from(advances)
      .innerJoin(employees, eq(advances.employeeId, employees.id))
      .where(and(
        eq(advances.status, 'pending'),
        eq(employees.role, 'manager')
      ))
      .orderBy(desc(advances.requestDate));

    const normalizedAdvances = pendingAdvances.map(request =>
      normalizeNumericFields(request, ['amount', 'eligibleAmount', 'currentSalary'])
    );

    const pendingAbsences = await db
      .select({
        id: absenceNotifications.id,
        employeeId: absenceNotifications.employeeId,
        employeeName: employees.fullName,
        employeeRole: employees.role,
        employeeBranch: employees.branch,
        absenceDate: absenceNotifications.absenceDate,
        status: absenceNotifications.status,
        deductionApplied: absenceNotifications.deductionApplied,
        notifiedAt: absenceNotifications.notifiedAt,
      })
      .from(absenceNotifications)
      .innerJoin(employees, eq(absenceNotifications.employeeId, employees.id))
      .where(and(
        eq(absenceNotifications.status, 'pending'),
        eq(employees.role, 'manager')
      ))
      .orderBy(desc(absenceNotifications.notifiedAt));

    const pendingBreaks = await db
      .select({
        id: breaks.id,
        employeeId: breaks.employeeId,
        employeeName: employees.fullName,
        employeeRole: employees.role,
        employeeBranch: employees.branch,
        requestedDurationMinutes: breaks.requestedDurationMinutes,
        status: breaks.status,
        createdAt: breaks.createdAt,
      })
      .from(breaks)
      .innerJoin(employees, eq(breaks.employeeId, employees.id))
      .where(and(
        eq(breaks.status, 'PENDING'),
        eq(employees.role, 'manager')
      ))
      .orderBy(desc(breaks.createdAt));

    const normalizedBreaks = pendingBreaks.map(request => ({
      ...normalizeNumericFields(request, ['requestedDurationMinutes']),
      status: String(request.status),
    }));

    res.json({
      success: true,
      owner: {
        id: ownerRecord.id,
        name: ownerRecord.fullName,
        role: ownerRecord.role,
      },
      dashboard: {
        attendanceRequests: normalizedAttendance,
        leaveRequests: normalizedLeaveRequests,
        advances: normalizedAdvances,
        absences: pendingAbsences,
        breakRequests: normalizedBreaks,
        summary: {
          totalPendingRequests:
            normalizedAttendance.length +
            normalizedLeaveRequests.length +
            normalizedAdvances.length +
            pendingAbsences.length +
            normalizedBreaks.length,
          attendanceRequestsCount: normalizedAttendance.length,
          leaveRequestsCount: normalizedLeaveRequests.length,
          advancesCount: normalizedAdvances.length,
          absencesCount: pendingAbsences.length,
          breakRequestsCount: normalizedBreaks.length,
        },
      },
    });
  } catch (error) {
    console.error('Owner dashboard error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// قائمة الموظفين للمالك
app.get('/api/owner/employees', async (req, res) => {
  try {
    const ownerId = req.query.owner_id as string | undefined;

    if (!ownerId) {
      return res.status(400).json({ error: 'owner_id is required' });
    }

    const ownerRecord = await getOwnerRecord(ownerId);
    if (!ownerRecord) {
      return res.status(403).json({ error: 'لا توجد صلاحيات للوصول إلى بيانات الموظفين' });
    }

    const employeeRows = await db
      .select({
        id: employees.id,
        fullName: employees.fullName,
        role: employees.role,
        branch: employees.branch,
        branchId: employees.branchId,
        monthlySalary: employees.monthlySalary,
        hourlyRate: employees.hourlyRate,
        active: employees.active,
        createdAt: employees.createdAt,
        updatedAt: employees.updatedAt,
      })
      .from(employees)
      .orderBy(employees.fullName);

    const employeesList = employeeRows.map(row =>
      normalizeNumericFields(row, ['monthlySalary', 'hourlyRate'])
    );

    let totalHourlyRateAssigned = 0;
    let totalMonthlySalary = 0;
    let activeEmployees = 0;
    let managersCount = 0;

    for (const employee of employeesList) {
      if (employee.active) {
        activeEmployees += 1;
      }
      if (employee.role === 'manager') {
        managersCount += 1;
      }
      if (typeof employee.hourlyRate === 'number' && !isNaN(employee.hourlyRate)) {
        totalHourlyRateAssigned += employee.hourlyRate;
      }
      if (typeof employee.monthlySalary === 'number' && !isNaN(employee.monthlySalary)) {
        totalMonthlySalary += employee.monthlySalary;
      }
    }

    res.json({
      success: true,
      owner: {
        id: ownerRecord.id,
        name: ownerRecord.fullName,
      },
      employees: employeesList,
      summary: {
        totalEmployees: employeesList.length,
        activeEmployees,
        managersCount,
        totalHourlyRateAssigned: Math.round(totalHourlyRateAssigned * 100) / 100,
        totalMonthlySalary: Math.round(totalMonthlySalary * 100) / 100,
      },
    });
  } catch (error) {
    console.error('Owner employees list error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// تحديث سعر الساعة لموظف بواسطة المالك
app.put('/api/owner/employees/:employeeId/hourly-rate', async (req, res) => {
  try {
    const ownerId = req.query.owner_id as string | undefined;
    const { employeeId } = req.params;
    const { hourly_rate } = req.body ?? {};

    if (!ownerId) {
      return res.status(400).json({ error: 'owner_id is required' });
    }

    const ownerRecord = await getOwnerRecord(ownerId);
    if (!ownerRecord) {
      return res.status(403).json({ error: 'لا توجد صلاحيات لتعديل سعر الساعة' });
    }

    if (hourly_rate === undefined || hourly_rate === null) {
      return res.status(400).json({ error: 'hourly_rate is required' });
    }

    const parsedRate = Number(hourly_rate);
    if (!Number.isFinite(parsedRate) || parsedRate < 0) {
      return res.status(400).json({ error: 'hourly_rate must be a positive number' });
    }

    const [updatedEmployee] = await db
      .update(employees)
      .set({
        hourlyRate: parsedRate.toString(),
        updatedAt: new Date(),
      })
      .where(eq(employees.id, employeeId))
      .returning({
        id: employees.id,
        fullName: employees.fullName,
        role: employees.role,
        branch: employees.branch,
        monthlySalary: employees.monthlySalary,
        hourlyRate: employees.hourlyRate,
        updatedAt: employees.updatedAt,
      });

    if (!updatedEmployee) {
      return res.status(404).json({ error: 'Employee not found' });
    }

    res.json({
      success: true,
      employee: normalizeNumericFields(updatedEmployee, ['monthlySalary', 'hourlyRate']),
    });
  } catch (error) {
    console.error('Owner hourly rate update error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ملخص الرواتب لجميع الموظفين للمالك
app.get('/api/owner/payroll/summary', async (req, res) => {
  try {
    const ownerId = req.query.owner_id as string | undefined;
    const startDate = req.query.start_date as string | undefined;
    const endDate = req.query.end_date as string | undefined;

    if (!ownerId) {
      return res.status(400).json({ error: 'owner_id is required' });
    }
    if (!startDate || !endDate) {
      return res.status(400).json({ error: 'start_date and end_date are required' });
    }

    const ownerRecord = await getOwnerRecord(ownerId);
    if (!ownerRecord) {
      return res.status(403).json({ error: 'لا توجد صلاحيات للوصول إلى ملخص الرواتب' });
    }

    const startDateTime = new Date(`${startDate}T00:00:00.000Z`);
    const endDateTime = new Date(`${endDate}T23:59:59.999Z`);

    if (Number.isNaN(startDateTime.getTime()) || Number.isNaN(endDateTime.getTime())) {
      return res.status(400).json({ error: 'Invalid date range provided' });
    }

    const employeeRows = await db
      .select({
        id: employees.id,
        fullName: employees.fullName,
        role: employees.role,
        branch: employees.branch,
        monthlySalary: employees.monthlySalary,
        hourlyRate: employees.hourlyRate,
        active: employees.active,
      })
      .from(employees)
      .orderBy(employees.fullName);

    const attendanceRecords = await db
      .select({
        employeeId: attendance.employeeId,
        workHours: attendance.workHours,
      })
      .from(attendance)
      .where(and(
        gte(attendance.date, startDate),
        lte(attendance.date, endDate)
      ));

    const pulsesSummary = await db
      .select({
        employeeId: pulses.employeeId,
        totalValidPulses: sql<number>`COALESCE(SUM(CASE WHEN ${pulses.isWithinGeofence} = true THEN 1 ELSE 0 END), 0)`,
      })
      .from(pulses)
      .where(and(
        gte(pulses.createdAt, startDateTime),
        lte(pulses.createdAt, endDateTime)
      ))
      .groupBy(pulses.employeeId);

    const attendanceMap = new Map<string, { totalWorkHours: number; attendanceDays: number }>();
    for (const record of attendanceRecords) {
      const hoursValue = record.workHours !== null && record.workHours !== undefined
        ? parseFloat(String(record.workHours))
        : 0;
      if (Number.isNaN(hoursValue)) {
        continue;
      }
      const existing = attendanceMap.get(record.employeeId) || { totalWorkHours: 0, attendanceDays: 0 };
      existing.totalWorkHours += hoursValue;
      existing.attendanceDays += 1;
      attendanceMap.set(record.employeeId, existing);
    }

    const pulsesMap = new Map<string, number>();
    for (const row of pulsesSummary) {
      pulsesMap.set(row.employeeId, Number(row.totalValidPulses) || 0);
    }

    const normalizedEmployees = employeeRows.map(row =>
      normalizeNumericFields(row, ['monthlySalary', 'hourlyRate'])
    );

    const payrollDetails = [] as Array<{
      id: string;
      name: string;
      role: string;
      branch: string | null;
      hourlyRate: number | null;
      monthlySalary: number | null;
      attendanceDays: number;
      totalWorkHours: number;
      totalValidPulses: number;
      hourlyPay: number;
      pulsePay: number;
      totalComputedPay: number;
      active: boolean;
    }>;

    let totalHourlyPay = 0;
    let totalPulsePay = 0;

    for (const employee of normalizedEmployees) {
      const attendanceInfo = attendanceMap.get(employee.id) || { totalWorkHours: 0, attendanceDays: 0 };
      const pulsesCount = pulsesMap.get(employee.id) || 0;
      const hourlyRateValue = typeof employee.hourlyRate === 'number' && !isNaN(employee.hourlyRate)
        ? employee.hourlyRate
        : null;
      const monthlySalaryValue = typeof employee.monthlySalary === 'number' && !isNaN(employee.monthlySalary)
        ? employee.monthlySalary
        : null;

      const effectiveHourlyRate = hourlyRateValue ?? 0;
      const hourlyPay = Math.round(attendanceInfo.totalWorkHours * effectiveHourlyRate * 100) / 100;
      const pulseValue = effectiveHourlyRate > 0 ? (effectiveHourlyRate / 3600) * 30 : 0;
      const pulsePay = Math.round(pulsesCount * pulseValue * 100) / 100;
      const totalComputedPay = Math.round((hourlyPay + pulsePay) * 100) / 100;

      totalHourlyPay += hourlyPay;
      totalPulsePay += pulsePay;

      payrollDetails.push({
        id: employee.id,
        name: employee.fullName,
        role: employee.role,
        branch: employee.branch,
        hourlyRate: hourlyRateValue,
        monthlySalary: monthlySalaryValue,
        attendanceDays: attendanceInfo.attendanceDays,
        totalWorkHours: Math.round(attendanceInfo.totalWorkHours * 100) / 100,
        totalValidPulses: pulsesCount,
        hourlyPay,
        pulsePay,
        totalComputedPay,
        active: employee.active,
      });
    }

    res.json({
      success: true,
      owner: {
        id: ownerRecord.id,
        name: ownerRecord.fullName,
      },
      period: {
        start: startDate,
        end: endDate,
      },
      payroll: payrollDetails,
      summary: {
        employeesCount: payrollDetails.length,
        totalHourlyPay: Math.round(totalHourlyPay * 100) / 100,
        totalPulsePay: Math.round(totalPulsePay * 100) / 100,
        totalComputedPay: Math.round((totalHourlyPay + totalPulsePay) * 100) / 100,
      },
    });
  } catch (error) {
    console.error('Owner payroll summary error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Hierarchical approval dashboard (Manager/Owner)
app.get('/api/approvals/pending/:reviewerId', async (req, res) => {
  try {
    const { reviewerId } = req.params;

    // Get reviewer info
    const [reviewer] = await db
      .select()
      .from(employees)
      .where(eq(employees.id, reviewerId))
      .limit(1);

    if (!reviewer) {
      return res.status(404).json({ error: 'Reviewer not found' });
    }

    const reviewerRole = reviewer.role;

    // Define which employee roles this reviewer can approve for
    let allowedEmployeeRoles: string[] = [];
    if (reviewerRole === 'owner' || reviewerRole === 'admin') {
      // Owners/admins can approve requests from managers, hr, monitor, and staff
      allowedEmployeeRoles = ['manager', 'hr', 'monitor', 'staff'];
    } else if (reviewerRole === 'manager') {
      // Managers can only approve requests from staff
      allowedEmployeeRoles = ['staff', 'monitor'];
    } else {
      // Other roles cannot approve
      return res.status(403).json({ 
        error: 'هذا الدور لا يملك صلاحيات الموافقة على الطلبات' 
      });
    }

    // Get pending attendance requests
    const attendanceReqs = await db
      .select({
        id: attendanceRequests.id,
        employeeId: attendanceRequests.employeeId,
        employeeName: employees.fullName,
        employeeRole: employees.role,
        requestType: attendanceRequests.requestType,
        requestedTime: attendanceRequests.requestedTime,
        reason: attendanceRequests.reason,
        status: attendanceRequests.status,
        createdAt: attendanceRequests.createdAt,
      })
      .from(attendanceRequests)
      .innerJoin(employees, eq(attendanceRequests.employeeId, employees.id))
      .where(eq(attendanceRequests.status, 'pending'))
      .orderBy(desc(attendanceRequests.createdAt));

    // Get pending leave requests
    const leaveReqs = await db
      .select({
        id: leaveRequests.id,
        employeeId: leaveRequests.employeeId,
        employeeName: employees.fullName,
        employeeRole: employees.role,
        startDate: leaveRequests.startDate,
        endDate: leaveRequests.endDate,
        leaveType: leaveRequests.leaveType,
        reason: leaveRequests.reason,
        daysCount: leaveRequests.daysCount,
        allowanceAmount: leaveRequests.allowanceAmount,
        status: leaveRequests.status,
        createdAt: leaveRequests.createdAt,
      })
      .from(leaveRequests)
      .innerJoin(employees, eq(leaveRequests.employeeId, employees.id))
      .where(eq(leaveRequests.status, 'pending'))
      .orderBy(desc(leaveRequests.createdAt));

    // Get pending advances
    const advanceReqs = await db
      .select({
        id: advances.id,
        employeeId: advances.employeeId,
        employeeName: employees.fullName,
        employeeRole: employees.role,
        amount: advances.amount,
        eligibleAmount: advances.eligibleAmount,
        currentSalary: advances.currentSalary,
        status: advances.status,
        requestDate: advances.requestDate,
      })
      .from(advances)
      .innerJoin(employees, eq(advances.employeeId, employees.id))
      .where(eq(advances.status, 'pending'))
      .orderBy(desc(advances.requestDate));

    // Get pending absences
    const absenceReqs = await db
      .select({
        id: absenceNotifications.id,
        employeeId: absenceNotifications.employeeId,
        employeeName: employees.fullName,
        employeeRole: employees.role,
        absenceDate: absenceNotifications.absenceDate,
        status: absenceNotifications.status,
        deductionApplied: absenceNotifications.deductionApplied,
        notifiedAt: absenceNotifications.notifiedAt,
      })
      .from(absenceNotifications)
      .innerJoin(employees, eq(absenceNotifications.employeeId, employees.id))
      .where(eq(absenceNotifications.status, 'pending'))
      .orderBy(desc(absenceNotifications.notifiedAt));

    // Filter requests based on reviewer role
    const filteredAttendance = attendanceReqs.filter(req => 
      allowedEmployeeRoles.includes(req.employeeRole as string)
    );
    const filteredLeave = leaveReqs.filter(req => 
      allowedEmployeeRoles.includes(req.employeeRole as string)
    );
    const filteredAdvances = advanceReqs.filter(req => 
      allowedEmployeeRoles.includes(req.employeeRole as string)
    );
    const filteredAbsences = absenceReqs.filter(req => 
      allowedEmployeeRoles.includes(req.employeeRole as string)
    );

    res.json({
      success: true,
      reviewer: {
        id: reviewer.id,
        name: reviewer.fullName,
        role: reviewerRole,
      },
      pendingRequests: {
        attendance: filteredAttendance,
        leave: filteredLeave,
        advances: filteredAdvances,
        absences: filteredAbsences,
      },
      summary: {
        totalPending: filteredAttendance.length + filteredLeave.length + 
                      filteredAdvances.length + filteredAbsences.length,
        attendanceCount: filteredAttendance.length,
        leaveCount: filteredLeave.length,
        advancesCount: filteredAdvances.length,
        absencesCount: filteredAbsences.length,
      }
    });
  } catch (error) {
    console.error('Get pending approvals error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// =============================================================================
// PAYROLL CALCULATION - حساب الرواتب
// =============================================================================

// Calculate payroll based on attendance and pulses
app.post('/api/payroll/calculate', async (req, res) => {
  try {
    const { employee_id, start_date, end_date } = req.body;
    const hourlyRateInput = req.body?.hourly_rate;

    if (!employee_id || !start_date || !end_date) {
      return res.status(400).json({ 
        error: 'employee_id, start_date, and end_date are required' 
      });
    }

    // Get employee info
    const [employee] = await db
      .select()
      .from(employees)
      .where(eq(employees.id, employee_id))
      .limit(1);

    if (!employee) {
      return res.status(404).json({ error: 'Employee not found' });
    }

    let hourlyRate = 40;
    if (hourlyRateInput !== undefined && hourlyRateInput !== null) {
      hourlyRate = Number(hourlyRateInput);
    } else if (employee.hourlyRate !== null && employee.hourlyRate !== undefined) {
      hourlyRate = parseFloat(String(employee.hourlyRate));
    }

    if (!Number.isFinite(hourlyRate) || hourlyRate < 0) {
      return res.status(400).json({ error: 'Invalid hourly rate provided' });
    }

    // Fetch all attendance records in the date range
    const attendanceRecords = await db
      .select()
      .from(attendance)
      .where(and(
        eq(attendance.employeeId, employee_id),
        gte(attendance.date, start_date),
        lte(attendance.date, end_date)
      ))
      .orderBy(attendance.date);

    // Fetch all valid pulses in the date range
    const validPulses = await db
      .select()
      .from(pulses)
      .where(and(
        eq(pulses.employeeId, employee_id),
        eq(pulses.isWithinGeofence, true),
        gte(pulses.createdAt, new Date(start_date)),
        lte(pulses.createdAt, new Date(end_date))
      ))
      .orderBy(pulses.createdAt);

    let totalValidPulses = validPulses.length;
    let totalWorkHours = 0;
    const attendanceDetail = [];

    // Process each attendance record
    for (const record of attendanceRecords) {
      const workHours = parseFloat(record.workHours || '0');
      totalWorkHours += workHours;

      // Count pulses for this day
      const dayStart = new Date(record.date);
      const dayEnd = new Date(record.date);
      dayEnd.setHours(23, 59, 59, 999);

      const dayPulses = validPulses.filter(p => {
        const pulseTime = new Date(p.createdAt);
        return pulseTime >= dayStart && pulseTime <= dayEnd;
      });

      attendanceDetail.push({
        date: record.date,
        check_in: record.checkInTime,
        check_out: record.checkOutTime,
        work_hours: workHours,
        valid_pulses: dayPulses.length,
        status: record.status,
      });
    }

    // Calculate total pay
    const totalPay = totalWorkHours * hourlyRate;

    // Calculate pulse-based pay (40 EGP/hour, pulse every 30 seconds = 0.333 EGP per pulse)
    const pulseValue = (hourlyRate / 3600) * 30;
    const pulsePay = totalValidPulses * pulseValue;

    // Get advances for this period
    const advancesList = await db
      .select()
      .from(advances)
      .where(and(
        eq(advances.employeeId, employee_id),
        eq(advances.status, 'approved'),
        gte(advances.requestDate, new Date(start_date)),
        lte(advances.requestDate, new Date(end_date))
      ));

    const totalAdvances = advancesList.reduce((sum, advance) => 
      sum + parseFloat(advance.amount || '0'), 0
    );

    // Get deductions for this period
    const deductionsList = await db
      .select()
      .from(deductions)
      .where(and(
        eq(deductions.employeeId, employee_id),
        gte(deductions.deductionDate, start_date),
        lte(deductions.deductionDate, end_date)
      ));

    const totalDeductions = deductionsList.reduce((sum, deduction) => 
      sum + parseFloat(deduction.amount || '0'), 0
    );

    // Get approved leaves for this period
    const leaves = await db
      .select()
      .from(leaveRequests)
      .where(and(
        eq(leaveRequests.employeeId, employee_id),
        eq(leaveRequests.status, 'approved'),
        gte(leaveRequests.startDate, start_date),
        lte(leaveRequests.endDate, end_date)
      ));

    const totalLeaveAllowance = leaves.reduce((sum, leave) => 
      sum + parseFloat(leave.allowanceAmount || '0'), 0
    );

    // Calculate attendance allowance (حافز الغياب)
    // يُمنح 100 جنيه إذا لم يتجاوز عدد أيام الإجازة يومين
    let attendanceAllowance = 0;
    const totalLeaveDays = leaves.reduce((sum, leave) => sum + (leave.daysCount || 0), 0);
    
    if (totalLeaveDays <= 2) {
      attendanceAllowance = 100; // حافز ثابت 100 جنيه
    }

    // Calculate net salary
  const netSalary = pulsePay - totalDeductions + totalLeaveAllowance + attendanceAllowance;

    res.json({
      success: true,
      payroll: {
        employee_id,
        employee_name: employee.fullName,
        period: {
          start: start_date,
          end: end_date,
        },
        total_attendance_days: attendanceRecords.length,
        total_valid_pulses: totalValidPulses,
        total_work_hours: Math.round(totalWorkHours * 100) / 100,
        hourly_rate: hourlyRate,
        pulse_value: Math.round(pulseValue * 1000) / 1000,
        total_pay_hours: Math.round(totalPay * 100) / 100,
        total_pay_pulses: Math.round(pulsePay * 100) / 100,
        total_advances: Math.round(totalAdvances * 100) / 100,
        total_deductions: Math.round(totalDeductions * 100) / 100,
        total_leave_allowance: Math.round(totalLeaveAllowance * 100) / 100,
        attendance_allowance: Math.round(attendanceAllowance * 100) / 100,
        net_salary: Math.round(netSalary * 100) / 100,
        attendance_detail: attendanceDetail,
        advances: advancesList,
        deductions: deductionsList,
        leaves: leaves,
      }
    });
  } catch (error) {
    console.error('Payroll calculation error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// =============================================================================
// EMPLOYEE STATUS & PULSES - حالة الموظف والنبضات
// =============================================================================

// Get employee current status and pulses
app.get('/api/employees/:employeeId/status', async (req, res) => {
  try {
    const { employeeId } = req.params;

    // Get employee info
    const [employee] = await db
      .select()
      .from(employees)
      .where(eq(employees.id, employeeId))
      .limit(1);

    if (!employee) {
      return res.status(404).json({ error: 'Employee not found' });
    }

    // Get today's attendance
    const today = new Date().toISOString().split('T')[0];
    const [todayAttendance] = await db
      .select()
      .from(attendance)
      .where(and(
        eq(attendance.employeeId, employeeId),
        eq(attendance.date, today)
      ))
      .orderBy(attendance.checkInTime)
      .limit(1);

    // Get today's pulses count
    const todayPulses = await db
      .select()
      .from(pulses)
      .where(and(
        eq(pulses.employeeId, employeeId),
        sql`DATE(${pulses.createdAt}) = ${today}`
      ));

    // Get last 10 pulses
    const recentPulses = await db
      .select()
      .from(pulses)
      .where(eq(pulses.employeeId, employeeId))
      .orderBy(sql`${pulses.createdAt} DESC`)
      .limit(10);

    // Calculate total pulses count
    const [totalPulsesResult] = await db
      .select({ count: sql<number>`count(*)` })
      .from(pulses)
      .where(eq(pulses.employeeId, employeeId));

    const totalPulses = totalPulsesResult?.count || 0;
    const todayPulsesCount = todayPulses.length;
    const validTodayPulses = todayPulses.filter(p => p.isWithinGeofence).length;

    res.json({
      success: true,
      employee: {
        id: employee.id,
        fullName: employee.fullName,
        role: employee.role,
        branch: employee.branch,
        active: employee.active,
      },
      attendance: todayAttendance ? {
        checkInTime: todayAttendance.checkInTime,
        checkOutTime: todayAttendance.checkOutTime,
        status: todayAttendance.status,
        workHours: todayAttendance.workHours,
      } : null,
      pulses: {
        total: totalPulses,
        today: todayPulsesCount,
        todayValid: validTodayPulses,
        recent: recentPulses.map(p => ({
          id: p.id,
          timestamp: p.createdAt,
          latitude: p.latitude,
          longitude: p.longitude,
          isWithinGeofence: p.isWithinGeofence,
        })),
      },
    });
  } catch (error) {
    console.error('Get employee status error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Delete attendance record (لحذف تسجيل الحضور)
app.delete('/api/attendance/:attendanceId', async (req, res) => {
  try {
    const { attendanceId } = req.params;

    const deleteResult = await db
      .delete(attendance)
      .where(eq(attendance.id, attendanceId))
      .returning();
    const deleted = extractFirstRow(deleteResult);

    if (!deleted) {
      return res.status(404).json({ error: 'Attendance record not found' });
    }

    res.json({
      success: true,
      message: 'تم حذف سجل الحضور بنجاح',
      deleted,
    });
  } catch (error) {
    console.error('Delete attendance error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// =============================================================================
// PULSE VALIDATION WITH GEOFENCING
// =============================================================================

// Constants for geofencing
const RESTAURANT_WIFI_BSSID = 'XX:XX:XX:XX:XX:XX'; // Placeholder
const RESTAURANT_LATITUDE = 31.2652;
const RESTAURANT_LONGITUDE = 29.9863;
const GEOFENCE_RADIUS_METERS = 100;

// Helper function to calculate distance between two coordinates (Haversine formula)
function calculateDistance(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371e3; // Earth's radius in meters
  const φ1 = (lat1 * Math.PI) / 180;
  const φ2 = (lat2 * Math.PI) / 180;
  const Δφ = ((lat2 - lat1) * Math.PI) / 180;
  const Δλ = ((lon2 - lon1) * Math.PI) / 180;

  const a = Math.sin(Δφ / 2) * Math.sin(Δφ / 2) +
    Math.cos(φ1) * Math.cos(φ2) * Math.sin(Δλ / 2) * Math.sin(Δλ / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

  return R * c; // Distance in meters
}

// Receive and validate pulse from Flutter app
app.post('/api/pulses', async (req, res) => {
  try {
    const { 
      employee_id, 
      wifi_bssid, 
      latitude, 
      longitude,
      timestamp 
    } = req.body;

    if (!employee_id || latitude === undefined || longitude === undefined) {
      return res.status(400).json({ 
        error: 'employee_id, latitude, and longitude are required' 
      });
    }

    // Get employee's branch
    const [employee] = await db
      .select()
      .from(employees)
      .where(eq(employees.id, employee_id))
      .limit(1);

    if (!employee) {
      return res.status(404).json({ error: 'Employee not found' });
    }

    let wifiValid = true;
    let geofenceValid = true;
    let distance = 0;
    let geofenceRadius = GEOFENCE_RADIUS_METERS;

    // Use branch-specific geofence and wifi if available
    let branchWifi: string | null = null;
    if (employee.branchId) {
      const [branch] = await db
        .select()
        .from(branches)
        .where(eq(branches.id, employee.branchId))
        .limit(1);

      if (branch) {
        if (branch.latitude && branch.longitude) {
          distance = calculateDistance(
            latitude,
            longitude,
            parseFloat(branch.latitude),
            parseFloat(branch.longitude)
          );
        }
        if (branch.geofenceRadius) {
          geofenceRadius = Number(branch.geofenceRadius) || geofenceRadius;
        }
        if (branch.wifiBssid) {
          branchWifi = String(branch.wifiBssid).toUpperCase();
        }
      }
    } else {
      // Fallback to default location
      distance = calculateDistance(
        latitude,
        longitude,
        RESTAURANT_LATITUDE,
        RESTAURANT_LONGITUDE
      );
    }

    // Determine geofence validity
    geofenceValid = distance <= geofenceRadius;

    // Determine wifi validity: check against branchBssids table
    if (employee.branchId) {
      const bssids = await db
        .select()
        .from(branchBssids)
        .where(eq(branchBssids.branchId, employee.branchId));

      if (bssids.length > 0) {
        if (!wifi_bssid) {
          wifiValid = false;
        } else {
          wifiValid = bssids.some(b => b.bssidAddress.toUpperCase() === String(wifi_bssid).toUpperCase());
        }
      } else {
        wifiValid = true; // No BSSIDs set, allow any
      }
    } else {
      wifiValid = true;
    }

    // Pulse is within geofence if geofenceValid and not on active break
    let isWithinGeofence = geofenceValid;

    // Check if employee has an active break
    const [activeBreak] = await db
      .select()
      .from(breaks)
      .where(and(
        eq(breaks.employeeId, employee_id),
        eq(breaks.status, 'ACTIVE')
      ))
      .limit(1);

    // Store pulse in database
    const insertPulseResult = await db
      .insert(pulses)
      .values({
        employeeId: employee_id,
        branchId: employee.branchId,
        latitude,
        longitude,
        bssidAddress: wifi_bssid,
        isWithinGeofence: activeBreak ? false : isWithinGeofence,
        status: 'IN', // Default status
        createdAt: timestamp ? new Date(timestamp) : new Date(),
      })
      .returning({ id: pulses.id, employeeId: pulses.employeeId, branchId: pulses.branchId, latitude: pulses.latitude, longitude: pulses.longitude, bssidAddress: pulses.bssidAddress, isWithinGeofence: pulses.isWithinGeofence, status: pulses.status, createdAt: pulses.createdAt });
    const pulse = extractFirstRow(insertPulseResult) as any;

    const overallValid = activeBreak ? false : (wifiValid && geofenceValid);

    res.json({
      success: true,
      pulse: {
        id: pulse.id,
        is_valid: overallValid,
        wifi_valid: wifiValid,
        geofence_valid: geofenceValid,
        distance_meters: Math.round(distance * 100) / 100,
        on_break: !!activeBreak,
      }
    });
  } catch (error) {
    console.error('Pulse validation error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// =============================================================================
// BRANCH MANAGEMENT - إدارة الفروع
// =============================================================================

// Create a new branch
app.post('/api/branches', async (req, res) => {
  try {
    const { name, wifi_bssid, latitude, longitude, geofence_radius } = req.body;

    if (!name) {
      return res.status(400).json({ error: 'Branch name is required' });
    }

    // Insert the branch and get the new branch ID
    const [newBranch] = await db
      .insert(branches)
      .values({
        name,
        latitude: latitude ? latitude.toString() : null,
        longitude: longitude ? longitude.toString() : null,
        geofenceRadius: geofence_radius || 100,
        wifiBssid: wifi_bssid || null,
      })
      .returning();

    // If wifi_bssid is provided, insert it into branchBssids table
    if (wifi_bssid && wifi_bssid.trim() !== '' && newBranch && newBranch.id) {
      await db
        .insert(branchBssids)
        .values({
          branchId: newBranch.id,
          bssidAddress: wifi_bssid.trim().toUpperCase(),
        });
      
      console.log(`[Branch Created] Branch ID: ${newBranch.id}, Name: ${name}, BSSID: ${wifi_bssid.trim().toUpperCase()}`);
    } else {
      console.log(`[Branch Created] Branch ID: ${newBranch?.id}, Name: ${name}, No BSSID provided`);
    }

    res.json({
      success: true,
      message: 'تم إنشاء الفرع بنجاح',
      branchId: newBranch.id,
    });
  } catch (error) {
    console.error('Create branch error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Get all branches
app.get('/api/branches', async (req, res) => {
  try {
    const branchesList = await db
      .select()
      .from(branches)
      .orderBy(branches.name);

    res.json({ branches: branchesList });
  } catch (error) {
    console.error('Get branches error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Assign manager to branch
app.post('/api/branches/:branchId/assign-manager', async (req, res) => {
  try {
    const { branchId } = req.params;
    const { employee_id } = req.body;

    if (!employee_id) {
      return res.status(400).json({ error: 'Employee ID is required' });
    }

    // Update branch record with manager_id
    const updateResult = await db
      .update(branches)
      .set({ managerId: employee_id })
      .where(eq(branches.id, branchId))
      .returning();
    const updatedBranch = extractFirstRow(updateResult);

    if (!updatedBranch) {
      return res.status(404).json({ error: 'Branch not found' });
    }

    res.json({
      success: true,
      message: 'تم تعيين المدير للفرع بنجاح',
      branch: updatedBranch,
    });
  } catch (error) {
    console.error('Assign manager error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Get employees by branch for managers
app.get('/api/branches/:branchId/employees', async (req, res) => {
  try {
    const { branchId } = req.params;

    const employeesList = await db
      .select()
      .from(employees)
      .where(eq(employees.branchId, branchId))
      .orderBy(employees.fullName);

    res.json({ employees: employeesList });
  } catch (error) {
    console.error('Get branch employees error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// =============================================================================
// BREAK MANAGEMENT SYSTEM - نظام إدارة الاستراحات
// Delete all rejected breaks for an employee
app.post('/api/breaks/delete-rejected', async (req, res) => {
  try {
    const { employee_id } = req.body;
    if (!employee_id) {
      return res.status(400).json({ error: 'employee_id is required' });
    }
    const deleted = await db.delete(breaks)
      .where(and(eq(breaks.employeeId, employee_id), eq(breaks.status, 'REJECTED')));
    res.json({ success: true, deleted });
  } catch (error) {
    console.error('Delete rejected breaks error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});
// =============================================================================

// Request a break
// Get breaks for an employee
app.get('/api/breaks', async (req, res) => {
  try {
    const { employee_id, status } = req.query;

    let query = db.select().from(breaks).$dynamic();

    if (employee_id) {
      query = query.where(eq(breaks.employeeId, employee_id as string));
    }

    if (status) {
      query = query.where(eq(breaks.status, status as any));
    }

    const results = await query;

    // Ensure numeric fields are numbers, not strings
    const normalizedResults = results.map(breakItem => ({
      ...breakItem,
      requestedDurationMinutes: typeof breakItem.requestedDurationMinutes === 'string' 
        ? parseInt(breakItem.requestedDurationMinutes) 
        : breakItem.requestedDurationMinutes,
    }));

    res.json({
      success: true,
      breaks: normalizedResults,
    });
  } catch (error) {
    console.error('Get breaks error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.post('/api/breaks/request', async (req, res) => {
  try {
    const { employee_id, shift_id, duration_minutes } = req.body;

    if (!employee_id || !duration_minutes) {
      return res.status(400).json({ error: 'employee_id and duration_minutes are required' });
    }

    // Prevent duplicate break requests for the same day
    const today = new Date();
    today.setHours(0,0,0,0);
    const tomorrow = new Date(today);
    tomorrow.setDate(today.getDate() + 1);

    const existingBreak = await db
      .select()
      .from(breaks)
      .where(
        and(
          eq(breaks.employeeId, employee_id),
          gte(breaks.createdAt, today),
          lt(breaks.createdAt, tomorrow),
          inArray(breaks.status, ['PENDING', 'APPROVED', 'ACTIVE'])
        )
      )
      .limit(1);

    if (existingBreak.length > 0) {
      return res.status(400).json({ error: 'لا يمكنك تقديم أكثر من طلب استراحة في نفس اليوم' });
    }

    // Create break request
    const insertBreakResult = await db
      .insert(breaks)
      .values({
        employeeId: employee_id,
        shiftId: shift_id || null,
        requestedDurationMinutes: duration_minutes,
        status: 'PENDING',
      })
      .returning();
    const breakRequest = extractFirstRow(insertBreakResult);

    res.json({
      success: true,
      message: 'تم إرسال طلب الاستراحة للمراجعة',
      break: breakRequest,
    });
  } catch (error) {
    console.error('Break request error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Alternative endpoint for break request (POST to /api/breaks directly)
app.post('/api/breaks', async (req, res) => {
  try {
    const { employee_id, shift_id, duration_minutes } = req.body;

    if (!employee_id || !duration_minutes) {
      return res.status(400).json({ error: 'employee_id and duration_minutes are required' });
    }

    // Create break request
    const insertBreakResult = await db
      .insert(breaks)
      .values({
        employeeId: employee_id,
        shiftId: shift_id || null,
        requestedDurationMinutes: duration_minutes,
        status: 'PENDING',
      })
      .returning();
    const breakRequest = extractFirstRow(insertBreakResult);

    res.json({
      success: true,
      message: 'تم إرسال طلب الاستراحة للمراجعة',
      break: breakRequest,
    });
  } catch (error) {
    console.error('Break request error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Review break request (approve/reject)
app.post('/api/breaks/:breakId/review', async (req, res) => {
  try {
    const { breakId } = req.params;
    const { action, manager_id } = req.body;

    if (!action || !['approve', 'reject', 'postpone'].includes(action)) {
      return res.status(400).json({ error: 'Action must be approve, reject or postpone' });
    }

    let setData: any = {
      approvedBy: manager_id,
      updatedAt: new Date(),
    };

    if (action === 'approve') {
      setData.status = 'APPROVED';
      setData.payoutEligible = false;
    } else if (action === 'reject') {
      setData.status = 'REJECTED';
      setData.payoutEligible = false;
    } else if (action === 'postpone') {
      setData.status = 'POSTPONED';
      setData.payoutEligible = true;
    }

    const updateResult = await db
      .update(breaks)
      .set(setData)
      .where(eq(breaks.id, breakId))
      .returning();
    const updated = extractFirstRow(updateResult);

    res.json({
      success: true,
      message: action === 'approve' ? 'تم الموافقة على الاستراحة' : action === 'reject' ? 'تم رفض الاستراحة' : 'تم تأجيل الاستراحة - متاح صرف الرصيد لاحقًا',
      break: updated,
    });
  } catch (error) {
    console.error('Break review error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Apply payout for a postponed break
app.post('/api/breaks/:breakId/apply-payout', async (req, res) => {
  try {
    const { breakId } = req.params;
    const { manager_id } = req.body;

    const [br] = await db.select().from(breaks).where(eq(breaks.id, breakId)).limit(1);
    if (!br) return res.status(404).json({ error: 'Break not found' });
    if (!br.payoutEligible) return res.status(400).json({ error: 'Payout is not eligible for this break' });

    const updateResult = await db
      .update(breaks)
      .set({ payoutApplied: true, payoutAppliedAt: new Date(), updatedAt: new Date(), approvedBy: manager_id })
      .where(eq(breaks.id, breakId))
      .returning();
    const updated = extractFirstRow(updateResult);

    res.json({ success: true, message: 'تم صرف مستحقات الاستراحة المؤجلة', break: updated });
  } catch (error) {
    console.error('Apply payout error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Start an approved break
app.post('/api/breaks/:breakId/start', async (req, res) => {
  try {
    const { breakId } = req.params;

    // Get break details
    const [breakRecord] = await db
      .select()
      .from(breaks)
      .where(eq(breaks.id, breakId))
      .limit(1);

    if (!breakRecord) {
      return res.status(404).json({ error: 'Break not found' });
    }

    if (breakRecord.status !== 'APPROVED') {
      return res.status(400).json({ error: 'Break must be approved before starting' });
    }

    const startTime = new Date();
    const endTime = new Date(startTime.getTime() + breakRecord.requestedDurationMinutes * 60000);

    const updateResult = await db
      .update(breaks)
      .set({
        status: 'ACTIVE',
        startTime,
        endTime,
        updatedAt: new Date(),
      })
      .where(eq(breaks.id, breakId))
      .returning();
    const updated = extractFirstRow(updateResult);

    res.json({
      success: true,
      message: 'تم بدء الاستراحة',
      break: updated,
    });
  } catch (error) {
    console.error('Break start error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// End a break
app.post('/api/breaks/:breakId/end', async (req, res) => {
  try {
    const { breakId } = req.params;

    const updateResult = await db
      .update(breaks)
      .set({
        status: 'COMPLETED',
        updatedAt: new Date(),
      })
      .where(eq(breaks.id, breakId))
      .returning();
    const updated = extractFirstRow(updateResult);

    res.json({
      success: true,
      message: 'تم إنهاء الاستراحة',
      break: updated,
    });
  } catch (error) {
    console.error('Break end error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Listen on 0.0.0.0 to accept connections from all interfaces (including IPv4)
console.log(`[DEBUG] About to call app.listen on port ${PORT}...`);

const server = app.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 Oldies Workers API server running on port ${PORT}`);
  console.log(`📍 Health check: http://localhost:${PORT}/health`);
  console.log(`🔐 Auth: http://localhost:${PORT}/api/auth/login`);
  console.log(`✅ Check-in: http://localhost:${PORT}/api/attendance/check-in`);
  console.log(`👋 Check-out: http://localhost:${PORT}/api/attendance/check-out`);
  console.log(`📝 Requests: http://localhost:${PORT}/api/attendance/requests`);
  console.log(`🏖️  Leaves: http://localhost:${PORT}/api/leave/requests`);
  console.log(`💰 Advances: http://localhost:${PORT}/api/advances`);
  console.log(`💵 Payroll: http://localhost:${PORT}/api/payroll/calculate`);
  console.log(`📡 Pulses: http://localhost:${PORT}/api/pulses`);
  console.log(`📊 Reports: http://localhost:${PORT}/api/reports/attendance/:id`);
  console.log(`☕ Breaks: http://localhost:${PORT}/api/breaks`);
  console.log(`👨‍💼 Manager Dashboard: http://localhost:${PORT}/manager-dashboard.html`);
  console.log(`\n✅ Server is ready to accept connections!`);
  console.log(`[DEBUG] Listening callback executed successfully`);
});

console.log(`[DEBUG] app.listen called, server object created`);
console.log(`[DEBUG] Server listening status:`, server.listening);

server.on('listening', () => {
  console.log('[DEBUG] Server "listening" event fired!');
  const address = server.address();
  console.log('[DEBUG] Server address:', address);
});

server.on('error', (error: any) => {
  console.error('[DEBUG] Server error event:', error);
  if (error.code === 'EADDRINUSE') {
    console.error(`❌ ERROR: Port ${PORT} is already in use!`);
    console.error(`   Run: taskkill /F /IM node.exe`);
    process.exit(1);
  } else {
    console.error(`❌ ERROR: Failed to start server:`, error);
    process.exit(1);
  }
});

// Keep process alive
setInterval(() => {
  console.log('[DEBUG] Process still alive, server listening:', server.listening);
}, 10000);

// =============================================================================
// DEVELOPMENT - Seed Database
// =============================================================================

app.get('/api/dev/seed', async (req, res) => {
  try {
    console.log('🌱 Seeding database...');

    // Check if already seeded
    const existingEmployees = await db.select().from(employees).limit(1);
    if (existingEmployees.length > 0) {
      return res.json({
        success: true,
        message: 'Database already seeded',
        note: 'Delete employees table data if you want to re-seed'
      });
    }

    // Hash PINs using bcrypt
    const defaultPinHash = await bcrypt.hash('1234', 10);
    const emp002PinHash = await bcrypt.hash('5555', 10);
    const mgrPinHash = await bcrypt.hash('8888', 10);

    // Seed employees
    const employeesToInsert = [
      {
        id: 'OWNER001',
        fullName: 'Ahmed Owner',
        role: 'owner' as const,
        branch: 'MAIN',
        branchId: null,
        pinHash: defaultPinHash,
        monthlySalary: '0',
        hourlyRate: '0',
        active: true,
      },
      {
        id: 'EMP001',
        fullName: 'Ahmed Mohamed',
        role: 'staff' as const,
        branch: 'MAADI',
        branchId: null,
        pinHash: defaultPinHash,
        monthlySalary: '3000',
        hourlyRate: '40',
        active: true,
      },
      {
        id: 'EMP_MAADI',
        fullName: 'Mohamed Ali',
        role: 'staff' as const,
        branch: 'MAADI',
        branchId: null,
        pinHash: emp002PinHash,
        monthlySalary: '3500',
        hourlyRate: '40',
        active: true,
      },
      {
        id: 'MGR_MAADI',
        fullName: 'Sara Manager',
        role: 'manager' as const,
        branch: 'MAADI',
        branchId: null,
        pinHash: mgrPinHash,
        monthlySalary: '5000',
        hourlyRate: '50',
        active: true,
      },
    ];

    await db.insert(employees).values(employeesToInsert);
    console.log('✅ Seeded employees');

    res.json({
      success: true,
      message: 'Database seeded successfully',
      employees: [
        { id: 'OWNER001', pin: '1234', role: 'owner' },
        { id: 'EMP001', pin: '1234', role: 'staff' },
        { id: 'EMP_MAADI', pin: '5555', role: 'staff' },
        { id: 'MGR_MAADI', pin: '8888', role: 'manager' },
      ]
    });
  } catch (error) {
    console.error('Seed error:', error);
    res.status(500).json({ error: 'Seed failed', message: error?.message });
  }
});

// 404 handler (JSON)
app.use((req, res) => {
  res.status(404).json({ error: 'Not Found', path: req.path });
});

// Error handler (JSON)
app.use((err: any, req: express.Request, res: express.Response, _next: express.NextFunction) => {
  console.error('Unhandled error:', err);
  const status = err?.status || 500;
  res.status(status).json({ error: 'Internal server error', message: err?.message });
});
