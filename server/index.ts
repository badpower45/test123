import express from 'express';
import cors from 'cors';
import path from 'path';
import { fileURLToPath } from 'url';
import { db } from './db.js';
import { 
  employees, attendance, attendanceRequests, leaveRequests, advances, 
  deductions, absenceNotifications, pulses, users, roles, permissions, 
  rolePermissions, userRoles, branches, branchManagers, breaks
} from '../shared/schema.js';
import { eq, and, gte, lte, desc, sql, between, inArray } from 'drizzle-orm';
import { requirePermission, getUserPermissions, checkUserPermission } from './auth.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const PORT = Number(process.env.PORT) || 5000;

app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, '../public')));

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

    res.json({
      success: true,
      leaveRequests: leaveReqs,
      advanceRequests: advanceReqs,
      attendanceRequests: attReqs,
      absenceNotifications: absenceAlerts,
    });
  } catch (err) {
    res.status(500).json({ error: 'Internal server error', message: err?.message });
  }
});

// Approve/reject a request (leave, advance, attendance, absence)
app.post('/api/branch/request/:type/:id/:action', async (req, res) => {
  try {
    const { type, id, action } = req.params;
    const validTypes = ['leave', 'advance', 'attendance', 'absence'];
    const validActions = ['approve', 'reject'];
    if (!validTypes.includes(type) || !validActions.includes(action)) {
      return res.status(400).json({ error: 'Invalid type or action' });
    }
    let table;
    switch (type) {
      case 'leave': table = leaveRequests; break;
      case 'advance': table = advances; break;
      case 'attendance': table = attendanceRequests; break;
      case 'absence': table = absenceNotifications; break;
    }
    const status = action === 'approve' ? 'approved' : 'rejected';
    const [updated] = await db.update(table).set({ status, reviewedAt: new Date() }).where(eq(table.id, id)).returning();
    res.json({ success: true, updated });
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

// -----------------------------------------------------------------------------
// Demo data seeding: branches and employees (for local/dev)
// -----------------------------------------------------------------------------
const ensureDemoData = async () => {
  try {
    // Minimal employees directory required by FK constraints
    const demoEmployees = [
      { id: 'EMP001', fullName: 'أحمد علي', pinHash: '1234', role: 'staff' as const, branch: 'فرع المعادي' },
      { id: 'EMP002', fullName: 'سارة أحمد', pinHash: '2222', role: 'staff' as const, branch: 'فرع المعادي' },
      { id: 'EMP003', fullName: 'محمد حسن', pinHash: '3333', role: 'manager' as const, branch: 'فرع المعادي' },
      { id: 'EMP004', fullName: 'فاطمة محمد', pinHash: '4444', role: 'staff' as const, branch: 'فرع المعادي' },
      // English-named demo accounts to avoid encoding issues for testing
      { id: 'MGR_MAADI', fullName: 'Manager Maadi', pinHash: '8888', role: 'manager' as const, branch: 'Maadi' },
      { id: 'EMP_MAADI', fullName: 'Employee Maadi', pinHash: '5555', role: 'staff' as const, branch: 'Maadi' },
    ];

    // Upsert employees (ignore if already exist)
    for (const e of demoEmployees) {
      try {
        await db
          .insert(employees)
          .values({
            id: e.id,
            fullName: e.fullName,
            pinHash: e.pinHash,
            role: e.role,
            branch: e.branch,
            active: true,
            updatedAt: new Date(),
          })
          .onConflictDoUpdate({
            target: employees.id,
            set: {
              fullName: e.fullName,
              pinHash: e.pinHash,
              role: e.role,
              branch: e.branch,
              active: true,
              updatedAt: new Date(),
            },
          });
      } catch (err) {
        console.warn('[seed] failed to upsert employee', e.id, err);
      }
    }

    console.log('[seed] Demo employees ensured:', demoEmployees.map(d => d.id).join(', '));
  } catch (error) {
    console.error('[seed] ensureDemoData failed:', error);
  }
};

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

// Dev endpoint to trigger seeding on-demand
app.get('/api/dev/seed', async (req, res) => {
  try {
    await ensureDemoData();
    res.json({ success: true, message: 'Demo data ensured' });
  } catch (err: any) {
    console.error('Dev seed error:', err);
    res.status(500).json({ error: 'Internal server error', message: err?.message });
  }
});

// =============================================================================
// AUTHENTICATION & LOGIN
// نظام تسجيل الدخول
// =============================================================================

// Login with PIN
app.post('/api/auth/login', async (req, res) => {
  try {
    const { employee_id, pin } = req.body;

    if (!employee_id || !pin) {
      return res.status(400).json({ error: 'Employee ID and PIN are required' });
    }

    // Find employee
    const [employee] = await db
      .select()
      .from(employees)
      .where(and(
        eq(employees.id, employee_id),
        eq(employees.active, true)
      ))
      .limit(1);

    if (!employee) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    // Verify PIN (demo: plaintext match against pinHash)
    const providedPin = String(pin).trim();
    const storedPin = String(employee.pinHash || '').trim();
    if (!storedPin || providedPin !== storedPin) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

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
    const [newAttendance] = await db
      .insert(attendance)
      .values({
        employeeId: employee_id,
        checkInTime: new Date(),
        date: today,
        status: 'active',
      })
      .returning();

    // Create pulse for location tracking
    if (latitude && longitude) {
      await db.insert(pulses).values({
        employeeId: employee_id,
        latitude,
        longitude,
        timestamp: new Date(),
      });
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
    const [updated] = await db
      .update(attendance)
      .set({
        checkOutTime,
        workHours: workHours.toFixed(2),
        status: 'completed',
        updatedAt: new Date(),
      })
      .where(eq(attendance.id, activeAttendance.id))
      .returning();

    // Create pulse for location tracking
    if (latitude && longitude) {
      await db.insert(pulses).values({
        employeeId: employee_id,
        latitude,
        longitude,
        timestamp: new Date(),
      });
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

    const [request] = await db
      .insert(attendanceRequests)
      .values({
        employeeId: employee_id,
        requestType: 'check-in',
        requestedTime: new Date(requested_time),
        reason,
        status: 'pending',
      })
      .returning();

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

    const [request] = await db
      .insert(attendanceRequests)
      .values({
        employeeId: employee_id,
        requestType: 'check-out',
        requestedTime: new Date(requested_time),
        reason,
        status: 'pending',
      })
      .returning();

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
    const [updated] = await db
      .update(attendanceRequests)
      .set({
        status: action === 'approve' ? 'approved' : 'rejected',
        reviewedBy: reviewer_id,
        reviewedAt: new Date(),
        reviewNotes: notes,
      })
      .where(eq(attendanceRequests.id, requestId))
      .returning();

    // If approved, create/update attendance record
    if (action === 'approve') {
      const requestDate = new Date(request.requestedTime).toISOString().split('T')[0];

      if (request.requestType === 'check-in') {
        await db.insert(attendance).values({
          employeeId: request.employeeId,
          checkInTime: request.requestedTime,
          date: requestDate,
          status: 'active',
        });
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
          const checkOutTime = new Date(request.requestedTime);
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
    res.status(500).json({ error: 'Internal server error' });
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

    // Calculate allowance (100 EGP per day for <= 2 days)
    let allowanceAmount = 0;
    if (daysCount <= 2) {
      allowanceAmount = daysCount * 100;
    }

    const [leaveRequest] = await db
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

    res.json({
      success: true,
      message: 'تم إرسال طلب الإجازة للمراجعة',
      leaveRequest,
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

    res.json({ requests });
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

    const [updated] = await db
      .update(leaveRequests)
      .set({
        status: action === 'approve' ? 'approved' : 'rejected',
        reviewedBy: reviewer_id,
        reviewedAt: new Date(),
        reviewNotes: notes,
      })
      .where(eq(leaveRequests.id, requestId))
      .returning();

    res.json({
      success: true,
      message: action === 'approve' ? 'تم الموافقة على الإجازة' : 'تم رفض الإجازة',
      request: updated,
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
        gte(pulses.timestamp, periodStart),
        lte(pulses.timestamp, now)
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

    const [advance] = await db
      .insert(advances)
      .values({
        employeeId: employee_id,
        amount,
        eligibleAmount: eligibleAmount.toString(),
        currentSalary: totalRealTimeEarnings.toString(),
        status: 'pending',
      })
      .returning();

    res.json({
      success: true,
      message: 'تم إرسال طلب السلفة للمراجعة',
      advance,
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

    res.json({ advances: advancesList });
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

    const updateData: any = {
      status: action === 'approve' ? 'approved' : 'rejected',
      reviewedBy: reviewer_id,
      reviewedAt: new Date(),
    };

    if (action === 'approve') {
      updateData.paidAt = new Date();
    }

    const [updated] = await db
      .update(advances)
      .set(updateData)
      .where(eq(advances.id, advanceId))
      .returning();

    res.json({
      success: true,
      message: action === 'approve' ? 'تم الموافقة على السلفة' : 'تم رفض السلفة',
      advance: updated,
    });
  } catch (error) {
    console.error('Review advance error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// =============================================================================
// ABSENCE NOTIFICATIONS & DEDUCTIONS - الغياب والخصومات
// =============================================================================

// Report absence (auto-notify manager)
app.post('/api/absence/notify', async (req, res) => {
  try {
    const { employee_id, absence_date } = req.body;

    if (!employee_id || !absence_date) {
      return res.status(400).json({ error: 'Employee ID and absence date are required' });
    }

    const [notification] = await db
      .insert(absenceNotifications)
      .values({
        employeeId: employee_id,
        absenceDate: absence_date,
        status: 'pending',
      })
      .returning();

    res.json({
      success: true,
      message: 'تم إرسال إخطار الغياب للمدير',
      notification,
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
    if (action === 'reject') {
      deductionAmount = '400'; // 2 days * 200 EGP/day

      // Create deduction record
      await db.insert(deductions).values({
        employeeId: notification.employeeId,
        amount: deductionAmount,
        reason: notes || 'غياب بدون إذن - رفض المدير',
        deductionDate: notification.absenceDate,
        deductionType: 'absence',
        appliedBy: reviewer_id,
      });
    }

    // Update notification
    const [updated] = await db
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
    const [updated] = await db
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

// Get comprehensive employee report (يوم 1 و 16)
app.get('/api/reports/comprehensive/:employeeId', async (req, res) => {
  try {
    const { employeeId } = req.params;
    const { start_date, end_date, skip_date_check } = req.query;

    // Check if it's 1st or 16th (skip for managers/admins)
    if (!skip_date_check) {
      const today = new Date().getDate();
      if (today !== 1 && today !== 16) {
        return res.status(403).json({ 
          error: 'التقارير متاحة فقط يوم 1 و 16 من كل شهر' 
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
        gte(pulses.timestamp, new Date(start_date as string)),
        lte(pulses.timestamp, new Date(end_date as string))
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

    // Calculate net salary
    const netSalary = grossSalary - totalAdvances - totalDeductions + totalLeaveAllowance;

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

// Create employee
app.post('/api/employees', async (req, res) => {
  try {
    const { id, full_name, pin_hash, role, branch, monthly_salary } = req.body;

    if (!id || !full_name || !pin_hash) {
      return res.status(400).json({ error: 'ID, full name, and PIN are required' });
    }

    const [newEmployee] = await db
      .insert(employees)
      .values({
        id,
        fullName: full_name,
        pinHash: pin_hash,
        role: role || 'staff',
        branch,
        monthlySalary: monthly_salary,
        active: true,
      })
      .returning();

    res.json({
      success: true,
      message: 'تم إضافة الموظف بنجاح',
      employee: newEmployee,
    });
  } catch (error) {
    console.error('Create employee error:', error);
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

    res.json({
      success: true,
      dashboard: {
        attendanceRequests: pendingAttendanceRequests,
        leaveRequests: pendingLeaveRequests,
        advances: pendingAdvances,
        absences: pendingAbsences,
        summary: {
          totalPendingRequests: pendingAttendanceRequests.length + pendingLeaveRequests.length + pendingAdvances.length + pendingAbsences.length,
          attendanceRequestsCount: pendingAttendanceRequests.length,
          leaveRequestsCount: pendingLeaveRequests.length,
          advancesCount: pendingAdvances.length,
          absencesCount: pendingAbsences.length,
        }
      }
    });
  } catch (error) {
    console.error('Dashboard error:', error);
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
    const { employee_id, start_date, end_date, hourly_rate = 40 } = req.body;

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
        gte(pulses.timestamp, new Date(start_date)),
        lte(pulses.timestamp, new Date(end_date))
      ))
      .orderBy(pulses.timestamp);

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
        const pulseTime = new Date(p.timestamp);
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
    const totalPay = totalWorkHours * hourly_rate;

    // Calculate pulse-based pay (40 EGP/hour, pulse every 30 seconds = 0.333 EGP per pulse)
    const pulseValue = (hourly_rate / 3600) * 30;
    const pulsePay = totalValidPulses * pulseValue;

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
        hourly_rate,
        pulse_value: Math.round(pulseValue * 1000) / 1000,
        total_pay_hours: Math.round(totalPay * 100) / 100,
        total_pay_pulses: Math.round(pulsePay * 100) / 100,
        attendance_detail: attendanceDetail,
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
        sql`DATE(${pulses.timestamp}) = ${today}`
      ));

    // Get last 10 pulses
    const recentPulses = await db
      .select()
      .from(pulses)
      .where(eq(pulses.employeeId, employeeId))
      .orderBy(sql`${pulses.timestamp} DESC`)
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
          timestamp: p.timestamp,
          latitude: p.latitude,
          longitude: p.longitude,
          isWithinGeofence: p.isWithinGeofence,
          isFake: p.isFake,
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

    const [deleted] = await db
      .delete(attendance)
      .where(eq(attendance.id, attendanceId))
      .returning();

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

    let wifiValid = true; // [TESTING] Bypassed for testing
    let geofenceValid = true; // [TESTING] Bypassed for testing
    let distance = 0;

    // Use branch-specific geofence if available
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

    // Pulse is valid only if both checks pass
    let isWithinGeofence = true; // [TESTING] Bypassed for testing

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
    const [pulse] = await db
      .insert(pulses)
      .values({
        employeeId: employee_id,
        latitude,
        longitude,
        isWithinGeofence: activeBreak ? false : isWithinGeofence,
        timestamp: timestamp ? new Date(timestamp) : new Date(),
        sentFromDevice: true,
      })
      .returning();

    res.json({
      success: true,
      pulse: {
        id: pulse.id,
  is_valid: activeBreak ? false : true, // [TESTING] Bypassed for testing
  wifi_valid: true, // [TESTING] Bypassed for testing
  geofence_valid: true, // [TESTING] Bypassed for testing
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

    const [branch] = await db
      .insert(branches)
      .values({
        name,
        wifiBssid: wifi_bssid,
        latitude: latitude ? latitude.toString() : null,
        longitude: longitude ? longitude.toString() : null,
        geofenceRadius: geofence_radius || 100,
      })
      .returning();

    res.json({
      success: true,
      message: 'تم إنشاء الفرع بنجاح',
      branch,
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

    const [assignment] = await db
      .insert(branchManagers)
      .values({
        employeeId: employee_id,
        branchId,
      })
      .returning();

    res.json({
      success: true,
      message: 'تم تعيين المدير للفرع بنجاح',
      assignment,
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
// =============================================================================

// Request a break
app.post('/api/breaks/request', async (req, res) => {
  try {
    const { employee_id, shift_id, duration_minutes } = req.body;

    if (!employee_id || !duration_minutes) {
      return res.status(400).json({ error: 'employee_id and duration_minutes are required' });
    }

    // Create break request
    const [breakRequest] = await db
      .insert(breaks)
      .values({
        employeeId: employee_id,
        shiftId: shift_id || null,
        requestedDurationMinutes: duration_minutes,
        status: 'PENDING',
      })
      .returning();

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

    if (!action || !['approve', 'reject'].includes(action)) {
      return res.status(400).json({ error: 'Action must be approve or reject' });
    }

    const [updated] = await db
      .update(breaks)
      .set({
        status: action === 'approve' ? 'APPROVED' : 'REJECTED',
        approvedBy: manager_id,
        updatedAt: new Date(),
      })
      .where(eq(breaks.id, breakId))
      .returning();

    res.json({
      success: true,
      message: action === 'approve' ? 'تم الموافقة على الاستراحة' : 'تم رفض الاستراحة',
      break: updated,
    });
  } catch (error) {
    console.error('Break review error:', error);
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

    const [updated] = await db
      .update(breaks)
      .set({
        status: 'ACTIVE',
        startTime,
        endTime,
        updatedAt: new Date(),
      })
      .where(eq(breaks.id, breakId))
      .returning();

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

    const [updated] = await db
      .update(breaks)
      .set({
        status: 'COMPLETED',
        updatedAt: new Date(),
      })
      .where(eq(breaks.id, breakId))
      .returning();

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

    const breaksList = await query.orderBy(desc(breaks.createdAt));

    res.json({ breaks: breaksList });
  } catch (error) {
    console.error('Get breaks error:', error);
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
