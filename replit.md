# Oldies Workers - Employee Attendance System

## Overview
**Oldies Workers** (أولديزز وركرز) is a comprehensive Flutter-based employee attendance tracking system with real-time location monitoring and pulse-based verification. The app features a mobile/web client for employees and an administrative dashboard for managers.

## Project Status
- **Language**: Dart 3.8.0 / Flutter 3.32.0
- **Platform**: Cross-platform (Web, Android, iOS, Desktop)
- **Current Setup**: Web deployment configured
- **Backend**: Supabase integration in progress

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

### Backend Stack (In Development)
- **Database**: Supabase (PostgreSQL with PostGIS)
- **Authentication**: Supabase Auth
- **Real-time**: Supabase Realtime subscriptions
- **Edge Functions**: TypeScript-based serverless functions
- **Geofencing**: PostGIS spatial queries for location validation

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
- **Flutter Web Server**: Serves the built web app on port 5000 using dhttpd

### Deployment
- **Type**: Autoscale (stateless web app)
- **Build**: `flutter build web --release`
- **Run**: `dhttpd --host 0.0.0.0 --port 5000 --path build/web`

## Recent Changes (October 2025)

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
