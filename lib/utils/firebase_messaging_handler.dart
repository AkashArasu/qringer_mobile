import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:qringer_mobile_stream_io/utils/app_init.dart' show AppInitializer;
import 'package:qringer_mobile_stream_io/utils/app_keys.dart' show AppKeys;
import 'package:stream_video_flutter/stream_video_flutter.dart' as streamvf;
import 'package:stream_video_push_notification/stream_video_push_notification.dart';
import 'package:flutter/material.dart';


@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    final tutorialUser = await AppInitializer.getStoredUser();
    if (tutorialUser == null) return;

    final streamVideo = streamvf.StreamVideo.create(
      AppKeys.streamApiKey,
      user: tutorialUser.user,
      userToken: tutorialUser.token,
      options: const streamvf.StreamVideoOptions(
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
          appName: 'Ringing Tutorial',
          ios: IOSParams(iconName: 'IconMask'),
        ),
      ),
    )..connect();

    final subscription = streamVideo.observeCallDeclinedCallKitEvent();

    streamVideo.disposeAfterResolvingRinging(
      disposingCallback: () => subscription?.cancel(),
    );

    await streamVideo.handleRingingFlowNotifications(message.data);
  } catch (e, stk) {
    debugPrint('Error handling remote message: $e');
    debugPrint(stk.toString());
  }
}