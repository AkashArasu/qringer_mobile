import AVFAudio
import CallKit
import Flutter
import PushKit
import UIKit
import stream_video_push_notification

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  private let nativeCallChannel = "com.qringer/calls"
  private let callKit = QringerCallKitCoordinator()
  private var methodChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    StreamVideoPKDelegateManager.shared.registerForPushNotifications()
    callKit.start()
    callKit.onAction = { [weak self] action, callId in self?.sendCallAction(action, callId: callId) }
    let didLaunch = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    DispatchQueue.main.async { [weak self] in self?.configureMethodChannel() }
    return didLaunch
  }

  private func configureMethodChannel() {
    guard let controller = UIApplication.shared.windows.first?.rootViewController as? FlutterViewController else { return }
    methodChannel = FlutterMethodChannel(name: nativeCallChannel, binaryMessenger: controller.binaryMessenger)
    methodChannel?.setMethodCallHandler { [weak self] call, result in
      if call.method == "consumePendingAction" {
        result.success(self?.callKit.consumePendingAction())
      } else { result(FlutterMethodNotImplemented) }
    }
  }

  private func sendCallAction(_ action: String, callId: String) {
    let payload: [String: String] = ["action": action, "callId": callId]
    callKit.storePendingAction(payload)
    methodChannel?.invokeMethod("incomingCallAction", arguments: payload)
  }
}

final class QringerCallKitCoordinator: NSObject, PKPushRegistryDelegate, CXProviderDelegate {
  private let provider: CXProvider
  private var registry: PKPushRegistry?
  private var calls = [UUID: String]()
  private var pendingAction: [String: String]?
  var onAction: ((String, String) -> Void)?

  override init() {
    let configuration = CXProviderConfiguration(localizedName: "QROnly")
    configuration.supportsVideo = true
    configuration.maximumCallsPerCallGroup = 1
    configuration.maximumCallGroups = 1
    configuration.iconTemplateImageData = UIImage(named: "Icon")?.pngData()
    provider = CXProvider(configuration: configuration)
    super.init()
    provider.setDelegate(self, queue: nil)
  }

  func start() {
    let registry = PKPushRegistry(queue: .main)
    registry.delegate = self
    registry.desiredPushTypes = [.voIP]
    self.registry = registry
  }

  func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType) {
    // StreamVideoPKDelegateManager registers the VoIP token with the configured
    // Stream provider. The app never sends this device token to the visitor.
  }

  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {}

  func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
    let data = payload.dictionaryPayload
    guard let cid = data["call_cid"] as? String ?? data["call_id"] as? String else { completion(); return }
    let callId = cid.split(separator: ":").last.map(String.init) ?? cid
    let uuid = UUID()
    calls[uuid] = callId
    let update = CXCallUpdate()
    update.localizedCallerName = (data["sender"] as? String) ?? "Visitor at your door"
    update.hasVideo = true
    update.supportsHolding = false
    update.supportsGrouping = false
    update.supportsUngrouping = false
    provider.reportNewIncomingCall(with: uuid, update: update) { _ in completion() }
  }

  func providerDidReset(_ provider: CXProvider) { calls.removeAll() }
  func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    if let callId = calls[action.callUUID] { onAction?("accept", callId) }
    action.fulfill()
  }
  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    if let callId = calls.removeValue(forKey: action.callUUID) { onAction?("reject", callId) }
    action.fulfill()
  }
  func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {}
  func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {}

  func storePendingAction(_ action: [String: String]) { pendingAction = action }
  func consumePendingAction() -> [String: String]? { defer { pendingAction = nil }; return pendingAction }
}
