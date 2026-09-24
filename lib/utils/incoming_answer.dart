import 'package:flutter/foundation.dart';
import 'package:stream_video_flutter/stream_video_flutter.dart';
import 'signaling_client.dart';

class IncomingAnswer {
  static final Map<String, Future<Call>> _pending = {};

  static Future<Call> accept(String uuid, String cid) {
    return _pending.putIfAbsent(
        cid,
        () => _accept(uuid, cid).whenComplete(() {
              _pending.remove(cid);
            }));
  }

  static Future<Call> _accept(String uuid, String cid) async {
    final timer = Stopwatch()..start();
    debugPrint(
        'QROnly answer received cid=$cid at=${DateTime.now().toUtc().toIso8601String()}');
    final callId = cid.substring(cid.indexOf(':') + 1);
    var accepted = false;
    try {
      // Reserve the call before startup/Stream round trips consume the ring
      // deadline. Device registration has no place in this critical path.
      await SignalingClient.accept(callId);
      debugPrint(
          'QROnly Worker accepted cid=$cid elapsedMs=${timer.elapsedMilliseconds}');
      accepted = true;
      final client = StreamVideo.instance;
      final connection = await client
          .connect(registerPushDevice: false)
          .timeout(const Duration(seconds: 12));
      if (connection.isFailure) throw StateError('Unable to connect the call');
      final restored = await client
          .consumeIncomingCall(uuid: uuid, cid: cid)
          .timeout(const Duration(seconds: 10));
      final call = restored.getDataOrNull();
      if (call == null) throw StateError('This call is no longer available');
      final result = await call.accept().timeout(const Duration(seconds: 8));
      if (result.isFailure) throw StateError('Unable to answer the call');
      debugPrint(
          'QROnly call ready cid=$cid elapsedMs=${timer.elapsedMilliseconds}');
      return call;
    } catch (_) {
      try {
        await StreamVideo.instance.pushNotificationManager
            ?.endCallByCid(cid, silent: true);
      } catch (error) {
        debugPrint('Native call cleanup failed: $error');
      }
      if (accepted) {
        try {
          await SignalingClient.end(callId);
        } catch (_) {}
      }
      rethrow;
    }
  }
}
