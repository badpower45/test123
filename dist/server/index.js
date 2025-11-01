import express from 'express';
import cors from 'cors';
import path from 'path';
import { fileURLToPath } from 'url';
import bcrypt from 'bcrypt';
import cron from 'node-cron';
import { db } from './db.js';
import { employees, attendance, attendanceRequests, leaveRequests, advances, deductions, absenceNotifications, pulses, branches, branchBssids, branchManagers, breaks, deviceSessions, notifications, salaryCalculations, geofenceViolations } from '../shared/schema.js';
import { eq, and, gte, lte, lt, desc, sql, inArray, isNull, or } from 'drizzle-orm';
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
/**
 * Helper function to get date string in YYYY-MM-DD format
 */
function getDateString(date) {
    if (typeof date === 'string') {
        return date;
    }
    return date.toISOString().split('T')[0];
}
/**
 * Helper function to validate BSSID format
 * BSSID should be 6 pairs of hex digits separated by colons or dashes
 */
function isValidBssid(bssid) {
    if (!bssid)
        return false;
    // Regex to match 6 pairs of hex digits (0-9, A-F, a-f) separated by : or -
    const bssidRegex = /^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$/;
    return bssidRegex.test(bssid);
}
// =============================================================================
/**
 * Convert string numbers to actual numbers in objects
 * This fixes PostgreSQL returning numeric fields as strings
 */
function normalizeNumericFields(obj, fields) {
    if (!obj)
        return obj;
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
function extractRows(result) {
    if (Array.isArray(result)) {
        return result;
    }
    return [];
}
function extractFirstRow(result) {
    const rows = extractRows(result);
    return rows.length > 0 ? rows[0] : undefined;
}
async function getOwnerRecord(ownerId) {
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
    const role = owner.role;
    if (role !== 'owner' && role !== 'admin') {
        return null;
    }
    return owner;
}
/**
 * Check if reviewer can approve a request from an employee
 * Rules:
 * - If employee is a MANAGER, only OWNER can approve
 * - If employee is STAFF, MANAGER or OWNER can approve
 */
async function canApproveRequest(reviewerId, employeeId) {
    try {
        console.log('🔍 Checking approval permissions:', { reviewerId, employeeId });
        // Get reviewer info
        const [reviewer] = await db
            .select()
            .from(employees)
            .where(eq(employees.id, reviewerId))
            .limit(1);
        if (!reviewer) {
            console.log('❌ Reviewer not found:', reviewerId);
            return { canApprove: false, reason: 'Reviewer not found' };
        }
        console.log('👤 Reviewer:', { id: reviewer.id, role: reviewer.role, branchId: reviewer.branchId });
        // Get employee info
        const [employee] = await db
            .select()
            .from(employees)
            .where(eq(employees.id, employeeId))
            .limit(1);
        if (!employee) {
            console.log('❌ Employee not found:', employeeId);
            return { canApprove: false, reason: 'Employee not found' };
        }
        console.log('👤 Employee:', { id: employee.id, role: employee.role, branchId: employee.branchId });
        const reviewerRole = reviewer.role;
        const employeeRole = employee.role;
        // Owner can approve anything
        if (reviewerRole === 'owner') {
            console.log('✅ Owner can approve anything');
            return { canApprove: true };
        }
        // If employee is a manager, only owner can approve
        if (employeeRole === 'manager') {
            console.log('❌ Only owner can approve manager requests');
            return {
                canApprove: false,
                reason: 'Only owner can approve requests from managers. Manager requests must be reviewed by owner.'
            };
        }
        // If employee is staff and reviewer is manager, check if they're in same branch
        if (reviewerRole === 'manager' && (employeeRole === 'staff' || employeeRole === 'monitor' || employeeRole === 'hr')) {
            // Check if they're in the same branch
            if (reviewer.branchId && employee.branchId && reviewer.branchId === employee.branchId) {
                console.log('✅ Manager can approve - same branch');
                return { canApprove: true };
            }
            console.log('❌ Manager cannot approve - different branch or missing branchId');
            return {
                canApprove: false,
                reason: 'Manager can only approve requests from employees in their branch'
            };
        }
        console.log('❌ Insufficient permissions');
        return {
            canApprove: false,
            reason: 'Insufficient permissions to approve this request'
        };
    }
    catch (error) {
        console.error('Error checking approval permissions:', error);
        return { canApprove: false, reason: 'Error checking permissions' };
    }
}
/**
 * Send notification to user
 */
async function sendNotification(recipientId, type, title, message, senderId, relatedId) {
    try {
        await db.insert(notifications).values({
            recipientId,
            senderId: senderId || null,
            type: type,
            title,
            message,
            relatedId: relatedId || null,
        });
    }
    catch (error) {
        console.error('Send notification error:', error);
    }
}
/**
 * Get owner employee ID
 */
async function getOwnerId() {
    try {
        const owners = await db
            .select()
            .from(employees)
            .where(eq(employees.role, 'owner'))
            .limit(1);
        if (owners.length > 0) {
            return owners[0].id;
        }
        return null;
    }
    catch (error) {
        console.error('Get owner ID error:', error);
        return null;
    }
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
    }
    catch (err) {
        res.status(500).json({ error: 'Internal server error', message: err?.message });
    }
});
// Approve/reject a request (leave, advance, attendance, absence)
app.post('/api/branch/request/:type/:id/:action', async (req, res) => {
    try {
        let { type, id, action } = req.params;
        const validTypes = ['leave', 'advance', 'attendance', 'absence', 'break'];
        // Normalize common plural aliases
        const typeMap = {
            leaves: 'leave',
            advances: 'advance',
            attendances: 'attendance',
            absences: 'absence',
            breaks: 'break',
        };
        type = (typeMap[type] || type);
        const validActions = ['approve', 'reject', 'postpone'];
        if (!validTypes.includes(type) || !validActions.includes(action)) {
            return res.status(400).json({ error: 'Invalid type or action' });
        }
        const reviewerId = req.body?.reviewer_id || req.body?.manager_id;
        if (!reviewerId) {
            return res.status(400).json({ error: 'reviewer_id or manager_id is required' });
        }
        // Get the employee ID from the request based on type
        let employeeId;
        if (type === 'break') {
            const [breakRecord] = await db.select().from(breaks).where(eq(breaks.id, id)).limit(1);
            if (!breakRecord) {
                return res.status(404).json({ error: 'Break request not found' });
            }
            employeeId = breakRecord.employeeId;
        }
        else {
            let table;
            switch (type) {
                case 'leave':
                    table = leaveRequests;
                    break;
                case 'advance':
                    table = advances;
                    break;
                case 'attendance':
                    table = attendanceRequests;
                    break;
                case 'absence':
                    table = absenceNotifications;
                    break;
                default: return res.status(400).json({ error: 'Invalid request type' });
            }
            const [record] = await db.select().from(table).where(eq(table.id, id)).limit(1);
            if (!record) {
                return res.status(404).json({ error: 'Request not found' });
            }
            employeeId = record.employeeId;
        }
        // Check if reviewer can approve this request
        const approvalCheck = await canApproveRequest(reviewerId, employeeId);
        if (!approvalCheck.canApprove) {
            return res.status(403).json({
                error: 'Forbidden',
                message: approvalCheck.reason || 'You do not have permission to approve this request'
            });
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
        }
        else {
            let table;
            switch (type) {
                case 'leave':
                    table = leaveRequests;
                    break;
                case 'advance':
                    table = advances;
                    break;
                case 'attendance':
                    table = attendanceRequests;
                    break;
                case 'absence':
                    table = absenceNotifications;
                    break;
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
    }
    catch (err) {
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
    }
    catch (err) {
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
            const updateData = { updatedAt: new Date() };
            if (check_in_time !== undefined)
                updateData.checkInTime = check_in_time;
            if (check_out_time !== undefined)
                updateData.checkOutTime = check_out_time;
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
        }
        else {
            // Create new attendance
            const insertData = {
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
    }
    catch (err) {
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
            .where(and(eq(employees.id, normalizedEmployeeId), eq(employees.active, true)))
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
        }
        else {
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
    }
    catch (error) {
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
        const { employee_id, latitude, longitude, wifi_bssid } = req.body;
        if (!employee_id) {
            return res.status(400).json({ error: 'Employee ID is required' });
        }
        // Fetch employee to check shift times
        const [employee] = await db
            .select()
            .from(employees)
            .where(eq(employees.id, employee_id))
            .limit(1);
        if (!employee) {
            return res.status(404).json({ error: 'Employee not found' });
        }
        // --- START VERIFICATION (WiFi OR Location) ---
        let isWifiValid = false;
        let isLocationValid = false;
        if (employee.branchId) {
            const [branch] = await db
                .select()
                .from(branches)
                .where(eq(branches.id, employee.branchId))
                .limit(1);
            if (branch) {
                // 1️⃣ Check WiFi BSSID
                const allowedBssids = new Set();
                // Add legacy BSSIDs
                if (branch.bssid_1)
                    allowedBssids.add(branch.bssid_1.toUpperCase());
                if (branch.bssid_2)
                    allowedBssids.add(branch.bssid_2.toUpperCase());
                // Add BSSIDs from branchBssids table
                const bssidRecords = await db
                    .select()
                    .from(branchBssids)
                    .where(eq(branchBssids.branchId, employee.branchId));
                bssidRecords.forEach(record => {
                    if (record.bssidAddress) {
                        allowedBssids.add(record.bssidAddress.toUpperCase());
                    }
                });
                if (allowedBssids.size > 0) {
                    const currentBssid = wifi_bssid ? String(wifi_bssid).toUpperCase() : null;
                    if (currentBssid && allowedBssids.has(currentBssid)) {
                        isWifiValid = true;
                        console.log(`[Check-In] ✅ WiFi VALID - BSSID: ${currentBssid}`);
                    }
                    else {
                        console.log(`[Check-In] ❌ WiFi INVALID - BSSID: ${currentBssid || 'غير موجود'}`);
                    }
                }
                else {
                    console.log(`[Check-In] ⚠️ No WiFi BSSIDs configured for branch`);
                }
                // 2️⃣ Check Location (Geofence)
                if (latitude && longitude) {
                    const branchLat = branch.latitude ? Number(branch.latitude) : null;
                    const branchLng = branch.longitude ? Number(branch.longitude) : null;
                    const radius = branch.geofenceRadius || 200;
                    if (branchLat && branchLng) {
                        const R = 6371000;
                        const toRad = (deg) => (deg * Math.PI) / 180;
                        const φ1 = toRad(branchLat);
                        const φ2 = toRad(latitude);
                        const Δφ = toRad(latitude - branchLat);
                        const Δλ = toRad(longitude - branchLng);
                        const a = Math.sin(Δφ / 2) * Math.sin(Δφ / 2) +
                            Math.cos(φ1) * Math.cos(φ2) *
                                Math.sin(Δλ / 2) * Math.sin(Δλ / 2);
                        const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
                        const distance = R * c;
                        if (distance <= radius) {
                            isLocationValid = true;
                            console.log(`[Check-In] ✅ Location VALID - Distance: ${distance.toFixed(2)}m`);
                        }
                        else {
                            console.log(`[Check-In] ❌ Location INVALID - Distance: ${distance.toFixed(2)}m (Max: ${radius}m)`);
                        }
                    }
                    else {
                        console.log(`[Check-In] ⚠️ No geofence configured for branch`);
                    }
                }
                else {
                    console.log(`[Check-In] ⚠️ No location provided`);
                }
                // 3️⃣ Check: WiFi OR Location (at least one must be valid)
                if (!isWifiValid && !isLocationValid) {
                    console.log(`[Check-In] ❌ REJECTED - Neither WiFi nor Location is valid`);
                    return res.status(403).json({
                        error: 'يجب أن تكون متصلاً بشبكة الواي فاي الخاصة بالفرع أو متواجداً في الموقع الصحيح لتسجيل الحضور.',
                        message: 'تأكد من الاتصال بالـ WiFi الصحيح أو التواجد داخل الفرع.',
                        code: 'INVALID_WIFI_OR_LOCATION',
                    });
                }
                console.log(`[Check-In] ✅ APPROVED - WiFi: ${isWifiValid}, Location: ${isLocationValid}`);
            }
        }
        // --- END VERIFICATION ---
        // --- START DEBUG LOG ---
        console.log(`[Check-In Debug] Employee: ${employee_id}, Shift Start: ${employee.shiftStartTime}, Shift End: ${employee.shiftEndTime}`);
        // Get Egypt/Cairo time
        const cairoTime = new Date().toLocaleString('en-US', { timeZone: 'Africa/Cairo' });
        const cairoDate = new Date(cairoTime);
        console.log(`[Check-In Debug] Server Time (UTC): ${new Date().toISOString()}`);
        console.log(`[Check-In Debug] Cairo Time: ${cairoTime}`);
        console.log(`[Check-In Debug] Cairo Time (Date Object): ${cairoDate.toISOString()}`);
        // --- END DEBUG LOG ---
        // Validate shift time using Cairo timezone
        if (employee.shiftStartTime && employee.shiftEndTime) {
            // Use Cairo time for validation
            const currentHour = cairoDate.getHours();
            const currentMinute = cairoDate.getMinutes();
            const currentTime = currentHour * 60 + currentMinute; // Convert to minutes since midnight
            console.log(`[Check-In Debug] Cairo Current Time: ${currentHour}:${currentMinute.toString().padStart(2, '0')} (${currentTime} minutes)`);
            // Parse shift times (format: "HH:mm")
            const [startHour, startMinute] = employee.shiftStartTime.split(':').map(Number);
            const [endHour, endMinute] = employee.shiftEndTime.split(':').map(Number);
            const shiftStart = startHour * 60 + startMinute;
            const shiftEnd = endHour * 60 + endMinute;
            console.log(`[Check-In Debug] Shift Window: ${employee.shiftStartTime} (${shiftStart} min) to ${employee.shiftEndTime} (${shiftEnd} min)`);
            // Check if current time is within shift window
            let isWithinShift = false;
            if (shiftEnd > shiftStart) {
                // Normal shift (e.g., 9:00 - 17:00)
                isWithinShift = currentTime >= shiftStart && currentTime <= shiftEnd;
                console.log(`[Check-In Debug] Normal shift check: ${currentTime} >= ${shiftStart} && ${currentTime} <= ${shiftEnd} = ${isWithinShift}`);
            }
            else {
                // Night shift crossing midnight (e.g., 21:00 - 05:00)
                isWithinShift = currentTime >= shiftStart || currentTime <= shiftEnd;
                console.log(`[Check-In Debug] Night shift check: ${currentTime} >= ${shiftStart} || ${currentTime} <= ${shiftEnd} = ${isWithinShift}`);
            }
            if (!isWithinShift) {
                const formatTime = (minutes) => {
                    const h = Math.floor(minutes / 60);
                    const m = minutes % 60;
                    return `${h.toString().padStart(2, '0')}:${m.toString().padStart(2, '0')}`;
                };
                console.log(`[Check-In Debug] ❌ REJECTED - Outside shift time`);
                return res.status(400).json({
                    error: 'لا يمكنك تسجيل الحضور خارج وقت الشيفت المحدد',
                    message: `وقت الشيفت الخاص بك من ${employee.shiftStartTime} إلى ${employee.shiftEndTime}. الوقت الحالي: ${formatTime(currentTime)}`,
                    shiftStartTime: employee.shiftStartTime,
                    shiftEndTime: employee.shiftEndTime,
                    currentTime: formatTime(currentTime),
                    cairoTime: cairoTime,
                    code: 'OUTSIDE_SHIFT_TIME',
                });
            }
            console.log(`[Check-In Debug] ✅ APPROVED - Within shift time`);
        }
        const today = new Date().toISOString().split('T')[0];
        // Check if already checked in today
        const [existing] = await db
            .select()
            .from(attendance)
            .where(and(eq(attendance.employeeId, employee_id), eq(attendance.date, today), eq(attendance.status, 'active')))
            .limit(1);
        if (existing) {
            return res.status(400).json({
                error: 'Already checked in today',
                attendance: existing
            });
        }
        // Use transaction to ensure atomicity
        const result = await db.transaction(async (tx) => {
            // Create new attendance record
            const insertResult = await tx
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
            if (latitude && longitude && employee.branchId) {
                await tx.insert(pulses).values({
                    employeeId: employee_id,
                    branchId: employee.branchId,
                    latitude,
                    longitude,
                    isWithinGeofence: true,
                });
            }
            return newAttendance;
        });
        // Send notification to owner
        const ownerId = await getOwnerId();
        if (ownerId) {
            const checkInTime = new Date().toLocaleTimeString('ar-EG', {
                hour: '2-digit',
                minute: '2-digit'
            });
            await sendNotification(ownerId, 'CHECK_IN', 'تسجيل حضور جديد', `${employee.fullName} سجل حضوره في ${checkInTime}`, employee_id, result?.id);
        }
        res.status(201).json({
            success: true,
            message: 'تم تسجيل الحضور بنجاح',
            attendance: {
                id: result?.id,
                employeeId: employee_id,
                date: today,
                checkInTime: result?.checkInTime,
                checkOutTime: null,
                workHours: '0.00',
                status: 'active',
            },
        });
    }
    catch (error) {
        console.error('Check-in error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// Check Out
app.post('/api/attendance/check-out', async (req, res) => {
    try {
        const { employee_id, latitude, longitude, wifi_bssid } = req.body;
        if (!employee_id) {
            return res.status(400).json({ error: 'Employee ID is required' });
        }
        const today = new Date().toISOString().split('T')[0];
        console.log(`[Check-Out] Looking for active attendance for employee: ${employee_id} on date: ${today}`);
        // Find active attendance record - look for active status (handle night shifts properly)
        const [activeAttendance] = await db
            .select()
            .from(attendance)
            .where(and(eq(attendance.employeeId, employee_id), eq(attendance.status, 'active')))
            .orderBy(desc(attendance.checkInTime)) // Get the most recent check-in for night shifts
            .limit(1);
        if (!activeAttendance) {
            console.log(`[Check-Out] ❌ No active attendance found for employee: ${employee_id}`);
            return res.status(400).json({ error: 'No active check-in found for today' });
        }
        console.log(`[Check-Out] ✅ Found active attendance ID: ${activeAttendance.id}`);
        // Fetch employee data
        const [employee] = await db
            .select()
            .from(employees)
            .where(eq(employees.id, employee_id))
            .limit(1);
        // --- START VERIFICATION (WiFi OR Location) ---
        let isWifiValid = false;
        let isLocationValid = false;
        if (employee && employee.branchId) {
            const [branch] = await db
                .select()
                .from(branches)
                .where(eq(branches.id, employee.branchId))
                .limit(1);
            if (branch) {
                // 1️⃣ Check WiFi BSSID
                const allowedBssids = new Set();
                // Add legacy BSSIDs
                if (branch.bssid_1)
                    allowedBssids.add(branch.bssid_1.toUpperCase());
                if (branch.bssid_2)
                    allowedBssids.add(branch.bssid_2.toUpperCase());
                // Add BSSIDs from branchBssids table
                const bssidRecords = await db
                    .select()
                    .from(branchBssids)
                    .where(eq(branchBssids.branchId, employee.branchId));
                bssidRecords.forEach(record => {
                    if (record.bssidAddress) {
                        allowedBssids.add(record.bssidAddress.toUpperCase());
                    }
                });
                if (allowedBssids.size > 0) {
                    const currentBssid = wifi_bssid ? String(wifi_bssid).toUpperCase().replace(/-/g, ':') : null;
                    if (currentBssid && allowedBssids.has(currentBssid)) {
                        isWifiValid = true;
                        console.log(`[Check-Out] ✅ WiFi VALID - BSSID: ${currentBssid}`);
                    }
                    else {
                        console.log(`[Check-Out] ❌ WiFi INVALID - BSSID: ${currentBssid || 'غير موجود'}`);
                    }
                }
                else {
                    console.log(`[Check-Out] ⚠️ No WiFi BSSIDs configured for branch`);
                }
                // 2️⃣ Check Location (Geofence)
                if (latitude && longitude) {
                    const branchLat = branch.latitude ? Number(branch.latitude) : null;
                    const branchLng = branch.longitude ? Number(branch.longitude) : null;
                    const radius = branch.geofenceRadius || 200;
                    if (branchLat && branchLng) {
                        const R = 6371000;
                        const toRad = (deg) => (deg * Math.PI) / 180;
                        const φ1 = toRad(branchLat);
                        const φ2 = toRad(latitude);
                        const Δφ = toRad(latitude - branchLat);
                        const Δλ = toRad(longitude - branchLng);
                        const a = Math.sin(Δφ / 2) * Math.sin(Δφ / 2) +
                            Math.cos(φ1) * Math.cos(φ2) *
                                Math.sin(Δλ / 2) * Math.sin(Δλ / 2);
                        const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
                        const distance = R * c;
                        if (distance <= radius) {
                            isLocationValid = true;
                            console.log(`[Check-Out] ✅ Location VALID - Distance: ${distance.toFixed(2)}m`);
                        }
                        else {
                            console.log(`[Check-Out] ❌ Location INVALID - Distance: ${distance.toFixed(2)}m (Max: ${radius}m)`);
                        }
                    }
                    else {
                        console.log(`[Check-Out] ⚠️ No geofence configured for branch`);
                    }
                }
                else {
                    console.log(`[Check-Out] ⚠️ No location provided`);
                }
                // 3️⃣ Check: WiFi OR Location (at least one must be valid)
                if (!isWifiValid && !isLocationValid) {
                    console.log(`[Check-Out] ❌ REJECTED - Neither WiFi nor Location is valid`);
                    return res.status(403).json({
                        error: 'يجب أن تكون متصلاً بشبكة الواي فاي الخاصة بالفرع أو متواجداً في الموقع الصحيح لتسجيل الانصراف.',
                        message: 'تأكد من الاتصال بالـ WiFi الصحيح أو التواجد داخل الفرع.',
                        code: 'INVALID_WIFI_OR_LOCATION',
                    });
                }
                console.log(`[Check-Out] ✅ APPROVED - WiFi: ${isWifiValid}, Location: ${isLocationValid}`);
            }
        }
        // --- END VERIFICATION ---
        // Calculate work hours
        const checkOutTime = new Date();
        const checkInTime = new Date(activeAttendance.checkInTime);
        const workHours = (checkOutTime.getTime() - checkInTime.getTime()) / (1000 * 60 * 60);
        // Use transaction to ensure atomicity
        const result = await db.transaction(async (tx) => {
            // Update attendance record
            const updateResult = await tx
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
            if (latitude && longitude && employee && employee.branchId) {
                await tx.insert(pulses).values({
                    employeeId: employee_id,
                    branchId: employee.branchId,
                    latitude,
                    longitude,
                    status: 'IN',
                    createdAt: new Date(),
                });
            }
            return updated;
        });
        res.json({
            success: true,
            message: 'تم تسجيل الانصراف بنجاح',
            attendance: result,
            workHours: parseFloat(workHours.toFixed(2)),
        });
    }
    catch (error) {
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
        const startTs = new Date(todayAttendance.checkInTime);
        const now = new Date();
        const result = await db
            .select({ count: sql `count(*)` })
            .from(pulses)
            .where(and(eq(pulses.employeeId, employeeId), eq(pulses.isWithinGeofence, true), gte(pulses.createdAt, startTs), lte(pulses.createdAt, now)));
        const validPulseCount = Number(result[0]?.count) || 0;
        // Fetch employee to get their hourly rate (fallback to 40 if not set)
        const [employeeRecord] = await db
            .select()
            .from(employees)
            .where(eq(employees.id, employeeId))
            .limit(1);
        const hourlyRate = employeeRecord && employeeRecord.hourlyRate ? Number(employeeRecord.hourlyRate) : 40;
        const pulseValue = (hourlyRate / 3600) * 30; // قيمة كل نبضة (30 ثانية)
        const earnings = validPulseCount * pulseValue;
        res.json({
            success: true,
            active: true,
            validPulseCount,
            earnings: parseFloat(earnings.toFixed(2)),
            checkInTime: todayAttendance.checkInTime,
        });
    }
    catch (error) {
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
            .select({ count: sql `count(*)` })
            .from(pulses)
            .where(and(eq(pulses.employeeId, employeeId), eq(pulses.isWithinGeofence, true), gte(pulses.createdAt, startTs), lte(pulses.createdAt, endTs)));
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
    }
    catch (error) {
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
            .where(and(eq(attendanceRequests.employeeId, employee_id), eq(attendanceRequests.requestType, 'check-in'), eq(attendanceRequests.status, 'pending'), sql `DATE(${attendanceRequests.requestedTime}) = ${reqDay}`))
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
    }
    catch (error) {
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
    }
    catch (error) {
        console.error('Check-out request error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// Get pending requests (for manager)
app.get('/api/attendance/requests', async (req, res) => {
    try {
        const { status = 'pending', manager_id } = req.query;
        let query = db
            .select({
            id: attendanceRequests.id,
            employeeId: attendanceRequests.employeeId,
            employeeName: employees.fullName,
            employeeBranch: employees.branch,
            employeeBranchId: employees.branchId,
            requestType: attendanceRequests.requestType,
            requestedTime: attendanceRequests.requestedTime,
            reason: attendanceRequests.reason,
            status: attendanceRequests.status,
            createdAt: attendanceRequests.createdAt,
        })
            .from(attendanceRequests)
            .innerJoin(employees, eq(attendanceRequests.employeeId, employees.id))
            .$dynamic();
        // أول فلترة (دي لازم تكون موجودة دايماً)
        query = query.where(eq(attendanceRequests.status, status));
        // If manager_id provided, filter by employees in that manager's branch
        if (manager_id && typeof manager_id === 'string') {
            // Get manager's branch
            const [manager] = await db
                .select()
                .from(employees)
                .where(eq(employees.id, manager_id))
                .limit(1);
            if (manager && manager.branchId) {
                // Find branches where this manager is assigned
                const managerBranches = await db
                    .select()
                    .from(branches)
                    .where(eq(branches.managerId, manager_id));
                const branchIds = managerBranches.map(b => b.id);
                if (branchIds.length > 0) {
                    // Filter requests to only employees in manager's branches
                    query = query.where(sql `${employees.branchId} = ANY(${branchIds})`);
                }
                else {
                    // Manager has no branches, return empty
                    return res.json({ requests: [] });
                }
            }
        }
        const requests = await query.orderBy(desc(attendanceRequests.createdAt));
        res.json({ requests });
    }
    catch (error) {
        console.error('Get requests error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// Approve/reject attendance request
app.post('/api/attendance/requests/:requestId/review', async (req, res) => {
    try {
        const { requestId } = req.params;
        const { action, reviewer_id, notes, owner_user_id, manager_id } = req.body;
        const approverId = reviewer_id || owner_user_id || manager_id;
        if (!action || !['approve', 'reject'].includes(action)) {
            return res.status(400).json({ error: 'Action must be approve or reject' });
        }
        if (!approverId) {
            return res.status(400).json({ error: 'reviewer_id, owner_user_id, or manager_id is required' });
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
        // Check if reviewer can approve this request
        const approvalCheck = await canApproveRequest(approverId, request.employeeId);
        if (!approvalCheck.canApprove) {
            return res.status(403).json({
                error: 'Forbidden',
                message: approvalCheck.reason || 'You do not have permission to approve this request'
            });
        }
        // Update request status
        const updateResult = await db
            .update(attendanceRequests)
            .set({
            status: action === 'approve' ? 'approved' : 'rejected',
            reviewedBy: approverId,
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
                    .where(and(eq(attendance.employeeId, request.employeeId), eq(attendance.date, requestDate)))
                    .limit(1);
                if (!existing) {
                    await db.insert(attendance).values({
                        employeeId: request.employeeId,
                        checkInTime: requestedDateTime,
                        date: requestDate,
                        status: 'active',
                    });
                }
                else {
                    // Update existing record with the new check-in time
                    await db
                        .update(attendance)
                        .set({
                        checkInTime: requestedDateTime,
                        status: 'active',
                    })
                        .where(eq(attendance.id, existing.id));
                }
            }
            else if (request.requestType === 'check-out') {
                const [activeAttendance] = await db
                    .select()
                    .from(attendance)
                    .where(and(eq(attendance.employeeId, request.employeeId), eq(attendance.date, requestDate), eq(attendance.status, 'active')))
                    .limit(1);
                if (activeAttendance) {
                    const checkOutTime = requestedDateTime;
                    const checkInTime = new Date(activeAttendance.checkInTime);
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
    }
    catch (error) {
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
        let leaveType = 'regular';
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
    }
    catch (error) {
        console.error('Leave request error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// Get leave requests
app.get('/api/leave/requests', async (req, res) => {
    try {
        const { employee_id, status, manager_id } = req.query;
        let query = db
            .select({
            id: leaveRequests.id,
            employeeId: leaveRequests.employeeId,
            employeeName: employees.fullName,
            employeeBranch: employees.branch,
            employeeBranchId: employees.branchId,
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
            query = query.where(eq(leaveRequests.employeeId, employee_id));
        }
        if (status) {
            query = query.where(eq(leaveRequests.status, status));
        }
        // If manager_id provided, filter by employees in that manager's branch
        if (manager_id && typeof manager_id === 'string' && !employee_id) {
            const managerBranches = await db
                .select()
                .from(branches)
                .where(eq(branches.managerId, manager_id));
            const branchIds = managerBranches.map(b => b.id);
            if (branchIds.length > 0) {
                query = query.where(sql `${employees.branchId} = ANY(${branchIds})`);
            }
            else {
                // Manager has no branches, return empty
                return res.json({ requests: [] });
            }
        }
        const requests = await query.orderBy(desc(leaveRequests.createdAt));
        res.json({
            requests: requests.map(r => normalizeNumericFields(r, ['daysCount', 'allowanceAmount']))
        });
    }
    catch (error) {
        console.error('Get leave requests error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// Approve/reject leave request
app.post('/api/leave/requests/:requestId/review', async (req, res) => {
    try {
        const { requestId } = req.params;
        const { action, reviewer_id, notes, owner_user_id, manager_id } = req.body;
        const approverId = reviewer_id || owner_user_id || manager_id;
        if (!action || !['approve', 'reject'].includes(action)) {
            return res.status(400).json({ error: 'Action must be approve or reject' });
        }
        if (!approverId) {
            return res.status(400).json({ error: 'reviewer_id, owner_user_id, or manager_id is required' });
        }
        // Get request details
        const [request] = await db
            .select()
            .from(leaveRequests)
            .where(eq(leaveRequests.id, requestId))
            .limit(1);
        if (!request) {
            return res.status(404).json({ error: 'Request not found' });
        }
        // Check if reviewer can approve this request
        const approvalCheck = await canApproveRequest(approverId, request.employeeId);
        if (!approvalCheck.canApprove) {
            return res.status(403).json({
                error: 'Forbidden',
                message: approvalCheck.reason || 'You do not have permission to approve this request'
            });
        }
        // Use transaction to ensure all operations succeed or fail together
        const result = await db.transaction(async (tx) => {
            // Update leave request status
            const updateResult = await tx
                .update(leaveRequests)
                .set({
                status: action === 'approve' ? 'approved' : 'rejected',
                reviewedBy: approverId,
                reviewedAt: new Date(),
                reviewNotes: notes,
            })
                .where(eq(leaveRequests.id, requestId))
                .returning();
            const updated = extractFirstRow(updateResult);
            // If approved, mark attendance and deduct allowance if needed
            if (action === 'approve' && updated) {
                // Get the leave dates
                const datesToLog = getDatesInRange(updated.startDate, updated.endDate);
                const datesAsStrings = datesToLog.map(d => d.toISOString().split('T')[0]);
                // Delete any existing attendance records for these dates
                await tx
                    .delete(attendance)
                    .where(and(eq(attendance.employeeId, updated.employeeId), inArray(attendance.date, datesAsStrings)));
                // Insert ON_LEAVE attendance records
                const attendanceRecordsToInsert = datesAsStrings.map(dateStr => ({
                    employeeId: updated.employeeId,
                    date: dateStr,
                    status: 'ON_LEAVE',
                    checkInTime: null,
                    checkOutTime: null,
                    workHours: '0',
                    createdAt: new Date(),
                    updatedAt: new Date(),
                }));
                if (attendanceRecordsToInsert.length > 0) {
                    await tx.insert(attendance).values(attendanceRecordsToInsert);
                }
                // Deduct allowance if days > 2
                const daysCount = Number(updated.daysCount);
                const allowanceAmount = Number(updated.allowanceAmount);
                if (daysCount > 2 && allowanceAmount > 0) {
                    const today = new Date().toISOString().split('T')[0];
                    await tx.insert(deductions).values({
                        employeeId: updated.employeeId,
                        amount: String(allowanceAmount),
                        reason: `خصم بدل إجازة (${daysCount} أيام)`,
                        deductionDate: today,
                        deductionType: 'leave_allowance',
                        appliedBy: reviewer_id,
                        createdAt: new Date(),
                    });
                }
            }
            return updated;
        });
        res.json({
            success: true,
            message: action === 'approve' ? 'تم الموافقة على الإجازة' : 'تم رفض الإجازة',
            request: normalizeNumericFields(result, ['daysCount', 'allowanceAmount']),
        });
    }
    catch (error) {
        console.error('Review leave request error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// =============================================================================
// LEAVE REQUEST ENHANCEMENTS - تحسينات نظام طلبات الإجازات
// =============================================================================
// دالة مساعدة للحصول على كل التواريخ بين تاريخين
function getDatesInRange(startDateStr, endDateStr) {
    const dates = [];
    // معالجة التواريخ لضمان عدم الوقوع في مشاكل التوقيت المحلي (Timezone)
    const start = new Date(startDateStr + 'T00:00:00Z');
    const end = new Date(endDateStr + 'T00:00:00Z');
    let current = new Date(start.getTime());
    while (current <= end) {
        dates.push(new Date(current.getTime())); // إضافة نسخة من التاريخ
        current.setDate(current.getDate() + 1); // الانتقال لليوم التالي
    }
    return dates;
}
/**
 * دالة لجلب طلبات الإجازة المعلقة مع تفاصيل الموظف والفرع للأونر
 */
export async function getDetailedPendingLeaveRequestsForOwner() {
    const detailedRequests = await db.select({
        // --- من جدول leaveRequests ---
        requestId: leaveRequests.id,
        startDate: leaveRequests.startDate,
        endDate: leaveRequests.endDate,
        leaveType: leaveRequests.leaveType,
        reason: leaveRequests.reason,
        status: leaveRequests.status,
        daysCount: leaveRequests.daysCount,
        allowanceAmount: leaveRequests.allowanceAmount,
        createdAt: leaveRequests.createdAt,
        // --- من جدول employees ---
        employeeId: employees.id,
        employeeName: employees.fullName,
        employeeRole: employees.role,
        employeeSalary: employees.monthlySalary,
        // --- من جدول branches ---
        branchName: branches.name,
    })
        .from(leaveRequests)
        .leftJoin(employees, eq(leaveRequests.employeeId, employees.id))
        .leftJoin(branches, eq(employees.branchId, branches.id))
        .where(eq(leaveRequests.status, 'pending'))
        .orderBy(desc(leaveRequests.createdAt));
    return detailedRequests;
}
/**
 * دالة لموافقة الأونر على طلب إجازة + تسجيله آلياً في جدول الحضور
 * @param leaveRequestId - ID طلب الإجازة للموافقة عليه
 * @param ownerUserId - ID الأونر الذي قام بالموافقة (من جدول 'users')
 */
export async function approveLeaveRequestAndLogAttendance(leaveRequestId, ownerUserId // نفترض أنه UUID حسب الـ schema
) {
    // نستخدم Transaction لضمان تنفيذ العمليتين معاً أو فشلهما معاً
    const result = await db.transaction(async (tx) => {
        // 1. تحديث حالة طلب الإجازة إلى "approved"
        const updatedLeaves = await tx
            .update(leaveRequests)
            .set({
            status: 'approved',
            reviewedBy: ownerUserId,
            reviewedAt: new Date(),
        })
            .where(and(eq(leaveRequests.id, leaveRequestId), eq(leaveRequests.status, 'pending')))
            .returning({
            employeeId: leaveRequests.employeeId,
            startDate: leaveRequests.startDate,
            endDate: leaveRequests.endDate
        });
        if (updatedLeaves.length === 0) {
            throw new Error('لم يتم العثور على الطلب أو تم مراجعته من قبل.');
        }
        const leave = updatedLeaves[0];
        // 2. الحصول على قائمة الأيام الخاصة بالإجازة
        // (الـ Schema تشير إلى أن startDate/endDate من نوع 'date')
        const datesToLog = getDatesInRange(leave.startDate, leave.endDate);
        if (datesToLog.length === 0) {
            throw new Error('نطاق التواريخ غير صحيح.');
        }
        const datesAsStrings = datesToLog.map(d => d.toISOString().split('T')[0]); // 'YYYY-MM-DD'
        // 3. (مهم جداً) حذف أي سجلات حضور موجودة لهذا الموظف في هذه الأيام
        // هذا يضمن أن سجل "الإجازة" يحل محل أي سجل "غياب آلي"
        await tx
            .delete(attendance)
            .where(and(eq(attendance.employeeId, leave.employeeId), inArray(attendance.date, datesAsStrings)));
        // 4. تجهيز سجلات الحضور الجديدة (يوم لكل تاريخ)
        const attendanceRecordsToInsert = datesAsStrings.map(dateStr => ({
            // 'id' سيتم إنشاؤه آلياً (defaultRandom)
            employeeId: leave.employeeId,
            date: dateStr, // تاريخ اليوم 'YYYY-MM-DD'
            status: 'ON_LEAVE', // <-- *** الحالة الجديدة التي تميز الإجازة ***
            checkInTime: null,
            checkOutTime: null,
            workHours: '0', // ساعات العمل صفر لأنه إجازة
            createdAt: new Date(),
            updatedAt: new Date(),
        }));
        // 5. إدخال السجلات الجديدة دفعة واحدة في جدول الحضور
        if (attendanceRecordsToInsert.length > 0) {
            await tx
                .insert(attendance)
                .values(attendanceRecordsToInsert);
        }
        return {
            success: true,
            message: 'تمت الموافقة وتسجيل الإجازة في الحضور',
            employeeId: leave.employeeId,
            daysLogged: datesToLog.length
        };
    });
    return result;
}
// New API endpoint for owner to get detailed pending leave requests
app.get('/api/owner/leaves/pending', async (req, res) => {
    try {
        const ownerId = req.query.owner_id;
        if (!ownerId) {
            return res.status(400).json({ error: 'owner_id is required' });
        }
        const ownerRecord = await getOwnerRecord(ownerId);
        if (!ownerRecord) {
            return res.status(403).json({ error: 'لا توجد صلاحيات للوصول إلى طلبات الإجازات' });
        }
        const detailedRequests = await getDetailedPendingLeaveRequestsForOwner();
        // Normalize numeric fields
        const normalizedRequests = detailedRequests.map(request => ({
            ...request,
            daysCount: request.daysCount ? Number(request.daysCount) : 0,
            allowanceAmount: request.allowanceAmount ? Number(request.allowanceAmount) : 0,
            employeeSalary: request.employeeSalary ? Number(request.employeeSalary) : 0,
        }));
        res.json({
            success: true,
            requests: normalizedRequests,
        });
    }
    catch (error) {
        console.error('Get detailed pending leave requests error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// New API endpoint for owner to approve leave request and log attendance
app.post('/api/owner/leaves/approve', async (req, res) => {
    try {
        const { leave_request_id, owner_user_id, reviewer_id, manager_id } = req.body;
        const approverId = owner_user_id || reviewer_id || manager_id;
        if (!leave_request_id || !approverId) {
            return res.status(400).json({ error: 'leave_request_id and (owner_user_id, reviewer_id, or manager_id) are required' });
        }
        // Verify owner permissions
        const ownerRecord = await getOwnerRecord(approverId);
        if (!ownerRecord) {
            return res.status(403).json({ error: 'لا توجد صلاحيات للموافقة على طلبات الإجازات' });
        }
        const result = await approveLeaveRequestAndLogAttendance(leave_request_id, approverId);
        res.json(result);
    }
    catch (error) {
        console.error('Approve leave and log attendance error:', error);
        res.status(500).json({
            success: false,
            error: 'Internal server error',
            message: error?.message
        });
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
            .where(and(eq(advances.employeeId, employee_id), gte(advances.requestDate, fiveDaysAgo)))
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
            .select({ count: sql `count(*)` })
            .from(pulses)
            .where(and(eq(pulses.employeeId, employee_id), eq(pulses.isWithinGeofence, true), gte(pulses.createdAt, periodStart), lte(pulses.createdAt, now)));
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
    }
    catch (error) {
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
            query = query.where(eq(advances.employeeId, employee_id));
        }
        if (status) {
            query = query.where(eq(advances.status, status));
        }
        const advancesList = await query.orderBy(desc(advances.requestDate));
        res.json({
            advances: advancesList.map(a => normalizeNumericFields(a, ['amount', 'eligibleAmount']))
        });
    }
    catch (error) {
        console.error('Get advances error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// Approve/reject advance
app.post('/api/advances/:advanceId/review', async (req, res) => {
    try {
        const { advanceId } = req.params;
        const { action, reviewer_id, owner_user_id, manager_id } = req.body;
        const approverId = reviewer_id || owner_user_id || manager_id;
        if (!action || !['approve', 'reject'].includes(action)) {
            return res.status(400).json({ error: 'Action must be approve or reject' });
        }
        if (!approverId) {
            return res.status(400).json({ error: 'reviewer_id, owner_user_id, or manager_id is required' });
        }
        // Get advance details
        const [advance] = await db
            .select()
            .from(advances)
            .where(eq(advances.id, advanceId))
            .limit(1);
        if (!advance) {
            return res.status(404).json({ error: 'Advance request not found' });
        }
        // Check if reviewer can approve this request
        const approvalCheck = await canApproveRequest(approverId, advance.employeeId);
        if (!approvalCheck.canApprove) {
            return res.status(403).json({
                error: 'Forbidden',
                message: approvalCheck.reason || 'You do not have permission to approve this request'
            });
        }
        // Use transaction to ensure all operations succeed or fail together
        const result = await db.transaction(async (tx) => {
            // Update advance status
            const updateResult = await tx
                .update(advances)
                .set({
                status: action === 'approve' ? 'approved' : 'rejected',
                reviewedBy: approverId,
                reviewedAt: new Date(),
            })
                .where(eq(advances.id, advanceId))
                .returning();
            const updated = extractFirstRow(updateResult);
            // If approved, create deduction record
            if (action === 'approve' && updated) {
                const advanceAmount = Number(updated.amount);
                const today = new Date().toISOString().split('T')[0];
                await tx.insert(deductions).values({
                    employeeId: updated.employeeId,
                    amount: String(advanceAmount),
                    reason: `خصم سلفة - تم الموافقة عليها`,
                    deductionDate: today,
                    deductionType: 'advance',
                    appliedBy: reviewer_id,
                    createdAt: new Date(),
                });
            }
            return updated;
        });
        res.json({
            success: true,
            message: action === 'approve' ? 'تم الموافقة على السلفة وسيتم خصمها من الراتب' : 'تم رفض السلفة',
            advance: result,
        });
    }
    catch (error) {
        console.error('Review advance error:', error);
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
            .where(eq(absenceNotifications.status, status))
            .orderBy(desc(absenceNotifications.notifiedAt));
        res.json({ notifications });
    }
    catch (error) {
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
        if (!reviewer_id) {
            return res.status(400).json({ error: 'reviewer_id is required' });
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
        // Check if reviewer can approve this request
        const approvalCheck = await canApproveRequest(reviewer_id, notification.employeeId);
        if (!approvalCheck.canApprove) {
            return res.status(403).json({
                error: 'Forbidden',
                message: approvalCheck.reason || 'You do not have permission to approve this request'
            });
        }
        let deductionAmount = '0';
        // If rejected → apply 2 days deduction based on employee's shift hours
        if (action === 'reject') {
            // Get employee to calculate shift-based deduction
            const [employee] = await db
                .select()
                .from(employees)
                .where(eq(employees.id, notification.employeeId))
                .limit(1);
            if (employee && employee.shiftStartTime && employee.shiftEndTime) {
                // Parse shift times
                const [startHour, startMinute] = employee.shiftStartTime.split(':').map(Number);
                const [endHour, endMinute] = employee.shiftEndTime.split(':').map(Number);
                // Calculate shift duration in hours
                let shiftDurationMinutes;
                const startTimeMinutes = startHour * 60 + startMinute;
                const endTimeMinutes = endHour * 60 + endMinute;
                if (endTimeMinutes > startTimeMinutes) {
                    // Normal shift (e.g., 9:00 - 17:00)
                    shiftDurationMinutes = endTimeMinutes - startTimeMinutes;
                }
                else {
                    // Night shift crossing midnight (e.g., 21:00 - 05:00)
                    shiftDurationMinutes = (24 * 60 - startTimeMinutes) + endTimeMinutes;
                }
                const shiftDurationHours = shiftDurationMinutes / 60;
                const hourlyRate = parseFloat(employee.hourlyRate?.toString() || '40'); // Default 40 EGP/hour
                // Calculate: (shift hours × hourly rate) × 2 days
                const oneDayDeduction = shiftDurationHours * hourlyRate;
                const twoDaysDeduction = oneDayDeduction * 2;
                deductionAmount = Math.round(twoDaysDeduction).toString();
                console.log(`[Absence Review] Employee: ${employee.fullName}`);
                console.log(`[Absence Review] Shift: ${employee.shiftStartTime} - ${employee.shiftEndTime}`);
                console.log(`[Absence Review] Duration: ${shiftDurationHours.toFixed(2)} hours`);
                console.log(`[Absence Review] Hourly Rate: ${hourlyRate} EGP`);
                console.log(`[Absence Review] 1 Day = ${oneDayDeduction.toFixed(2)} EGP`);
                console.log(`[Absence Review] 2 Days Deduction = ${deductionAmount} EGP`);
            }
            else {
                // Fallback: if no shift info, use default 400 EGP (8 hours × 40 EGP/hour × 2 days)
                deductionAmount = '400';
                console.log(`[Absence Review] No shift info, using default deduction: ${deductionAmount} EGP`);
            }
            // Create deduction record
            await db.insert(deductions).values({
                employeeId: notification.employeeId,
                amount: deductionAmount,
                reason: notes || `غياب بدون إذن - خصم يومين (${deductionAmount} جنيه)`,
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
                : `تم رفض الغياب - تم تطبيق خصم يومين (${deductionAmount} جنيه)`,
            notification: updated,
            deductionAmount: action === 'reject' ? deductionAmount : '0',
        });
    }
    catch (error) {
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
    }
    catch (error) {
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
            .where(and(eq(attendance.employeeId, employeeId), gte(attendance.date, start_date), lte(attendance.date, end_date)))
            .orderBy(attendance.date);
        // Get valid pulses count for salary calculation
        const validPulsesResult = await db
            .select({ count: sql `count(*)` })
            .from(pulses)
            .where(and(eq(pulses.employeeId, employeeId), eq(pulses.isWithinGeofence, true), gte(pulses.createdAt, new Date(start_date)), lte(pulses.createdAt, new Date(end_date))));
        const validPulseCount = validPulsesResult[0]?.count || 0;
        // Calculate salary from pulses (40 EGP/hour, pulse every 30 seconds)
        const HOURLY_RATE = 40;
        const pulseValue = (HOURLY_RATE / 3600) * 30; // 0.333 EGP per pulse
        const grossSalary = validPulseCount * pulseValue;
        // Get advances
        const advancesList = await db
            .select()
            .from(advances)
            .where(and(eq(advances.employeeId, employeeId), eq(advances.status, 'approved'), gte(advances.requestDate, new Date(start_date)), lte(advances.requestDate, new Date(end_date))));
        // Get leaves
        const leaves = await db
            .select()
            .from(leaveRequests)
            .where(and(eq(leaveRequests.employeeId, employeeId), eq(leaveRequests.status, 'approved'), gte(leaveRequests.startDate, start_date), lte(leaveRequests.endDate, end_date)));
        // Get deductions
        const deductionsList = await db
            .select()
            .from(deductions)
            .where(and(eq(deductions.employeeId, employeeId), gte(deductions.deductionDate, start_date), lte(deductions.deductionDate, end_date)));
        // Calculate totals
        const totalWorkHours = attendanceRecords.reduce((sum, record) => sum + parseFloat(record.workHours || '0'), 0);
        const totalAdvances = advancesList.reduce((sum, advance) => sum + parseFloat(advance.amount || '0'), 0);
        const totalDeductions = deductionsList.reduce((sum, deduction) => sum + parseFloat(deduction.amount || '0'), 0);
        const totalLeaveAllowance = leaves.reduce((sum, leave) => sum + parseFloat(leave.allowanceAmount || '0'), 0);
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
    }
    catch (error) {
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
            .where(and(eq(attendance.employeeId, employeeId), gte(attendance.date, start_date), lte(attendance.date, end_date)))
            .orderBy(attendance.date);
        // Get advances
        const advancesList = await db
            .select()
            .from(advances)
            .where(and(eq(advances.employeeId, employeeId), eq(advances.status, 'approved'), gte(advances.requestDate, new Date(start_date)), lte(advances.requestDate, new Date(end_date))));
        // Get leaves
        const leaves = await db
            .select()
            .from(leaveRequests)
            .where(and(eq(leaveRequests.employeeId, employeeId), eq(leaveRequests.status, 'approved'), gte(leaveRequests.startDate, start_date), lte(leaveRequests.endDate, end_date)));
        // Get deductions
        const deductionsList = await db
            .select()
            .from(deductions)
            .where(and(eq(deductions.employeeId, employeeId), gte(deductions.deductionDate, start_date), lte(deductions.deductionDate, end_date)));
        // Calculate totals
        const totalWorkHours = attendanceRecords.reduce((sum, record) => sum + parseFloat(record.workHours || '0'), 0);
        const totalAdvances = advancesList.reduce((sum, advance) => sum + parseFloat(advance.amount || '0'), 0);
        const totalDeductions = deductionsList.reduce((sum, deduction) => sum + parseFloat(deduction.amount || '0'), 0);
        const totalLeaveAllowance = leaves.reduce((sum, leave) => sum + parseFloat(leave.allowanceAmount || '0'), 0);
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
    }
    catch (error) {
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
    }
    catch (error) {
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
    }
    catch (error) {
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
            .select({ count: sql `count(*)` })
            .from(pulses)
            .where(and(eq(pulses.employeeId, id), eq(pulses.isWithinGeofence, true), gte(pulses.createdAt, periodStart), lte(pulses.createdAt, now)));
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
    }
    catch (error) {
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
        // Get branchId (UUID) from request
        const branchIdInput = typeof req.body.branchId === 'string' ? req.body.branchId.trim() : undefined;
        const branchId = branchIdInput && branchIdInput !== '' ? branchIdInput : null;
        // Optional: Keep branch name for backward compatibility
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
        let hourlyRate;
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
        // Get shift times from request
        const shiftStartTime = typeof req.body.shiftStartTime === 'string' ? req.body.shiftStartTime.trim() : undefined;
        const shiftEndTime = typeof req.body.shiftEndTime === 'string' ? req.body.shiftEndTime.trim() : undefined;
        const shiftType = typeof req.body.shiftType === 'string' ? req.body.shiftType.trim() : undefined;
        const insertData = {
            id,
            fullName,
            pinHash,
            role,
            branch,
            branchId, // Save branchId (UUID) for geofencing
            active,
        };
        if (hourlyRate !== undefined) {
            insertData.hourlyRate = hourlyRate;
        }
        if (shiftStartTime) {
            insertData.shiftStartTime = shiftStartTime;
        }
        if (shiftEndTime) {
            insertData.shiftEndTime = shiftEndTime;
        }
        if (shiftType) {
            insertData.shiftType = shiftType;
        }
        const [newEmployee] = await db
            .insert(employees)
            .values(insertData)
            .returning({
            id: employees.id,
            fullName: employees.fullName,
            role: employees.role,
            branch: employees.branch,
            branchId: employees.branchId,
            hourlyRate: employees.hourlyRate,
            active: employees.active,
            createdAt: employees.createdAt,
            updatedAt: employees.updatedAt,
        });
        if (!newEmployee) {
            return res.status(500).json({ error: 'فشل إنشاء الموظف: استجابة غير متوقعة من قاعدة البيانات' });
        }
        console.log(`[Employee Created] ID: ${id}, Name: ${fullName}, Branch ID: ${branchId || 'null'}, Branch: ${branch || 'null'}`);
        res.status(201).json({
            success: true,
            message: 'تم إضافة الموظف بنجاح',
            employee: normalizeNumericFields(newEmployee, ['hourlyRate']),
        });
    }
    catch (error) {
        if (error?.code === '23505') {
            return res.status(409).json({ error: 'يوجد موظف بنفس المعرف بالفعل' });
        }
        console.error('Create employee error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// Update employee
app.put('/api/employees/:id', async (req, res) => {
    try {
        const employeeId = req.params.id;
        const updateData = {};
        if (req.body.fullName !== undefined) {
            const fullName = typeof req.body.fullName === 'string' ? req.body.fullName.trim() : '';
            if (!fullName) {
                return res.status(400).json({ error: 'fullName cannot be empty' });
            }
            updateData.fullName = fullName;
        }
        if (req.body.pin !== undefined) {
            const pin = typeof req.body.pin === 'string' ? req.body.pin.trim() : '';
            if (!pin) {
                return res.status(400).json({ error: 'pin cannot be empty' });
            }
            updateData.pinHash = await bcrypt.hash(pin, 10);
        }
        if (req.body.role !== undefined) {
            const roleInput = typeof req.body.role === 'string' ? req.body.role.trim().toLowerCase() : '';
            const allowedRoles = new Set(['owner', 'admin', 'manager', 'hr', 'monitor', 'staff']);
            if (!allowedRoles.has(roleInput)) {
                return res.status(400).json({ error: 'Invalid role' });
            }
            updateData.role = roleInput;
        }
        if (req.body.branch !== undefined) {
            updateData.branch = req.body.branch ? String(req.body.branch).trim() : null;
        }
        if (req.body.branchId !== undefined) {
            updateData.branchId = req.body.branchId ? String(req.body.branchId).trim() : null;
        }
        if (req.body.hourlyRate !== undefined) {
            const parsed = Number(req.body.hourlyRate);
            if (!Number.isFinite(parsed) || parsed < 0) {
                return res.status(400).json({ error: 'hourlyRate must be a positive number' });
            }
            updateData.hourlyRate = parsed;
        }
        if (req.body.active !== undefined) {
            updateData.active = Boolean(req.body.active);
        }
        if (req.body.shiftStartTime !== undefined) {
            updateData.shiftStartTime = req.body.shiftStartTime ? String(req.body.shiftStartTime).trim() : null;
        }
        if (req.body.shiftEndTime !== undefined) {
            updateData.shiftEndTime = req.body.shiftEndTime ? String(req.body.shiftEndTime).trim() : null;
        }
        if (req.body.shiftType !== undefined) {
            updateData.shiftType = req.body.shiftType ? String(req.body.shiftType).trim() : null;
        }
        if (Object.keys(updateData).length === 0) {
            return res.status(400).json({ error: 'No fields to update' });
        }
        updateData.updatedAt = new Date();
        const [updatedEmployee] = await db
            .update(employees)
            .set(updateData)
            .where(eq(employees.id, employeeId))
            .returning({
            id: employees.id,
            fullName: employees.fullName,
            role: employees.role,
            branch: employees.branch,
            branchId: employees.branchId,
            hourlyRate: employees.hourlyRate,
            active: employees.active,
            updatedAt: employees.updatedAt,
        });
        if (!updatedEmployee) {
            return res.status(404).json({ error: 'الموظف غير موجود' });
        }
        console.log(`[Employee Updated] ID: ${employeeId}, Changes: ${Object.keys(updateData).join(', ')}`);
        res.json({
            success: true,
            message: 'تم تحديث بيانات الموظف بنجاح',
            employee: normalizeNumericFields(updatedEmployee, ['hourlyRate']),
        });
    }
    catch (error) {
        console.error('Update employee error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// Delete employee
app.delete('/api/employees/:id', async (req, res) => {
    try {
        const employeeId = req.params.id;
        // Check if employee exists
        const [existingEmployee] = await db
            .select({ id: employees.id, fullName: employees.fullName })
            .from(employees)
            .where(eq(employees.id, employeeId))
            .limit(1);
        if (!existingEmployee) {
            return res.status(404).json({ error: 'الموظف غير موجود' });
        }
        // Use a transaction to ensure all deletions happen or none do
        await db.transaction(async (tx) => {
            // Delete related records from all referencing tables first
            console.log(`[Delete Employee] Deleting related records for ${employeeId}...`);
            await tx.delete(attendance).where(eq(attendance.employeeId, employeeId));
            console.log(`[Delete Employee] Deleted attendance.`);
            await tx.delete(pulses).where(eq(pulses.employeeId, employeeId));
            console.log(`[Delete Employee] Deleted pulses.`);
            await tx.delete(breaks).where(eq(breaks.employeeId, employeeId));
            console.log(`[Delete Employee] Deleted breaks.`);
            await tx.delete(deviceSessions).where(eq(deviceSessions.employeeId, employeeId));
            console.log(`[Delete Employee] Deleted device sessions.`);
            await tx.delete(notifications).where(eq(notifications.recipientId, employeeId));
            // Optionally delete notifications sent BY this employee if needed,
            // but schema might have ON DELETE SET NULL for senderId
            // await tx.delete(notifications).where(eq(notifications.senderId, employeeId));
            console.log(`[Delete Employee] Deleted notifications.`);
            await tx.delete(salaryCalculations).where(eq(salaryCalculations.employeeId, employeeId));
            console.log(`[Delete Employee] Deleted salary calculations.`);
            await tx.delete(attendanceRequests).where(eq(attendanceRequests.employeeId, employeeId));
            console.log(`[Delete Employee] Deleted attendance requests.`);
            await tx.delete(leaveRequests).where(eq(leaveRequests.employeeId, employeeId));
            console.log(`[Delete Employee] Deleted leave requests.`);
            await tx.delete(advances).where(eq(advances.employeeId, employeeId));
            console.log(`[Delete Employee] Deleted advances.`);
            await tx.delete(deductions).where(eq(deductions.employeeId, employeeId));
            console.log(`[Delete Employee] Deleted deductions.`);
            await tx.delete(absenceNotifications).where(eq(absenceNotifications.employeeId, employeeId));
            console.log(`[Delete Employee] Deleted absence notifications.`);
            await tx.delete(branchManagers).where(eq(branchManagers.employeeId, employeeId)); // Handles linking table if used
            console.log(`[Delete Employee] Deleted branch manager links.`);
            // Consider userRoles if employees can be users (adjust userId column if needed)
            // Assuming employee.id might map to a user id elsewhere. Check your user table structure.
            // await tx.delete(userRoles).where(eq(userRoles.userId, /* potential user UUID linked to employee */));
            // Unlink manager from branches if this employee was a manager
            console.log(`[Delete Employee] Unlinking as manager from branches for ${employeeId}`);
            await tx.update(branches).set({ managerId: null, updatedAt: new Date() }).where(eq(branches.managerId, employeeId));
            // Finally, delete the employee
            console.log(`[Delete Employee] Deleting employee record ${employeeId}...`);
            await tx.delete(employees).where(eq(employees.id, employeeId));
        });
        console.log(`[Employee Deleted] ID: ${employeeId}, Name: ${existingEmployee.fullName}`);
        res.json({
            success: true,
            message: 'تم حذف الموظف وجميع سجلاته المرتبطة بنجاح',
            employeeId,
        });
    }
    catch (error) {
        console.error('Delete employee error:', error);
        // Provide more specific error details if possible
        res.status(500).json({ error: 'Internal server error', message: error.message, stack: error.stack });
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
            .where(and(eq(attendance.date, today), eq(attendance.status, 'active')))
            .$dynamic();
        if (branch_id) {
            query = query.where(eq(employees.branchId, branch_id));
        }
        const activeShifts = await query.orderBy(attendance.checkInTime);
        res.json({
            success: true,
            activeShifts,
            count: activeShifts.length,
            date: today,
        });
    }
    catch (error) {
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
            .where(and(eq(attendance.employeeId, employee_id), eq(attendance.date, today), eq(attendance.status, 'active')))
            .limit(1);
        if (!activeAttendance) {
            return res.status(404).json({ error: 'No active shift found for this employee' });
        }
        const checkOutTime = new Date();
        const checkInTime = new Date(activeAttendance.checkInTime);
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
    }
    catch (error) {
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
            .where(and(eq(attendance.employeeId, employeeId), eq(attendance.date, today)))
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
    }
    catch (error) {
        console.error('Get shift status error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// Get daily attendance sheet (for managers)
app.get('/api/attendance/daily-sheet', async (req, res) => {
    try {
        const { date, branch_id } = req.query;
        const targetDate = date ? date : new Date().toISOString().split('T')[0];
        // Get all active employees
        let employeesQuery = db
            .select()
            .from(employees)
            .where(eq(employees.active, true))
            .$dynamic();
        if (branch_id) {
            employeesQuery = employeesQuery.where(eq(employees.branchId, branch_id));
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
    }
    catch (error) {
        console.error('Get daily attendance sheet error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// =============================================================================
// MANAGER DASHBOARD - لوحة تحكم المدير
// =============================================================================
// =============================================================================
// MANAGER ABSENCE NOTIFICATIONS API - إدارة إشعارات الغياب للمدير
// =============================================================================
// Get absence notifications for manager's branch
app.get('/api/manager/absence-notifications', async (req, res) => {
    try {
        const managerId = req.query.manager_id;
        if (!managerId) {
            return res.status(400).json({ error: 'manager_id is required' });
        }
        // Get manager's branch
        const [manager] = await db.select().from(employees).where(eq(employees.id, managerId)).limit(1);
        if (!manager || !manager.branchId) {
            return res.status(403).json({ error: 'Manager not found or not assigned to a branch' });
        }
        // Get pending absence notifications for employees in manager's branch
        const notifications = await db
            .select({
            id: absenceNotifications.id,
            employeeId: absenceNotifications.employeeId,
            employeeName: employees.fullName,
            absenceDate: absenceNotifications.absenceDate,
            status: absenceNotifications.status,
            notifiedAt: absenceNotifications.notifiedAt,
            deductionApplied: absenceNotifications.deductionApplied,
            deductionAmount: absenceNotifications.deductionAmount,
        })
            .from(absenceNotifications)
            .innerJoin(employees, eq(absenceNotifications.employeeId, employees.id))
            .where(and(eq(employees.branchId, manager.branchId), eq(absenceNotifications.status, 'pending')))
            .orderBy(desc(absenceNotifications.absenceDate));
        res.json({
            success: true,
            notifications: notifications.map(n => normalizeNumericFields(n, ['deductionAmount']))
        });
    }
    catch (error) {
        console.error('Get manager absence notifications error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// Apply deduction for absence notification
app.post('/api/manager/absence-notifications/:id/apply-deduction', async (req, res) => {
    try {
        const { id } = req.params;
        const { managerId, deductionAmount, reason } = req.body;
        if (!managerId) {
            return res.status(400).json({ error: 'managerId is required' });
        }
        if (!deductionAmount || isNaN(parseFloat(deductionAmount))) {
            return res.status(400).json({ error: 'Valid deductionAmount is required' });
        }
        // Get the absence notification
        const [notification] = await db
            .select()
            .from(absenceNotifications)
            .where(and(eq(absenceNotifications.id, id), eq(absenceNotifications.status, 'pending')))
            .limit(1);
        if (!notification) {
            return res.status(404).json({ error: 'Absence notification not found or already reviewed' });
        }
        // Check if manager can approve this absence notification
        const approvalCheck = await canApproveRequest(managerId, notification.employeeId);
        if (!approvalCheck.canApprove) {
            return res.status(403).json({
                error: 'Forbidden',
                message: approvalCheck.reason || 'You do not have permission to apply deduction for this employee'
            });
        }
        const deductionValue = parseFloat(deductionAmount);
        // Use transaction to update notification and create deduction
        const result = await db.transaction(async (tx) => {
            // Update absence notification
            await tx
                .update(absenceNotifications)
                .set({
                status: 'approved',
                deductionApplied: true,
                deductionAmount: deductionValue.toString(),
                reviewedBy: managerId,
                reviewedAt: new Date(),
            })
                .where(eq(absenceNotifications.id, id));
            // Create deduction record
            await tx.insert(deductions).values({
                employeeId: notification.employeeId,
                amount: deductionValue.toString(),
                reason: reason || `خصم غياب يوم ${notification.absenceDate} - ${deductionValue} جنيه`,
                deductionDate: notification.absenceDate,
                deductionType: 'absence',
                appliedBy: managerId,
            });
            return notification;
        });
        res.json({
            success: true,
            message: `تم تطبيق خصم الغياب بنجاح (${deductionValue} جنيه)`,
            notification: result,
            deductionAmount: deductionValue
        });
    }
    catch (error) {
        console.error('Apply deduction error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// Excuse absence (no deduction)
app.post('/api/manager/absence-notifications/:id/excuse', async (req, res) => {
    try {
        const { id } = req.params;
        const { managerId, reason } = req.body;
        if (!managerId) {
            return res.status(400).json({ error: 'managerId is required' });
        }
        // Get the absence notification
        const [notification] = await db
            .select()
            .from(absenceNotifications)
            .where(and(eq(absenceNotifications.id, id), eq(absenceNotifications.status, 'pending')))
            .limit(1);
        if (!notification) {
            return res.status(404).json({ error: 'Absence notification not found or already reviewed' });
        }
        // Check if manager can excuse this absence notification
        const approvalCheck = await canApproveRequest(managerId, notification.employeeId);
        if (!approvalCheck.canApprove) {
            return res.status(403).json({
                error: 'Forbidden',
                message: approvalCheck.reason || 'You do not have permission to excuse this employee'
            });
        }
        // Update absence notification to excused
        await db
            .update(absenceNotifications)
            .set({
            status: 'approved', // Using 'approved' but with no deduction
            deductionApplied: false,
            reviewedBy: managerId,
            reviewedAt: new Date(),
        })
            .where(eq(absenceNotifications.id, id));
        res.json({
            success: true,
            message: 'تم قبول عذر الغياب بدون تطبيق خصم',
            notification: notification
        });
    }
    catch (error) {
        console.error('Excuse absence error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});
app.get('/api/manager/dashboard', async (req, res) => {
    try {
        const managerId = req.query.manager_id;
        if (!managerId) {
            return res.status(400).json({ error: 'manager_id is required' });
        }
        // Get manager details
        const [manager] = await db
            .select()
            .from(employees)
            .where(eq(employees.id, managerId))
            .limit(1);
        if (!manager) {
            return res.status(404).json({ error: 'Manager not found' });
        }
        if (!manager.branchId) {
            return res.status(400).json({ error: 'Manager is not assigned to any branch' });
        }
        // Only show pending requests from NON-MANAGER employees in the same branch
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
            .where(and(eq(attendanceRequests.status, 'pending'), eq(employees.branchId, manager.branchId), sql `${employees.id} != ${managerId}`, // استبعاد المدير نفسه
        or(eq(employees.role, 'staff'), eq(employees.role, 'hr'), eq(employees.role, 'monitor'))))
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
            .where(and(eq(leaveRequests.status, 'pending'), eq(employees.branchId, manager.branchId), sql `${employees.id} != ${managerId}`, // استبعاد المدير نفسه
        or(eq(employees.role, 'staff'), eq(employees.role, 'hr'), eq(employees.role, 'monitor'))))
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
            .where(and(eq(advances.status, 'pending'), eq(employees.branchId, manager.branchId), sql `${employees.id} != ${managerId}`, // استبعاد المدير نفسه
        or(eq(employees.role, 'staff'), eq(employees.role, 'hr'), eq(employees.role, 'monitor'))))
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
            .where(and(eq(absenceNotifications.status, 'pending'), eq(employees.branchId, manager.branchId), sql `${employees.id} != ${managerId}`, // استبعاد المدير نفسه
        or(eq(employees.role, 'staff'), eq(employees.role, 'hr'), eq(employees.role, 'monitor'))))
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
            .where(and(eq(breaks.status, 'PENDING'), eq(employees.branchId, manager.branchId), sql `${employees.id} != ${managerId}`, // استبعاد المدير نفسه
        or(eq(employees.role, 'staff'), eq(employees.role, 'hr'), eq(employees.role, 'monitor'))))
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
    }
    catch (error) {
        console.error('Dashboard error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// =============================================================================
// OWNER DASHBOARD - لوحة تحكم المالك
// =============================================================================
app.get('/api/owner/dashboard', async (req, res) => {
    try {
        const ownerId = req.query.owner_id;
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
            .where(and(eq(attendanceRequests.status, 'pending'), eq(employees.role, 'manager')))
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
            .where(and(eq(leaveRequests.status, 'pending'), eq(employees.role, 'manager')))
            .orderBy(desc(leaveRequests.createdAt));
        const normalizedLeaveRequests = pendingLeaveRequests.map(request => normalizeNumericFields(request, ['allowanceAmount']));
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
            .where(and(eq(advances.status, 'pending'), eq(employees.role, 'manager')))
            .orderBy(desc(advances.requestDate));
        const normalizedAdvances = pendingAdvances.map(request => normalizeNumericFields(request, ['amount', 'eligibleAmount', 'currentSalary']));
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
            .where(and(eq(absenceNotifications.status, 'pending'), eq(employees.role, 'manager')))
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
            .where(and(eq(breaks.status, 'PENDING'), eq(employees.role, 'manager')))
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
                    totalPendingRequests: normalizedAttendance.length +
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
    }
    catch (error) {
        console.error('Owner dashboard error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// Update branch BSSIDs for owner
app.put('/api/owner/branches/:branchId/bssid', async (req, res) => {
    const branchId = req.params.branchId;
    const { bssid_1, bssid_2, owner_id } = req.body;
    // Verify owner permissions
    if (!owner_id) {
        return res.status(400).json({ error: 'owner_id is required' });
    }
    const ownerRecord = await getOwnerRecord(owner_id);
    if (!ownerRecord) {
        return res.status(403).json({ error: 'لا توجد صلاحيات للوصول إلى بيانات الفروع' });
    }
    // Validate BSSID formats
    if (!bssid_1 || !isValidBssid(bssid_1)) {
        return res.status(400).json({ message: 'صيغة BSSID 1 غير صحيحة.' });
    }
    if (bssid_2 && !isValidBssid(bssid_2)) {
        return res.status(400).json({ message: 'صيغة BSSID 2 غير صحيحة.' });
    }
    // Standardize BSSID formats
    const formattedBssid1 = bssid_1.toUpperCase().replace(/-/g, ':');
    const formattedBssid2 = bssid_2 ? bssid_2.toUpperCase().replace(/-/g, ':') : null;
    try {
        // Update branch BSSIDs
        const updated = await db.update(branches)
            .set({
            bssid_1: formattedBssid1,
            bssid_2: formattedBssid2,
            updatedAt: new Date(),
        })
            .where(eq(branches.id, branchId))
            .returning();
        if (updated.length === 0) {
            return res.status(404).json({ message: 'لم يتم العثور على الفرع.' });
        }
        res.json({
            success: true,
            message: 'تم تحديث BSSIDs الفرع بنجاح.',
            branch: updated[0]
        });
    }
    catch (error) {
        console.error("Error updating branch BSSIDs:", error);
        res.status(500).json({ message: "حدث خطأ أثناء تحديث BSSIDs." });
    }
});
// Get all BSSIDs for a branch (using branchBssids table + legacy bssid_1/bssid_2)
app.get('/api/owner/branches/:branchId/bssids', async (req, res) => {
    const branchId = req.params.branchId;
    try {
        // Get BSSIDs from branchBssids table
        const bssidRecords = await db
            .select()
            .from(branchBssids)
            .where(eq(branchBssids.branchId, branchId));
        // Also get legacy bssid_1 and bssid_2 from branches table
        const [branch] = await db
            .select()
            .from(branches)
            .where(eq(branches.id, branchId))
            .limit(1);
        const allBssids = new Set();
        // Add from branchBssids table
        bssidRecords.forEach(record => {
            if (record.bssidAddress) {
                allBssids.add(record.bssidAddress.toUpperCase());
            }
        });
        // Add legacy BSSIDs if they exist
        if (branch?.bssid_1)
            allBssids.add(branch.bssid_1.toUpperCase());
        if (branch?.bssid_2)
            allBssids.add(branch.bssid_2.toUpperCase());
        res.json({
            success: true,
            bssids: Array.from(allBssids),
        });
    }
    catch (error) {
        console.error("Error fetching branch BSSIDs:", error);
        res.status(500).json({ message: "حدث خطأ أثناء تحميل BSSIDs." });
    }
});
// Add a new BSSID to a branch
app.post('/api/owner/branches/:branchId/bssids', async (req, res) => {
    const branchId = req.params.branchId;
    const { bssid, owner_id } = req.body;
    // Verify owner permissions
    if (!owner_id) {
        return res.status(400).json({ error: 'owner_id is required' });
    }
    const ownerRecord = await getOwnerRecord(owner_id);
    if (!ownerRecord) {
        return res.status(403).json({ error: 'لا توجد صلاحيات للوصول إلى بيانات الفروع' });
    }
    // Validate BSSID format
    if (!bssid || !isValidBssid(bssid)) {
        return res.status(400).json({ message: 'صيغة BSSID غير صحيحة.' });
    }
    const formattedBssid = bssid.toUpperCase().replace(/-/g, ':');
    try {
        // Check if BSSID already exists for this branch
        const existing = await db
            .select()
            .from(branchBssids)
            .where(and(eq(branchBssids.branchId, branchId), eq(branchBssids.bssidAddress, formattedBssid)))
            .limit(1);
        if (existing.length > 0) {
            return res.status(400).json({ message: 'هذا الـ BSSID موجود بالفعل' });
        }
        // Insert new BSSID
        await db.insert(branchBssids).values({
            branchId: branchId,
            bssidAddress: formattedBssid,
            createdAt: new Date(),
        });
        res.json({
            success: true,
            message: 'تم إضافة BSSID بنجاح',
            bssid: formattedBssid,
        });
    }
    catch (error) {
        console.error("Error adding branch BSSID:", error);
        res.status(500).json({ message: "حدث خطأ أثناء إضافة BSSID." });
    }
});
// Remove a BSSID from a branch
app.delete('/api/owner/branches/:branchId/bssids/:bssid', async (req, res) => {
    const branchId = req.params.branchId;
    const bssid = req.params.bssid.toUpperCase().replace(/-/g, ':');
    try {
        // Delete from branchBssids table
        const deleted = await db
            .delete(branchBssids)
            .where(and(eq(branchBssids.branchId, branchId), eq(branchBssids.bssidAddress, bssid)))
            .returning();
        if (deleted.length === 0) {
            return res.status(404).json({ message: 'BSSID غير موجود' });
        }
        res.json({
            success: true,
            message: 'تم حذف BSSID بنجاح',
        });
    }
    catch (error) {
        console.error("Error removing branch BSSID:", error);
        res.status(500).json({ message: "حدث خطأ أثناء حذف BSSID." });
    }
});
// قائمة الموظفين للمالك
app.get('/api/owner/employees', async (req, res) => {
    try {
        const ownerId = req.query.owner_id;
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
        const employeesList = employeeRows.map(row => normalizeNumericFields(row, ['monthlySalary', 'hourlyRate']));
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
    }
    catch (error) {
        console.error('Owner employees list error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// =============================================================================
// OWNER ATTENDANCE REQUESTS API - طلبات الحضور للمالك
// =============================================================================
/**
 * GET /api/owner/pending-attendance-requests
 * جلب طلبات الحضور المعلقة من المديرين للأونر
 */
app.get('/api/owner/pending-attendance-requests', async (req, res) => {
    try {
        const ownerId = req.query.owner_id;
        if (!ownerId) {
            return res.status(400).json({ error: 'owner_id is required' });
        }
        const ownerRecord = await getOwnerRecord(ownerId);
        if (!ownerRecord) {
            return res.status(403).json({ error: 'لا توجد صلاحيات للوصول إلى طلبات الحضور' });
        }
        // جلب طلبات الحضور المعلقة من المديرين فقط
        const managerRoles = ['manager', 'hr', 'monitor', 'admin', 'owner'];
        const detailedRequests = await db.select({
            // --- من attendanceRequests ---
            requestId: attendanceRequests.id,
            requestType: attendanceRequests.requestType,
            requestedTime: attendanceRequests.requestedTime,
            reason: attendanceRequests.reason,
            status: attendanceRequests.status,
            createdAt: attendanceRequests.createdAt,
            // --- من employees ---
            employeeId: employees.id,
            employeeName: employees.fullName,
            employeeRole: employees.role,
            // --- من branches ---
            branchName: branches.name,
        })
            .from(attendanceRequests)
            .leftJoin(employees, eq(attendanceRequests.employeeId, employees.id))
            .leftJoin(branches, eq(employees.branchId, branches.id))
            .where(and(
        // 1. الطلبات المعلقة فقط
        eq(attendanceRequests.status, 'pending'), 
        // 2. من المديرين فقط
        inArray(employees.role, managerRoles)))
            .orderBy(desc(attendanceRequests.createdAt));
        // Normalize numeric fields if needed
        const normalizedRequests = detailedRequests.map(request => ({
            ...request,
            status: String(request.status),
            requestType: String(request.requestType),
        }));
        res.json({
            success: true,
            requests: normalizedRequests,
        });
    }
    catch (error) {
        console.error('Get owner pending attendance requests error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});
/**
 * POST /api/owner/attendance-requests/:id/approve
 * موافقة الأونر على طلب الحضور وتعديل سجل الحضور
 */
app.post('/api/owner/attendance-requests/:id/approve', async (req, res) => {
    try {
        const requestId = req.params.id;
        const { action, owner_user_id, reviewer_id, manager_id } = req.body;
        const approverId = owner_user_id || reviewer_id || manager_id;
        if (!action || !['approve', 'reject'].includes(action)) {
            return res.status(400).json({ error: 'Action must be approve or reject' });
        }
        if (!approverId) {
            return res.status(400).json({ error: 'owner_user_id, reviewer_id, or manager_id is required' });
        }
        // Verify owner permissions
        const ownerRecord = await getOwnerRecord(approverId);
        if (!ownerRecord) {
            return res.status(403).json({ error: 'لا توجد صلاحيات للموافقة على طلبات الحضور' });
        }
        const result = await db.transaction(async (tx) => {
            // 1. تحديث حالة الطلب نفسه
            const updatedRequests = await tx
                .update(attendanceRequests)
                .set({
                status: action === 'approve' ? 'approved' : 'rejected',
                reviewedBy: owner_user_id,
                reviewedAt: new Date(),
            })
                .where(and(eq(attendanceRequests.id, requestId), eq(attendanceRequests.status, 'pending')))
                .returning();
            if (updatedRequests.length === 0) {
                throw new Error('لم يتم العثور على الطلب أو تمت مراجعته.');
            }
            const req = updatedRequests[0];
            // If approved, update attendance record
            if (action === 'approve') {
                const requestedDateTime = new Date(req.requestedTime);
                const requestDate = requestedDateTime.toISOString().split('T')[0];
                // 2. جلب سجل الحضور الأصلي لهذا اليوم
                const attendanceRecord = await tx
                    .select()
                    .from(attendance)
                    .where(and(eq(attendance.employeeId, req.employeeId), eq(attendance.date, requestDate)))
                    .limit(1);
                if (attendanceRecord.length === 0) {
                    // إنشاء سجل حضور جديد إذا لم يكن موجوداً
                    const newAttendanceData = {
                        employeeId: req.employeeId,
                        date: requestDate,
                        status: 'active',
                        createdAt: new Date(),
                        updatedAt: new Date(),
                    };
                    // تحديد الحقل الذي سيتم تعديله
                    if (req.requestType === 'check_in') {
                        newAttendanceData.checkInTime = requestedDateTime;
                        newAttendanceData.modifiedCheckInTime = requestedDateTime;
                        newAttendanceData.modifiedBy = owner_user_id;
                        newAttendanceData.modifiedAt = new Date();
                        newAttendanceData.modificationReason = `[طلب مُعتمد] ${req.reason}`;
                    }
                    else if (req.requestType === 'check_out') {
                        // للـ check-out، نفترض أنه كان قد سجل حضوراً يدوياً
                        newAttendanceData.checkOutTime = requestedDateTime;
                        newAttendanceData.modifiedBy = owner_user_id;
                        newAttendanceData.modifiedAt = new Date();
                        newAttendanceData.modificationReason = `[طلب مُعتمد] ${req.reason}`;
                    }
                    await tx.insert(attendance).values(newAttendanceData);
                }
                else {
                    // تحديث السجل الموجود
                    const existingRecord = attendanceRecord[0];
                    let updatedCheckIn = existingRecord.checkInTime;
                    let updatedCheckOut = existingRecord.checkOutTime;
                    const updateData = {
                        updatedAt: new Date(),
                    };
                    // 3. تحديد الحقل الذي سيتم تعديله
                    if (req.requestType === 'check_in') {
                        updatedCheckIn = requestedDateTime;
                        updateData.checkInTime = requestedDateTime;
                        updateData.modifiedCheckInTime = requestedDateTime;
                        updateData.modifiedBy = owner_user_id;
                        updateData.modifiedAt = new Date();
                        updateData.modificationReason = `[طلب مُعتمد] ${req.reason}`;
                    }
                    else if (req.requestType === 'check_out') {
                        updatedCheckOut = requestedDateTime;
                        updateData.checkOutTime = requestedDateTime;
                        updateData.modifiedBy = owner_user_id;
                        updateData.modifiedAt = new Date();
                        updateData.modificationReason = `[طلب مُعتمد] ${req.reason}`;
                    }
                    // 4. إعادة حساب ساعات العمل
                    if (updatedCheckIn && updatedCheckOut) {
                        const checkInTime = new Date(updatedCheckIn);
                        const checkOutTime = new Date(updatedCheckOut);
                        const workHours = (checkOutTime.getTime() - checkInTime.getTime()) / (1000 * 60 * 60);
                        updateData.workHours = workHours.toFixed(2);
                        updateData.status = 'completed';
                    }
                    await tx.update(attendance)
                        .set(updateData)
                        .where(eq(attendance.id, existingRecord.id));
                }
            }
            return req;
        });
        res.json({
            success: true,
            message: action === 'approve' ? 'تمت الموافقة وتعديل الحضور.' : 'تم رفض الطلب.',
            request: result
        });
    }
    catch (error) {
        console.error('Owner approve attendance request error:', error);
        res.status(500).json({
            success: false,
            error: 'Internal server error',
            message: error.message
        });
    }
});
// تحديث سعر الساعة لموظف بواسطة المالك
app.put('/api/owner/employees/:employeeId/hourly-rate', async (req, res) => {
    try {
        const ownerId = req.query.owner_id;
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
    }
    catch (error) {
        console.error('Owner hourly rate update error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// ملخص الرواتب لجميع الموظفين للمالك
app.get('/api/owner/payroll/summary', async (req, res) => {
    try {
        const ownerId = req.query.owner_id;
        const startDate = req.query.start_date;
        const endDate = req.query.end_date;
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
            .where(and(gte(attendance.date, startDate), lte(attendance.date, endDate)));
        const pulsesSummary = await db
            .select({
            employeeId: pulses.employeeId,
            totalValidPulses: sql `COALESCE(SUM(CASE WHEN ${pulses.isWithinGeofence} = true THEN 1 ELSE 0 END), 0)`,
        })
            .from(pulses)
            .where(and(gte(pulses.createdAt, startDateTime), lte(pulses.createdAt, endDateTime)))
            .groupBy(pulses.employeeId);
        const attendanceMap = new Map();
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
        const pulsesMap = new Map();
        for (const row of pulsesSummary) {
            pulsesMap.set(row.employeeId, Number(row.totalValidPulses) || 0);
        }
        // Get advances for all employees in date range
        const advancesResult = await db
            .select({
            employeeId: advances.employeeId,
            amount: advances.amount,
        })
            .from(advances)
            .where(and(eq(advances.status, 'approved'), gte(advances.requestDate, new Date(startDate)), lte(advances.requestDate, new Date(endDate))));
        const advancesMap = new Map();
        for (const adv of advancesResult) {
            const amount = parseFloat(adv.amount || '0');
            const existing = advancesMap.get(adv.employeeId) || 0;
            advancesMap.set(adv.employeeId, existing + amount);
        }
        const normalizedEmployees = employeeRows.map(row => normalizeNumericFields(row, ['monthlySalary', 'hourlyRate']));
        const payrollDetails = [];
        let totalHourlyPay = 0;
        let totalPulsePay = 0;
        let totalAdvancesSum = 0;
        for (const employee of normalizedEmployees) {
            const attendanceInfo = attendanceMap.get(employee.id) || { totalWorkHours: 0, attendanceDays: 0 };
            const pulsesCount = pulsesMap.get(employee.id) || 0;
            const employeeAdvances = advancesMap.get(employee.id) || 0;
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
            const netSalary = Math.round((totalComputedPay - employeeAdvances) * 100) / 100;
            totalHourlyPay += hourlyPay;
            totalPulsePay += pulsePay;
            totalAdvancesSum += employeeAdvances;
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
                totalAdvances: Math.round(employeeAdvances * 100) / 100,
                totalComputedPay,
                netSalary,
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
                totalAdvances: Math.round(totalAdvancesSum * 100) / 100,
                totalComputedPay: Math.round((totalHourlyPay + totalPulsePay) * 100) / 100,
                totalNetSalary: Math.round((totalHourlyPay + totalPulsePay - totalAdvancesSum) * 100) / 100,
            },
        });
    }
    catch (error) {
        console.error('Owner payroll summary error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});
/**
 * GET /api/owner/attendance/status
 * (مُعدّل) جلب قائمة الموظفين وحالة حضورهم ليوم معين وفرع معين
 * يقبل ?branchId=xxx و ?date=YYYY-MM-DD
 */
app.get('/api/owner/attendance/status', async (req, res) => {
    const branchId = req.query.branchId;
    // --- التعديل: قراءة التاريخ من الـ query ---
    const dateQuery = req.query.date;
    // استخدام التاريخ المطلوب أو تاريخ اليوم الحالي
    const targetDateStr = dateQuery && /^\d{4}-\d{2}-\d{2}$/.test(dateQuery)
        ? dateQuery
        : new Date().toISOString().split('T')[0];
    try {
        // 1. جلب الموظفين (مع الفلترة بالفرع)
        const employeeQuery = db.select({
            id: employees.id,
            fullName: employees.fullName,
            role: employees.role,
            branchName: branches.name,
            // photoUrl: employees.photoUrl // (إذا أضفنا حقل للصورة)
        })
            .from(employees)
            .leftJoin(branches, eq(employees.branchId, branches.id))
            .where(and(eq(employees.active, true), branchId ? eq(employees.branchId, branchId) : undefined))
            .orderBy(employees.fullName);
        const employeeList = await employeeQuery;
        if (employeeList.length === 0) {
            return res.json({ summary: { present: 0, absent: 0, on_leave: 0, checked_out: 0 }, employees: [] });
        }
        // 2. جلب سجلات الحضور لهؤلاء الموظفين للتاريخ المستهدف
        const employeeIds = employeeList.map(emp => emp.id);
        const attendanceRecords = await db.select()
            .from(attendance)
            .where(and(
        // --- التعديل: استخدام التاريخ المستهدف ---
        eq(attendance.date, targetDateStr), inArray(attendance.employeeId, employeeIds)));
        // 3. دمج البيانات وتحديد الحالة (نفس المنطق السابق)
        let presentCount = 0, absentCount = 0, onLeaveCount = 0, checkedOutCount = 0;
        const results = employeeList.map(emp => {
            const record = attendanceRecords.find(att => att.employeeId === emp.id);
            let status = 'absent';
            let checkInTime = null;
            let checkOutTime = null;
            let recordId = null;
            if (record) {
                recordId = record.id;
                checkInTime = record.checkInTime ?? record.modifiedCheckInTime;
                checkOutTime = record.checkOutTime;
                if (record.status === 'ON_LEAVE') {
                    status = 'on_leave';
                    onLeaveCount++;
                }
                else if (checkInTime && !checkOutTime) {
                    status = 'present';
                    presentCount++;
                }
                else if (checkInTime && checkOutTime) {
                    status = 'checked_out';
                    checkedOutCount++;
                }
                else {
                    absentCount++; // إذا كان السجل موجود ولكن بدون أوقات (قد لا تحدث)
                }
            }
            else {
                absentCount++; // لا يوجد سجل = غائب
            }
            return {
                employeeId: emp.id,
                employeeName: emp.fullName,
                employeeRole: emp.role,
                branchName: emp.branchName,
                // photoUrl: emp.photoUrl,
                status: status,
                checkInTime: checkInTime?.toISOString(),
                checkOutTime: checkOutTime?.toISOString(),
                attendanceRecordId: recordId,
            };
        });
        // --- إرجاع الملخص مع قائمة الموظفين ---
        res.json({
            summary: {
                present: presentCount,
                absent: absentCount,
                on_leave: onLeaveCount,
                checked_out: checkedOutCount,
            },
            employees: results
        });
    }
    catch (error) {
        console.error("Error fetching employee attendance status:", error);
        res.status(500).json({ message: "حدث خطأ." });
    }
});
/**
 * POST /api/owner/attendance/manual-checkin
 * تسجيل حضور يدوي لموظف بواسطة الأونر
 */
app.post('/api/owner/attendance/manual-checkin', async (req, res) => {
    const { employeeId, reason } = req.body;
    if (!employeeId) {
        return res.status(400).json({ message: "معرف الموظف مطلوب." });
    }
    try {
        await db.transaction(async (tx) => {
            // 1. تحقق إذا كان هناك سجل حضور مفتوح بالفعل لهذا اليوم
            const existingRecord = await tx.select({ id: attendance.id })
                .from(attendance)
                .where(and(eq(attendance.employeeId, employeeId), eq(attendance.date, new Date().toISOString().split('T')[0]), isNull(attendance.checkOutTime) // لا يزال مفتوحاً
            ))
                .limit(1);
            if (existingRecord.length > 0) {
                throw new Error('الموظف مسجل حضوره بالفعل ولم يسجل انصراف.');
            }
            // 2. احذف أي سجل حضور آخر لهذا اليوم (مثل سجل غياب سابق)
            await tx.delete(attendance)
                .where(and(eq(attendance.employeeId, employeeId), eq(attendance.date, new Date().toISOString().split('T')[0])));
            // 3. إنشاء سجل الحضور اليدوي
            await tx.insert(attendance).values({
                employeeId: employeeId,
                date: new Date().toISOString().split('T')[0],
                checkInTime: new Date(), // وقت الحضور هو الآن
                // استخدام حقول التعديل لتوضيح أنه يدوي
                modifiedCheckInTime: new Date(),
                modifiedBy: 'owner', // سيتم تحديث هذا لاحقاً
                modifiedAt: new Date(),
                modificationReason: `[تسجيل يدوي بواسطة الأونر] ${reason || 'لا يوجد سبب'}`,
                status: 'active', // أو 'present'
                createdAt: new Date(),
                updatedAt: new Date(),
            });
        });
        res.json({ success: true, message: 'تم تسجيل الحضور اليدوي بنجاح.' });
    }
    catch (error) {
        console.error("Error manual check-in:", error);
        res.status(500).json({ success: false, message: error.message });
    }
});
/**
 * POST /api/owner/attendance/manual-checkout
 * تسجيل انصراف يدوي لموظف بواسطة الأونر
 */
app.post('/api/owner/attendance/manual-checkout', async (req, res) => {
    const { employeeId, reason } = req.body;
    if (!employeeId) {
        return res.status(400).json({ message: "معرف الموظف مطلوب." });
    }
    try {
        // 1. البحث عن سجل الحضور المفتوح وتحديثه
        const updated = await db.update(attendance)
            .set({
            checkOutTime: new Date(), // وقت الانصراف هو الآن
            modifiedBy: 'owner', // سيتم تحديث هذا لاحقاً
            modifiedAt: new Date(),
            modificationReason: `[انصراف يدوي بواسطة الأونر] ${reason || 'لا يوجد سبب'}`,
            updatedAt: new Date(),
            // (يجب إعادة حساب ساعات العمل هنا أيضاً)
        })
            .where(and(eq(attendance.employeeId, employeeId), eq(attendance.date, new Date().toISOString().split('T')[0]), isNull(attendance.checkOutTime) // فقط السجلات المفتوحة
        ))
            .returning();
        if (updated.length === 0) {
            return res.status(404).json({ message: 'لم يتم العثور على سجل حضور مفتوح لهذا الموظف اليوم.' });
        }
        res.json({ success: true, message: 'تم تسجيل الانصراف اليدوي بنجاح.' });
    }
    catch (error) {
        console.error("Error manual check-out:", error);
        res.status(500).json({ success: false, message: error.message });
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
        let allowedEmployeeRoles = [];
        if (reviewerRole === 'owner' || reviewerRole === 'admin') {
            // Owners/admins can approve requests from managers, hr, monitor, and staff
            allowedEmployeeRoles = ['manager', 'hr', 'monitor', 'staff'];
        }
        else if (reviewerRole === 'manager') {
            // Managers can only approve requests from staff
            allowedEmployeeRoles = ['staff', 'monitor'];
        }
        else {
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
        const filteredAttendance = attendanceReqs.filter(req => allowedEmployeeRoles.includes(req.employeeRole));
        const filteredLeave = leaveReqs.filter(req => allowedEmployeeRoles.includes(req.employeeRole));
        const filteredAdvances = advanceReqs.filter(req => allowedEmployeeRoles.includes(req.employeeRole));
        const filteredAbsences = absenceReqs.filter(req => allowedEmployeeRoles.includes(req.employeeRole));
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
    }
    catch (error) {
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
        }
        else if (employee.hourlyRate !== null && employee.hourlyRate !== undefined) {
            hourlyRate = parseFloat(String(employee.hourlyRate));
        }
        if (!Number.isFinite(hourlyRate) || hourlyRate < 0) {
            return res.status(400).json({ error: 'Invalid hourly rate provided' });
        }
        // Fetch all attendance records in the date range
        const attendanceRecords = await db
            .select()
            .from(attendance)
            .where(and(eq(attendance.employeeId, employee_id), gte(attendance.date, start_date), lte(attendance.date, end_date)))
            .orderBy(attendance.date);
        // Fetch all valid pulses in the date range
        const validPulses = await db
            .select()
            .from(pulses)
            .where(and(eq(pulses.employeeId, employee_id), eq(pulses.isWithinGeofence, true), gte(pulses.createdAt, new Date(start_date)), lte(pulses.createdAt, new Date(end_date))))
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
            .where(and(eq(advances.employeeId, employee_id), eq(advances.status, 'approved'), gte(advances.requestDate, new Date(start_date)), lte(advances.requestDate, new Date(end_date))));
        const totalAdvances = advancesList.reduce((sum, advance) => sum + parseFloat(advance.amount || '0'), 0);
        // Get deductions for this period
        const deductionsList = await db
            .select()
            .from(deductions)
            .where(and(eq(deductions.employeeId, employee_id), gte(deductions.deductionDate, start_date), lte(deductions.deductionDate, end_date)));
        const totalDeductions = deductionsList.reduce((sum, deduction) => sum + parseFloat(deduction.amount || '0'), 0);
        // Get approved leaves for this period
        const leaves = await db
            .select()
            .from(leaveRequests)
            .where(and(eq(leaveRequests.employeeId, employee_id), eq(leaveRequests.status, 'approved'), gte(leaveRequests.startDate, start_date), lte(leaveRequests.endDate, end_date)));
        const totalLeaveAllowance = leaves.reduce((sum, leave) => sum + parseFloat(leave.allowanceAmount || '0'), 0);
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
    }
    catch (error) {
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
            .where(and(eq(attendance.employeeId, employeeId), eq(attendance.date, today)))
            .orderBy(attendance.checkInTime)
            .limit(1);
        // Get today's pulses count
        const todayPulses = await db
            .select()
            .from(pulses)
            .where(and(eq(pulses.employeeId, employeeId), sql `DATE(${pulses.createdAt}) = ${today}`));
        // Get last 10 pulses
        const recentPulses = await db
            .select()
            .from(pulses)
            .where(eq(pulses.employeeId, employeeId))
            .orderBy(sql `${pulses.createdAt} DESC`)
            .limit(10);
        // Calculate total pulses count
        const [totalPulsesResult] = await db
            .select({ count: sql `count(*)` })
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
                branchId: employee.branchId,
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
    }
    catch (error) {
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
    }
    catch (error) {
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
/**
 * Calculate distance between two GPS coordinates using Haversine formula
 * Returns distance in meters with high precision
 */
function calculateDistance(lat1, lon1, lat2, lon2) {
    const R = 6371000; // Earth's radius in meters (more precise)
    const toRad = (deg) => (deg * Math.PI) / 180;
    const φ1 = toRad(lat1);
    const φ2 = toRad(lat2);
    const Δφ = toRad(lat2 - lat1);
    const Δλ = toRad(lon2 - lon1);
    const a = Math.sin(Δφ / 2) * Math.sin(Δφ / 2) +
        Math.cos(φ1) * Math.cos(φ2) * Math.sin(Δλ / 2) * Math.sin(Δλ / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c; // Distance in meters
}
// Receive and validate pulse from Flutter app
app.post('/api/pulses', async (req, res) => {
    try {
        const { employee_id, wifi_bssid, latitude, longitude, timestamp } = req.body;
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
        // Default radius to 200m for better GPS accuracy tolerance
        let geofenceRadius = 200;
        // Use branch-specific geofence and wifi if available
        let branchWifi = null;
        if (employee.branchId) {
            const [branch] = await db
                .select()
                .from(branches)
                .where(eq(branches.id, employee.branchId))
                .limit(1);
            if (branch) {
                console.log(`[Pulse] Checking for employee ${employee_id} in branch: ${branch.name}`);
                if (branch.latitude && branch.longitude) {
                    distance = calculateDistance(latitude, longitude, parseFloat(branch.latitude), parseFloat(branch.longitude));
                    console.log(`[Pulse] Distance from branch: ${distance.toFixed(2)}m`);
                }
                if (branch.geofenceRadius) {
                    geofenceRadius = Number(branch.geofenceRadius) || geofenceRadius;
                }
                console.log(`[Pulse] Geofence radius: ${geofenceRadius}m`);
                if (branch.bssid_1) {
                    branchWifi = String(branch.bssid_1).toUpperCase();
                }
            }
        }
        else {
            // Fallback to default location
            console.log(`[Pulse] Using default location for employee ${employee_id}`);
            distance = calculateDistance(latitude, longitude, RESTAURANT_LATITUDE, RESTAURANT_LONGITUDE);
            geofenceRadius = GEOFENCE_RADIUS_METERS;
        }
        // Determine geofence validity
        geofenceValid = distance <= geofenceRadius;
        console.log(`[Pulse] Geofence valid: ${geofenceValid} (distance: ${distance.toFixed(2)}m <= ${geofenceRadius}m)`);
        // Determine wifi validity: check against branches table AND branchBssids table
        if (employee.branchId) {
            const [branch] = await db
                .select()
                .from(branches)
                .where(eq(branches.id, employee.branchId))
                .limit(1);
            if (branch) {
                // Get BSSIDs from both sources: legacy (bssid_1, bssid_2) and new table (branchBssids)
                const allowedBssids = new Set();
                // Add legacy BSSIDs
                if (branch.bssid_1)
                    allowedBssids.add(branch.bssid_1.toUpperCase());
                if (branch.bssid_2)
                    allowedBssids.add(branch.bssid_2.toUpperCase());
                // Add BSSIDs from branchBssids table
                const bssidRecords = await db
                    .select()
                    .from(branchBssids)
                    .where(eq(branchBssids.branchId, employee.branchId));
                bssidRecords.forEach(record => {
                    if (record.bssidAddress) {
                        allowedBssids.add(record.bssidAddress.toUpperCase());
                    }
                });
                if (allowedBssids.size > 0) {
                    if (!wifi_bssid) {
                        wifiValid = false;
                    }
                    else {
                        const normalizedCurrentBssid = String(wifi_bssid || '').toUpperCase().replace(/-/g, ':');
                        wifiValid = allowedBssids.has(normalizedCurrentBssid);
                    }
                }
                else {
                    wifiValid = true; // No BSSIDs set, allow any
                }
            }
            else {
                wifiValid = true;
            }
        }
        else {
            wifiValid = true;
        }
        // Pulse is within geofence if geofenceValid and not on active break
        let isWithinGeofence = geofenceValid;
        // Check if employee has an active break
        const [activeBreak] = await db
            .select()
            .from(breaks)
            .where(and(eq(breaks.employeeId, employee_id), eq(breaks.status, 'ACTIVE')))
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
            isWithinGeofence: isWithinGeofence,
            status: 'IN', // Default status
            createdAt: timestamp ? new Date(timestamp) : new Date(),
        })
            .returning({ id: pulses.id, employeeId: pulses.employeeId, branchId: pulses.branchId, latitude: pulses.latitude, longitude: pulses.longitude, bssidAddress: pulses.bssidAddress, isWithinGeofence: pulses.isWithinGeofence, status: pulses.status, createdAt: pulses.createdAt });
        const pulse = extractFirstRow(insertPulseResult);
        const overallValid = (wifiValid && geofenceValid);
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
    }
    catch (error) {
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
        const result = await db
            .insert(branches)
            .values({
            name,
            latitude: latitude ? latitude.toString() : null,
            longitude: longitude ? longitude.toString() : null,
            geofenceRadius: geofence_radius || 100,
            bssid_1: wifi_bssid || null,
        })
            .returning();
        const newBranch = extractFirstRow(result);
        if (!newBranch) {
            return res.status(500).json({ error: 'Failed to create branch' });
        }
        // If wifi_bssid is provided, insert it into branchBssids table
        const branchId = String(newBranch.id || '');
        if (wifi_bssid && wifi_bssid.trim() !== '' && branchId) {
            await db
                .insert(branchBssids)
                .values({
                branchId: branchId,
                bssidAddress: wifi_bssid.trim().toUpperCase(),
            });
            console.log(`[Branch Created] Branch ID: ${branchId}, Name: ${name}, BSSID: ${wifi_bssid.trim().toUpperCase()}`);
        }
        else {
            console.log(`[Branch Created] Branch ID: ${branchId || 'null'}, Name: ${name}, No BSSID provided`);
        }
        res.json({
            success: true,
            message: 'تم إنشاء الفرع بنجاح',
            branchId: branchId,
        });
    }
    catch (error) {
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
    }
    catch (error) {
        console.error('Get branches error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// Get single branch with BSSIDs
app.get('/api/branches/:id', async (req, res) => {
    try {
        const { id } = req.params;
        const [branch] = await db
            .select()
            .from(branches)
            .where(eq(branches.id, id))
            .limit(1);
        if (!branch) {
            return res.status(404).json({ error: 'Branch not found' });
        }
        // Get associated BSSIDs
        const bssids = await db
            .select({ bssidAddress: branchBssids.bssidAddress })
            .from(branchBssids)
            .where(eq(branchBssids.branchId, id));
        // Convert to uppercase
        const bssidList = bssids.map(b => b.bssidAddress.toUpperCase());
        res.json({
            success: true,
            branch: normalizeNumericFields(branch, ['latitude', 'longitude', 'geofenceRadius']),
            allowedBssids: bssidList,
        });
    }
    catch (error) {
        console.error('Get single branch error:', error);
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
    }
    catch (error) {
        console.error('Assign manager error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// Delete branch
app.delete('/api/branches/:id', async (req, res) => {
    try {
        const branchId = req.params.id;
        // Check if branch exists
        const [existingBranch] = await db
            .select({ id: branches.id, name: branches.name })
            .from(branches)
            .where(eq(branches.id, branchId))
            .limit(1);
        if (!existingBranch) {
            return res.status(404).json({ error: 'الفرع غير موجود' });
        }
        // Use transaction to ensure atomicity
        await db.transaction(async (tx) => {
            // Delete related BSSIDs first
            console.log(`[Delete Branch] Deleting BSSIDs for branch ${branchId}`);
            await tx.delete(branchBssids).where(eq(branchBssids.branchId, branchId));
            // Unlink employees from this branch (set branchId and branch name to null)
            console.log(`[Delete Branch] Unlinking employees from branch ${branchId}`);
            await tx
                .update(employees)
                .set({ branchId: null, branch: null, updatedAt: new Date() }) // Also update 'branch' name column if used
                .where(eq(employees.branchId, branchId));
            // Unlink any managers directly linked via branchManagers table (if this table is actively used)
            console.log(`[Delete Branch] Deleting links from branch_managers for branch ${branchId}`);
            await tx.delete(branchManagers).where(eq(branchManagers.branchId, branchId));
            // Finally, delete the branch itself
            console.log(`[Delete Branch] Deleting branch record ${branchId}`);
            await tx.delete(branches).where(eq(branches.id, branchId));
        });
        console.log(`[Branch Deleted] ID: ${branchId}, Name: ${existingBranch.name}`);
        res.json({
            success: true,
            message: 'تم حذف الفرع بنجاح، وتم فك ارتباط الموظفين به.',
            branchId,
        });
    }
    catch (error) {
        console.error('Delete branch error:', error);
        res.status(500).json({ error: 'Internal server error', message: error.message });
    }
});
// Update branch
app.put('/api/branches/:id', async (req, res) => {
    try {
        const branchId = req.params.id;
        const { name, wifi_bssid, latitude, longitude, geofence_radius } = req.body;
        const updateData = {};
        if (name !== undefined) {
            const trimmedName = typeof name === 'string' ? name.trim() : '';
            if (!trimmedName) {
                return res.status(400).json({ error: 'Branch name cannot be empty' });
            }
            updateData.name = trimmedName;
        }
        if (latitude !== undefined) {
            updateData.latitude = latitude ? latitude.toString() : null;
        }
        if (longitude !== undefined) {
            updateData.longitude = longitude ? longitude.toString() : null;
        }
        if (geofence_radius !== undefined) {
            // Default to 200m for better GPS accuracy tolerance
            updateData.geofenceRadius = geofence_radius || 200;
        }
        if (wifi_bssid !== undefined) {
            updateData.bssid_1 = wifi_bssid || null;
            // Update branchBssids table
            if (wifi_bssid && wifi_bssid.trim() !== '') {
                // Delete old BSSIDs for this branch
                await db.delete(branchBssids).where(eq(branchBssids.branchId, branchId));
                // Insert new BSSID
                await db.insert(branchBssids).values({
                    branchId,
                    bssidAddress: wifi_bssid.trim().toUpperCase(),
                });
            }
            else {
                // If wifi_bssid is null/empty, delete all BSSIDs for this branch
                await db.delete(branchBssids).where(eq(branchBssids.branchId, branchId));
            }
        }
        if (Object.keys(updateData).length === 0) {
            return res.status(400).json({ error: 'No fields to update' });
        }
        const [updatedBranch] = await db
            .update(branches)
            .set(updateData)
            .where(eq(branches.id, branchId))
            .returning();
        if (!updatedBranch) {
            return res.status(404).json({ error: 'الفرع غير موجود' });
        }
        console.log(`[Branch Updated] ID: ${branchId}, Changes: ${Object.keys(updateData).join(', ')}`);
        res.json({
            success: true,
            message: 'تم تحديث بيانات الفرع بنجاح',
            branch: updatedBranch,
        });
    }
    catch (error) {
        console.error('Update branch error:', error);
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
    }
    catch (error) {
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
    }
    catch (error) {
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
            query = query.where(eq(breaks.employeeId, employee_id));
        }
        if (status) {
            query = query.where(eq(breaks.status, status));
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
    }
    catch (error) {
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
        // Check if employee has checked in today
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        const todayString = today.toISOString().split('T')[0];
        const [todayAttendance] = await db
            .select()
            .from(attendance)
            .where(and(eq(attendance.employeeId, employee_id), eq(attendance.date, todayString), isNull(attendance.checkOutTime) // Still checked in
        ))
            .limit(1);
        if (!todayAttendance) {
            return res.status(400).json({
                error: 'يجب تسجيل الحضور أولاً قبل طلب الاستراحة',
                code: 'NOT_CHECKED_IN'
            });
        }
        // Prevent duplicate break requests for the same day
        const tomorrow = new Date(today);
        tomorrow.setDate(today.getDate() + 1);
        const existingBreak = await db
            .select()
            .from(breaks)
            .where(and(eq(breaks.employeeId, employee_id), gte(breaks.createdAt, today), lt(breaks.createdAt, tomorrow), inArray(breaks.status, ['PENDING', 'APPROVED', 'ACTIVE'])))
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
    }
    catch (error) {
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
    }
    catch (error) {
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
        if (!manager_id) {
            return res.status(400).json({ error: 'manager_id is required' });
        }
        // Get break details
        const [breakRecord] = await db
            .select()
            .from(breaks)
            .where(eq(breaks.id, breakId))
            .limit(1);
        if (!breakRecord) {
            return res.status(404).json({ error: 'Break request not found' });
        }
        // Check if reviewer can approve this request
        const approvalCheck = await canApproveRequest(manager_id, breakRecord.employeeId);
        if (!approvalCheck.canApprove) {
            return res.status(403).json({
                error: 'Forbidden',
                message: approvalCheck.reason || 'You do not have permission to approve this request'
            });
        }
        let setData = {
            approvedBy: manager_id,
            updatedAt: new Date(),
        };
        if (action === 'approve') {
            setData.status = 'APPROVED';
            setData.payoutEligible = false;
        }
        else if (action === 'reject') {
            setData.status = 'REJECTED';
            setData.payoutEligible = false;
        }
        else if (action === 'postpone') {
            setData.status = 'POSTPONED';
            setData.payoutEligible = true;
        }
        const updateResult = await db
            .update(breaks)
            .set(setData)
            .where(eq(breaks.id, breakId))
            .returning();
        const updated = extractFirstRow(updateResult);
        // Send notification to employee about break approval/rejection
        if (action === 'approve') {
            await sendNotification(breakRecord.employeeId, 'BREAK_APPROVED', 'تمت الموافقة على طلب الاستراحة', `تمت الموافقة على طلب الاستراحة الخاص بك لمدة ${breakRecord.requestedDurationMinutes} دقيقة`, manager_id, breakId);
        }
        else if (action === 'reject') {
            await sendNotification(breakRecord.employeeId, 'BREAK_REJECTED', 'تم رفض طلب الاستراحة', `تم رفض طلب الاستراحة الخاص بك لمدة ${breakRecord.requestedDurationMinutes} دقيقة`, manager_id, breakId);
        }
        res.json({
            success: true,
            message: action === 'approve' ? 'تم الموافقة على الاستراحة' : action === 'reject' ? 'تم رفض الاستراحة' : 'تم تأجيل الاستراحة - متاح صرف الرصيد لاحقًا',
            break: updated,
        });
    }
    catch (error) {
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
        if (!br)
            return res.status(404).json({ error: 'Break not found' });
        if (!br.payoutEligible)
            return res.status(400).json({ error: 'Payout is not eligible for this break' });
        const updateResult = await db
            .update(breaks)
            .set({ payoutApplied: true, payoutAppliedAt: new Date(), updatedAt: new Date(), approvedBy: manager_id })
            .where(eq(breaks.id, breakId))
            .returning();
        const updated = extractFirstRow(updateResult);
        res.json({ success: true, message: 'تم صرف مستحقات الاستراحة المؤجلة', break: updated });
    }
    catch (error) {
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
    }
    catch (error) {
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
    }
    catch (error) {
        console.error('Break end error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// ============ Geofence Violations (النسخة المحدثة) ============
app.post('/api/alerts/geofence-violation', async (req, res) => {
    try {
        const { employeeId, timestamp, latitude, longitude, action } = req.body;
        // (الـ 'action' يأتي من المكتبة الجديدة: "ENTER" أو "EXIT")
        if (!employeeId || !timestamp || !action) {
            return res.status(400).json({ error: 'Missing required fields (employeeId, timestamp, action)' });
        }
        const [employee] = await db
            .select()
            .from(employees)
            .where(eq(employees.id, employeeId))
            .limit(1);
        if (!employee) {
            return res.status(404).json({ error: 'Employee not found' });
        }
        const eventTime = new Date(timestamp);
        if (action === 'EXIT') {
            // الموظف خرج - سجل مخالفة جديدة بوقت خروج
            await db.insert(geofenceViolations).values({
                employeeId: employeeId,
                branchId: employee.branchId,
                exitTime: eventTime,
                latitude: latitude,
                longitude: longitude,
            });
            console.log(`[Geofence] VIOLATION (EXIT) logged for ${employeeId}`);
            // (يمكن إرسال تنبيه للمدير هنا)
        }
        else if (action === 'ENTER') {
            // الموظف عاد - ابحث عن آخر مخالفة (EXIT) لنفس الموظف لم يُسجل لها دخول
            const [lastViolation] = await db
                .select()
                .from(geofenceViolations)
                .where(and(eq(geofenceViolations.employeeId, employeeId), isNull(geofenceViolations.enterTime) // لم يسجل دخول
            ))
                .orderBy(desc(geofenceViolations.exitTime))
                .limit(1);
            if (lastViolation) {
                // وجدنا مخالفة مفتوحة، قم بتحديثها
                const enterTime = eventTime;
                const exitTime = new Date(lastViolation.exitTime);
                const durationSeconds = Math.round((enterTime.getTime() - exitTime.getTime()) / 1000);
                await db
                    .update(geofenceViolations)
                    .set({
                    enterTime: enterTime,
                    durationSeconds: durationSeconds,
                })
                    .where(eq(geofenceViolations.id, lastViolation.id));
                console.log(`[Geofence] VIOLATION (ENTER) logged for ${employeeId}. Duration: ${durationSeconds}s`);
            }
            else {
                // الموظف دخل النطاق (ربما كان التطبيق مغلقاً عند الخروج) - تجاهل
                console.log(`[Geofence] (ENTER) event for ${employeeId} without matching EXIT, ignoring.`);
            }
        }
        res.json({
            success: true,
            message: `Geofence action ${action} logged.`,
        });
    }
    catch (error) {
        console.error('Geofence violation error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// =============================================================================
// NEW FEATURES - Device Sessions, Notifications, Salary Management
// =============================================================================
// ============ Device Sessions - Single Device Login ============
// Check/Register device session on login
app.post('/api/device/register', async (req, res) => {
    try {
        const { employeeId, deviceId, deviceName, deviceModel, osVersion, appVersion } = req.body;
        if (!employeeId || !deviceId) {
            return res.status(400).json({ error: 'Employee ID and Device ID are required' });
        }
        // Check if there's an active session for this employee on a different device
        const activeSessions = await db
            .select()
            .from(deviceSessions)
            .where(and(eq(deviceSessions.employeeId, employeeId), eq(deviceSessions.isActive, true)));
        // If there's an active session on a different device, deactivate it
        for (const session of activeSessions) {
            if (session.deviceId !== deviceId) {
                await db
                    .update(deviceSessions)
                    .set({ isActive: false })
                    .where(eq(deviceSessions.id, session.id));
            }
        }
        // Check if this device already has a session
        const existingSession = await db
            .select()
            .from(deviceSessions)
            .where(and(eq(deviceSessions.employeeId, employeeId), eq(deviceSessions.deviceId, deviceId)))
            .limit(1);
        if (existingSession.length > 0) {
            // Update existing session
            const updateResult = await db
                .update(deviceSessions)
                .set({
                isActive: true,
                lastActiveAt: new Date(),
                deviceName,
                deviceModel,
                osVersion,
                appVersion,
            })
                .where(eq(deviceSessions.id, existingSession[0].id))
                .returning();
            const updated = extractFirstRow(updateResult);
            res.json({
                success: true,
                message: 'تم تسجيل الدخول بنجاح',
                session: updated,
                wasLoggedOutFromOtherDevice: activeSessions.length > 1,
            });
        }
        else {
            // Create new session
            const insertResult = await db
                .insert(deviceSessions)
                .values({
                employeeId,
                deviceId,
                deviceName,
                deviceModel,
                osVersion,
                appVersion,
                isActive: true,
            })
                .returning();
            const newSession = extractFirstRow(insertResult);
            res.json({
                success: true,
                message: 'تم تسجيل الدخول بنجاح',
                session: newSession,
                wasLoggedOutFromOtherDevice: activeSessions.length > 0,
            });
        }
    }
    catch (error) {
        console.error('Device registration error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// ============ Notifications ============
// Get notifications for an employee
app.get('/api/notifications/:employeeId', async (req, res) => {
    try {
        const { employeeId } = req.params;
        const { unreadOnly } = req.query;
        let query = db
            .select()
            .from(notifications)
            .where(eq(notifications.recipientId, employeeId))
            .orderBy(desc(notifications.createdAt));
        if (unreadOnly === 'true') {
            query = db
                .select()
                .from(notifications)
                .where(and(eq(notifications.recipientId, employeeId), eq(notifications.isRead, false)))
                .orderBy(desc(notifications.createdAt));
        }
        const result = await query;
        res.json({
            success: true,
            notifications: result,
            unreadCount: result.filter((n) => !n.isRead).length,
        });
    }
    catch (error) {
        console.error('Get notifications error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// Mark notification as read
app.post('/api/notifications/:notificationId/read', async (req, res) => {
    try {
        const { notificationId } = req.params;
        const updateResult = await db
            .update(notifications)
            .set({
            isRead: true,
            readAt: new Date(),
        })
            .where(eq(notifications.id, notificationId))
            .returning();
        const updated = extractFirstRow(updateResult);
        res.json({
            success: true,
            notification: updated,
        });
    }
    catch (error) {
        console.error('Mark notification read error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// Send notification (helper endpoint - usually called internally)
app.post('/api/notifications/send', async (req, res) => {
    try {
        const { recipientId, senderId, type, title, message, relatedId } = req.body;
        if (!recipientId || !type || !title || !message) {
            return res.status(400).json({ error: 'Missing required fields' });
        }
        const insertResult = await db
            .insert(notifications)
            .values({
            recipientId,
            senderId: senderId || null,
            type,
            title,
            message,
            relatedId: relatedId || null,
        })
            .returning();
        const notification = extractFirstRow(insertResult);
        res.json({
            success: true,
            notification,
        });
    }
    catch (error) {
        console.error('Send notification error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// ============ Attendance Time Modification ============
// Modify check-in time
app.post('/api/attendance/:attendanceId/modify-time', async (req, res) => {
    try {
        const { attendanceId } = req.params;
        const { modifiedCheckInTime, modifiedBy, modificationReason } = req.body;
        if (!modifiedCheckInTime || !modifiedBy) {
            return res.status(400).json({ error: 'Missing required fields' });
        }
        // Get the attendance record
        const attendanceRecords = await db
            .select()
            .from(attendance)
            .where(eq(attendance.id, attendanceId))
            .limit(1);
        if (attendanceRecords.length === 0) {
            return res.status(404).json({ error: 'Attendance record not found' });
        }
        const attendanceRecord = attendanceRecords[0];
        // Store actual check-in time if not already stored
        const actualCheckInTime = attendanceRecord.actualCheckInTime || attendanceRecord.checkInTime;
        // Calculate new work hours if check-out exists
        let newWorkHours = attendanceRecord.workHours;
        if (attendanceRecord.checkOutTime) {
            const modifiedIn = new Date(modifiedCheckInTime);
            const checkOut = new Date(attendanceRecord.checkOutTime);
            newWorkHours = ((checkOut.getTime() - modifiedIn.getTime()) / (1000 * 60 * 60)).toFixed(2);
        }
        // Update attendance record
        const updateResult = await db
            .update(attendance)
            .set({
            checkInTime: new Date(modifiedCheckInTime),
            actualCheckInTime,
            modifiedCheckInTime: new Date(modifiedCheckInTime),
            modifiedBy,
            modifiedAt: new Date(),
            modificationReason,
            workHours: newWorkHours,
            updatedAt: new Date(),
        })
            .where(eq(attendance.id, attendanceId))
            .returning();
        const updated = extractFirstRow(updateResult);
        res.json({
            success: true,
            message: 'تم تعديل وقت الحضور بنجاح',
            attendance: updated,
        });
    }
    catch (error) {
        console.error('Modify attendance time error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// ============ Salary Calculations ============
// Calculate salary for employee for a period
app.post('/api/salary/calculate', async (req, res) => {
    try {
        const { employeeId, periodStart, periodEnd } = req.body;
        if (!employeeId || !periodStart || !periodEnd) {
            return res.status(400).json({ error: 'Missing required fields' });
        }
        // Get employee info
        const employeeResult = await db
            .select()
            .from(employees)
            .where(eq(employees.id, employeeId))
            .limit(1);
        if (employeeResult.length === 0) {
            return res.status(404).json({ error: 'Employee not found' });
        }
        const employee = employeeResult[0];
        const baseSalary = parseFloat(employee.monthlySalary || '0');
        const hourlyRate = parseFloat(employee.hourlyRate || '0');
        // Get attendance records for the period
        const attendanceRecords = await db
            .select()
            .from(attendance)
            .where(and(eq(attendance.employeeId, employeeId), gte(attendance.date, periodStart), lte(attendance.date, periodEnd)));
        // Calculate total work hours and days
        let totalWorkHours = 0;
        const workDays = new Set();
        for (const record of attendanceRecords) {
            if (record.workHours) {
                totalWorkHours += parseFloat(record.workHours);
                workDays.add(record.date);
            }
        }
        const totalWorkDays = workDays.size;
        // Get ALL approved advances that haven't been deducted yet
        // NOTE: We deduct all pending advances regardless of when they were requested
        // This ensures advances are deducted once and only once
        const advancesResult = await db
            .select()
            .from(advances)
            .where(and(eq(advances.employeeId, employeeId), eq(advances.status, 'approved'), isNull(advances.deductedAt) // Only get advances that haven't been deducted yet
        ));
        const advancesTotal = advancesResult.reduce((sum, adv) => sum + parseFloat(adv.amount || '0'), 0); // Ensure amount is parsed correctly
        // Get deductions for the period
        const deductionsResult = await db
            .select()
            .from(deductions)
            .where(and(eq(deductions.employeeId, employeeId), gte(deductions.deductionDate, periodStart), lte(deductions.deductionDate, periodEnd)));
        const deductionsTotal = deductionsResult.reduce((sum, ded) => sum + parseFloat(ded.amount), 0);
        // Get absence deductions
        const absenceResult = await db
            .select()
            .from(absenceNotifications)
            .where(and(eq(absenceNotifications.employeeId, employeeId), eq(absenceNotifications.deductionApplied, true), gte(absenceNotifications.absenceDate, periodStart), lte(absenceNotifications.absenceDate, periodEnd)));
        const absenceDeductions = absenceResult.reduce((sum, abs) => sum + parseFloat(abs.deductionAmount || '0'), 0);
        // Calculate net salary
        const grossSalary = baseSalary + (totalWorkHours * hourlyRate);
        const netSalary = grossSalary - advancesTotal - deductionsTotal - absenceDeductions;
        // Save calculation
        const insertResult = await db
            .insert(salaryCalculations)
            .values({
            employeeId,
            periodStart,
            periodEnd,
            baseSalary: baseSalary.toString(),
            totalWorkHours: totalWorkHours.toString(),
            totalWorkDays,
            advancesTotal: advancesTotal.toString(),
            deductionsTotal: deductionsTotal.toString(),
            absenceDeductions: absenceDeductions.toString(),
            netSalary: netSalary.toString(),
        })
            .returning();
        const calculation = extractFirstRow(insertResult);
        // Mark advances as deducted (Remove isDeducted)
        if (advancesResult.length > 0) {
            await db
                .update(advances)
                .set({ deductedAt: new Date() }) // Only set deductedAt
                .where(inArray(advances.id, advancesResult.map(a => a.id)));
        }
        res.json({
            success: true,
            calculation,
            breakdown: {
                baseSalary,
                totalWorkHours,
                totalWorkDays,
                hourlyRate,
                hourlyEarnings: totalWorkHours * hourlyRate,
                grossSalary,
                advancesTotal,
                deductionsTotal,
                absenceDeductions,
                netSalary,
            },
        });
    }
    catch (error) {
        console.error('Calculate salary error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// Get salary calculations for employee
app.get('/api/salary/:employeeId', async (req, res) => {
    try {
        const { employeeId } = req.params;
        const calculations = await db
            .select()
            .from(salaryCalculations)
            .where(eq(salaryCalculations.employeeId, employeeId))
            .orderBy(desc(salaryCalculations.periodStart));
        res.json({
            success: true,
            calculations,
        });
    }
    catch (error) {
        console.error('Get salary calculations error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// ============ Attendance Statistics ============
// Get attendance statistics for employee
app.get('/api/attendance/stats/:employeeId', async (req, res) => {
    try {
        const { employeeId } = req.params;
        const { startDate, endDate } = req.query;
        if (!startDate || !endDate) {
            return res.status(400).json({ error: 'Start date and end date are required' });
        }
        // Get attendance records
        const attendanceRecords = await db
            .select()
            .from(attendance)
            .where(and(eq(attendance.employeeId, employeeId), gte(attendance.date, startDate), lte(attendance.date, endDate)));
        // Calculate statistics
        let totalWorkHours = 0;
        const workDays = new Set();
        let completedDays = 0;
        for (const record of attendanceRecords) {
            if (record.workHours) {
                totalWorkHours += parseFloat(record.workHours);
            }
            workDays.add(record.date);
            if (record.status === 'completed') {
                completedDays++;
            }
        }
        const totalWorkDays = workDays.size;
        res.json({
            success: true,
            stats: {
                totalWorkDays,
                completedDays,
                totalWorkHours: totalWorkHours.toFixed(2),
                averageHoursPerDay: totalWorkDays > 0 ? (totalWorkHours / totalWorkDays).toFixed(2) : '0',
            },
            records: attendanceRecords,
        });
    }
    catch (error) {
        console.error('Get attendance stats error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// ============ Owner: Get Employee Attendance Table ============
// Get employee attendance table (same view as employee sees)
app.get('/api/owner/employee-attendance/:employeeId', async (req, res) => {
    try {
        const { employeeId } = req.params;
        const { startDate, endDate } = req.query;
        if (!startDate || !endDate) {
            return res.status(400).json({ error: 'Start date and end date are required' });
        }
        // Get employee info
        const employeeResult = await db
            .select()
            .from(employees)
            .where(eq(employees.id, employeeId))
            .limit(1);
        if (employeeResult.length === 0) {
            return res.status(404).json({ error: 'Employee not found' });
        }
        const employee = employeeResult[0];
        // Get attendance records with JOIN to get leave requests
        const attendanceRecords = await db
            .select({
            attendance: attendance,
            leaveRequest: leaveRequests
        })
            .from(attendance)
            .leftJoin(leaveRequests, and(eq(leaveRequests.employeeId, employeeId), gte(attendance.date, leaveRequests.startDate), lte(attendance.date, leaveRequests.endDate), eq(leaveRequests.status, 'approved')))
            .where(and(eq(attendance.employeeId, employeeId), gte(attendance.date, startDate), lte(attendance.date, endDate)))
            .orderBy(desc(attendance.date));
        // Get all advances for this employee in date range
        // Convert startDate and endDate to Date objects for comparison
        const advancesResult = await db
            .select()
            .from(advances)
            .where(and(eq(advances.employeeId, employeeId), gte(advances.requestDate, new Date(startDate)), // Convert to Date
        lte(advances.requestDate, new Date(endDate)) // Convert to Date
        ))
            .orderBy(desc(advances.requestDate));
        // Get all deductions for this employee in date range
        const deductionsResult = await db
            .select()
            .from(deductions)
            .where(and(eq(deductions.employeeId, employeeId), gte(deductions.deductionDate, startDate), lte(deductions.deductionDate, endDate)))
            .orderBy(desc(deductions.deductionDate));
        // Build attendance table rows
        const tableRows = attendanceRecords.map(record => {
            const att = record.attendance;
            const leave = record.leaveRequest;
            // Get advances for this date (Compare YYYY-MM-DD strings)
            const attDateString = att.date; // Already YYYY-MM-DD
            const dayAdvances = advancesResult.filter(
            // Convert adv.requestDate to YYYY-MM-DD string for comparison
            adv => getDateString(adv.requestDate) === attDateString && adv.status === 'approved');
            const advancesAmount = dayAdvances.reduce((sum, adv) => sum + parseFloat(adv.amount || '0'), 0);
            // Get deductions for this date
            const dayDeductions = deductionsResult.filter(ded => ded.deductionDate === att.date);
            const deductionsAmount = dayDeductions.reduce((sum, ded) => sum + parseFloat(ded.amount || '0'), 0);
            return {
                date: att.date,
                checkIn: att.checkInTime || '--',
                checkOut: att.checkOutTime || '--',
                workHours: att.workHours ? parseFloat(att.workHours).toFixed(2) : '0.00',
                advances: advancesAmount.toFixed(2),
                // Use leave.allowanceAmount instead of leave.amount
                leaveAllowance: leave ? parseFloat(leave.allowanceAmount || '0').toFixed(2) : '0.00',
                hasLeave: !!leave,
                deductions: deductionsAmount.toFixed(2),
                advancesList: dayAdvances.map(a => normalizeNumericFields(a, ['amount', 'eligibleAmount', 'currentSalary'])), // Normalize fields
                deductionsList: dayDeductions.map(d => normalizeNumericFields(d, ['amount'])) // Normalize fields
            };
        });
        // Calculate totals
        let totalWorkHours = 0;
        let totalAdvances = 0;
        let totalLeaveAllowances = 0;
        let totalDeductions = 0;
        const workDays = new Set();
        for (const row of tableRows) {
            totalWorkHours += parseFloat(row.workHours);
            totalAdvances += parseFloat(row.advances);
            totalLeaveAllowances += parseFloat(row.leaveAllowance);
            totalDeductions += parseFloat(row.deductions);
            if (parseFloat(row.workHours) > 0) {
                workDays.add(row.date);
            }
        }
        // Calculate net (after deducting advances from total)
        const grossAmount = (employee.monthlySalary ? parseFloat(employee.monthlySalary) : 0);
        const netAfterAdvances = grossAmount - totalAdvances;
        res.json({
            success: true,
            employee: {
                id: employee.id,
                fullName: employee.fullName,
                role: employee.role,
                monthlySalary: employee.monthlySalary,
                hourlyRate: employee.hourlyRate,
            },
            tableRows: tableRows,
            summary: {
                totalWorkDays: workDays.size,
                totalWorkHours: totalWorkHours.toFixed(2),
                totalAdvances: totalAdvances.toFixed(2),
                totalLeaveAllowances: totalLeaveAllowances.toFixed(2),
                totalDeductions: totalDeductions.toFixed(2),
                grossSalary: grossAmount.toFixed(2),
                netAfterAdvances: netAfterAdvances.toFixed(2),
            },
        });
    }
    catch (error) {
        console.error('Get employee attendance table error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// ============ Attendance Presence Dashboard ============
// Get current presence status (who is checked in/out)
app.get('/api/attendance/presence', async (req, res) => {
    try {
        const { branchId } = req.query;
        const today = new Date().toISOString().split('T')[0];
        // Build query based on branch filter
        let attendanceQuery;
        if (branchId) {
            // Get employees from specific branch
            const branchEmployees = await db
                .select()
                .from(employees)
                .where(and(eq(employees.branchId, branchId), eq(employees.active, true)));
            const employeeIds = branchEmployees.map(e => e.id);
            if (employeeIds.length === 0) {
                return res.json({
                    success: true,
                    present: [],
                    absent: [],
                    summary: { present: 0, absent: 0, total: 0 },
                });
            }
            attendanceQuery = db
                .select()
                .from(attendance)
                .where(and(inArray(attendance.employeeId, employeeIds), eq(attendance.date, today)));
        }
        else {
            // Get all attendance for today
            attendanceQuery = db
                .select()
                .from(attendance)
                .where(eq(attendance.date, today));
        }
        const todayAttendance = await attendanceQuery;
        // Get all active employees
        let allEmployeesQuery = db
            .select()
            .from(employees)
            .where(eq(employees.active, true));
        if (branchId) {
            allEmployeesQuery = db
                .select()
                .from(employees)
                .where(and(eq(employees.branchId, branchId), eq(employees.active, true)));
        }
        const allEmployees = await allEmployeesQuery;
        // Build presence map
        const presentEmployees = [];
        const absentEmployees = [];
        for (const employee of allEmployees) {
            const employeeAttendance = todayAttendance.find(a => a.employeeId === employee.id);
            if (employeeAttendance) {
                presentEmployees.push({
                    ...employee,
                    attendance: employeeAttendance,
                    status: employeeAttendance.status,
                    checkInTime: employeeAttendance.checkInTime,
                    checkOutTime: employeeAttendance.checkOutTime,
                });
            }
            else {
                absentEmployees.push(employee);
            }
        }
        res.json({
            success: true,
            present: presentEmployees,
            absent: absentEmployees,
            summary: {
                present: presentEmployees.length,
                absent: absentEmployees.length,
                total: allEmployees.length,
            },
        });
    }
    catch (error) {
        console.error('Get presence status error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// =============================================================================
// CRON JOB - Daily Absence Check and Late Employee Check
// =============================================================================
// Daily absence check - runs at 2:00 AM Cairo time
cron.schedule('0 2 * * *', async () => {
    try {
        console.log('[CRON] Running daily absence check...');
        // Get yesterday's date in Cairo timezone
        const cairoTimeString = new Date().toLocaleString('en-US', { timeZone: 'Africa/Cairo' });
        const cairoDate = new Date(cairoTimeString);
        cairoDate.setDate(cairoDate.getDate() - 1); // Yesterday
        const yesterdayDateStr = cairoDate.toISOString().split('T')[0];
        console.log(`[CRON] Checking absences for date: ${yesterdayDateStr}`);
        // 1. Get all active employees
        const activeEmployees = await db.select({
            id: employees.id,
            fullName: employees.fullName,
            branchId: employees.branchId,
        })
            .from(employees)
            .where(eq(employees.active, true));
        if (activeEmployees.length === 0) {
            console.log('[CRON] No active employees found.');
            return;
        }
        const employeeIds = activeEmployees.map(e => e.id);
        // 2. Get attendance records for yesterday
        const attendanceRecords = await db.select({
            employeeId: attendance.employeeId,
            status: attendance.status, // For leave status
            checkInTime: attendance.checkInTime,
            modifiedCheckInTime: attendance.modifiedCheckInTime,
        })
            .from(attendance)
            .where(and(eq(attendance.date, yesterdayDateStr), inArray(attendance.employeeId, employeeIds)));
        // 3. Identify absent employees (no check-in AND not on leave)
        const absentEmployees = activeEmployees.filter(emp => {
            const record = attendanceRecords.find(att => att.employeeId === emp.id);
            // Consider absent if:
            // - No attendance record at all, OR
            // - Has record but no check-in times and not on leave
            return !record ||
                ((!record.checkInTime || record.checkInTime === null) &&
                    (!record.modifiedCheckInTime || record.modifiedCheckInTime === null) &&
                    record.status !== 'ON_LEAVE');
        });
        if (absentEmployees.length === 0) {
            console.log('[CRON] No absent employees found for', yesterdayDateStr);
            return;
        }
        console.log(`[CRON] Found ${absentEmployees.length} absent employees for ${yesterdayDateStr}`);
        // 4. Check for existing notifications to avoid duplicates
        const existingNotifications = await db.select({ employeeId: absenceNotifications.employeeId })
            .from(absenceNotifications)
            .where(and(eq(absenceNotifications.absenceDate, yesterdayDateStr), inArray(absenceNotifications.employeeId, absentEmployees.map(e => e.id))));
        const notifiedEmployeeIds = existingNotifications.map(n => n.employeeId);
        // 5. Create new absence notifications
        const notificationsToInsert = absentEmployees
            .filter(emp => !notifiedEmployeeIds.includes(emp.id))
            .map(emp => ({
            employeeId: emp.id,
            absenceDate: yesterdayDateStr,
            status: 'pending',
            createdAt: new Date(),
            notifiedAt: new Date(),
        }));
        if (notificationsToInsert.length > 0) {
            const insertedNotifications = await db.insert(absenceNotifications).values(notificationsToInsert).returning();
            console.log(`[CRON] Inserted ${insertedNotifications.length} new absence notifications.`);
            // 6. Send notifications to branch managers
            for (const notification of insertedNotifications) {
                const employee = absentEmployees.find(e => e.id === notification.employeeId);
                if (employee && employee.branchId) {
                    // Find manager for this branch
                    const [branch] = await db.select({ managerId: branches.managerId })
                        .from(branches)
                        .where(eq(branches.id, employee.branchId))
                        .limit(1);
                    if (branch?.managerId) {
                        await sendNotification(branch.managerId, 'ABSENCE_ALERT', 'غياب موظف', `تنبيه: الموظف ${employee.fullName} غائب يوم ${yesterdayDateStr}. يرجى مراجعة الغياب واتخاذ الإجراء المناسب.`, employee.id, notification.id);
                        console.log(`[CRON] Sent absence notification for ${employee.fullName} to manager ${branch.managerId}`);
                    }
                }
            }
        }
        else {
            console.log('[CRON] No new notifications to insert (already notified).');
        }
    }
    catch (error) {
        console.error('[CRON] Error during daily absence check:', error);
    }
});
// Late employee check - runs every 30 minutes
cron.schedule('*/30 * * * *', async () => {
    try {
        console.log('[CRON] Checking for late employees...');
        // Get Egypt/Cairo time
        const cairoTimeString = new Date().toLocaleString('en-US', { timeZone: 'Africa/Cairo' });
        const cairoDate = new Date(cairoTimeString);
        const today = cairoDate.toISOString().split('T')[0];
        const currentHour = cairoDate.getHours();
        const currentMinute = cairoDate.getMinutes();
        const currentTime = currentHour * 60 + currentMinute;
        console.log(`[CRON] Cairo Time: ${cairoTimeString}, Current Time: ${currentHour}:${currentMinute.toString().padStart(2, '0')}`);
        // Get all active employees with shift times
        const allEmployees = await db
            .select()
            .from(employees)
            .where(and(eq(employees.active, true), sql `${employees.shiftStartTime} IS NOT NULL`));
        for (const employee of allEmployees) {
            if (!employee.shiftStartTime)
                continue;
            // Parse shift start time
            const [startHour, startMinute] = employee.shiftStartTime.split(':').map(Number);
            const shiftStart = startHour * 60 + startMinute;
            const twoHoursAfterStart = shiftStart + 120; // 2 hours = 120 minutes
            // Check if it's been 2+ hours since shift start
            if (currentTime < twoHoursAfterStart)
                continue;
            // Check if employee has checked in today
            const [todayAttendance] = await db
                .select()
                .from(attendance)
                .where(and(eq(attendance.employeeId, employee.id), eq(attendance.date, today)))
                .limit(1);
            if (todayAttendance)
                continue; // Employee already checked in
            // Check if we already sent notification today
            const todayStart = new Date(cairoTimeString);
            todayStart.setHours(0, 0, 0, 0);
            const [existingNotification] = await db
                .select()
                .from(notifications)
                .where(and(eq(notifications.type, 'ABSENCE_ALERT'), eq(notifications.relatedId, employee.id), gte(notifications.createdAt, todayStart)))
                .limit(1);
            if (existingNotification)
                continue; // Already notified
            // Find manager for this employee's branch
            let managerId = null;
            if (employee.branchId) {
                const [branch] = await db
                    .select()
                    .from(branches)
                    .where(eq(branches.id, employee.branchId))
                    .limit(1);
                if (branch?.managerId) {
                    managerId = branch.managerId;
                }
            }
            // If no branch manager, send to owner
            if (!managerId) {
                managerId = await getOwnerId();
            }
            if (managerId) {
                // Send notification to manager
                await sendNotification(managerId, 'ABSENCE_ALERT', 'تأخير موظف', `تنبيه: الموظف ${employee.fullName} تأخر لمدة ساعتين عن شيفت اليوم (${employee.shiftStartTime}). هل ترغب بتطبيق خصم؟`, employee.id, employee.id);
                console.log(`[CRON] Sent late notification for employee ${employee.fullName} to manager ${managerId}`);
            }
        }
        console.log('[CRON] Late employee check completed');
    }
    catch (error) {
        console.error('[CRON] Error checking late employees:', error);
    }
});
// =============================================================================
// AUTO CHECKOUT AT SHIFT END - تسجيل خروج آلي عند نهاية الشيفت
// =============================================================================
// Check every 10 minutes for employees who need auto checkout
cron.schedule('*/10 * * * *', async () => {
    try {
        console.log('[CRON] Checking for employees needing auto checkout...');
        // Get Egypt/Cairo time
        const cairoTimeString = new Date().toLocaleString('en-US', { timeZone: 'Africa/Cairo' });
        const cairoDate = new Date(cairoTimeString);
        const currentHour = cairoDate.getHours();
        const currentMinute = cairoDate.getMinutes();
        const currentTime = currentHour * 60 + currentMinute; // Convert to minutes since midnight
        console.log(`[CRON] Current Cairo Time: ${currentHour}:${currentMinute.toString().padStart(2, '0')}`);
        // Get today's date
        const today = cairoDate.toISOString().split('T')[0];
        // Get all active attendance records (employees currently checked in)
        const activeAttendances = await db
            .select({
            attendanceId: attendance.id,
            employeeId: attendance.employeeId,
            checkInTime: attendance.checkInTime,
            employeeName: employees.fullName,
            shiftEndTime: employees.shiftEndTime,
            shiftType: employees.shiftType,
        })
            .from(attendance)
            .innerJoin(employees, eq(attendance.employeeId, employees.id))
            .where(and(eq(attendance.date, today), eq(attendance.status, 'active'), eq(employees.active, true)));
        if (activeAttendances.length === 0) {
            console.log('[CRON] No active attendances found for auto checkout');
            return;
        }
        console.log(`[CRON] Found ${activeAttendances.length} active attendances to check`);
        let autoCheckoutCount = 0;
        for (const record of activeAttendances) {
            if (!record.shiftEndTime) {
                console.log(`[CRON] Employee ${record.employeeName} has no shift end time, skipping`);
                continue;
            }
            // Parse shift end time
            const [endHour, endMinute] = record.shiftEndTime.split(':').map(Number);
            const shiftEnd = endHour * 60 + endMinute;
            // Check if shift has ended (add 10 minute grace period)
            const graceMinutes = 10;
            let shouldAutoCheckout = false;
            if (record.shiftType === 'PM' && shiftEnd < 12 * 60) {
                // Night shift (e.g., 21:00 to 05:00)
                // If current time is past shift end (accounting for midnight crossing)
                if (currentTime >= 0 && currentTime >= shiftEnd + graceMinutes) {
                    shouldAutoCheckout = true;
                }
            }
            else {
                // Day shift (e.g., 09:00 to 17:00)
                if (currentTime >= shiftEnd + graceMinutes) {
                    shouldAutoCheckout = true;
                }
            }
            if (shouldAutoCheckout) {
                console.log(`[CRON] Auto checkout for ${record.employeeName} (shift ended at ${record.shiftEndTime})`);
                // Calculate work hours
                const checkInTime = new Date(record.checkInTime);
                const checkOutTime = new Date();
                const workHours = (checkOutTime.getTime() - checkInTime.getTime()) / (1000 * 60 * 60);
                // Update attendance record
                await db
                    .update(attendance)
                    .set({
                    checkOutTime,
                    workHours: workHours.toFixed(2),
                    status: 'completed',
                    isAutoCheckout: true,
                    updatedAt: new Date(),
                })
                    .where(eq(attendance.id, record.attendanceId));
                autoCheckoutCount++;
                // Send notification to employee
                await sendNotification(record.employeeId, 'CHECK_OUT', 'تسجيل خروج آلي', `تم تسجيل خروجك آلياً في نهاية الشيفت (${record.shiftEndTime})`, record.employeeId, record.attendanceId);
                console.log(`[CRON] ✅ Auto checkout completed for ${record.employeeName}`);
            }
        }
        console.log(`[CRON] Auto checkout completed: ${autoCheckoutCount} employees checked out`);
    }
    catch (error) {
        console.error('[CRON] Error during auto checkout:', error);
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
server.on('error', (error) => {
    console.error('[DEBUG] Server error event:', error);
    if (error.code === 'EADDRINUSE') {
        console.error(`❌ ERROR: Port ${PORT} is already in use!`);
        console.error(`   Run: taskkill /F /IM node.exe`);
        process.exit(1);
    }
    else {
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
                role: 'owner',
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
                role: 'staff',
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
                role: 'staff',
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
                role: 'manager',
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
    }
    catch (error) {
        console.error('Seed error:', error);
        res.status(500).json({ error: 'Seed failed', message: error?.message });
    }
});
// 404 handler (JSON)
app.use((req, res) => {
    res.status(404).json({ error: 'Not Found', path: req.path });
});
// Error handler (JSON)
app.use((err, req, res, _next) => {
    console.error('Unhandled error:', err);
    const status = err?.status || 500;
    res.status(status).json({ error: 'Internal server error', message: err?.message });
});
