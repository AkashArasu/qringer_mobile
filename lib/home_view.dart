import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:qringer_mobile_stream_io/callscreen_view.dart';
import 'package:qringer_mobile_stream_io/my_qrcode_view.dart';
import 'package:qringer_mobile_stream_io/utils/app_init.dart';
import 'package:qringer_mobile_stream_io/login_view.dart';
import 'package:stream_video_flutter/stream_video_flutter.dart' as streamvf;
import 'package:qringer_mobile_stream_io/utils/firebase_messaging_handler.dart';
import 'package:qringer_mobile_stream_io/utils/app_theme.dart';
import 'package:qringer_mobile_stream_io/utils/signaling_client.dart';
import 'package:qringer_mobile_stream_io/utils/incoming_answer.dart';

// Grid pattern painter for drawer header
class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 0.5;

    // Draw horizontal lines
    for (double y = 0; y < size.height; y += 15) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Draw vertical lines
    for (double x = 0; x < size.width; x += 15) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Simplified dots for better performance
    final dotPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..strokeWidth = 1;

    // Draw fewer dots for better performance
    final random = math.Random(42);
    for (int i = 0; i < 8; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      canvas.drawCircle(Offset(x, y), 0.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class HomeView extends StatefulWidget {
  const HomeView({this.initialVideoCall, super.key});

  /// The saved preference read before the first frame during a cold start.
  /// It avoids briefly rendering Video Call before an Audio Call preference
  /// is restored from secure storage.
  final bool? initialVideoCall;

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> with WidgetsBindingObserver {
  final streamvf.Subscriptions subscriptions = streamvf.Subscriptions();
  bool videoCall = true;
  bool _isLoading = false;
  bool _isHandlingNativeAnswer = false;
  bool _hasOpenedIncomingCall = false;
  String? _openedIncomingCallCid;
  bool _callPreferenceLoaded = false;
  streamvf.CallData? _pendingNativeAccept;
  static const int _fcmSubscription = 1;
  static const int _nativeAcceptSubscription = 2;
  static const int _nativeDeclineSubscription = 3;
  static const int _nativeEndSubscription = 4;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    videoCall = widget.initialVideoCall ?? true;
    // Attach before any await. Android may deliver the Answer action as soon
    // as Flutter attaches to a process launched from a notification.
    _observeNativeRingingActions();
    _initializeApp();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Repair a connection or device mapping that may have failed while the
      // phone was offline. This is idempotent and never changes call state.
      unawaited(AppInitializer.ensurePushRegistration());
      unawaited(_recoverAcceptedNativeCall());
    }
  }

  Future<void> _initializeApp() async {
    try {
      // A normal authenticated cold start already supplied this before the
      // first frame. Retain the storage read for direct HomeView construction
      // after sign-in and in tests.
      videoCall = widget.initialVideoCall ??
          await BackgroundStreamVideoManager.getCallPreference();
      _callPreferenceLoaded = true;
      if (mounted) setState(() {});

      final pendingAccept = _pendingNativeAccept;
      _pendingNativeAccept = null;
      if (pendingAccept != null) {
        debugPrint('Processing native Answer queued during startup');
        unawaited(_acceptNativeCall(pendingAccept));
      }

      _observeFcmMessages();
      _recoverAcceptedCallAfterTerminatedLaunch();
    } catch (e) {
      debugPrint('Error initializing app: $e');
      _showErrorSnackBar('Failed to initialize app features');
    }
  }

  void _observeFcmMessages() {
    subscriptions.add(
      _fcmSubscription,
      FirebaseMessaging.onMessage.listen(_handleRemoteMessage),
    );
  }

  Future<bool> _handleRemoteMessage(RemoteMessage message) async {
    try {
      if (message.data['sender'] != 'stream.video') return false;
      final client = streamvf.StreamVideo.instance;
      if (message.data['type'] != 'call.ring') {
        return client.handleRingingFlowNotifications(message.data);
      }
      final callCid = message.data['call_cid'] as String?;
      final uuid = nativeUuidForCallCid(callCid);
      if (uuid == null || callCid == null) return false;
      final sentAt = message.sentTime;
      if (sentAt != null &&
          DateTime.now().difference(sentAt) >= const Duration(seconds: 30)) {
        debugPrint('Ignoring expired foreground ring cid=$callCid');
        return false;
      }
      if (await hasNativeCallForCid(callCid, client)) return true;
      await client.pushNotificationManager?.showIncomingCall(
        uuid: uuid,
        callCid: callCid,
        callerName: 'Visitor',
        handle: 'Visitor at your door',
        hasVideo: videoCall,
      );
      debugPrint('QROnly foreground ring presented cid=$callCid');
      return true;
    } catch (e, stackTrace) {
      debugPrint('Foreground ring failed: $e');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }

  void _observeNativeRingingActions() {
    // Stream's observeCoreRingingEvents joins RTC before its callback. Listen
    // to native actions directly so the Worker can accept first and CallScreen
    // can apply the saved audio/video mode to the one and only media join.
    final client = streamvf.StreamVideo.instance;
    final accept = client.onRingingEvent<streamvf.ActionCallAccept>((event) {
      if (!_callPreferenceLoaded) {
        _pendingNativeAccept = event.data;
      } else {
        unawaited(_acceptNativeCall(event.data));
      }
    });
    if (accept != null) subscriptions.add(_nativeAcceptSubscription, accept);

    final decline = client.onRingingEvent<streamvf.ActionCallDecline>((event) {
      final cid = event.data.callCid;
      if (cid != null) unawaited(_rejectNativeCall(cid));
    });
    if (decline != null) subscriptions.add(_nativeDeclineSubscription, decline);

    final ended = client.onRingingEvent<streamvf.ActionCallEnded>((event) {
      final cid = event.data.callCid;
      if (cid != null && event.data.endedBySystem) {
        unawaited(SignalingClient.end(_callIdFromCid(cid)));
      }
    });
    if (ended != null) subscriptions.add(_nativeEndSubscription, ended);
  }

  /// Native Answer can arrive before the Flutter listener exists.
  /// Recover only an explicitly accepted call, never a merely ringing one.
  void _recoverAcceptedCallAfterTerminatedLaunch() {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_recoverAcceptedNativeCall());
    });
  }

  Future<void> _recoverAcceptedNativeCall() async {
    if (!_callPreferenceLoaded || !mounted) return;
    for (var attempt = 1; attempt <= 4; attempt++) {
      if (_isHandlingNativeAnswer || _hasOpenedIncomingCall) return;
      try {
        final call = await acceptedNativeCall();
        if (call != null) {
          debugPrint('Recovering accepted native call (attempt $attempt)');
          await _acceptNativeCall(call);
          return;
        }
      } catch (error, stackTrace) {
        debugPrint('Native Answer recovery attempt $attempt failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }

      if (attempt < 4) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
  }

  Future<void> _acceptNativeCall(streamvf.CallData data) async {
    if (_isHandlingNativeAnswer) return;
    final uuid = data.uuid;
    final callCid = data.callCid;
    if (uuid == null || callCid == null) {
      debugPrint('Native Answer ignored: missing call identifiers');
      return;
    }

    _isHandlingNativeAnswer = true;
    try {
      if (_hasOpenedIncomingCall) return;
      final callToJoin = await IncomingAnswer.accept(uuid, callCid);
      debugPrint('Native Answer ready; opening CallScreen: ${callToJoin.callCid}');
      await _acceptAndOpenCall(callToJoin, source: 'native Answer');
    } catch (error, stackTrace) {
      debugPrint('Native Answer failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted && error is! CallUnavailableException) {
        _showErrorSnackBar('Unable to answer the incoming call');
      }
    } finally {
      _isHandlingNativeAnswer = false;
    }
  }

  Future<void> _rejectNativeCall(String callCid) async {
    try {
      await SignalingClient.reject(_callIdFromCid(callCid));
    } catch (error) {
      debugPrint('Native decline signaling failed: $error');
    }
  }

  Future<void> _acceptAndOpenCall(
    streamvf.Call callToJoin, {
    required String source,
  }) async {
    final callCid = callToJoin.callCid.id;
    if (_hasOpenedIncomingCall) {
      debugPrint(
        'Incoming-call navigation suppressed: active=$_openedIncomingCallCid, '
        'requested=$callCid',
      );
      return;
    }
    _hasOpenedIncomingCall = true;
    _openedIncomingCallCid = callCid;
    try {
      debugPrint(
          'Marking QROnly call accepted and opening screen: ${callToJoin.callCid}, video=$videoCall');
      await _handleCallJoin(callToJoin, source);
    } catch (_) {
      _hasOpenedIncomingCall = false;
      _openedIncomingCallCid = null;
      rethrow;
    }
  }

  String _callIdFromCid(String cid) =>
      cid.contains(':') ? cid.split(':').last : cid;

  Future<void> _handleCallJoin(streamvf.Call callToJoin, String source) async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      debugPrint('Joining call from $source with video: $videoCall');

      // CallScreen owns the single join and applies the homeowner's media
      // preference as initial connect options. Joining here first with SDK
      // defaults could publish video before an audio-only preference was set.
      debugPrint(
          'Opening call from $source - CallScreen will join with video: $videoCall');

      if (mounted) {
        // Keep the duplicate-event guard only while this route is actually
        // open. Previously Navigator.push was deliberately not awaited, but
        // the guard was never reset when CallScreen popped. Every later
        // notification Answer action was therefore accepted natively yet
        // suppressed before it could navigate away from Home.
        final route = Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => CallScreen(
              call: callToJoin,
              videoCall: videoCall,
            ),
          ),
        );
        unawaited(route.whenComplete(() {
          if (_openedIncomingCallCid == callToJoin.callCid.id) {
            debugPrint(
                'Incoming call route closed; enabling the next Answer action');
            _hasOpenedIncomingCall = false;
            _openedIncomingCallCid = null;
          }
        }));
      }
    } catch (e) {
      debugPrint('Error joining call from $source: $e');
      if (mounted) {
        _showErrorSnackBar('Failed to join call: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.withOpacity(0.8),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Dismiss',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  Future<void> _updateCallPreference(bool newVideoCall) async {
    try {
      setState(() {
        videoCall = newVideoCall;
      });

      // Sync with background handler
      await BackgroundStreamVideoManager.setCallPreference(newVideoCall);
      debugPrint('Call preference updated to video: $newVideoCall');
    } catch (e) {
      debugPrint('Error updating call preference: $e');
      _showErrorSnackBar('Failed to save call preference');
    }
  }

  Future<void> _handleLogout() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      debugPrint('Starting logout process...');

      // Cancel all subscriptions first
      subscriptions.cancelAll();

      // Disconnect and reset main StreamVideo instance
      await streamvf.StreamVideo.instance.disconnect();
      await streamvf.StreamVideo.reset();

      // Clear stored user data
      await AppInitializer.clearStoredUser();

      debugPrint('Logout completed successfully');

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const LoginView(),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error during logout: $e');
      if (mounted) {
        _showErrorSnackBar('Logout failed. Please try again.');
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    subscriptions.cancelAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      body: RepaintBoundary(
        child: Container(
          decoration: const BoxDecoration(
            gradient: AppTheme.backgroundGradient,
          ),
          child: SafeArea(
            child: Column(
              children: [
                // Custom App Bar
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.menu, color: Colors.white),
                          onPressed: () {
                            _scaffoldKey.currentState?.openDrawer();
                          },
                        ),
                      ),
                      const Spacer(),
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [Colors.green, Colors.lightGreen],
                        ).createShader(bounds),
                        child: const Text(
                          'QROnly',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: _isLoading
                            ? const Padding(
                                padding: EdgeInsets.all(12.0),
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                                  ),
                                ),
                              )
                            : IconButton(
                                icon: const Icon(Icons.logout,
                                    color: Colors.white),
                                onPressed: () async {
                                  await _handleLogout();
                                },
                              ),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Profile Avatar
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                Colors.green.withOpacity(0.8),
                                Colors.lightGreen.withOpacity(0.6),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.green.withOpacity(0.3),
                                blurRadius: 20,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.person,
                            size: 50,
                            color: Colors.white,
                          ),
                        ),

                        const SizedBox(height: 32),

                        Text(
                          'Welcome back,',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[400],
                          ),
                        ),

                        const SizedBox(height: 8),

                        Text(
                          streamvf.StreamVideo.instance.currentUser.name,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),

                        const SizedBox(height: 60),

                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.cyan.withOpacity(0.2),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              const Text(
                                'Call Preference',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Choose how visitors will reach you',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[400],
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 32),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildCallTypeButton(
                                      icon: Icons.videocam,
                                      label: 'Video Call',
                                      isSelected: videoCall,
                                      onTap: _isLoading
                                          ? null
                                          : () => _updateCallPreference(true),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _buildCallTypeButton(
                                      icon: Icons.phone,
                                      label: 'Audio Call',
                                      isSelected: !videoCall,
                                      onTap: _isLoading
                                          ? null
                                          : () => _updateCallPreference(false),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 40),

                        Text(
                          'Your digital doorbell is ready',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      drawer: _buildDrawer(),
    );
  }

  Widget _buildCallTypeButton({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback? onTap,
  }) {
    final bool isDisabled = onTap == null || _isLoading;

    return GestureDetector(
      onTap: isDisabled ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 0),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          gradient: isSelected && !isDisabled
              ? LinearGradient(
                  colors: [
                    Colors.cyan.withOpacity(0.6),
                    Colors.blue.withOpacity(0.6),
                  ],
                )
              : null,
          color: isSelected && !isDisabled
              ? null
              : Colors.white.withOpacity(isDisabled ? 0.02 : 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected && !isDisabled
                ? Colors.green.withOpacity(0.8)
                : Colors.grey.withOpacity(isDisabled ? 0.1 : 0.2),
            width: 1,
          ),
        ),
        child: Column(
          children: [
            if (_isLoading && isSelected)
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            else
              Icon(
                icon,
                color: isSelected && !isDisabled
                    ? Colors.white
                    : Colors.grey[isDisabled ? 600 : 400],
                size: 28,
              ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected && !isDisabled
                    ? Colors.white
                    : Colors.grey[isDisabled ? 600 : 400],
                fontWeight: isSelected && !isDisabled
                    ? FontWeight.bold
                    : FontWeight.normal,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    required VoidCallback? onTap,
    Color iconColor = Colors.green,
  }) {
    final bool isDisabled = onTap == null;
    final Color effectiveIconColor =
        isDisabled ? iconColor.withOpacity(0.5) : iconColor;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: isDisabled ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: effectiveIconColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: effectiveIconColor, size: 22),
                ),
                const SizedBox(width: 16),
                Text(
                  title,
                  style: TextStyle(
                    color: isDisabled
                        ? Colors.white.withOpacity(0.5)
                        : Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white.withOpacity(isDisabled ? 0.1 : 0.3),
                  size: 14,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF1A1A2E),
      child: Column(
        children: [
          Container(
            height: 200,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.green.withOpacity(0.8),
                  Colors.lightGreen.withOpacity(0.7),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: SafeArea(
              child: Stack(
                children: [
                  // Background pattern
                  Positioned.fill(
                    child: Opacity(
                      opacity: 0.1,
                      child: CustomPaint(
                        painter: GridPainter(),
                      ),
                    ),
                  ),
                  // User info
                  Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Row(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const CircleAvatar(
                                radius: 35,
                                backgroundColor: Colors.white,
                                child: Icon(
                                  Icons.person,
                                  size: 40,
                                  color: Colors.green,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    streamvf
                                        .StreamVideo.instance.currentUser.name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      shadows: [
                                        Shadow(
                                          color: Colors.black26,
                                          blurRadius: 2,
                                          offset: Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      streamvf
                                          .StreamVideo.instance.currentUser.id,
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.9),
                                        fontSize: 14,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                _buildDrawerItem(
                  icon: Icons.qr_code_2,
                  title: 'My QR Code',
                  onTap: _isLoading
                      ? null
                      : () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const MyQRCodeScreen(),
                            ),
                          );
                        },
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Container(
                    height: 1,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          Colors.white.withOpacity(0.2),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                _buildDrawerItem(
                  icon: Icons.logout,
                  title: 'Logout',
                  iconColor: Colors.red,
                  onTap: _isLoading
                      ? null
                      : () async {
                          Navigator.pop(context);
                          await _handleLogout();
                        },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
