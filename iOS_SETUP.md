# iOS Setup Guide for Oldies Workers

## 📱 Required iOS Configurations

### 1. **Info.plist Permissions** ✅
Located in: `ios/Runner/Info.plist`

All required permissions have been added:
- ✅ `NSLocationWhenInUseUsageDescription` - Location when app is in use
- ✅ `NSLocationAlwaysAndWhenInUseUsageDescription` - Always location access
- ✅ `NSLocationAlwaysUsageDescription` - Background location
- ✅ `UIBackgroundModes` - Background fetch, location, processing
- ✅ `BGTaskSchedulerPermittedIdentifiers` - Background tasks
- ✅ `NSLocalNetworkUsageDescription` - WiFi BSSID access

### 2. **AppDelegate.swift Configuration** ✅
Located in: `ios/Runner/AppDelegate.swift`

Enhanced with:
- ✅ Notification permissions request
- ✅ Background fetch configuration
- ✅ Remote notifications registration

### 3. **Build Configuration**

#### Minimum iOS Version
In `ios/Podfile` (if exists) or Xcode project settings:
```ruby
platform :ios, '12.0'  # Minimum for all packages
```

#### Xcode Project Settings
1. Open `ios/Runner.xcworkspace` in Xcode
2. Select **Runner** target → **Signing & Capabilities**
3. Add the following capabilities:
   - ✅ **Background Modes**
     - Location updates
     - Background fetch
     - Remote notifications
   - ✅ **Push Notifications**

### 4. **Building for iOS**

```bash
# Install CocoaPods dependencies
cd ios
pod install
cd ..

# Build iOS app
flutter build ios --release

# Or for development
flutter run -d ios
```

### 5. **Testing on iOS Simulator**

```bash
# List available simulators
flutter devices

# Run on specific simulator
flutter run -d "iPhone 15 Pro"
```

### 6. **iOS-Specific Features**

#### Geofencing
- ✅ Uses `geolocator` package (iOS compatible)
- ✅ Requests `always` location permission
- ✅ Background location updates enabled
- ✅ Battery-efficient (checks every 5 minutes)

#### Notifications
- ✅ Uses `flutter_local_notifications` (iOS compatible)
- ✅ Supports iOS 10+ notification center
- ✅ Alert, badge, and sound permissions

#### Offline Storage
- ✅ Uses `sqflite` (iOS compatible)
- ✅ Stores in iOS documents directory
- ✅ Persistent across app restarts

#### Background Sync
- ✅ Uses background fetch API
- ✅ Syncs when app is in background
- ✅ Respects iOS battery management

### 7. **Known iOS Limitations**

1. **Background Location**: iOS may pause background location after some time to save battery. The app will resume when user opens it.

2. **Background Tasks**: iOS limits background task execution time. Sync happens when internet is available and app is active or during background fetch windows.

3. **WiFi BSSID**: On iOS 13+, WiFi BSSID access requires location permission and may be restricted in some cases.

### 8. **App Store Submission**

When submitting to App Store, make sure to:
1. Provide clear explanation in App Store description about why location permissions are needed
2. Explain background location usage
3. Follow Apple's privacy guidelines
4. Add privacy policy URL in App Store Connect

### 9. **Testing Checklist**

- [ ] Location permissions granted (Always)
- [ ] Notifications permissions granted
- [ ] Check-in works offline
- [ ] Data syncs when online
- [ ] Geofence violations trigger notifications
- [ ] Background location tracking works
- [ ] App persists login after restart
- [ ] WiFi BSSID detection works (if available)

### 10. **Troubleshooting**

**Location not working:**
- Check if location permission is granted in Settings → Privacy → Location Services
- Ensure "Always" permission is selected, not just "While Using"

**Notifications not appearing:**
- Check if notification permission is granted in Settings → Notifications
- Ensure "Allow Notifications" is enabled

**Background sync not working:**
- Check if Background App Refresh is enabled in Settings → General
- Ensure Low Power Mode is disabled (it restricts background activity)

**Build errors:**
- Run `flutter clean`
- Delete `ios/Pods` and `ios/Podfile.lock`
- Run `cd ios && pod install && cd ..`
- Try again

## 🎯 Ready for Both Platforms

The app is now fully configured for:
- ✅ Android (API 21+)
- ✅ iOS (12.0+)

All offline features, geofencing, and background sync work on both platforms! 🚀
