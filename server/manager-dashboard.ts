import { Router } from 'express';
import { db } from './db.js';
import {
  attendanceRequests, leaveRequests, advances, absenceNotifications, employees
} from '@shared/schema.js';
import { eq, desc } from 'drizzle-orm';

const router = Router();

// Get all pending items for manager dashboard
router.get('/api/manager/dashboard', async (req, res) => {
  try {
    // Get pending attendance requests
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

    // Get pending leave requests
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

    // Get pending salary advances
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

    // Get pending absence notifications
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

export default router;
