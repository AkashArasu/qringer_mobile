import 'dart:async';
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
  static Future<bool>? _pushRegistrationInFlight;
  static StreamSubscription<String>? _fcmTokenRefreshSubscription;

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
    await _fcmTokenRefreshSubscription?.cancel();
    _fcmTokenRefreshSubscription = null;
    _pushRegistrationInFlight = null;
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

  static Future<stream.StreamVideo> init(
    User user, {
    bool connect = true,
  }) async {
    debugPrint(
        '🚀 Initializing StreamVideo for foreground app with user: ${user.user.id}');

    if (stream.StreamVideo.isInitialized()) {
      final existing = stream.StreamVideo.instance;
      if (connect) {
        await ensurePushRegistration(client: existing);
      }
      return existing;
    }

    // A still-valid cached token lets a background isolate inspect a ringing
    // call without first waiting on Firebase + Worker round trips. The token
    // loader remains installed so the SDK can refresh it when necessary.
    final storedToken = user.token;
    final cachedToken =
        storedToken != null && hasReusableStreamToken(storedToken)
            ? storedToken
            : null;
    final client = stream.StreamVideo(
      AppKeys.streamApiKey,
      user: user.user,
      userToken: cachedToken,
      // Stream user tokens are short-lived. A dynamic loader avoids reusing
      // an expired token from secure storage after an app restart.
      tokenLoader: (_) =>
          _loadFreshStreamToken(user.user.id, user.user.name ?? 'Homeowner'),
      onTokenUpdated: (token) => storeUser(
        User(user: user.user, token: token.rawValue),
      ),
      options: const stream.StreamVideoOptions(
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
    _observeFcmTokenRefresh(client);

    if (connect) {
      final registered = await ensurePushRegistration(
        client: client,
        maxAttempts: 2,
      );
      if (!registered) {
        // Do not hold the first frame indefinitely on poor connectivity. A
        // bounded repair continues after startup and app resume retries again.
        unawaited(ensurePushRegistration(client: client, maxAttempts: 3));
      }
    }
    return client;
  }

  /// Repairs both the Stream coordinator connection and push-device mapping.
  /// Safe to call repeatedly: Stream connect and create-device are idempotent.
  static Future<bool> ensurePushRegistration({
    stream.StreamVideo? client,
    int maxAttempts = 3,
  }) {
    final activeClient = client ??
        (stream.StreamVideo.isInitialized()
            ? stream.StreamVideo.instance
            : null);
    if (activeClient == null) return Future<bool>.value(false);

    final inFlight = _pushRegistrationInFlight;
    if (inFlight != null) return inFlight;

    final operation = _connectAndRegister(activeClient, maxAttempts);
    _pushRegistrationInFlight = operation;
    return operation.whenComplete(() {
      if (identical(_pushRegistrationInFlight, operation)) {
        _pushRegistrationInFlight = null;
      }
    });
  }

  static Future<bool> _connectAndRegister(
    stream.StreamVideo client,
    int maxAttempts,
  ) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final connection = await client.connect();
        if (connection.isSuccess) {
          final registered = await _registerAndroidPushDevice(client);
          if (registered) return true;
        } else {
          debugPrint(
            '❌ Stream connection attempt $attempt/$maxAttempts failed: $connection',
          );
        }
      } catch (error, stackTrace) {
        debugPrint(
          '❌ Stream connection attempt $attempt/$maxAttempts threw: $error',
        );
        if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
      }

      if (attempt < maxAttempts) {
        await Future<void>.delayed(Duration(milliseconds: 300 * attempt));
      }
    }
    return false;
  }

  /// Registers the current FCM token explicitly. The push-notification
  /// manager also registers it, but its registration failures are silent in
  /// the current Stream SDK; doing this here makes first-login delivery
  /// reliable and visible in the Flutter log.
  static Future<bool> _registerAndroidPushDevice(
    stream.StreamVideo client, {
    String? pushToken,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      final token = pushToken ?? await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) {
        debugPrint(
            '❌ FCM did not return a device token; incoming calls cannot be delivered');
        return false;
      }
      final result = await client.addDevice(
        pushToken: token,
        pushProvider: stream.PushProvider.firebase,
        pushProviderName: AppKeys.androidPushProviderName,
      );
      if (result.isFailure) {
        debugPrint('❌ Stream rejected FCM device registration: $result');
        return false;
      } else {
        debugPrint('✅ FCM device registered with Stream');
        return true;
      }
    } catch (error) {
      debugPrint('❌ Unable to register the FCM device with Stream: $error');
      return false;
    }
  }

  static void _observeFcmTokenRefresh(stream.StreamVideo client) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    _fcmTokenRefreshSubscription ??=
        FirebaseMessaging.instance.onTokenRefresh.listen(
      (token) async {
        debugPrint('FCM token changed; refreshing Stream device mapping');
        final connected = await client.connect();
        if (connected.isFailure) {
          debugPrint('Unable to reconnect Stream after FCM token refresh');
          return;
        }
        await _registerAndroidPushDevice(client, pushToken: token);
      },
      onError: (Object error) {
        debugPrint('FCM token refresh listener failed: $error');
      },
    );
  }

  /// Reject cached JWTs that are expired or close enough to expiry that a
  /// cold background start could lose the race while presenting the call.
  @visibleForTesting
  static bool hasReusableStreamToken(
    String token, {
    DateTime? now,
    Duration minimumValidity = const Duration(minutes: 2),
  }) {
    try {
      final segments = token.split('.');
      if (segments.length != 3) return false;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(segments[1]))),
      ) as Map<String, dynamic>;
      final expirySeconds = payload['exp'];
      if (expirySeconds is! num) return false;
      final expiry = DateTime.fromMillisecondsSinceEpoch(
        expirySeconds.toInt() * 1000,
        isUtc: true,
      );
      return expiry
          .isAfter((now ?? DateTime.now().toUtc()).add(minimumValidity));
    } catch (_) {
      return false;
    }
  }

  static Future<String> _loadFreshStreamToken(
      String expectedHomeownerId, String displayName) async {
    final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      throw StateError('Firebase homeowner session is unavailable');
    }
    final firebaseToken = await firebaseUser.getIdToken(true);
    if (firebaseToken == null || firebaseToken.isEmpty) {
      throw StateError('Firebase homeowner token is unavailable');
    }

    final response = await http
        .post(
          Uri.parse('${AppKeys.signalingBaseUrl}/v1/homeowner/session'),
          headers: {
            'Authorization': 'Bearer $firebaseToken',
            'Content-Type': 'application/json'
          },
          body: jsonEncode({'displayName': displayName}),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw StateError(
          'Unable to refresh Stream session (${response.statusCode})');
    }

    final session = jsonDecode(response.body) as Map<String, dynamic>;
    final homeownerId = session['homeownerId'] as String?;
    final streamToken = session['streamToken'] as String?;
    final propertyId = session['propertyId'] as String?;
    if (homeownerId != expectedHomeownerId ||
        streamToken == null ||
        streamToken.isEmpty) {
      throw StateError('Worker returned an invalid Stream homeowner session');
    }
    if (propertyId != null && propertyId.isNotEmpty) {
      await storePropertyId(propertyId);
    }
    return streamToken;
  }
}
