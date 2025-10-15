import { db } from './db.js';
import { sql } from 'drizzle-orm';
// Middleware factory to check if user has a specific permission
export function requirePermission(permissionName) {
    return async (req, res, next) => {
        try {
            const userId = req.headers['x-user-id'];
            if (!userId) {
                return res.status(401).json({ error: 'Unauthorized - No user ID provided' });
            }
            // Check if user has the required permission using parameterized query
            const result = await db.execute(sql `SELECT user_has_permission(${userId}::uuid, ${permissionName}) as user_has_permission`);
            const hasPermission = result.rows[0]?.user_has_permission;
            if (!hasPermission) {
                return res.status(403).json({
                    error: 'Forbidden - You do not have permission to perform this action',
                    required_permission: permissionName
                });
            }
            next();
        }
        catch (error) {
            console.error('Permission check error:', error);
            res.status(500).json({ error: 'Internal server error during permission check' });
        }
    };
}
// Get all permissions for a user
export async function getUserPermissions(userId) {
    try {
        const result = await db.execute(sql `SELECT * FROM get_user_permissions(${userId}::uuid)`);
        return result.rows;
    }
    catch (error) {
        console.error('Error getting user permissions:', error);
        return [];
    }
}
// Check if user has specific permission
export async function checkUserPermission(userId, permissionName) {
    try {
        const result = await db.execute(sql `SELECT user_has_permission(${userId}::uuid, ${permissionName}) as user_has_permission`);
        return result.rows[0]?.user_has_permission || false;
    }
    catch (error) {
        console.error('Error checking user permission:', error);
        return false;
    }
}
