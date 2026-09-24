import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:stream_video_flutter/stream_video_flutter.dart' as streamvf;
import 'package:stream_video_push_notification/stream_video_push_notification.dart';
import 'package:qringer_mobile_stream_io/callscreen_view.dart';
import 'package:qringer_mobile_stream_io/home_view.dart';
import 'package:qringer_mobile_stream_io/login_view.dart';

import 'package:qringer_mobile_stream_io/utils/app_init.dart';
import 'package:qringer_mobile_stream_io/utils/user.dart';
import 'package:qringer_mobile_stream_io/utils/firebase_messaging_handler.dart';

import 'firebase_options.dart';
import 'utils/incoming_answer.dart';

// Apply global green gradient surfaces if needed via themes

/// Enhanced Firebase Messaging setup for reliable background call handling
Future<void> _setupFirebaseMessaging() async {
  final messaging = FirebaseMessaging.instance;

  try {
    debugPrint('🔥 Setting up Firebase Messaging for background calls...');

    // Request permissions with maximum settings for calls
    final settings = await messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      // VoIP pushes/CallKit handle incoming calls on iOS. Requesting critical
      // alerts without Apple's entitlement can make the permission request
      // fail and is not needed for this flow.
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    debugPrint('🔥 FCM permission status: ${settings.authorizationStatus}');

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('✅ FCM permissions granted');

      // Confirm token availability without writing credential material to logs.
      final token = await messaging.getToken();
      debugPrint('🔥 FCM token available: ${token?.isNotEmpty == true}');

      // Android-specific: Set foreground notification presentation options
      if (Platform.isAndroid) {
        await messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
        // Android 14+ can require explicit user approval before an incoming
        // call notification may open full-screen over a locked device.
        await StreamVideoPushNotificationManager
            .ensureFullScreenIntentPermission();
      }

      // Push priority is selected by Stream's server payload, not the Android
      // manifest. What the app can guarantee here is a valid device mapping.
      await AppInitializer.ensurePushRegistration(maxAttempts: 3);
    } else {
      debugPrint('❌ FCM permissions denied: ${settings.authorizationStatus}');
    }
  } catch (e) {
    debugPrint('❌ Error setting up Firebase Messaging: $e');
  }
}

/// Returns only a call that the homeowner explicitly accepted in the native
/// native notification UI. A merely ringing call must continue to open Home,
/// otherwise launching the app manually could answer a visitor accidentally.
Future<streamvf.CallData?> _acceptedNativeCallForColdStart() async {
  if (!Platform.isAndroid && !Platform.isIOS) return null;
  try {
    for (var attempt = 0; attempt < 4; attempt++) {
      final call = await acceptedNativeCall();
      if (call != null) return call;
      if (attempt < 3) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
  } catch (error) {
    debugPrint('Cold-start native call lookup failed: $error');
  }
  return null;
}

Future<void> main() async {
  // Initialize Flutter binding
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations for better performance
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set system UI overlay style for better integration
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF1A1A2E),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Register Firebase Cloud Messaging background handler
  // This ensures notifications work when app is in background or terminated
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Read these independently of the Stream connection. Passing the saved
  // preference into HomeView prevents a video-to-audio visual jump on every
  // cold start for an audio-only homeowner.
  final storedUserFuture = AppInitializer.getStoredUser();
  final callPreferenceFuture = BackgroundStreamVideoManager.getCallPreference();
  final storedUser = await storedUserFuture;
  final initialVideoCall = await callPreferenceFuture;
  streamvf.CallData? acceptedNativeCall;

  if (storedUser != null) {
    // Construct the authenticated client immediately, but do not block the
    // first frame on a WebSocket connection. Normal startup repairs it just
    // after runApp; a notification Answer route connects explicitly below.
    await AppInitializer.init(storedUser, connect: false);
    acceptedNativeCall = await _acceptedNativeCallForColdStart();
  }

  // Render as soon as the authenticated Stream client is available. Permission
  // and token-refresh work is not required to consume an Answer action, and
  // doing it before runApp made notification-launched startup unnecessarily
  // slow.
  runApp(QROnlyApp(
    storedUser: storedUser,
    initialVideoCall: initialVideoCall,
    acceptedNativeCall: acceptedNativeCall,
  ));

  if (storedUser != null && acceptedNativeCall == null) {
    // Connection repair must not depend on the notification permission dialog
    // or FCM token lookup succeeding.
    unawaited(AppInitializer.ensurePushRegistration(maxAttempts: 3));
  }
  if (acceptedNativeCall == null) unawaited(_setupFirebaseMessaging());
}

class QROnlyApp extends StatelessWidget {
  final User? storedUser;
  final bool? initialVideoCall;
  final streamvf.CallData? acceptedNativeCall;

  /// Allows widget tests to verify initial routing without loading Firebase.
  /// Production uses [LoginView].
  final Widget Function()? unauthenticatedHomeBuilder;

  const QROnlyApp({
    this.storedUser,
    this.initialVideoCall,
    this.acceptedNativeCall,
    this.unauthenticatedHomeBuilder,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QROnly - Digital Doorbell',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A3A1A)),
        useMaterial3: true,
        fontFamily: 'Inter',
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1A3A1A),
          foregroundColor: Colors.white,
        ),
        // Performance optimizations
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: CupertinoPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
            TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
          },
        ),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      debugShowCheckedModeBanner: false,
      // Use builder to apply global performance optimizations
      builder: (context, child) {
        return MediaQuery(
          // Disable text scaling for consistent UI
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.0),
          ),
          child: child!,
        );
      },
      home: _getInitialScreen(),
    );
  }

  Widget _getInitialScreen() {
    // If no stored user, always go to login
    if (storedUser == null) {
      return unauthenticatedHomeBuilder?.call() ?? const LoginView();
    }

    // Normal flow - go to home screen
    final acceptedCall = acceptedNativeCall;
    if (acceptedCall != null && initialVideoCall != null) {
      return ColdStartCallScreen(
        nativeCall: acceptedCall,
        videoCall: initialVideoCall!,
      );
    }
    return HomeView(initialVideoCall: initialVideoCall);
  }
}

/// First route for an Answer action that launched a terminated mobile app.
/// It intentionally has no Home UI: native Answer has already expressed the
/// homeowner's intent, so the only visible state while Stream resolves the
/// call is a branded connecting screen.
class ColdStartCallScreen extends StatefulWidget {
  const ColdStartCallScreen({
    required this.nativeCall,
    required this.videoCall,
    super.key,
  });

  final streamvf.CallData nativeCall;
  final bool videoCall;

  @override
  State<ColdStartCallScreen> createState() => _ColdStartCallScreenState();
}

class _ColdStartCallScreenState extends State<ColdStartCallScreen> {
  final String _status = 'Connecting to visitor…';
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_openAcceptedCall());
    });
  }

  Future<void> _openAcceptedCall() async {
    if (_started) return;
    _started = true;
    final uuid = widget.nativeCall.uuid;
    final callCid = widget.nativeCall.callCid;
    if (uuid == null || callCid == null) {
      await _fallbackToHome('The accepted call data is unavailable.');
      return;
    }

    try {
      final call = await IncomingAnswer.accept(uuid, callCid);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CallScreen(call: call, videoCall: widget.videoCall),
        ),
      );
      // CallScreen pops when the visitor or homeowner ends the call. Return
      // to the normal homeowner home route without ever showing the
      // connecting screen again.
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
              builder: (_) => HomeView(initialVideoCall: widget.videoCall)),
        );
        unawaited(_setupFirebaseMessaging());
      }
    } catch (error, stackTrace) {
      debugPrint('Direct cold-start call routing failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      await _fallbackToHome(
          'Unable to connect this call. It may have ended. Please ask the visitor to try again.');
    }
  }

  Future<void> _fallbackToHome(String message) async {
    debugPrint(message);
    final callCid = widget.nativeCall.callCid;
    if (callCid != null && streamvf.StreamVideo.isInitialized()) {
      try {
        await streamvf.StreamVideo.instance.pushNotificationManager
            ?.endCallByCid(callCid, silent: true);
      } catch (error) {
        debugPrint('Native call cleanup failed: $error');
      }
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
          builder: (_) => HomeView(initialVideoCall: widget.videoCall)),
    );
    unawaited(_setupFirebaseMessaging());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.doorbell, color: Colors.lightGreen, size: 72),
            const SizedBox(height: 24),
            Text(
              _status,
              style: const TextStyle(color: Colors.white, fontSize: 22),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            const CircularProgressIndicator(color: Colors.lightGreen),
          ],
        ),
      ),
    );
  }
}
