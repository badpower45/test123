# Oldies Workers - Employee Attendance System

نظام حضور وانصراف الموظفين مع تتبع الموقع الجغرافي

## Overview

Oldies Workers is a comprehensive employee attendance tracking system with real-time location monitoring and pulse-based verification. The system includes a Flutter mobile/web app for employees and a Node.js backend API with geofencing capabilities.

## Tech Stack

- **Frontend**: Flutter 3.32.0 (Dart 3.8.0)
- **Backend**: Node.js/TypeScript with Express.js
- **Database**: Neon PostgreSQL (Replit-managed)
- **ORM**: Drizzle ORM

## Quick Start

### Development

```bash
# Install dependencies
npm install

# Start the API server (port 5000)
npm run dev

# Push database schema
npm run db:push
```

### API Endpoints

The server provides the following main endpoints:

- **Authentication**: `POST /api/auth/login`
- **Attendance**: `POST /api/attendance/check-in`, `POST /api/attendance/check-out`
- **Pulses**: `POST /api/pulses` - Submit location pulse with geofencing
- **Payroll**: `POST /api/payroll/calculate` - Calculate employee salary
- **Dashboard**: `GET /manager-dashboard.html` - Manager dashboard

### Initial Setup

- On first run, the system creates a default owner account (ID: OWNER001, PIN: 1234).
- Use this account to log in as owner and add employees via the owner interface.
- No demo employees are included; all data is managed through the owner dashboard.

### Geofencing System

The system validates employee location using:
- Wi-Fi BSSID verification
- GPS coordinates (Haversine distance calculation)
- 100-meter geofence radius
- Both checks must pass for a valid pulse

### Pulse-Based Payroll

- Hourly rate: 40 EGP/hour
- Pulse frequency: Every 30 seconds
- Pulse value: 0.333 EGP per valid pulse

## Project Structure

```
├── server/          # Express.js API server
├── shared/          # Shared TypeScript schemas
├── lib/             # Flutter app source
├── public/          # Static web files
├── migrations/      # Database migrations
└── supabase/        # Legacy Supabase files (archived)
```

## Documentation

See `replit.md` for detailed documentation including:
- Complete API reference
- Database schema
- Migration history
- Deployment instructions

## License

Private - Oldies Restaurant Chain
