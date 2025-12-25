# Employee Home Page BLV Integration Guide

## Quick Integration Steps

### Step 1: Add Import Statements

Add these imports to `employee_home_page.dart`:

```dart
import '../../widgets/blv_realtime_status_widget.dart';
import 'employee_blv_status_screen.dart';
```

### Step 2: Add BLV Quick Status Widget to Home Page

Add the BLV quick status widget in the home page body. Recommended location: After the check-in/out button section.

```dart
// Inside the build method, after check-in/out buttons:

// BLV Status Quick View
Padding(
  padding: const EdgeInsets.all(16),
  child: BLVRealtimeStatusWidget(
    employeeId: widget.employeeId,
    compact: true,
    onTap: () {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => EmployeeBLVStatusScreen(
            employeeId: widget.employeeId,
          ),
        ),
      );
    },
  ),
),
```

### Step 3: (Optional) Add Navigation MenuItem

If you have a drawer or bottom navigation, add a menu item for BLV status:

```dart
ListTile(
  leading: const Icon(Icons.verified_user),
  title: const Text('BLV Status'),
  subtitle: const Text('View verification history'),
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EmployeeBLVStatusScreen(
          employeeId: widget.employeeId,
        ),
      ),
    );
  },
),
```

## Complete Example

Here's a complete example showing where to place the BLV widget in the employee home page:

```dart
@override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(
      title: const Text('Home'),
    ),
    body: SingleChildScrollView(
      child: Column(
        children: [
          // Existing check-in/out section
          _buildCheckInOutSection(),

          const SizedBox(height: 16),

          // ⭐ BLV Status Quick View - ADD THIS
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: BLVRealtimeStatusWidget(
              employeeId: widget.employeeId,
              compact: true,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => EmployeeBLVStatusScreen(
                      employeeId: widget.employeeId,
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 16),

          // Rest of your existing widgets
          _buildStatistics(),
          _buildRecentActivity(),
          // ...
        ],
      ),
    ),
  );
}
```

## Alternative: Full Status Card on Home Page

If you prefer showing the full status card instead of the compact view:

```dart
BLVRealtimeStatusWidget(
  employeeId: widget.employeeId,
  compact: false, // Show full card
),
```

## Features Included

When integrated, employees will see:

✅ **Real-time Updates**: Status updates automatically when check-ins/pulses occur
✅ **Current Status**: Shows if checked in, out, or other states
✅ **Last BLV Score**: Displays the most recent verification score
✅ **Tap to View Details**: Opens full BLV status screen with history
✅ **Color Coding**: Green (good), Orange (fair), Red (needs attention)

## Testing

After integration:

1. **Test Initial Load**: Open employee home page, verify BLV status shows
2. **Test Navigation**: Tap on BLV status, verify detailed screen opens
3. **Test Real-time**: Perform check-in/out, verify status updates automatically
4. **Test Offline**: Disconnect internet, verify graceful handling
5. **Test Empty State**: Test with employee who has no validation history

## Troubleshooting

### Widget not showing?
- Verify imports are added correctly
- Check that employeeId is being passed
- Look for errors in console

### Status not updating in real-time?
- Check Supabase connection
- Verify real-time is enabled in Supabase dashboard
- Check console for subscription errors

### Navigation not working?
- Verify both screen imports are present
- Check Navigator.push syntax

## Notes

- The widget automatically handles loading states
- No manual refresh needed - updates happen via Supabase real-time
- Widget cleans up subscriptions when disposed
- Supports both Arabic and English text (based on app locale)



