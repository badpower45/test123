import Flutter
import UIKit
import GoogleMaps
import CoreLocation
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, CLLocationManagerDelegate {
  private var locationManager: CLLocationManager?
  private let iosPeriodicPulseTaskIdentifier = "com.oldies.attendance.full.pulse.periodic"
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Google Maps API Key
    GMSServices.provideAPIKey("AIzaSyBXGZ8vQZ3q0YhJ8hF5K_9n7g_xN8Y3pQc")
    
    // Register plugins
    GeneratedPluginRegistrant.register(with: self)

    // Ensure background isolates can register plugins when Workmanager runs in background.
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }

    if #available(iOS 13.0, *) {
      WorkmanagerPlugin.registerPeriodicTask(
        withIdentifier: iosPeriodicPulseTaskIdentifier,
        frequency: NSNumber(value: 15 * 60)
      )
    }
    
    // ✅ V2: Initialize location manager for background tracking
    setupLocationManager()
    
    // Request notification permissions
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
      
      let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
      UNUserNotificationCenter.current().requestAuthorization(
        options: authOptions,
        completionHandler: { _, _ in }
      )
    } else {
      let settings: UIUserNotificationSettings =
        UIUserNotificationSettings(types: [.alert, .badge, .sound], categories: nil)
      application.registerUserNotificationSettings(settings)
    }
    
    application.registerForRemoteNotifications()
    
    // Enable background fetch - set minimum interval
    UIApplication.shared.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  // ✅ V2: Setup location manager for continuous background tracking
  private func setupLocationManager() {
    locationManager = CLLocationManager()
    locationManager?.delegate = self
    locationManager?.desiredAccuracy = kCLLocationAccuracyHundredMeters
    locationManager?.distanceFilter = 100 // Update every 100 meters
    locationManager?.allowsBackgroundLocationUpdates = true
    locationManager?.pausesLocationUpdatesAutomatically = false
    locationManager?.showsBackgroundLocationIndicator = true
    
    // Request always authorization for background tracking
    if CLLocationManager.authorizationStatus() == .notDetermined {
      locationManager?.requestAlwaysAuthorization()
    }
  }
  
  // ✅ V2: Handle significant location changes (for better background tracking)
  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    // Location updates are handled by Flutter plugins
  }
  
  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    print("Location manager error: \(error)")
  }

  func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
    if status == .authorizedAlways {
      manager.startUpdatingLocation()
    }
  }
  
  // ✅ V2: Handle app entering background
  override func applicationDidEnterBackground(_ application: UIApplication) {
    super.applicationDidEnterBackground(application)
    
    // Start significant location monitoring for background
    locationManager?.startMonitoringSignificantLocationChanges()
  }
  
  // ✅ V2: Handle app returning to foreground
  override func applicationWillEnterForeground(_ application: UIApplication) {
    super.applicationWillEnterForeground(application)
    
    // Stop significant location monitoring (regular tracking will resume)
    locationManager?.stopMonitoringSignificantLocationChanges()
  }
}
