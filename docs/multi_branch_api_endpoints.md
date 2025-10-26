# API Endpoints for Multi-Branch Smart Heartbeat Attendance System

## Overview
These endpoints support branch management, user authentication, attendance tracking, and role-based access. All endpoints require authentication (e.g., JWT token) and enforce permissions based on user roles (OWNER, MANAGER, EMPLOYEE).

## Authentication Endpoints
- **POST /auth/login**
  - Description: User login with username/password.
  - Body: { "username": "string", "password": "string" }
  - Response: { "token": "jwt", "user": { "id", "role", "branch_id" } }
  - Permissions: Public

- **POST /auth/logout**
  - Description: Logout user.
  - Permissions: Authenticated users

## Branch Management Endpoints (OWNER Only)
- **POST /owner/branches**
  - Description: Create a new branch.
  - Body: { "name": "string", "address": "string", "manager_id": "uuid", "geo_lat": "decimal", "geo_lon": "decimal", "geo_radius": "integer", "bssid_list": ["string"] }
  - Response: { "branch": { "id", "name", ... } }
  - Permissions: OWNER

- **GET /owner/branches**
  - Description: List all branches.
  - Response: { "branches": [ { "id", "name", "address", "manager_id", "geo_lat", "geo_lon", "geo_radius" } ] }
  - Permissions: OWNER

- **PUT /owner/branches/{branch_id}**
  - Description: Update branch details, including manager, geofence, and BSSIDs.
  - Body: { "name": "string", "address": "string", "manager_id": "uuid", "geo_lat": "decimal", "geo_lon": "decimal", "geo_radius": "integer", "bssid_list": ["string"] }
  - Permissions: OWNER

- **DELETE /owner/branches/{branch_id}**
  - Description: Delete a branch (cascades to users and pulses).
  - Permissions: OWNER

- **POST /owner/branches/{branch_id}/bssids**
  - Description: Add BSSIDs to a branch.
  - Body: { "bssid_list": ["string"] }
  - Permissions: OWNER

- **DELETE /owner/branches/{branch_id}/bssids/{bssid_id}**
  - Description: Remove a BSSID from a branch.
  - Permissions: OWNER

## User Management Endpoints
- **POST /owner/users**
  - Description: Create a new user (OWNER can create any role; MANAGER can create EMPLOYEE for their branch).
  - Body: { "username": "string", "password": "string", "role": "string", "branch_id": "uuid", "full_name": "string", "email": "string" }
  - Permissions: OWNER or MANAGER (for EMPLOYEE only)

- **GET /owner/users**
  - Description: List all users (OWNER sees all; MANAGER sees branch users).
  - Response: { "users": [ { "id", "username", "role", "branch_id", "full_name" } ] }
  - Permissions: OWNER or MANAGER

- **PUT /owner/users/{user_id}**
  - Description: Update user details (role, branch, etc.).
  - Permissions: OWNER or MANAGER (for branch users)

- **DELETE /owner/users/{user_id}**
  - Description: Delete a user.
  - Permissions: OWNER or MANAGER (for branch users)

## Employee/Manager Specific Endpoints
- **GET /employee/my_branch_settings**
  - Description: Fetch branch settings for the logged-in employee (geofence, BSSIDs).
  - Response: { "branch": { "id", "name", "geo_lat", "geo_lon", "geo_radius", "bssid_list": ["string"] } }
  - Permissions: EMPLOYEE or MANAGER

- **POST /employee/pulses**
  - Description: Send a pulse (check-in/out).
  - Body: { "latitude": "decimal", "longitude": "decimal", "bssid_address": "string", "status": "IN/OUT" }
  - Response: { "pulse": { "id", "is_within_geofence", "status" } }
  - Permissions: EMPLOYEE (for their branch only)

- **GET /employee/pulses**
  - Description: Get employee's pulse history.
  - Response: { "pulses": [ { "id", "timestamp", "is_within_geofence", "status" } ] }
  - Permissions: EMPLOYEE (own pulses) or MANAGER (branch pulses)

- **GET /manager/branch_reports**
  - Description: Get attendance reports for the manager's branch.
  - Query: ?start_date=YYYY-MM-DD&end_date=YYYY-MM-DD
  - Response: { "reports": [ { "employee_id", "total_hours", "pulses_count" } ] }
  - Permissions: MANAGER

- **GET /owner/reports**
  - Description: Get reports for all branches.
  - Query: ?branch_id=uuid&start_date=YYYY-MM-DD&end_date=YYYY-MM-DD
  - Response: { "reports": [ ... ] }
  - Permissions: OWNER

## Attendance Requests (Manager/Owner Approval)
- **POST /requests/attendance**
  - Description: Submit attendance request (e.g., for forgotten check-in).
  - Body: { "employee_id": "string", "requested_time": "datetime", "reason": "string" }
  - Permissions: EMPLOYEE

- **GET /manager/requests/attendance**
  - Description: Get pending attendance requests for branch.
  - Response: { "requests": [ ... ] }
  - Permissions: MANAGER

- **PUT /manager/requests/attendance/{request_id}**
  - Description: Approve/reject attendance request.
  - Body: { "status": "approved/rejected", "review_notes": "string" }
  - Permissions: MANAGER

## System Settings (OWNER Only)
- **GET /owner/system_settings**
  - Description: Get system-wide settings (e.g., default radius).
  - Permissions: OWNER

- **PUT /owner/system_settings**
  - Description: Update system settings.
  - Body: { "default_geofence_radius": "integer" }
  - Permissions: OWNER

## Notes
- All endpoints return errors for insufficient permissions (403 Forbidden).
- Geofence and BSSID are validated on pulse submission.
- Offline pulses are stored locally and synced when online.
- Role-based filtering ensures users only access authorized data.