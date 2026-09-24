import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qringer_mobile_stream_io/main.dart';
import 'package:qringer_mobile_stream_io/utils/app_init.dart';
import 'package:qringer_mobile_stream_io/utils/firebase_messaging_handler.dart';
import 'package:qringer_mobile_stream_io/utils/signaling_client.dart';

void main() {
  test('Answer never joins a timed out, cancelled, or malformed session', () {
    for (final status in [
      'no_answer',
      'cancelled',
      'ended',
      'declined',
      null
    ]) {
      expect(
          () =>
              SignalingClient.validateTransition('accept', {'status': status}),
          throwsA(isA<CallUnavailableException>()));
    }
    expect(
        () => SignalingClient.validateTransition(
            'accept', {'status': 'accepted'}),
        returnsNormally);
    expect(() => SignalingClient.validateTransition('end', {'status': 'ended'}),
        returnsNormally);
  });
  testWidgets('unauthenticated homeowner is routed to sign in', (tester) async {
    await tester.pumpWidget(
      QROnlyApp(
        unauthenticatedHomeBuilder: () => const Scaffold(
          body: Text('Sign in'),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Sign in'), findsOneWidget);
  });

  test('cached Stream token is used only when safely before expiry', () {
    final now = DateTime.utc(2026, 9, 15, 12);
    String tokenAt(DateTime expiry) {
      final header = base64Url.encode(utf8.encode('{}')).replaceAll('=', '');
      final payload = base64Url
          .encode(utf8.encode(jsonEncode({
            'exp': expiry.millisecondsSinceEpoch ~/ 1000,
            'user_id': 'home_test',
          })))
          .replaceAll('=', '');
      return '$header.$payload.signature';
    }

    expect(
      AppInitializer.hasReusableStreamToken(
        tokenAt(now.add(const Duration(minutes: 10))),
        now: now,
      ),
      isTrue,
    );
    expect(
      AppInitializer.hasReusableStreamToken(
        tokenAt(now.add(const Duration(seconds: 30))),
        now: now,
      ),
      isFalse,
    );
    expect(
        AppInitializer.hasReusableStreamToken('not-a-jwt', now: now), isFalse);
  });

  test('native call UUID is deterministic for a valid call CID', () {
    expect(
      nativeUuidForCallCid('default:0123456789abcdef0123456789abcdef'),
      '01234567-89ab-cdef-0123-456789abcdef',
    );
    expect(nativeUuidForCallCid('default:call-123'), isNull);
  });
}
