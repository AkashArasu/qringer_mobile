import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:qringer_mobile_stream_io/callscreen_view.dart';
import 'package:qringer_mobile_stream_io/firebase_options.dart';
import 'package:qringer_mobile_stream_io/qrcode_view.dart';
import 'package:qringer_mobile_stream_io/utils/app_init.dart';
import 'package:qringer_mobile_stream_io/login_view.dart';
import 'package:qringer_mobile_stream_io/utils/app_keys.dart' show AppKeys;
import 'package:qringer_mobile_stream_io/utils/user.dart';
import 'package:stream_video_flutter/stream_video_flutter.dart' as streamvf;
import 'package:qringer_mobile_stream_io/utils/auth_utils.dart';
import 'package:stream_video_push_notification/stream_video_push_notification.dart';
import 'package:qringer_mobile_stream_io/utils/firebase_messaging_handler.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();

}

class _HomeViewState extends State<HomeView> {
  final streamvf.Subscriptions subscriptions = streamvf.Subscriptions();
  bool videoCall = true;
  static const int _fcmSubscription = 1;
  static const int _callKitSubscription = 2;

  @override
  void initState() {
    super.initState();

    FirebaseMessaging.instance.requestPermission();

    _tryConsumingIncomingCallFromTerminatedState();

    _observeFcmMessages();
    _observeCallKitEvents();
  }

  void _observeFcmMessages() {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    
    subscriptions.add(
      _fcmSubscription,
      FirebaseMessaging.onMessage.listen(_handleRemoteMessage),
    );

    subscriptions.add(
      _fcmSubscription,
      FirebaseMessaging.onMessage.listen(_handleRemoteMessage),
    );
  }

  Future<bool> _handleRemoteMessage(RemoteMessage message) async {
    return streamvf.StreamVideo.instance.handleRingingFlowNotifications(message.data);
  }

  void _observeCallKitEvents() {
    final streamVideo = streamvf.StreamVideo.instance;

    subscriptions.add(
      _callKitSubscription,
      streamVideo.observeCoreCallKitEvents(
        onCallAccepted: (callToJoin) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CallScreen(
                call: callToJoin,
              ),
            ),
          );
        },
      ),
    );
  }

  void _tryConsumingIncomingCallFromTerminatedState() {
    // This is only relevant for Android.
    if (streamvf.CurrentPlatform.isIos) return;

    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      streamvf.StreamVideo.instance.consumeAndAcceptActiveCall(
        onCallAccepted: (callToJoin) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CallScreen(
                call: callToJoin,
              ),
            ),
          );
        },
      );
    });
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Welcome to QRinger'),
        centerTitle: true,
        // automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await streamvf.StreamVideo.instance.disconnect();
              await streamvf.StreamVideo.reset();
              await AppInitializer.clearStoredUser();
              // await AuthUtils.signOut();

              subscriptions.cancelAll();

              if (context.mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (context) => const LoginView(),
                  ),
                );
              }
            },
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            const DrawerHeader(
              decoration: BoxDecoration(
                color: Colors.green,
              ),
              child: Text(
                'Menu',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.qr_code),
              title: const Text('QR Code'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => QRCodeScreen(
                      userId: streamvf.StreamVideo.instance.currentUser.id,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Hello ${streamvf.StreamVideo.instance.currentUser.name}!',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 90),

            Text(
              'Should it be a video or audio call?',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Row(
              spacing: 16,
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton(
                  onPressed: () async {
                    setState(() {
                      videoCall = true;
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    foregroundColor: videoCall ? Colors.green : null,
                  ),
                  child: const Text('Video'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    setState(() {
                      videoCall = false;
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    foregroundColor: !videoCall ? Colors.green : null,
                  ),
                  child: const Text('Audio'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    subscriptions.cancelAll();
    super.dispose();
  }
}