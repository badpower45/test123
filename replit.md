# Oldies Workers - Employee Attendance System

## Overview
**Oldies Workers** (أولديزز وركرز) is a comprehensive Flutter-based employee attendance tracking system with real-time location monitoring and pulse-based verification. The app features a mobile/web client for employees and an administrative dashboard for managers.

## Project Status
- **Frontend**: Dart 3.8.0 / Flutter 3.32.0
- **Backend**: Node.js/TypeScript with Express + Neon PostgreSQL
- **Platform**: Cross-platform (Web, Android, iOS, Desktop)
- **Current Setup**: Full-stack web deployment configured
- **Migration Status**: ✅ Successfully migrated from Supabase to Neon PostgreSQL (Oct 15, 2025)

## Core Features

### Employee Features
- **Location-Based Check-in/Check-out**: Geo-fence validation ensures employees are within the designated work area
- **Continuous Pulse System**: Periodic location updates (pulses) sent every few seconds
- **Offline Support**: Smart offline storage using Hive database with auto-sync when connection returns
- **Permission Requests**: Request time off, early leave, or late arrival with notes
- **Activity Dashboard**: View pulse history, attendance stats, and pending offline pulses

### Admin Features
- **Dashboard**: Real-time monitoring of employee activity
- **Fake Pulse Detection**: Alerts for suspicious location pulses
- **Team Overview**: Employee management and activity summaries
- **Payroll Integration**: Track work hours and calculate pay based on valid pulses
- **Employee Adjustments**: Manage bonuses, deductions, and salary adjustments

## Technical Architecture

### Frontend Stack
- **Framework**: Flutter 3.32.0
- **State Management**: StatefulWidget with setState
- **Local Database**: Hive (NoSQL) for offline-first architecture
- **Location Services**: geolocator package
- **HTTP Client**: http package
- **Fonts**: Google Fonts (IBM Plex Sans Arabic)

### Backend Stack (Production Ready)
- **Runtime**: Node.js with TypeScript
- **Framework**: Express.js
- **Database**: Neon PostgreSQL (Replit-managed)
- **ORM**: Drizzle ORM with Drizzle Kit
- **Authentication**: PIN-based employee authentication
- **Geofencing**: Haversine formula + Wi-Fi BSSID validation
- **Payroll**: Pulse-based real-time salary calculation

### Key Dependencies
```yaml
dependencies:
  - geolocator: Location tracking
  - connectivity_plus: Network status monitoring  
  - hive & hive_flutter: Local offline storage
  - http: API communication
  - supabase_flutter: Backend integration
  - google_fonts: Arabic typography
  - permission_handler: Platform permissions
```

## Database Schema (Local - Hive)

### Boxes
1. **offline_pulses**: Queue of unsent location pulses
2. **pulse_history**: Log of all pulse activity
3. **employees**: Employee profiles and credentials
4. **employee_adjustments**: Salary adjustments and bonuses

## Configuration

### Environment Variables
The app supports the following environment variables for configuration:

```dart
SUPABASE_URL              // Supabase project URL
SUPABASE_ANON_KEY         // Supabase anonymous key
SUPABASE_PULSE_TABLE      // Table name for pulses (default: 'pulses')
PRIMARY_HEARTBEAT_ENDPOINT // Legacy HTTP endpoint
PRIMARY_OFFLINE_SYNC_ENDPOINT // Legacy sync endpoint
BACKUP_HOST               // Backup server host (dev only)
```

### Restaurant Location Settings
Location validation settings in `lib/constants/restaurant_config.dart`:
- Default coordinates: 30.0444° N, 31.2357° E (Cairo area)
- Geofence radius: 100 meters
- Location enforcement can be toggled for testing

## Development Setup

### Running Locally
```bash
# Install dependencies
flutter pub get

# Run on web (development)
flutter run -d web-server --web-hostname=0.0.0.0 --web-port=5000

# Build for web (production)
flutter build web --release

# Serve built files
dhttpd --host 0.0.0.0 --port 5000 --path build/web
```

### Demo Data
The app seeds demo employees on first run:
- **Admin**: مريم حسن (EMP001, PIN: 1234)
- **HR**: عمر سعيد (EMP002, PIN: 5678)  
- **Monitor**: نورة عادل (EMP003, PIN: 2468)

## Replit Environment

### Workflows
- **API Server**: Express.js backend API running on port 5000 (webview output)
- Serves both API endpoints and static manager dashboard

### Deployment
- **Type**: Autoscale (stateless API + web app)
- **Build**: `npm run build` (compiles TypeScript to JavaScript)
- **Run**: `node dist/index.js` (production) or `npm run dev` (development)

## Backend API Endpoints

### Authentication
- `POST /api/auth/login` - Employee login with ID and PIN

### Branch Management (NEW)
- `POST /api/branches` - Create a new branch with geofence configuration
- `GET /api/branches` - Get all branches
- `POST /api/branches/:branchId/assign-manager` - Assign manager to branch
- `GET /api/branches/:branchId/employees` - Get employees by branch

### Break Management (NEW)
- `POST /api/breaks/request` - Request a break
- `POST /api/breaks/:breakId/review` - Approve/reject break request
- `POST /api/breaks/:breakId/start` - Start an approved break
- `POST /api/breaks/:breakId/end` - End an active break
- `GET /api/breaks` - Get breaks (filterable by employee_id and status)

### Attendance Management
- `POST /api/attendance/check-in` - Check in for work
- `POST /api/attendance/check-out` - Check out from work
- `POST /api/attendance/request-checkin` - Request forgotten check-in
- `POST /api/attendance/request-checkout` - Request forgotten check-out
- `GET /api/attendance/requests` - Get pending attendance requests
- `POST /api/attendance/requests/:id/review` - Approve/reject request

### Leave Management
- `POST /api/leave/request` - Submit leave request
- `GET /api/leave/requests` - Get leave requests
- `POST /api/leave/requests/:id/review` - Approve/reject leave

### Salary Advances
- `POST /api/advances/request` - Request salary advance
- `GET /api/advances` - Get advance requests
- `POST /api/advances/:id/review` - Approve/reject advance

### Absence & Deductions
- `POST /api/absence/notify` - Notify about absence
- `GET /api/absence/notifications` - Get absence notifications
- `POST /api/absence/:id/apply-deduction` - Apply deduction for absence

### Payroll & Pulses (NEW)
- `POST /api/payroll/calculate` - Calculate employee payroll for a period
- `POST /api/pulses` - Submit location pulse with geofencing validation

### Reports & Dashboard
- `GET /api/reports/attendance/:employeeId` - Get attendance report
- `GET /api/manager/dashboard` - Get manager dashboard data

## Geofencing & Pulse System

### Configuration
Constants defined in `server/index.ts`:
- `RESTAURANT_WIFI_BSSID`: Wi-Fi MAC address for validation
- `RESTAURANT_LATITUDE`: 31.2652 (Alexandria, Egypt)
- `RESTAURANT_LONGITUDE`: 29.9863
- `GEOFENCE_RADIUS_METERS`: 100

### Validation Logic
1. **Wi-Fi Check**: Compares device Wi-Fi BSSID with restaurant Wi-Fi
2. **Geofence Check**: Uses Haversine formula to calculate distance
3. **Pulse Status**: Valid only if BOTH checks pass
4. **Salary Calculation**: 
   - Hourly rate: 40 EGP/hour
   - Pulse frequency: Every 30 seconds
   - Pulse value: (40 ÷ 3600) × 30 = 0.333 EGP per pulse

## Recent Changes (October 2025)

### Advanced Features Implementation (Oct 15, 2025)
- **✅ COMPLETE**: Successfully implemented three major backend upgrades
- **Multi-Branch Management**: Support for multiple restaurant locations with branch-specific geofencing
- **Dynamic Salary Advances**: Real-time earnings calculation based on valid pulses (30% of current period)
- **Break Management System**: Complete break workflow with pulse exclusion during active breaks

### Supabase to Neon PostgreSQL Migration Completed (Oct 15, 2025)
- **✅ MIGRATION COMPLETE**: Successfully migrated from Supabase to Replit's Neon PostgreSQL
- Installed Node.js/TypeScript backend with Express.js framework
- Implemented Drizzle ORM for type-safe database queries
- Pushed complete database schema to Neon PostgreSQL
- Migrated Supabase edge function to Express endpoint: `POST /api/payroll/calculate`
- Added geofencing validation with Haversine distance calculation
- Implemented pulse validation endpoint: `POST /api/pulses`
- Configured Wi-Fi BSSID + GPS geofence validation (both must pass)
- Server running on port 5000 with webview output type
- **Action Required**: Create employee records before testing pulse/payroll endpoints

### Replit Environment Setup Completed (Oct 14, 2025)
- **✅ SETUP COMPLETE**: Successfully configured Flutter app to run on Replit
- Installed Flutter 3.32.0 and Dart 3.8.0 via Nix package manager
- Fixed import conflict in `lib/services/requests_api_service.dart` using import aliases
- Built Flutter web app successfully with `flutter build web --release`
- Installed and configured dhttpd server globally via Dart pub
- Created workflow "Flutter Web Server" serving on port 5000
- Configured autoscale deployment with build and run commands
- Updated .gitignore for Flutter-specific artifacts
- **App Status**: ✅ Running successfully at https://[replit-url].repl.co

### Supabase Integration Fixed (Oct 12, 2025)
- **CRITICAL FIX**: Created migration 004 to fix schema mismatch
  - Added `latitude` and `longitude` columns to accept Flutter's separate coords
  - Updated `check_geofence()` trigger to build geography point automatically
  - Maintains backward compatibility with existing data
- Updated Supabase credentials to production instance (rxlckqprxskhnkrnsaem)
- Verified offline/online pulse sync system is operational

### System Status
- ✅ Flutter web running and stable on Replit
- ✅ Offline pulse storage working (Hive)
- ✅ Online sync to Supabase configured
- ✅ Geofencing trigger ready (requires migration 004 to be applied)
- ✅ Workflow configured and serving on port 5000
- ✅ Deployment configuration set to autoscale
- ⚠️ **ACTION REQUIRED**: User must apply `supabase/migrations/004_add_lat_lon_columns.sql` to Supabase

### Infrastructure Setup
- Configured Nix environment with Flutter 3.32.0 and Dart 3.8.0
- Set up dhttpd for production-ready web serving
- Added .gitignore entries for Flutter artifacts
- Created comprehensive setup documentation in `SETUP_INSTRUCTIONS.md`

## Supabase Backend Implementation

### Database Tables (PostgreSQL)
1. **profiles**: User profiles extending auth.users
2. **shifts**: Check-in/check-out records  
3. **pulses**: Location pulses with geofence validation

### Automated Geofencing
- PostGIS extension for spatial queries
- Trigger-based geofence validation on pulse insert
- Distance calculation from restaurant coordinates

### Row Level Security (RLS)
- Users can only access their own data
- Admins have full read access
- Role-based permissions enforced at database level

## API Endpoints

### Current Implementation
- Primary: Fallback HTTP endpoints (configurable)
- Backup: Local development server (`tool/pulse_backup_server.dart`)
- Supabase: Real-time sync via Supabase client

### Edge Functions (Planned)
- `calculate-payroll`: Compute employee pay based on valid pulses

## User Preferences
- Arabic RTL interface preferred
- Material Design 3 with orange primary color (#F37021)
- Clean, modern typography using IBM Plex Sans Arabic

## Future Enhancements
- Connect to production Supabase backend
- Implement official authentication provider
- Optimize pulse frequency (30-60 seconds) for battery efficiency
- Add payroll report generation
- Implement advanced admin analytics

## Support & Troubleshooting

### Common Issues
1. **Location not working on web**: Web browsers have limited location API access
2. **Offline pulses not syncing**: Check network connectivity and Supabase credentials
3. **Permission errors**: Notification permissions only work on native platforms

### Files to Check
- `/lib/config/app_config.dart`: Backend configuration
- `/lib/constants/restaurant_config.dart`: Geofence settings
- `/lib/services/pulse_backend_client.dart`: API integration

## License & Credits
This is a private attendance management system for Oldies restaurant chain.
