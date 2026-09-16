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

    // Stream's delegate owns the single PushKit registry and forwards its
    // actions through flutter_callkit_incoming, which Dart already observes.
    // A second custom PKPushRegistry/CXProvider previously produced duplicate
    // calls and sent actions to a method channel with no Dart consumer.
    StreamVideoPKDelegateManager.shared.registerForPushNotifications()
    return super.application(
      application,
      didFinishLaunchingWithOptions: launchOptions
    )
  }
}
