import Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Google Maps API Key
    GMSServices.provideAPIKey("AIzaSyBXGZ8vQZ3q0YhJ8hF5K_9n7g_xN8Y3pQc")
    
    // Register plugins
    GeneratedPluginRegistrant.register(with: self)
    
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
    
    // Enable background fetch
    UIApplication.shared.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  // Handle background fetch
  override func application(
    _ application: UIApplication,
    performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    completionHandler(.newData)
  }
}
