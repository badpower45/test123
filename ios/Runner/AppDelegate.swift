import Flutter
import UIKit
import GoogleMaps
import CoreLocation
import workmanager_apple
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, CLLocationManagerDelegate {
  private var locationManager: CLLocationManager?
  private let iosPeriodicPulseTaskIdentifier = "com.oldies.attendance.full.pulse.periodic"
  
  // Background Task Management for OS Watchdog (0x8badf00d) prevention
  private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
  private var isTrackingActive = false
  
  // Headless Engine for surviving Force-Quit (Swipe-Up)
  private var headlessEngine: FlutterEngine?
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Google Maps API Key
    GMSServices.provideAPIKey("AIzaSyBXGZ8vQZ3q0YhJ8hF5K_9n7g_xN8Y3pQc")
    
    // Register plugins
    GeneratedPluginRegistrant.register(with: self)

    // Setup Method Channels
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    setupPulseMethodChannel(binaryMessenger: controller.binaryMessenger)
    setupGeofenceBackgroundMethodChannel(binaryMessenger: controller.binaryMessenger)

    // Workmanager setup
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }

    if #available(iOS 13.0, *) {
      WorkmanagerPlugin.registerPeriodicTask(
        withIdentifier: iosPeriodicPulseTaskIdentifier,
        frequency: NSNumber(value: 15 * 60)
      )
    }
    
    // Setup location manager for continuous background tracking & hardware geofences
    setupLocationManager()
    
    // Directives 3: Low Power Mode (LPM) Observer Registration
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handlePowerStateChange),
      name: NSNotification.Name.NSProcessInfoPowerStateDidChange,
      object: nil
    )
    
    // Request notification permissions
    setupNotificationCenter()
    
    // Directive 1: Handle Force-Quit Relaunch by iOS Location / Geofence Event
    if launchOptions?[.location] != nil {
      print("🚀 [OS Geofence] App woken up in background by iOS after Force-Quit / Location Event")
      beginNativeBackgroundTask()
      ensureHeadlessEngineRunning()
    }
    
    // Enable background fetch - set minimum interval
    UIApplication.shared.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  // MARK: - Method Channel Configuration
  
  private func setupPulseMethodChannel(binaryMessenger: FlutterBinaryMessenger) {
    let pulseChannel = FlutterMethodChannel(name: "persistent_pulse", binaryMessenger: binaryMessenger)
    pulseChannel.setMethodCallHandler({
      [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      guard let self = self else { return }
      
      switch call.method {
      case "startPersistentService":
          self.startBackgroundLocationTracking()
          result(true)
      case "stopPersistentService":
          self.stopBackgroundLocationTracking()
          result(true)
      case "startMonitoringRegion":
          if let args = call.arguments as? [String: Any],
             let lat = args["latitude"] as? Double,
             let lng = args["longitude"] as? Double,
             let radius = args["radius"] as? Double,
             let identifier = args["identifier"] as? String {
            self.startMonitoringHardwareRegion(latitude: lat, longitude: lng, radius: radius, identifier: identifier)
            result(true)
          } else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing latitude, longitude, radius, or identifier", details: nil))
          }
      case "stopMonitoringRegion":
          if let args = call.arguments as? [String: Any],
             let identifier = args["identifier"] as? String {
            self.stopMonitoringHardwareRegion(identifier: identifier)
            result(true)
          } else {
            self.stopAllHardwareRegions()
            result(true)
          }
      case "beginBackgroundTask":
          self.beginNativeBackgroundTask()
          result(true)
      case "endBackgroundTask":
          self.endNativeBackgroundTask()
          result(true)
      case "isServiceRunning":
          result(self.isTrackingActive)
      case "getPulseStats":
          let stats: [String: Any] = [
              "pulse_count": 0,
              "last_pulse_time": Int(Date().timeIntervalSince1970 * 1000),
              "service_uptime": 0,
              "tracking_active": self.isTrackingActive,
              "low_power_mode": ProcessInfo.processInfo.isLowPowerModeEnabled
          ]
          result(stats)
      default:
          result(FlutterMethodNotImplemented)
      }
    })
  }
  
  private func setupGeofenceBackgroundMethodChannel(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "geofence_background_channel", binaryMessenger: binaryMessenger)
    channel.setMethodCallHandler { call, result in
      if call.method == "backgroundChannelReady" {
        print("✅ Headless Geofence Background Channel Ready")
        result(true)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }
  
  // MARK: - Directive 1: OS-Level Region Monitoring (CLCircularRegion)
  
  private func setupLocationManager() {
    locationManager = CLLocationManager()
    locationManager?.delegate = self
    locationManager?.desiredAccuracy = kCLLocationAccuracyHundredMeters
    locationManager?.distanceFilter = 100
    locationManager?.allowsBackgroundLocationUpdates = true
    locationManager?.pausesLocationUpdatesAutomatically = false // Strictly false
    locationManager?.showsBackgroundLocationIndicator = true
    
    let status = CLLocationManager.authorizationStatus()
    if status == .notDetermined {
      locationManager?.requestAlwaysAuthorization()
    } else if status == .authorizedAlways || status == .authorizedWhenInUse {
      locationManager?.startUpdatingLocation()
      isTrackingActive = true
    }
  }
  
  public func startMonitoringHardwareRegion(latitude: Double, longitude: Double, radius: Double, identifier: String) {
    guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
      print("❌ Hardware CLCircularRegion monitoring is not available on this device")
      return
    }
    
    let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    let maxRadius = min(radius, locationManager?.maximumRegionMonitoringDistance ?? 1000.0)
    let region = CLCircularRegion(center: center, radius: maxRadius, identifier: identifier)
    region.notifyOnEntry = true
    region.notifyOnExit = true
    
    locationManager?.startMonitoring(for: region)
    print("✅ [OS Hardware Geofence] Monitoring registered: \(identifier) (Lat: \(latitude), Lng: \(longitude), Radius: \(maxRadius)m)")
  }
  
  public func stopMonitoringHardwareRegion(identifier: String) {
    guard let monitored = locationManager?.monitoredRegions else { return }
    for region in monitored {
      if region.identifier == identifier {
        locationManager?.stopMonitoring(for: region)
        print("🛑 [OS Hardware Geofence] Stopped region: \(identifier)")
      }
    }
  }
  
  public func stopAllHardwareRegions() {
    guard let monitored = locationManager?.monitoredRegions else { return }
    for region in monitored {
      locationManager?.stopMonitoring(for: region)
    }
    print("🛑 [OS Hardware Geofence] Stopped all monitored regions")
  }
  
  // MARK: - CLLocationManagerDelegate (Region Monitoring Delegates)
  
  func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
    print("📍 [OS Hardware Geofence] Entered Region: \(region.identifier)")
    handleGeofenceRegionEvent(regionId: region.identifier, eventType: "didEnterRegion")
  }
  
  func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
    print("📍 [OS Hardware Geofence] Exited Region: \(region.identifier)")
    handleGeofenceRegionEvent(regionId: region.identifier, eventType: "didExitRegion")
  }
  
  func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
    print("❌ [OS Hardware Geofence] Monitoring failed for \(region?.identifier ?? "unknown"): \(error.localizedDescription)")
  }
  
  // MARK: - Directive 2: Headless Flutter Execution & Event Forwarding
  
  private func handleGeofenceRegionEvent(regionId: String, eventType: String) {
    beginNativeBackgroundTask()
    
    let payload: [String: Any] = [
      "regionId": regionId,
      "eventType": eventType,
      "timestamp": Int(Date().timeIntervalSince1970 * 1000)
    ]
    
    if let controller = window?.rootViewController as? FlutterViewController {
      // Warm Engine Path
      let channel = FlutterMethodChannel(name: "geofence_background_channel", binaryMessenger: controller.binaryMessenger)
      channel.invokeMethod("onGeofenceRegionEvent", arguments: payload)
    } else {
      // Headless Engine Path (Survives Force-Quit / Swipe-Up)
      ensureHeadlessEngineRunning()
      if let engine = headlessEngine {
        let channel = FlutterMethodChannel(name: "geofence_background_channel", binaryMessenger: engine.binaryMessenger)
        channel.invokeMethod("onGeofenceRegionEvent", arguments: payload)
      }
    }
  }
  
  private func ensureHeadlessEngineRunning() {
    if headlessEngine != nil { return }
    
    print("⚡ Starting Headless Flutter Engine for Background Geofence Processing...")
    headlessEngine = FlutterEngine(name: "HeadlessGeofenceEngine")
    headlessEngine?.run(withEntrypoint: "backgroundGeofenceEntryPoint", libraryURI: "main.dart")
    
    if let engine = headlessEngine {
      GeneratedPluginRegistrant.register(with: engine)
      setupGeofenceBackgroundMethodChannel(binaryMessenger: engine.binaryMessenger)
    }
  }
  
  // MARK: - Directive 3: Low Power Mode (LPM) Mitigation
  
  @objc private func handlePowerStateChange() {
    if ProcessInfo.processInfo.isLowPowerModeEnabled {
      print("⚠️ Low Power Mode (LPM) Enabled by user!")
      sendLowPowerModeNotification()
    } else {
      print("ℹ️ Low Power Mode (LPM) Disabled")
    }
  }
  
  private func sendLowPowerModeNotification() {
    let content = UNMutableNotificationContent()
    content.title = "⚠️ وضع توفير الطاقة مفعّل"
    content.body = "قد يقلل وضع توفير الطاقة من دقة تتبع الحضور والموقع. يرجى إيقافه لضمان تسجيل ساعات عملك بدقة."
    content.sound = UNNotificationSound.default
    
    let request = UNNotificationRequest(
      identifier: "LowPowerModeWarning_\(Date().timeIntervalSince1970)",
      content: content,
      trigger: nil
    )
    
    UNUserNotificationCenter.current().add(request) { error in
      if let error = error {
        print("❌ Error presenting LPM Notification: \(error.localizedDescription)")
      } else {
        print("✅ LPM Notification dispatched successfully")
      }
    }
  }
  
  // MARK: - Native Background Task Expiration Handlers (Prevents Watchdog 0x8badf00d)
  
  private func startBackgroundLocationTracking() {
    beginNativeBackgroundTask()
    locationManager?.startUpdatingLocation()
    isTrackingActive = true
    print("✅ iOS Native background location tracking started")
  }
  
  private func stopBackgroundLocationTracking() {
    locationManager?.stopUpdatingLocation()
    locationManager?.stopMonitoringSignificantLocationChanges()
    isTrackingActive = false
    endNativeBackgroundTask()
    print("🛑 iOS Native background location tracking stopped")
  }
  
  private func beginNativeBackgroundTask() {
    if backgroundTaskID != .invalid { return }
    
    backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "OldiesWorkersPulseTask") { [weak self] in
      print("⚠️ OS Background Task Expiration Warning - ending task safely")
      self?.endNativeBackgroundTask()
    }
    
    DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak self] in
      self?.endNativeBackgroundTask()
    }
  }
  
  private func endNativeBackgroundTask() {
    if backgroundTaskID != .invalid {
      UIApplication.shared.endBackgroundTask(backgroundTaskID)
      backgroundTaskID = .invalid
    }
  }
  
  private func setupNotificationCenter() {
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
      let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
      UNUserNotificationCenter.current().requestAuthorization(options: authOptions, completionHandler: { _, _ in })
    } else {
      let settings: UIUserNotificationSettings = UIUserNotificationSettings(types: [.alert, .badge, .sound], categories: nil)
      UIApplication.shared.registerUserNotificationSettings(settings)
    }
    UIApplication.shared.registerForRemoteNotifications()
  }
  
  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    beginNativeBackgroundTask()
  }
  
  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    print("Location manager error: \(error.localizedDescription)")
  }

  func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
    if status == .authorizedAlways || status == .authorizedWhenInUse {
      manager.startUpdatingLocation()
      isTrackingActive = true
    }
  }
  
  override func applicationDidEnterBackground(_ application: UIApplication) {
    super.applicationDidEnterBackground(application)
    beginNativeBackgroundTask()
  }
  
  override func applicationWillEnterForeground(_ application: UIApplication) {
    super.applicationWillEnterForeground(application)
    endNativeBackgroundTask()
  }
}
