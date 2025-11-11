# BLV Real-time Integration Guide

## Overview
This guide shows how to integrate BLV (Behavioral Location Verification) real-time status updates into your employee screens.

## Quick Start

### 1. Simple Integration with BLVRealtimeStatusWidget

The easiest way to add BLV status with real-time updates:

```dart
import 'package:flutter/material.dart';
import '../widgets/blv_realtime_status_widget.dart';

class EmployeeHomePage extends StatelessWidget {
  final String employeeId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Compact status widget
          BLVRealtimeStatusWidget(
            employeeId: employeeId,
            compact: true,
            onTap: () {
              // Navigate to detailed BLV screen
              Navigator.push(context, ...);
            },
          ),

          // OR full status card
          BLVRealtimeStatusWidget(
            employeeId: employeeId,
            compact: false,
          ),
        ],
      ),
    );
  }
}
```

### 2. Advanced Integration with BLVProvider

For more control, use the BLVProvider directly:

```dart
import 'package:flutter/material.dart';
import '../providers/blv_provider.dart';
import '../widgets/blv_status_card.dart';
import '../widgets/blv_validation_history_list.dart';

class BLVStatusScreen extends StatefulWidget {
  final String employeeId;

  @override
  State<BLVStatusScreen> createState() => _BLVStatusScreenState();
}

class _BLVStatusScreenState extends State<BLVStatusScreen> {
  late BLVProvider _blvProvider;

  @override
  void initState() {
    super.initState();
    // Initialize provider - automatically starts real-time subscriptions
    _blvProvider = BLVProvider(employeeId: widget.employeeId);
    _blvProvider.addListener(_onUpdate);
  }

  @override
  void dispose() {
    _blvProvider.removeListener(_onUpdate);
    _blvProvider.dispose(); // Cleans up real-time subscriptions
    super.dispose();
  }

  void _onUpdate() {
    setState(() {}); // Rebuild when provider updates
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Status Card
          BLVStatusCard(
            status: _blvProvider.isCheckedIn ? 'Checked In' : 'Checked Out',
            lastScore: _blvProvider.lastScore,
            lastValidationType: _blvProvider.lastValidationType,
            lastValidationTime: _blvProvider.lastValidationTime,
            isLoading: _blvProvider.isLoading,
          ),

          // History List
          Expanded(
            child: BLVValidationHistoryList(
              events: _blvProvider.validationHistory,
              isLoading: _blvProvider.isLoading,
              onRefresh: () => _blvProvider.refresh(),
            ),
          ),
        ],
      ),
    );
  }
}
```

## Available Widgets

### BLVStatusCard
Large status card with gradient background showing current status and last score.
```dart
BLVStatusCard(
  status: 'Checked In',
  lastScore: 85,
  lastValidationType: 'Pulse',
  lastValidationTime: DateTime.now(),
)
```

### BLVQuickStatus
Compact status widget for home page.
```dart
BLVQuickStatus(
  isCheckedIn: true,
  lastScore: 85,
  onTap: () => navigateToDetails(),
)
```

### BLVValidationHistoryList
Scrollable list of validation events with date grouping.
```dart
BLVValidationHistoryList(
  events: validationEvents,
  isLoading: false,
  onRefresh: () async => await refresh(),
  groupByDate: true,
)
```

### BLVScoreBreakdown
Detailed breakdown of BLV component scores.
```dart
BLVScoreBreakdown(
  event: validationEvent,
)
```

## BLVProvider API

### Properties
- `latestValidation` - Most recent validation event
- `validationHistory` - List of all validation events
- `validationStats` - Statistics (total, approved, average score, etc.)
- `isLoading` - Loading state
- `currentStatus` - Current check-in status
- `lastScore` - Last BLV score (0-100)
- `isCheckedIn` - Boolean check-in state

### Methods
- `loadLatestValidation()` - Refresh latest validation
- `loadValidationHistory()` - Refresh history
- `loadTodayValidations()` - Get today's validations
- `loadWeekValidations()` - Get this week's validations
- `loadMonthValidations()` - Get this month's validations
- `refresh()` - Refresh all data

### Real-time Updates
The provider automatically:
- Subscribes to Supabase real-time channels on initialization
- Updates state when new validations occur
- Notifies listeners (triggers UI rebuild)
- Cleans up subscriptions on disposal

## Example: Full BLV Status Screen

See `lib/screens/employee/blv_status_example_screen.dart` for a complete implementation showing:
- Real-time status card
- Statistics summary
- Period filtering (All, Today, This Week, This Month)
- Validation history with pull-to-refresh
- Automatic updates when new events occur

## Integration Checklist

- [ ] Import required widgets and provider
- [ ] Initialize BLVProvider with employee ID
- [ ] Add listener for state updates
- [ ] Display status using BLVStatusCard or BLVQuickStatus
- [ ] Show history using BLVValidationHistoryList
- [ ] Implement refresh functionality
- [ ] Clean up provider in dispose()
- [ ] Test real-time updates by triggering check-in/pulse events

## Notes

- Real-time subscriptions are automatically managed by BLVProvider
- Subscriptions are cleaned up when provider is disposed
- All widgets handle null/empty states gracefully
- Date formatting is locale-independent
- Color coding: Green (80+), Orange (60-79), Red (<60)
