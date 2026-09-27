import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:qringer_mobile_stream_io/firebase_options.dart';
import 'package:qringer_mobile_stream_io/utils/app_init.dart';
import 'package:qringer_mobile_stream_io/utils/app_keys.dart';
import 'package:qringer_mobile_stream_io/utils/signaling_client.dart';
import 'package:stream_video_push_notification/stream_video_push_notification.dart';
import 'package:stream_video_push_notification/stream_video_push_notification_platform_interface.dart';
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
      await _storage.write(
          key: _callPreferenceKey, value: videoCall.toString());
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

Future<bool> hasNativeCallForCid(String? cid,
    [streamvf.StreamVideo? client]) async {
  if (cid == null) return false;
  if (client != null) {
    final calls = await client.pushNotificationManager?.activeCalls();
    return calls?.any((call) => call.callCid == cid) ?? false;
  }
  final calls =
      await StreamVideoPushNotificationPlatform.instance.activeCalls();
  if (calls is! List) return false;
  return calls.whereType<Map>().any((call) {
    final extra = call['extra'];
    return extra is Map && extra['callCid'] == cid;
  });
}

Future<bool> showMissedCallIfUnanswered(String cid) async {
  final uuid = nativeUuidForCallCid(cid);
  if (uuid == null) return false;
  final callId = cid.substring('default:'.length);
  for (var attempt = 1; attempt <= 4; attempt++) {
    String? status;
    try {
      status = await SignalingClient.callStatus(callId);
    } catch (error) {
      debugPrint('QROnly missed-call state check failed: $error');
    }
    if (status == 'no_answer') {
      final platform = StreamVideoPushNotificationPlatform.instance;
      await platform.init(AppInitializer.pushConfiguration.toJson());
      await platform.showMissCallNotification(StreamVideoPushParams(
        id: uuid,
        callerName: 'Visitor',
        handle: 'Visitor at your door',
        extra: {'callCid': cid},
        android: AndroidParams.fromPushConfiguration(
          AppInitializer.pushConfiguration.android!,
        ),
      ));
      debugPrint('QROnly missed-call notification shown: cid=$cid');
      return true;
    }
    if (status != 'ringing' && status != 'calling') {
      debugPrint(
          'QROnly missed-call notification suppressed: cid=$cid status=$status');
      return false;
    }
    if (attempt < 4) await Future<void>.delayed(const Duration(seconds: 1));
  }
  debugPrint(
      'QROnly missed-call notification suppressed: cid=$cid Worker still ringing');
  return false;
}

/// Called by Firebase in a separate Android isolate. Present the native ring
/// without constructing StreamVideo, which switches Android to in-call audio
/// mode before the homeowner accepts and can silence the background ringtone.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (!Platform.isAndroid) return;
    final payload = message.data;
    final sender = payload['sender'];
    final type = payload['type'];
    final cid = payload['call_cid'] as String?;
    final sentAt = message.sentTime;
    final ageMs = sentAt == null
        ? null
        : DateTime.now().difference(sentAt).inMilliseconds;
    debugPrint('QROnly background push received: sender=$sender type=$type '
        'hasCid=${cid != null} hasNotification=${message.notification != null} '
        'ageMs=$ageMs');
    if (sender != 'stream.video') {
      debugPrint('QROnly background push ignored: non-Stream sender');
      return;
    }
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    final storedUser = await AppInitializer.getStoredUser();
    if (storedUser == null) {
      debugPrint('QROnly background ring skipped: no saved homeowner session');
      return;
    }

    final uuid = nativeUuidForCallCid(cid);
    if (cid == null || uuid == null) {
      debugPrint('QROnly background push skipped: invalid call CID');
      return;
    }
    if (type != 'call.ring' && type != 'call.missed') {
      debugPrint('QROnly background push ignored: type=$type');
      return;
    }
    if (type == 'call.missed') {
      await showMissedCallIfUnanswered(cid);
      return;
    }

    if (ageMs != null && ageMs >= 30000) {
      debugPrint('QROnly background ring skipped: stale push ageMs=$ageMs');
      return;
    }

    if (await hasNativeCallForCid(cid)) {
      debugPrint('QROnly background ring already active: cid=$cid');
    } else {
      final videoCall = await BackgroundStreamVideoManager.getCallPreference();
      final propertyId = await AppInitializer.getPropertyId();
      final platform = StreamVideoPushNotificationPlatform.instance;
      await platform.init(AppInitializer.pushConfiguration.toJson());
      debugPrint(
          'QROnly background ring presenting: cid=$cid video=$videoCall');
      await platform.showIncomingCall(StreamVideoPushParams(
        id: uuid,
        callerName: 'Visitor',
        handle: 'Visitor at your door',
        type: videoCall ? 1 : 0,
        duration: 30000,
        extra: {
          'callCid': cid,
          if (propertyId != null) 'propertyId': propertyId,
          'signalingBaseUrl': AppKeys.signalingBaseUrl,
        },
        android: AndroidParams.fromPushConfiguration(
          AppInitializer.pushConfiguration.android!,
        ),
      ));
      debugPrint(
          'QROnly background ring presentation requested: cid=$cid pushAgeMs=$ageMs '
          'at=${DateTime.now().toUtc().toIso8601String()}');
    }

    // Native timeout and explicit accept/reject/end actions own cleanup.
  } catch (error, stackTrace) {
    debugPrint('Background incoming-call handling failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}
