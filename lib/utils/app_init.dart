import 'package:qringer_mobile_stream_io/utils/app_keys.dart';
import 'package:qringer_mobile_stream_io/utils/user.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:stream_video_flutter/stream_video_flutter.dart' as stream;
import 'package:stream_video_push_notification/stream_video_push_notification.dart';

class AppInitializer {
  static const storedUserPhoneNumberKey = 'loggedInUserPhoneNumber';
  static const storedUserNameKey = 'loggedInUserName';
  static const storedUserTokenKey = 'loggedInUserToken';

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
  }

  static Future<stream.StreamVideo> init(User user) async {
    return stream.StreamVideo(
      AppKeys.streamApiKey,
      user: user.user,
      userToken: user.token,
      options: const stream.StreamVideoOptions(
        keepConnectionsAliveWhenInBackground: true,
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
          appName: 'QRinger',
          ios: IOSParams(iconName: 'IconMask'),
        ),
        registerApnDeviceToken: true,
      ),
    )..connect();
  }
}