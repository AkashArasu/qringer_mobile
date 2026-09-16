import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:qringer_mobile_stream_io/firebase_options.dart';
import 'package:qringer_mobile_stream_io/utils/app_init.dart';
import 'package:stream_video_flutter/stream_video_flutter.dart' as streamvf;

/// Stores the homeowner's preferred media mode. StreamVideo itself is owned by
/// [AppInitializer]; keeping a second client here previously caused stale-token
/// and duplicate-notification problems.
class BackgroundStreamVideoManager {
  static streamvf.StreamVideo? _instance;
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _callPreferenceKey = 'user_call_preference';

  static Future<streamvf.StreamVideo?> getInstance() async {
    final storedUser = await AppInitializer.getStoredUser();
    if (storedUser == null) return null;

    if (streamvf.StreamVideo.isInitialized()) {
      _instance = streamvf.StreamVideo.instance;
      return _instance;
    }

    try {
      _instance = await AppInitializer.init(storedUser);
      return _instance;
    } catch (error, stackTrace) {
      debugPrint('Unable to initialize StreamVideo: $error');
      debugPrintStack(stackTrace: stackTrace);
      _instance = null;
      return null;
    }
  }

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
      await _storage.write(
        key: _callPreferenceKey,
        value: videoCall.toString(),
      );
    } catch (error) {
      debugPrint('Error storing call preference: $error');
    }
  }

  static Future<void> cleanup() async {
    final client = _instance;
    _instance = null;
    if (client == null) return;
    try {
      await client.disconnect();
    } catch (error) {
      debugPrint('Error cleaning up StreamVideo instance: $error');
    }
  }
}

String? callCidFromNativeCall(dynamic rawCall) {
  if (rawCall is! Map) return null;
  final call = Map<String, dynamic>.from(rawCall);
  final extra = call['extra'];
  if (extra is! Map) return null;
  return Map<String, dynamic>.from(extra)['callCid'] as String?;
}

Future<bool> hasNativeCallForCid(String? callCid) async {
  if (callCid == null || callCid.isEmpty) return false;
  try {
    final calls = await FlutterCallkitIncoming.activeCalls();
    return calls.any((call) => callCidFromNativeCall(call) == callCid);
  } catch (error) {
    debugPrint('Unable to inspect native incoming calls: $error');
    return false;
  }
}

Future<bool> waitForNativeCall(String? callCid) async {
  for (var attempt = 0; attempt < 12; attempt++) {
    if (await hasNativeCallForCid(callCid)) return true;
    await Future<void>.delayed(const Duration(milliseconds: 75));
  }
  return false;
}

/// Firebase invokes this entry point in a background isolate. That isolate has
/// no foreground StreamVideo singleton. It restores an authenticated client
/// without opening the coordinator WebSocket; the SDK only needs its HTTP call
/// lookup to validate the ring and present the native incoming-call UI.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    // A background isolate has no Firebase or Stream singleton yet. Always
    // initialize it before inspecting/handling the payload so Android can
    // present Stream's native ringing UI while the app is backgrounded.
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    final payload = message.data;
    if (payload['sender'] != 'stream.video') {
      debugPrint('Ignoring non-Stream background message ${message.messageId}');
      return;
    }

    final callCid = payload['call_cid'] as String?;
    debugPrint(
        'Handling Stream background ringing message ${message.messageId}: $callCid');

    // FCM may redeliver the same high-priority data message. The pinned Stream
    // SDK generates a new native UUID for each delivery, so deduplicate by CID
    // before asking it to show another incoming-call card.
    if (await hasNativeCallForCid(callCid)) {
      debugPrint('Ignoring duplicate incoming-call delivery for $callCid');
      return;
    }

    final storedUser = await AppInitializer.getStoredUser();
    if (storedUser == null) {
      debugPrint('Cannot ring in background: no signed-in homeowner');
      return;
    }

    final client = streamvf.StreamVideo.isInitialized()
        ? streamvf.StreamVideo.instance
        : await AppInitializer.init(storedUser, connect: false);

    final handled = await client.handleRingingFlowNotifications(payload);
    final presented = handled && await waitForNativeCall(callCid);
    debugPrint(
      presented
          ? 'Background incoming-call notification presented'
          : handled
              ? 'Stream handled the ring but native presentation was not confirmed'
              : 'Stream did not handle background message ${message.messageId}',
    );
  } catch (error, stackTrace) {
    debugPrint('Background incoming-call handling failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}
