# Flutter App Modifications for Multi-Branch Smart Heartbeat Attendance System

## Overview
The Flutter app needs updates to support dynamic branch settings, role-based navigation, and enhanced pulse logic with BSSID verification. Key changes include fetching branch data on login, dynamic geofencing, and UI adaptations for OWNER, MANAGER, and EMPLOYEE roles.

## High-Level Logic for Loading Settings and Monitoring

### 1. Authentication and Role-Based Setup
- **Login Process:**
  - After successful login via `AuthApiService`, fetch user details including `role` and `branch_id`.
  - If `role` is EMPLOYEE or MANAGER, call `GET /employee/my_branch_settings` to retrieve branch-specific data: `geo_lat`, `geo_lon`, `geo_radius`, `bssid_list`.
  - Store branch settings in local storage (e.g., SharedPreferences or Hive) for offline access.
  - Use branch settings to initialize geofence and BSSID checks dynamically.

- **Role-Based Navigation:**
  - Redirect to appropriate home screen based on role:
    - OWNER: `OwnerMainScreen` (with Branch Management tab).
    - MANAGER: `ManagerMainScreen`.
    - EMPLOYEE: `EmployeeMainScreen`.

### 2. Dynamic Geofence Setup
- **Replace Hardcoded Config:**
  - Remove reliance on `RestaurantConfig` for geofence. Instead, use fetched branch settings.
  - In `LocationService`, update `isWithinRestaurantArea` to use dynamic `restaurantLat`, `restaurantLon`, `radiusInMeters` from branch settings.

- **Geofencing Implementation:**
  - Use Flutter plugins like `geolocator` and `geofencing` to set up geofences based on branch coordinates and radius.
  - Register geofence events (ENTER/EXIT) to trigger pulse sending.
  - On ENTER event:
    - Fetch current BSSID using `wifi_info_flutter` plugin.
    - Compare with branch's `bssid_list`.
    - If matched, send "Pulse IN" to `POST /employee/pulses` with `status: 'IN'`, `bssid_address`, lat/lon.
    - Start Foreground Service for continuous monitoring.

### 3. Pulse Logic Updates
- **Pulse Sending:**
  - Modify `Pulse` model to include `branch_id` (fetched from user data).
  - In `PulseBackendClient`, ensure payload includes `branch_id`, `bssid_address`, `status` ('IN' or 'OUT').
  - For OUT: On EXIT geofence or manual check-out, send "Pulse OUT".
  - Validate BSSID on pulse send: If BSSID doesn't match branch list, set `is_within_geofence` to FALSE or reject pulse.

- **Offline Support:**
  - Store unsent pulses in Hive with `is_synced: false`.
  - Use `PulseSyncManager` to sync when online, including branch_id.

### 4. UI Modifications
- **Owner Dashboard (Add Branch Management):**
  - In `lib/screens/owner/owner_comprehensive_screen.dart`, add a new tab or section for "Branch Management".
  - Form for creating/editing branches with fields: Branch Name, Address, Manager Assignment (dropdown of users with MANAGER role), Geofence Lat/Lon/Radius, BSSID List (multi-input).
  - Integrate with `POST /owner/branches` and `GET /owner/branches`.
  - List all branches with edit/delete options.

- **Manager Screens:**
  - Update to show only branch-specific data (e.g., branch employees, reports).
  - Add employee management: Add/remove employees via `POST /owner/users` (role: EMPLOYEE).

- **Employee Screens:**
  - On login, load branch settings and restrict attendance to branch geofence/BSSIDs.
  - Update `AttendanceApiService` to use branch-aware endpoints if needed.

- **Global Changes:**
  - Add role checks in all screens to hide/show features based on permissions.
  - Update models (e.g., `Employee` model to include `branch_id`).
  - Handle BSSID fetching in a new service, e.g., `WifiService`.

### 5. Additional Services and Utilities
- **New Services:**
  - `BranchApiService`: Handle branch CRUD operations.
  - `WifiService`: Fetch current BSSID for validation.
  - Update `LocationService` to support dynamic geofence registration.

- **Background Monitoring:**
  - Enhance `BackgroundPulseService` to use branch settings for geofence and BSSID checks.

### 6. Error Handling and Permissions
- **Role Enforcement:**
  - Add middleware in API calls to check user role and branch access.
  - On UI, disable buttons/features for insufficient permissions.

- **Validation:**
  - Ensure BSSID is uppercase and colon-separated.
  - Handle cases where branch settings are missing (fallback to error).

## Integration Steps
1. Update `pubspec.yaml` for new plugins (e.g., `wifi_info_flutter` for BSSID).
2. Modify authentication flow in `AuthRouter`.
3. Test geofence events and pulse syncing in isolated branch scenarios.
4. Ensure backward compatibility with existing single-branch logic.

## Mermaid Diagram for Workflow
```mermaid
graph TD
    A[Login] --> B{Fetch User Role}
    B -->|OWNER| C[OwnerMainScreen]
    B -->|MANAGER| D[ManagerMainScreen]
    B -->|EMPLOYEE| E[EmployeeMainScreen]

    E --> F[Fetch Branch Settings]
    F --> G[Set Dynamic Geofence]
    G --> H[Monitor Geofence Events]
    H -->|ENTER| I[Fetch BSSID]
    I --> J{BSSID Match Branch List?}
    J -->|Yes| K[Send Pulse IN]
    J -->|No| L[Reject Pulse]
    H -->|EXIT| M[Send Pulse OUT]

    C --> N[Branch Management Tab]
    N --> O[Create/Edit Branches]
    O --> P[Update Geofence/BSSIDs]

    D --> Q[Manage Branch Employees]
    Q --> R[View Branch Reports]

    K --> S[Store Offline if Needed]
    S --> T[Sync When Online]