# Oldies Workers - Employee Attendance System

## Overview
**Oldies Workers** (أولديزز وركرز) is a comprehensive Flutter-based employee attendance tracking system designed for the Oldies restaurant chain. It features real-time location monitoring, a "pulse" based verification system, and supports both mobile/web clients for employees and an administrative dashboard for managers. The system aims to streamline attendance, payroll, and employee management with capabilities like geo-fenced check-ins, continuous location tracking, offline support, and advanced administrative controls.

## User Preferences
- Arabic RTL interface preferred
- Material Design 3 with orange primary color (#F37021)
- Clean, modern typography using IBM Plex Sans Arabic

## System Architecture

### UI/UX Decisions
The application uses Material Design 3 principles with a primary orange color scheme (#F37021) and the IBM Plex Sans Arabic font for a clean, modern, and Arabic RTL-friendly interface.

### Technical Implementations
- **Frontend**: Built with Flutter 3.32.0, utilizing `StatefulWidget` with `setState` for state management, and Hive (NoSQL) for robust offline data storage. Location services are handled by the `geolocator` package.
- **Backend**: Developed with Node.js and TypeScript using Express.js, leveraging Neon PostgreSQL (Replit-managed) as the primary database with Drizzle ORM for type-safe interactions.
- **Core Features**:
    - **Location-Based Attendance**: Geo-fence validation (Haversine formula + Wi-Fi BSSID) for check-in/check-out and continuous "pulse" tracking.
    - **Offline-First**: Hive database stores offline pulses and data, syncing automatically upon connection.
    - **Permission Requests**: Employees can request time off, early leave, or late arrivals.
    - **Comprehensive Admin Controls**: Real-time monitoring, fake pulse detection, employee management, payroll integration (pulse-based salary calculation), and adjustments.
    - **Multi-Branch Support**: Manages multiple restaurant locations with branch-specific geofencing.
    - **Break Management**: Full workflow for requesting, approving, starting, and ending breaks, with pulse exclusion during active breaks.
    - **Hierarchical Approvals**: Role-based approval workflows for requests (Staff → Manager; Manager/HR → Owner/Admin).
    - **Smart Absence Management**: Automated deduction logic (e.g., 2 days salary for unapproved absence).
    - **Comprehensive Reporting**: Detailed salary reports based on valid pulses, advances, deductions, and leave allowances.
    - **Shift Management**: Tools to view active employees, force auto-checkout, and generate daily attendance sheets.

### System Design Choices
- **Authentication**: PIN-based system for employee login.
- **Geofencing**: Combines GPS coordinates with Wi-Fi BSSID validation for enhanced accuracy.
- **Payroll Logic**: Salary is calculated based on validated location pulses (40 EGP/hour, 0.333 EGP per 30-second pulse).
- **Deduction Rules**: Specific rules for absence (e.g., 2 days salary deduction for unauthorized absence), and allowances for approved leave.
- **Environment**: Optimized for Replit deployment, utilizing Replit's Neon PostgreSQL integration and autoscale deployment.

## External Dependencies

- **Database**: Neon PostgreSQL (Replit-managed)
- **ORM**: Drizzle ORM
- **Location Services**: `geolocator` package (Flutter)
- **Offline Storage**: Hive & `hive_flutter` (Flutter)
- **Network Status**: `connectivity_plus` (Flutter)
- **HTTP Client**: `http` package (Flutter)
- **Font Integration**: `google_fonts` (Flutter)
- **Permissions**: `permission_handler` (Flutter)
- **Backend Framework**: Express.js (Node.js/TypeScript)
- **Legacy/Reference Backend (Not in active use)**: Supabase (files retained for reference)