import Flutter
import UIKit
import GoogleMaps
import BackgroundTasks
import CoreLocation

@main
@objc class AppDelegate: FlutterAppDelegate, CLLocationManagerDelegate {
  private var locationManager: CLLocationManager?
  private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Google Maps API Key
    GMSServices.provideAPIKey("AIzaSyBXGZ8vQZ3q0YhJ8hF5K_9n7g_xN8Y3pQc")
    
    // Register plugins
    GeneratedPluginRegistrant.register(with: self)
    
    // ✅ V2: Initialize location manager for background tracking
    setupLocationManager()
    
    // ✅ V2: Register background tasks
    registerBackgroundTasks()
    
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
  
  // ✅ V2: Register background tasks for iOS 13+
  private func registerBackgroundTasks() {
    if #available(iOS 13.0, *) {
      BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.oldies.workers.geofence", using: nil) { task in
        self.handleGeofenceTask(task: task as! BGProcessingTask)
      }
      
      BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.oldies.workers.sync", using: nil) { task in
        self.handleSyncTask(task: task as! BGAppRefreshTask)
      }
    }
  }
  
  // ✅ V2: Schedule background tasks
  @available(iOS 13.0, *)
  private func scheduleBackgroundTasks() {
    // Schedule geofence task
    let geofenceRequest = BGProcessingTaskRequest(identifier: "com.oldies.workers.geofence")
    geofenceRequest.requiresNetworkConnectivity = false
    geofenceRequest.requiresExternalPower = false
    geofenceRequest.earliestBeginDate = Date(timeIntervalSinceNow: 5 * 60) // 5 minutes
    
    do {
      try BGTaskScheduler.shared.submit(geofenceRequest)
    } catch {
      print("Could not schedule geofence task: \(error)")
    }
    
    // Schedule sync task
    let syncRequest = BGAppRefreshTaskRequest(identifier: "com.oldies.workers.sync")
    syncRequest.earliestBeginDate = Date(timeIntervalSinceNow: 5 * 60) // 5 minutes
    
    do {
      try BGTaskScheduler.shared.submit(syncRequest)
    } catch {
      print("Could not schedule sync task: \(error)")
    }
  }
  
  // ✅ V2: Handle geofence background task
  @available(iOS 13.0, *)
  private func handleGeofenceTask(task: BGProcessingTask) {
    // Schedule next task
    scheduleBackgroundTasks()
    
    // Create background task
    let operationQueue = OperationQueue()
    operationQueue.maxConcurrentOperationCount = 1
    
    task.expirationHandler = {
      operationQueue.cancelAllOperations()
    }
    
    // The actual pulse logic will be handled by Flutter
    // This just keeps the app alive
    
    task.setTaskCompleted(success: true)
  }
  
  // ✅ V2: Handle sync background task
  @available(iOS 13.0, *)
  private func handleSyncTask(task: BGAppRefreshTask) {
    // Schedule next task
    scheduleBackgroundTasks()
    
    task.expirationHandler = {
      task.setTaskCompleted(success: false)
    }
    
    task.setTaskCompleted(success: true)
  }
  
  // Handle background fetch
  override func application(
    _ application: UIApplication,
    performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    // ✅ V2: Start background task to get more time
    backgroundTaskIdentifier = application.beginBackgroundTask(withName: "PulseFetch") {
      application.endBackgroundTask(self.backgroundTaskIdentifier)
      self.backgroundTaskIdentifier = .invalid
    }
    
    // The Flutter engine will handle the actual pulse
    completionHandler(.newData)
    
    // End background task after a delay
    DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
      if self.backgroundTaskIdentifier != .invalid {
        application.endBackgroundTask(self.backgroundTaskIdentifier)
        self.backgroundTaskIdentifier = .invalid
      }
    }
  }
  
  // ✅ V2: Handle significant location changes (for better background tracking)
  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    // Location updates are handled by Flutter plugins
  }
  
  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    print("Location manager error: \(error)")
  }
  
  // ✅ V2: Handle app entering background
  override func applicationDidEnterBackground(_ application: UIApplication) {
    super.applicationDidEnterBackground(application)
    
    // Start significant location monitoring for background
    locationManager?.startMonitoringSignificantLocationChanges()
    
    // Schedule background tasks on iOS 13+
    if #available(iOS 13.0, *) {
      scheduleBackgroundTasks()
    }
  }
  
  // ✅ V2: Handle app returning to foreground
  override func applicationWillEnterForeground(_ application: UIApplication) {
    super.applicationWillEnterForeground(application)
    
    // Stop significant location monitoring (regular tracking will resume)
    locationManager?.stopMonitoringSignificantLocationChanges()
  }
}
