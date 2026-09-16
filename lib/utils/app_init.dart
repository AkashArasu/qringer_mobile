import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:http/http.dart' as http;
import 'package:qringer_mobile_stream_io/utils/app_keys.dart';
import 'package:qringer_mobile_stream_io/utils/user.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:stream_video_flutter/stream_video_flutter.dart' as stream;
import 'package:stream_video_push_notification/stream_video_push_notification.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class AppInitializer {
  static const storedUserPhoneNumberKey = 'loggedInUserPhoneNumber';
  static const storedUserNameKey = 'loggedInUserName';
  static const storedUserTokenKey = 'loggedInUserToken';
  static const storedPropertyIdKey = 'propertyPublicId';

  static Future<User?> getStoredUser() async {
    const storage = FlutterSecureStorage();

    final phoneNumber = await storage.read(key: storedUserPhoneNumberKey);
    final userName = await storage.read(key: storedUserNameKey);
    final token = await storage.read(key: storedUserTokenKey);
    if (phoneNumber == null || userName == null || token == null) {
      return null;
    }

    return User.createUser(
      userId: phoneNumber,
      name: userName,
      role: 'user',
      token: token,
    );
  }

  static Future<void> storeUser(User user) async {
    const storage = FlutterSecureStorage();
    await storage.write(key: storedUserPhoneNumberKey, value: user.user.id);
    await storage.write(key: storedUserNameKey, value: user.user.name);
    await storage.write(key: storedUserTokenKey, value: user.token);
  }

  static Future<void> clearStoredUser() async {
    const storage = FlutterSecureStorage();
    await storage.delete(key: storedUserPhoneNumberKey);
    await storage.delete(key: storedUserNameKey);
    await storage.delete(key: storedUserTokenKey);
    await storage.delete(key: storedPropertyIdKey);
  }

  static Future<void> storePropertyId(String propertyId) async {
    const storage = FlutterSecureStorage();
    await storage.write(key: storedPropertyIdKey, value: propertyId);
  }

  static Future<String?> getPropertyId() async {
    const storage = FlutterSecureStorage();
    return storage.read(key: storedPropertyIdKey);
  }

  static Future<stream.StreamVideo> init(User user) async {
    debugPrint('🚀 Initializing StreamVideo for foreground app with user: ${user.user.id}');
    
    final client = stream.StreamVideo(
      AppKeys.streamApiKey,
      user: user.user,
      // Stream user tokens are short-lived. A dynamic loader avoids reusing
      // an expired token from secure storage after an app restart.
      tokenLoader: (_) => _loadFreshStreamToken(user.user.id, user.user.name ?? 'Homeowner'),
      onTokenUpdated: (token) => storeUser(
        User(user: user.user, token: token.rawValue),
      ),
      options: stream.StreamVideoOptions(
        keepConnectionsAliveWhenInBackground: true,
        // Stream's default logger is silent. Keep production quiet, but emit
        // coordinator WebSocket close codes while diagnosing debug builds.
        logPriority: kDebugMode ? stream.Priority.debug : stream.Priority.none,
      ),
      pushNotificationManagerProvider:
          StreamVideoPushNotificationManager.create(
        iosPushProvider: const StreamVideoPushProvider.apn(
          name: AppKeys.iosPushProviderName,
        ),
        androidPushProvider: const StreamVideoPushProvider.firebase(
          name: AppKeys.androidPushProviderName,
        ),
        pushParams: const StreamVideoPushParams(
          appName: 'QROnly',
          ios: IOSParams(iconName: 'IconMask'),
          missedCallNotification: NotificationParams(
            showNotification: true,
            isShowCallback: false,
            subtitle: 'Missed visitor',
          ),
        ),
        registerApnDeviceToken: true,
      ),
    );
    final connection = await client.connect();
    if (connection.isFailure) {
      debugPrint('❌ Stream connection failed: $connection');
      return client;
    }

    await _registerAndroidPushDevice(client);
    return client;
  }

  /// Registers the current FCM token explicitly. The push-notification
  /// manager also registers it, but its registration failures are silent in
  /// the current Stream SDK; doing this here makes first-login delivery
  /// reliable and visible in the Flutter log.
  static Future<void> _registerAndroidPushDevice(stream.StreamVideo client) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) {
        debugPrint('❌ FCM did not return a device token; incoming calls cannot be delivered');
        return;
      }
      final result = await client.addDevice(
        pushToken: token,
        pushProvider: stream.PushProvider.firebase,
        pushProviderName: AppKeys.androidPushProviderName,
      );
      if (result.isFailure) {
        debugPrint('❌ Stream rejected FCM device registration: $result');
      } else {
        debugPrint('✅ FCM device registered with Stream');
      }
    } catch (error) {
      debugPrint('❌ Unable to register the FCM device with Stream: $error');
    }
  }

  static Future<String> _loadFreshStreamToken(String expectedHomeownerId, String displayName) async {
    final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      throw StateError('Firebase homeowner session is unavailable');
    }
    final firebaseToken = await firebaseUser.getIdToken(true);
    if (firebaseToken == null || firebaseToken.isEmpty) {
      throw StateError('Firebase homeowner token is unavailable');
    }

    final response = await http.post(
      Uri.parse('${AppKeys.signalingBaseUrl}/v1/homeowner/session'),
      headers: {'Authorization': 'Bearer $firebaseToken', 'Content-Type': 'application/json'},
      body: jsonEncode({'displayName': displayName}),
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw StateError('Unable to refresh Stream session (${response.statusCode})');
    }

    final session = jsonDecode(response.body) as Map<String, dynamic>;
    final homeownerId = session['homeownerId'] as String?;
    final streamToken = session['streamToken'] as String?;
    final propertyId = session['propertyId'] as String?;
    if (homeownerId != expectedHomeownerId || streamToken == null || streamToken.isEmpty) {
      throw StateError('Worker returned an invalid Stream homeowner session');
    }
    if (propertyId != null && propertyId.isNotEmpty) {
      await storePropertyId(propertyId);
    }
    return streamToken;
  }
}
