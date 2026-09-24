import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:qringer_mobile_stream_io/firebase_options.dart';
import 'package:qringer_mobile_stream_io/utils/app_init.dart';
import 'package:stream_video_flutter/stream_video_flutter.dart' as streamvf;

/// The saved media preference is loaded before the first UI frame and is never
/// inferred from a notification, which may have been created on another device.
class BackgroundStreamVideoManager {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _callPreferenceKey = 'user_call_preference';

  static Future<bool> getCallPreference() async {
    try {
      final preference = await _storage.read(key: _callPreferenceKey);
      return preference == null || preference == 'true';
    } catch (error) {
      debugPrint('Error reading call preference: $error');
      return true;
    }
  }

  static Future<void> setCallPreference(bool videoCall) async {
    try {
      await _storage.write(key: _callPreferenceKey, value: videoCall.toString());
    } catch (error) {
      debugPrint('Error storing call preference: $error');
    }
  }
}

/// Stream's Worker generates 32-hex call IDs. A stable native UUID makes a
/// redelivered FCM message idempotent even across Android background isolates.
String? nativeUuidForCallCid(String? cid) {
  if (cid == null || !RegExp(r'^default:[a-f0-9]{32}$').hasMatch(cid)) {
    return null;
  }
  final id = cid.substring('default:'.length);
  return '${id.substring(0, 8)}-${id.substring(8, 12)}-'
      '${id.substring(12, 16)}-${id.substring(16, 20)}-${id.substring(20)}';
}

Future<streamvf.CallData?> acceptedNativeCall() async {
  if (!streamvf.StreamVideo.isInitialized()) return null;
  final calls = await streamvf.StreamVideo.instance.pushNotificationManager
      ?.activeCalls();
  for (final call in calls ?? <streamvf.CallData>[]) {
    if (call.isAccepted && call.uuid != null && call.callCid != null) {
      return call;
    }
  }
  return null;
}

Future<bool> hasNativeCallForCid(String? cid, streamvf.StreamVideo client) async {
  if (cid == null) return false;
  final calls = await client.pushNotificationManager?.activeCalls();
  return calls?.any((call) => call.callCid == cid) ?? false;
}

/// Called by Firebase in a separate Android isolate. Present the native ring
/// before any Firebase-token refresh, Stream connection, or call lookup. Those
/// network tasks only verify and clean up a stale ring after it is visible.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    final payload = message.data;
    if (payload['sender'] != 'stream.video') return;
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    final storedUser = await AppInitializer.getStoredUser();
    if (storedUser == null) return;

    final client = AppInitializer.createBackgroundClient(storedUser);
    if (payload['type'] != 'call.ring') {
      await client.handleRingingFlowNotifications(payload);
      return;
    }

    final cid = payload['call_cid'] as String?;
    final uuid = nativeUuidForCallCid(cid);
    if (cid == null || uuid == null) return;
    final sentAt = message.sentTime;
    final ageMs = sentAt == null
        ? 0
        : DateTime.now().difference(sentAt).inMilliseconds;
    if (ageMs >= 30000) return;

    if (!await hasNativeCallForCid(cid, client)) {
      final videoCall = await BackgroundStreamVideoManager.getCallPreference();
      await client.pushNotificationManager?.showIncomingCall(
        uuid: uuid,
        callCid: cid,
        callerName: 'Visitor',
        handle: 'Visitor at your door',
        hasVideo: videoCall,
      );
      debugPrint('QROnly ring presented cid=$cid pushAgeMs=$ageMs '
          'at=${DateTime.now().toUtc().toIso8601String()}');
    }

    // A late or cancelled push must not ring indefinitely. The Stream event
    // listener also dismisses calls ended while this verification is running.
    try {
      final connection = await client
          .connect(registerPushDevice: false)
          .timeout(const Duration(seconds: 8));
      if (connection.isFailure) return;
      final state = await client
          .getCallRingingState(
            callType: streamvf.StreamCallType.defaultType(),
            id: cid.substring('default:'.length),
          )
          .timeout(const Duration(seconds: 8));
      if (state != streamvf.CallRingingState.ringing) {
        final active = await client.pushNotificationManager?.activeCalls();
        final answeredHere = active?.any(
              (call) => call.callCid == cid && call.isAccepted,
            ) ??
            false;
        if (!answeredHere) {
          await client.pushNotificationManager
              ?.endCallByCid(cid, silent: true);
        }
      }
    } catch (error) {
      debugPrint('Post-presentation ring verification deferred: $error');
    }
  } catch (error, stackTrace) {
    debugPrint('Background incoming-call handling failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}
