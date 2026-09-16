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
    final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (propertyId == null || idToken == null) throw StateError('Homeowner session is unavailable');
    final response = await http.post(
      Uri.parse('${AppKeys.signalingBaseUrl}/v1/calls/$callId/$action'),
      headers: {'Authorization': 'Bearer $idToken', 'Content-Type': 'application/json', 'X-Property-Id': propertyId},
      body: jsonEncode({'propertyId': propertyId}),
    ).timeout(const Duration(seconds: 8));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Unable to $action call (${response.statusCode})');
    }
  }
}
