import Flutter
import UIKit
import stream_video_push_notification

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Stream's delegate owns the single PushKit registry and forwards native
    // CallKit actions to the Flutter push manager. Do not add a second registry.
    StreamVideoPKDelegateManager.shared.registerForPushNotifications()
    return super.application(
      application,
      didFinishLaunchingWithOptions: launchOptions
    )
  }
}
