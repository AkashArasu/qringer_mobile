// import 'package:flutter/material.dart';

// void main() {
//   runApp(const MyApp());
// }

// class MyApp extends StatelessWidget {
//   const MyApp({super.key});

//   // This widget is the root of your application.
//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'Flutter Demo',
//       theme: ThemeData(
//         // This is the theme of your application.
//         //
//         // TRY THIS: Try running your application with "flutter run". You'll see
//         // the application has a purple toolbar. Then, without quitting the app,
//         // try changing the seedColor in the colorScheme below to Colors.green
//         // and then invoke "hot reload" (save your changes or press the "hot
//         // reload" button in a Flutter-supported IDE, or press "r" if you used
//         // the command line to start the app).
//         //
//         // Notice that the counter didn't reset back to zero; the application
//         // state is not lost during the reload. To reset the state, use hot
//         // restart instead.
//         //
//         // This works for code too, not just values: Most code changes can be
//         // tested with just a hot reload.
//         colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
//         useMaterial3: true,
//       ),
//       home: const MyHomePage(title: 'Flutter Demo Home Page'),
//     );
//   }
// }

// class MyHomePage extends StatefulWidget {
//   const MyHomePage({super.key, required this.title});

//   // This widget is the home page of your application. It is stateful, meaning
//   // that it has a State object (defined below) that contains fields that affect
//   // how it looks.

//   // This class is the configuration for the state. It holds the values (in this
//   // case the title) provided by the parent (in this case the App widget) and
//   // used by the build method of the State. Fields in a Widget subclass are
//   // always marked "final".

//   final String title;

//   @override
//   State<MyHomePage> createState() => _MyHomePageState();
// }

// class _MyHomePageState extends State<MyHomePage> {
//   int _counter = 0;

//   void _incrementCounter() {
//     setState(() {
//       // This call to setState tells the Flutter framework that something has
//       // changed in this State, which causes it to rerun the build method below
//       // so that the display can reflect the updated values. If we changed
//       // _counter without calling setState(), then the build method would not be
//       // called again, and so nothing would appear to happen.
//       _counter++;
//     });
//   }

//   @override
//   Widget build(BuildContext context) {
//     // This method is rerun every time setState is called, for instance as done
//     // by the _incrementCounter method above.
//     //
//     // The Flutter framework has been optimized to make rerunning build methods
//     // fast, so that you can just rebuild anything that needs updating rather
//     // than having to individually change instances of widgets.
//     return Scaffold(
//       appBar: AppBar(
//         // TRY THIS: Try changing the color here to a specific color (to
//         // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
//         // change color while the other colors stay the same.
//         backgroundColor: Theme.of(context).colorScheme.inversePrimary,
//         // Here we take the value from the MyHomePage object that was created by
//         // the App.build method, and use it to set our appbar title.
//         title: Text(widget.title),
//       ),
//       body: Center(
//         // Center is a layout widget. It takes a single child and positions it
//         // in the middle of the parent.
//         child: Column(
//           // Column is also a layout widget. It takes a list of children and
//           // arranges them vertically. By default, it sizes itself to fit its
//           // children horizontally, and tries to be as tall as its parent.
//           //
//           // Column has various properties to control how it sizes itself and
//           // how it positions its children. Here we use mainAxisAlignment to
//           // center the children vertically; the main axis here is the vertical
//           // axis because Columns are vertical (the cross axis would be
//           // horizontal).
//           //
//           // TRY THIS: Invoke "debug painting" (choose the "Toggle Debug Paint"
//           // action in the IDE, or press "p" in the console), to see the
//           // wireframe for each widget.
//           mainAxisAlignment: MainAxisAlignment.center,
//           children: <Widget>[
//             const Text(
//               'You have pushed the button this many times:',
//             ),
//             Text(
//               '$_counter',
//               style: Theme.of(context).textTheme.headlineMedium,
//             ),
//           ],
//         ),
//       ),
//       floatingActionButton: FloatingActionButton(
//         onPressed: _incrementCounter,
//         tooltip: 'Increment',
//         child: const Icon(Icons.add),
//       ), // This trailing comma makes auto-formatting nicer for build methods.
//     );
//   }
// }

// import 'dart:nativewrappers/_internal/vm/lib/ffi_allocation_patch.dart';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:qringer_mobile_stream_io/register_view.dart';
import 'package:stream_video_flutter/stream_video_flutter.dart';
import 'package:stream_video_push_notification/stream_video_push_notification.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:rxdart/rxdart.dart';
import 'package:qringer_mobile_stream_io/login_view.dart';
// import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Call Receiver',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const RegisterView(),
    );
  }
}

class CallReceiverPage extends StatefulWidget {
  const CallReceiverPage({super.key});

  @override
  State<CallReceiverPage> createState() => _CallReceiverPageState();
}

class _CallReceiverPageState extends State<CallReceiverPage>
    with WidgetsBindingObserver {
  late final StreamVideo _streamVideo;
  Call? _call;
  bool _isReceivingCall = false;
  String? _incomingCallId;
  // final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final _compositeSubscription = CompositeSubscription();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    // await Firebase.initializeApp();
    _initializeStreamVideo();
    // await _initializePushNotifications();
    // _setupCallHandlers();
    _observeCallKitEvents();
  }

  void _initializeStreamVideo() {
    _streamVideo = StreamVideo(
      'y8h5754fwgma',
      user: User.regular(
        userId: 'homeowner',
        name: 'Aashika',
        role: 'user',
      ),

      userToken:
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiaG9tZW93bmVyIn0.dCKk27c3QZiJsBZxnMW5PHpSxbwPD6QdjSTWBsNzIY0',

      options: const StreamVideoOptions(
        // It's important to keep connections alive when the app is in the background to properly handle incoming calls while the app is in the background
        keepConnectionsAliveWhenInBackground: true,
      ),
      // pushNotificationManagerProvider:
      //     StreamVideoPushNotificationManager.create(
      //   iosPushProvider:
      //       const StreamVideoPushProvider.apn(name: 'ios-provider-name'),
      //   androidPushProvider: const StreamVideoPushProvider.firebase(
      //       name: 'firebase_push_provider'),
      //   pushParams: const StreamVideoPushParams(
      //     appName: "qringer_mobile_stream_io",
      //     ios: IOSParams(iconName: "IconMask"),
      //   ),
      // ),
    );
  }

  // void _setupCallHandlers() {

  //   _streamVideo.state.incomingCall.listen((call) async {
  //     setState(() {
  //       _isReceivingCall = true;
  //       _incomingCallId = call!.id;
  //     });

  //     // Play ringtone
  //     FlutterRingtonePlayer.playRingtone();

  //     // Show incoming call UI
  //     _showIncomingCallDialog(call!);
  //   });
  // }

  Future<void> _observeCallKitEvents() async {
    // final streamVideo = StreamVideo.instance;
    // You can use our helper method to observe core CallKit events
    // It will handled call accepted, declined and ended events

    // _compositeSubscription.add(_streamVideo.observeCoreCallKitEvents(
    //   onCallAccepted: (callToJoin) {
    //     // _acceptCall(callToJoin);
    //     _showIncomingCallDialog(callToJoin);

    //     // <---- IMPLEMENT NAVIGATION TO CALL SCREEN HERE
    //   },
    // ));

    _compositeSubscription
        .add(_streamVideo.state.incomingCall.listen((call) async {
      setState(() {
        _isReceivingCall = true;
        _incomingCallId = call!.id;
      });

      // Play ringtone
      FlutterRingtonePlayer.playRingtone();

      // Show incoming call UI
      _showIncomingCallDialog(call!);
      // _acceptCall(call!);
    }));

    // Or you can handle them by yourself, and/or add additional events such as handling mute events from CallKit
    // _compositeSubscription.add(streamVideo.onCallKitEvent<ActionCallToggleMute>(_onCallToggleMute));
  }

  // Future<void> _initializePushNotifications() async {
  //   await _firebaseMessaging.requestPermission();
  //   final fcmToken = await _firebaseMessaging.getToken();

  //   // Register FCM token with Stream
  //   await _streamVideo.addDevice(
  //     // deviceId: fcmToken!,
  //     pushToken: fcmToken!,
  //     pushProvider: PushProvider.firebase,
  //   );

  //   // Handle foreground messages
  //   FirebaseMessaging.onMessage.listen(_handlePushNotification);

  //   // Handle background/terminated messages
  //   FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  //   // Handle when app is opened from terminated state
  //   final initialMessage = await _firebaseMessaging.getInitialMessage();
  //   if (initialMessage != null) {
  //     _handlePushNotification(initialMessage);
  //   }
  // }

  // Future<void> _handlePushNotification(RemoteMessage message) async {
  //   if (message.data['type'] == 'call') {
  //     final callId = message.data['call_id'];
  //     final callCid = message.data['call_cid'];

  //     final call = await _streamVideo.getCall(callCid);
  //     setState(() {
  //       _isReceivingCall = true;
  //       _incomingCallId = callId;
  //     });

  //     FlutterRingtonePlayer.playRingtone();
  //     _showIncomingCallDialog(call);
  //   }
  // }

  Future<void> _showIncomingCallDialog(Call call) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Incoming Call'),
        content: Text('Call from ${call.id}'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _rejectCall(call);
            },
            child: const Text('Decline'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _acceptCall(call);
            },
            child: const Text('Accept'),
          ),
        ],
      ),
    );
  }

  Future<void> _acceptCall(Call call) async {
    FlutterRingtonePlayer.stop();
    setState(() {
      _call = call;
      _isReceivingCall = false;
    });

    // final callCredentials = await _streamVideo.getCallCredentials(
    //   callId: call.id,
    //   callType: call.type,
    // );

    await _call?.join(
        connectOptions: CallConnectOptions(
      camera: TrackOption.disabled(),
    ));
  }

  Future<void> _rejectCall(Call call) async {
    FlutterRingtonePlayer.stop();
    await call.reject();
    setState(() {
      _isReceivingCall = false;
      _incomingCallId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Call Receiver')),
      body: _call != null
          ? StreamCallContainer(
              call: _call!,
              callContentBuilder: (context, call, participants) {
                return StreamCallContent(
                  call: call,
                  callState: participants,
                  layoutMode: ParticipantLayoutMode.spotlight,
                  callAppBarBuilder: (context, call, callState) {
                    return AppBar(
                      actions: const [],
                    );
                  },
                  callControlsBuilder: (context, call, callState) {
                    final localParticipant = callState.localParticipant!;
                    return StreamCallControls(options: [
                      LeaveCallOption(
                          call: call,
                          onLeaveCallTap: () async {
                            await call.leave();
                            setState(() => _call = null);
                          }),
                      ToggleCameraOption(
                          call: call, localParticipant: localParticipant),
                      ToggleMicrophoneOption(
                          call: call, localParticipant: localParticipant),
                      ToggleSpeakerphoneOption(call: call),
                    ]);
                  },
                );

                // return Stack(
                //   children: [
                //     participants.participantCount > 0
                //         ? GridView.count(
                //             crossAxisCount:
                //                 2, //participants.length == 1 ? 1 : 2,
                //             children: participants.callParticipants
                //                 .map((participant) {
                //               return StreamVideoRenderer(
                //                 call: call,
                //                 participant: participant,
                //                 videoTrackType: SfuTrackType.video,
                //               );
                //             }).toList(),
                //           )
                //         : const Center(
                //             child: Text('Waiting for participants...'),
                //           ),
                //     Positioned(
                //       bottom: 32,
                //       left: 0,
                //       right: 0,
                //       child: Row(
                //         mainAxisAlignment: MainAxisAlignment.center,
                //         children: [
                //           FloatingActionButton(
                //             backgroundColor: Colors.red,
                //             onPressed: () async {
                //               await _call?.leave();
                //               setState(() => _call = null);
                //             },
                //             child: const Icon(Icons.call_end),
                //           ),
                //         ],
                //       ),
                //     ),
                //   ],
                // );
              },
            )
          : const Center(
              child: Text('Waiting for calls'),
            ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _call?.leave();
    super.dispose();
    _compositeSubscription.cancel();
  }
}

// Handle background messages
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // Handle the background message
}
