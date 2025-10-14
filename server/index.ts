import express from 'express';
import cors from 'cors';
import { db } from './db.js';
import { profiles, shifts, pulses, users, roles, permissions, rolePermissions, userRoles } from '../shared/schema.js';
import { eq, and, gte, lte, desc } from 'drizzle-orm';
import { requirePermission, getUserPermissions, checkUserPermission } from './auth.js';

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'ok', message: 'Oldies Workers API is running' });
});

// Calculate payroll endpoint (ported from Supabase Edge Function)
app.post('/api/calculate-payroll', async (req, res) => {
  try {
    const { user_id, start_date, end_date, hourly_rate = 30 } = req.body;

    // Validate required fields
    if (!user_id || !start_date || !end_date) {
      return res.status(400).json({ 
        error: 'user_id, start_date, and end_date are required' 
      });
    }

    // Get user profile
    const [profile] = await db
      .select({
        employeeId: profiles.employeeId,
        fullName: profiles.fullName,
      })
      .from(profiles)
      .where(eq(profiles.id, user_id))
      .limit(1);

    if (!profile) {
      return res.status(404).json({ error: 'User not found' });
    }

    // Fetch all shifts for the user in the date range
    const userShifts = await db
      .select({
        id: shifts.id,
        checkInTime: shifts.checkInTime,
        checkOutTime: shifts.checkOutTime,
        status: shifts.status,
      })
      .from(shifts)
      .where(
        and(
          eq(shifts.userId, user_id),
          gte(shifts.checkInTime, new Date(start_date)),
          lte(shifts.checkInTime, new Date(end_date))
        )
      )
      .orderBy(shifts.checkInTime);

    let totalValidPulses = 0;
    let totalWorkHours = 0;
    const shiftsDetail: any[] = [];

    // Process each shift
    for (const shift of userShifts) {
      // Fetch valid pulses for this shift
      const validPulses = await db
        .select({
          id: pulses.id,
          createdAt: pulses.createdAt,
        })
        .from(pulses)
        .where(
          and(
            eq(pulses.shiftId, shift.id),
            eq(pulses.isWithinGeofence, true)
          )
        )
        .orderBy(pulses.createdAt);

      const validPulseCount = validPulses.length;
      totalValidPulses += validPulseCount;

      // Calculate work duration for this shift
      let workDurationHours = 0;

      if (validPulses.length > 0 && validPulses[0].createdAt && validPulses[validPulses.length - 1].createdAt) {
        // Use first and last valid pulse to determine work duration
        const firstPulse = new Date(validPulses[0].createdAt);
        const lastPulse = new Date(validPulses[validPulses.length - 1].createdAt);

        const durationMs = lastPulse.getTime() - firstPulse.getTime();
        workDurationHours = durationMs / (1000 * 60 * 60); // Convert to hours
      }

      totalWorkHours += workDurationHours;

      shiftsDetail.push({
        shift_id: shift.id,
        check_in: shift.checkInTime,
        check_out: shift.checkOutTime,
        valid_pulses: validPulseCount,
        work_duration_hours: Math.round(workDurationHours * 100) / 100,
      });
    }

    // Calculate total pay
    const totalPay = totalWorkHours * hourly_rate;

    // Prepare response
    const result = {
      user_id,
      employee_id: profile.employeeId,
      full_name: profile.fullName,
      period: {
        start: start_date,
        end: end_date,
      },
      total_shifts: userShifts.length,
      total_valid_pulses: totalValidPulses,
      total_work_hours: Math.round(totalWorkHours * 100) / 100,
      hourly_rate,
      total_pay: Math.round(totalPay * 100) / 100,
      shifts_detail: shiftsDetail,
    };

    res.json(result);
  } catch (error) {
    console.error('Error calculating payroll:', error);
    res.status(500).json({ 
      error: error instanceof Error ? error.message : 'Internal server error' 
    });
  }
});

// Insert pulse endpoint (for Flutter app to send pulses)
app.post('/api/pulses', async (req, res) => {
  try {
    const { shift_id, latitude, longitude } = req.body;

    if (!shift_id || !latitude || !longitude) {
      return res.status(400).json({ 
        error: 'shift_id, latitude, and longitude are required' 
      });
    }

    // Insert pulse - the trigger will automatically validate geofence
    const [newPulse] = await db
      .insert(pulses)
      .values({
        shiftId: shift_id,
        latitude: latitude.toString(),
        longitude: longitude.toString(),
      })
      .returning();

    res.json({
      success: true,
      pulse_id: newPulse.id,
      is_within_geofence: newPulse.isWithinGeofence,
    });
  } catch (error) {
    console.error('Error inserting pulse:', error);
    res.status(500).json({ 
      error: error instanceof Error ? error.message : 'Internal server error' 
    });
  }
});

// Get pulses for a shift
app.get('/api/shifts/:shift_id/pulses', async (req, res) => {
  try {
    const { shift_id } = req.params;

    const shiftPulses = await db
      .select()
      .from(pulses)
      .where(eq(pulses.shiftId, shift_id))
      .orderBy(desc(pulses.createdAt));

    res.json({
      shift_id,
      pulses: shiftPulses,
    });
  } catch (error) {
    console.error('Error fetching pulses:', error);
    res.status(500).json({ 
      error: error instanceof Error ? error.message : 'Internal server error' 
    });
  }
});

// =============================================================================
// USER MANAGEMENT ENDPOINTS
// =============================================================================

// Get all admin users
app.get('/api/users', requirePermission('view_users'), async (req, res) => {
  try {
    const allUsers = await db
      .select({
        id: users.id,
        email: users.email,
        fullName: users.fullName,
        isActive: users.isActive,
        createdAt: users.createdAt,
      })
      .from(users);

    res.json({ users: allUsers });
  } catch (error) {
    console.error('Error fetching users:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Get user with their roles and permissions
app.get('/api/users/:userId', async (req, res) => {
  try {
    const { userId } = req.params;

    const [user] = await db
      .select()
      .from(users)
      .where(eq(users.id, userId))
      .limit(1);

    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    // Get user roles
    const userRolesList = await db
      .select({
        roleId: roles.id,
        roleName: roles.name,
        roleNameAr: roles.nameAr,
      })
      .from(userRoles)
      .innerJoin(roles, eq(userRoles.roleId, roles.id))
      .where(eq(userRoles.userId, userId));

    // Get user permissions
    const userPermissions = await getUserPermissions(userId);

    res.json({
      user: {
        id: user.id,
        email: user.email,
        fullName: user.fullName,
        isActive: user.isActive,
      },
      roles: userRolesList,
      permissions: userPermissions,
    });
  } catch (error) {
    console.error('Error fetching user details:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Create new admin user
app.post('/api/users', requirePermission('create_users'), async (req, res) => {
  try {
    const { email, password_hash, full_name, role_ids } = req.body;

    if (!email || !password_hash || !full_name) {
      return res.status(400).json({ error: 'Email, password_hash, and full_name are required' });
    }

    // Create user
    const [newUser] = await db
      .insert(users)
      .values({
        email,
        passwordHash: password_hash,
        fullName: full_name,
      })
      .returning();

    // Assign roles if provided
    if (role_ids && Array.isArray(role_ids) && role_ids.length > 0) {
      const assignedBy = req.headers['x-user-id'] as string;
      
      await db.insert(userRoles).values(
        role_ids.map((roleId: string) => ({
          userId: newUser.id,
          roleId,
          assignedBy: assignedBy || null,
        }))
      );
    }

    res.status(201).json({
      message: 'User created successfully',
      user: {
        id: newUser.id,
        email: newUser.email,
        fullName: newUser.fullName,
      },
    });
  } catch (error) {
    console.error('Error creating user:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// =============================================================================
// ROLE MANAGEMENT ENDPOINTS
// =============================================================================

// Get all roles
app.get('/api/roles', async (req, res) => {
  try {
    const allRoles = await db.select().from(roles);
    res.json({ roles: allRoles });
  } catch (error) {
    console.error('Error fetching roles:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Get role with permissions
app.get('/api/roles/:roleId', async (req, res) => {
  try {
    const { roleId } = req.params;

    const [role] = await db
      .select()
      .from(roles)
      .where(eq(roles.id, roleId))
      .limit(1);

    if (!role) {
      return res.status(404).json({ error: 'Role not found' });
    }

    // Get role permissions
    const rolePerms = await db
      .select({
        permissionId: permissions.id,
        permissionName: permissions.name,
        permissionNameAr: permissions.nameAr,
        category: permissions.category,
      })
      .from(rolePermissions)
      .innerJoin(permissions, eq(rolePermissions.permissionId, permissions.id))
      .where(eq(rolePermissions.roleId, roleId));

    res.json({
      role,
      permissions: rolePerms,
    });
  } catch (error) {
    console.error('Error fetching role details:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Create new role
app.post('/api/roles', requirePermission('manage_roles'), async (req, res) => {
  try {
    const { name, name_ar, description, permission_ids } = req.body;

    if (!name || !name_ar) {
      return res.status(400).json({ error: 'Name and name_ar are required' });
    }

    // Create role
    const [newRole] = await db
      .insert(roles)
      .values({
        name,
        nameAr: name_ar,
        description,
        isSystemRole: false,
      })
      .returning();

    // Assign permissions if provided
    if (permission_ids && Array.isArray(permission_ids) && permission_ids.length > 0) {
      await db.insert(rolePermissions).values(
        permission_ids.map((permId: string) => ({
          roleId: newRole.id,
          permissionId: permId,
        }))
      );
    }

    res.status(201).json({
      message: 'Role created successfully',
      role: newRole,
    });
  } catch (error) {
    console.error('Error creating role:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Update role permissions
app.put('/api/roles/:roleId/permissions', requirePermission('manage_roles'), async (req, res) => {
  try {
    const { roleId } = req.params;
    const { permission_ids } = req.body;

    if (!Array.isArray(permission_ids)) {
      return res.status(400).json({ error: 'permission_ids must be an array' });
    }

    // Delete existing permissions
    await db.delete(rolePermissions).where(eq(rolePermissions.roleId, roleId));

    // Add new permissions
    if (permission_ids.length > 0) {
      await db.insert(rolePermissions).values(
        permission_ids.map((permId: string) => ({
          roleId,
          permissionId: permId,
        }))
      );
    }

    res.json({ message: 'Role permissions updated successfully' });
  } catch (error) {
    console.error('Error updating role permissions:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// =============================================================================
// PERMISSION MANAGEMENT ENDPOINTS
// =============================================================================

// Get all permissions (grouped by category)
app.get('/api/permissions', async (req, res) => {
  try {
    const allPermissions = await db.select().from(permissions);
    
    // Group by category
    const grouped = allPermissions.reduce((acc: any, perm) => {
      if (!acc[perm.category]) {
        acc[perm.category] = [];
      }
      acc[perm.category].push(perm);
      return acc;
    }, {});

    res.json({ permissions: grouped });
  } catch (error) {
    console.error('Error fetching permissions:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Assign role to user
app.post('/api/users/:userId/roles', requirePermission('edit_users'), async (req, res) => {
  try {
    const { userId } = req.params;
    const { role_id } = req.body;
    const assignedBy = req.headers['x-user-id'] as string;

    if (!role_id) {
      return res.status(400).json({ error: 'role_id is required' });
    }

    await db.insert(userRoles).values({
      userId,
      roleId: role_id,
      assignedBy: assignedBy || null,
    });

    res.json({ message: 'Role assigned successfully' });
  } catch (error) {
    console.error('Error assigning role:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Remove role from user
app.delete('/api/users/:userId/roles/:roleId', requirePermission('edit_users'), async (req, res) => {
  try {
    const { userId, roleId } = req.params;

    await db
      .delete(userRoles)
      .where(
        and(
          eq(userRoles.userId, userId),
          eq(userRoles.roleId, roleId)
        )
      );

    res.json({ message: 'Role removed successfully' });
  } catch (error) {
    console.error('Error removing role:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.listen(PORT, () => {
  console.log(`🚀 Oldies Workers API server running on port ${PORT}`);
  console.log(`📍 Health check: http://localhost:${PORT}/health`);
  console.log(`💰 Payroll API: http://localhost:${PORT}/api/calculate-payroll`);
  console.log(`📡 Pulse API: http://localhost:${PORT}/api/pulses`);
  console.log(`👥 User Management: http://localhost:${PORT}/api/users`);
  console.log(`🔐 Role Management: http://localhost:${PORT}/api/roles`);
  console.log(`✅ Permissions: http://localhost:${PORT}/api/permissions`);
});
