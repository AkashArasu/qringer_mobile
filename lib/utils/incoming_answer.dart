import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:stream_video_flutter/stream_video_flutter.dart';
import 'signaling_client.dart';

class IncomingAnswer {
  static const _channel = MethodChannel('qronly/pending_answer');
  static final Map<String, Future<Call>> _pending = {};

  static Future<Map<String, dynamic>?> readNative() async {
    if (!Platform.isAndroid) return null;
    final result = await _channel.invokeMapMethod<String, dynamic>('read');
    return result;
  }

  static Future<void> acknowledge(String uuid) async {
    if (Platform.isAndroid) await _channel.invokeMethod<void>('ack', uuid);
  }

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
      final connection =
          await client.connect().timeout(const Duration(seconds: 12));
      if (connection.isFailure) throw StateError('Unable to connect the call');
      final restored = await client
          .consumeIncomingCall(uuid: uuid, cid: cid)
          .timeout(const Duration(seconds: 10));
      final call = restored.getDataOrNull();
      if (call == null) throw StateError('This call is no longer available');
      final result = await call.accept().timeout(const Duration(seconds: 8));
      if (result.isFailure) throw StateError('Unable to answer the call');
      await acknowledge(uuid);
      debugPrint(
          'QROnly call ready cid=$cid elapsedMs=${timer.elapsedMilliseconds}');
      return call;
    } catch (_) {
      // Both persisted launch intent and plugin active-call record must be
      // cleared, otherwise Home's resume recovery retries the expired Answer.
      try {
        await acknowledge(uuid);
      } catch (error) {
        debugPrint('Answer cleanup failed: $error');
      }
      try {
        await FlutterCallkitIncoming.endCall(uuid);
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
