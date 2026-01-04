# 🎯 Build Flavors Setup - Usage Guide

## Overview

The app now has two build flavors:
- **lite**: Lightweight version for Employees/Managers (without BLV and Google Maps)
- **full**: Full-featured version for Owners (with all features)

## ✅ What Was Changed

### 1. Android Configuration (`android/app/build.gradle.kts`)

Added flavor dimensions and product flavors:
```kotlin
flavorDimensions += "version"
productFlavors {
    create("lite") {
        dimension = "version"
        applicationIdSuffix = ".lite"
        versionNameSuffix = "-lite"
    }
    
    create("full") {
        dimension = "version"
    }
}
```

### 2. Dart Configuration (`lib/core/config/build_config.dart`)

Created a comprehensive configuration file with:
- Flavor detection
- Feature flags (BLV, Google Maps, etc.)
- Performance settings
- UI customization

## 🚀 How to Build

### Build Lite Version (for Employees/Managers)
```bash
# Debug
flutter run --flavor lite --dart-define=FLAVOR=lite

# Release
flutter build apk --flavor lite --dart-define=FLAVOR=lite --release

# App Bundle
flutter build appbundle --flavor lite --dart-define=FLAVOR=lite --release
```

### Build Full Version (for Owners)
```bash
# Debug
flutter run --flavor full --dart-define=FLAVOR=full

# Release
flutter build apk --flavor full --dart-define=FLAVOR=full --release

# App Bundle
flutter build appbundle --flavor full --dart-define=FLAVOR=full --release
```

## 📝 How to Use in Code

### 1. Initialize in main.dart

Add this at the beginning of your `main()` function:

```dart
import 'core/config/build_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Detect and configure build flavor
  await BuildConfig.detectFlavor();
  BuildConfig.printConfig(); // Print config for debugging
  
  // Your existing initialization code...
}
```

### 2. Use Feature Flags

```dart
import 'package:heartbeat/core/config/build_config.dart';

// Check if BLV is supported before initializing
if (BuildConfig.supportsBLV) {
  await BLVService.initialize();
} else {
  print('BLV not available in Lite version');
}

// Check Google Maps support
if (BuildConfig.supportsGoogleMaps) {
  // Show Google Maps
} else {
  // Show alternative (static map or text-based location)
}

// Use adaptive pulse interval
final interval = BuildConfig.pulseInterval; // 10 min for lite, 5 min for full
PulseService.setInterval(interval);
```

### 3. Conditional Imports (Optional)

For even better optimization, you can use conditional imports:

```dart
// lib/services/blv_service.dart (only for full version)
import 'package:heartbeat/core/config/build_config.dart';

class BLVService {
  static Future<void> initialize() async {
    if (!BuildConfig.supportsBLV) {
      print('⚠️ BLV not supported in this build');
      return;
    }
    
    // Initialize BLV...
  }
}
```

## 📦 Package Structure

```
lib/
├── core/
│   └── config/
│       └── build_config.dart  ✅ NEW - Build flavor configuration
├── config/
│   ├── app_config.dart
│   └── supabase_config.dart
└── main.dart
```

## 🎨 App Differences

| Feature | Lite Version | Full Version |
|---------|-------------|--------------|
| **App ID** | `com.example.heartbeat.lite` | `com.example.heartbeat` |
| **App Name** | Heartbeat Lite | Heartbeat |
| **BLV System** | ❌ Disabled | ✅ Enabled |
| **Google Maps** | ❌ Disabled | ✅ Enabled |
| **Sensors** | ❌ Basic only | ✅ Advanced |
| **Pulse Interval** | 10 minutes | 5 minutes |
| **Location Updates** | 5 minutes | 1 minute |
| **Cache Size** | 50MB | 200MB |
| **Image Quality** | 60% | 90% |
| **APK Size** | ~20-25MB | ~35-40MB |

## 🧪 Testing

### Test Flavor Detection
```dart
void testFlavorConfig() {
  print('Current Flavor: ${BuildConfig.flavor}');
  print('Is Lite: ${BuildConfig.isLite}');
  print('Is Full: ${BuildConfig.isFull}');
  print('Supports BLV: ${BuildConfig.supportsBLV}');
  print('Supports Google Maps: ${BuildConfig.supportsGoogleMaps}');
  
  BuildConfig.printConfig(); // Print all config
}
```

### Check Build Info at Runtime
```dart
// In your app, add a debug screen to show build info
Widget buildDebugInfo() {
  return Column(
    children: [
      Text('App: ${BuildConfig.appName}'),
      Text('Flavor: ${BuildConfig.flavor}'),
      Text('BLV: ${BuildConfig.supportsBLV ? "✅" : "❌"}'),
      Text('Maps: ${BuildConfig.supportsGoogleMaps ? "✅" : "❌"}'),
      Text('Pulse: ${BuildConfig.pulseInterval.inMinutes} min'),
    ],
  );
}
```

## 🔄 VS Code Launch Configuration (Optional)

Create `.vscode/launch.json`:

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Lite (Debug)",
      "request": "launch",
      "type": "dart",
      "program": "lib/main.dart",
      "args": [
        "--flavor", "lite",
        "--dart-define=FLAVOR=lite"
      ]
    },
    {
      "name": "Full (Debug)",
      "request": "launch",
      "type": "dart",
      "program": "lib/main.dart",
      "args": [
        "--flavor", "full",
        "--dart-define=FLAVOR=full"
      ]
    },
    {
      "name": "Lite (Release)",
      "request": "launch",
      "type": "dart",
      "program": "lib/main.dart",
      "flutterMode": "release",
      "args": [
        "--flavor", "lite",
        "--dart-define=FLAVOR=lite"
      ]
    },
    {
      "name": "Full (Release)",
      "request": "launch",
      "type": "dart",
      "program": "lib/main.dart",
      "flutterMode": "release",
      "args": [
        "--flavor", "full",
        "--dart-define=FLAVOR=full"
      ]
    }
  ]
}
```

## 📱 Testing on Device

1. **Uninstall any previous version** first to avoid conflicts
2. **Build and install Lite version**:
   ```bash
   flutter build apk --flavor lite --dart-define=FLAVOR=lite
   flutter install --flavor lite
   ```
3. **Verify**: Check Settings → Apps → should see "Heartbeat Lite"
4. **Both versions can be installed simultaneously** (different app IDs)

## ⚠️ Important Notes

1. **Both flavors can coexist** on the same device (different applicationId)
2. **Flavor must be specified** for every build command
3. **Use `--dart-define=FLAVOR=<flavor>`** to pass flavor to Dart code
4. **Clean build if switching flavors**:
   ```bash
   flutter clean
   flutter pub get
   ```

## 🐛 Troubleshooting

### Issue: "No flavor dimension specified"
**Solution**: Make sure you're using `--flavor` flag:
```bash
flutter run --flavor lite --dart-define=FLAVOR=lite
```

### Issue: Features not disabled in Lite version
**Solution**: Check if `BuildConfig.detectFlavor()` is called in main():
```dart
await BuildConfig.detectFlavor();
```

### Issue: Both apps have same name/icon
**Solution**: 
1. Lite version automatically gets ".lite" suffix in app ID
2. To change app name/icon per flavor, create flavor-specific resources:
   - `android/app/src/lite/res/values/strings.xml`
   - `android/app/src/full/res/values/strings.xml`

## 🎯 Next Steps

1. ✅ Build flavors configured
2. ✅ Feature flags created
3. 🔄 Update main.dart to call `BuildConfig.detectFlavor()`
4. 🔄 Add conditional feature initialization
5. 🔄 Test both flavors on real devices
6. 🔄 Configure ProGuard rules for both flavors
7. 🔄 Setup CI/CD to build both flavors

---

**Created**: January 4, 2026  
**Status**: ✅ Ready to use  
**Next**: Update main.dart and test builds
