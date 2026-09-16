import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:qringer_mobile_stream_io/utils/app_init.dart';
import 'package:qringer_mobile_stream_io/utils/app_keys.dart';

class SignalingClient {
  static Future<void> accept(String callId) => _transition(callId, 'accept');
  static Future<void> reject(String callId) => _transition(callId, 'reject');
  static Future<void> end(String callId) => _transition(callId, 'end');

  static Future<void> _transition(String callId, String action) async {
    final propertyId = await AppInitializer.getPropertyId();
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (propertyId == null || firebaseUser == null) {
      throw StateError('Homeowner session is unavailable');
    }

    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        // Force-refresh after an authorization failure or transient retry so
        // an expired Firebase token cannot strand an accepted/ended call.
        final idToken = await firebaseUser.getIdToken(attempt > 1);
        if (idToken == null || idToken.isEmpty) {
          throw StateError('Homeowner token is unavailable');
        }
        final response = await http
            .post(
              Uri.parse(
                '${AppKeys.signalingBaseUrl}/v1/calls/$callId/$action',
              ),
              headers: {
                'Authorization': 'Bearer $idToken',
                'Content-Type': 'application/json',
                'X-Property-Id': propertyId,
              },
              body: jsonEncode({'propertyId': propertyId}),
            )
            .timeout(const Duration(seconds: 8));
        if (response.statusCode >= 200 && response.statusCode < 300) return;

        lastError = StateError(
          'Unable to $action call (${response.statusCode})',
        );
        final retryable = response.statusCode == 401 ||
            response.statusCode == 408 ||
            response.statusCode == 429 ||
            response.statusCode >= 500;
        if (!retryable) throw lastError;
      } catch (error) {
        lastError = error;
        if (attempt == 3) rethrow;
      }

      await Future<void>.delayed(Duration(milliseconds: 250 * attempt));
    }
    throw lastError ?? StateError('Unable to $action call');
  }
}
