import 'package:flutter/material.dart';
import 'dart:async';
import 'package:stream_video_flutter/stream_video_flutter.dart';
import 'package:qringer_mobile_stream_io/utils/performance_optimizations.dart' show OptimizedColors;
import 'package:qringer_mobile_stream_io/utils/signaling_client.dart';

class CallScreen extends StatefulWidget {
  final Call call;
  final bool videoCall;

  const CallScreen({
    super.key,
    required this.call,
    required this.videoCall,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  late bool _isCameraEnabled;
  bool _isMicEnabled = true;
  bool _isLoading = false;
  bool _endSignalled = false;
  bool _closing = false;
  StreamSubscription<CallState>? _participantSubscription;

  @override
  void initState() {
    super.initState();
    // Initialize camera state based on call type preference
    _isCameraEnabled = widget.videoCall;
    
    // Listen for participant changes to debug visibility issues
    _listenToParticipantChanges();
  }
  
  void _listenToParticipantChanges() {
    _participantSubscription = widget.call.state.listen((callState) {
      debugPrint('Participants changed:');
      debugPrint('- Total: ${callState.callParticipants.length}');
      debugPrint('- Local: ${callState.localParticipant?.name}');
      debugPrint('- All participants: ${callState.callParticipants.map((p) => p.name).toList()}');
      
      // Log video track information in a simpler way
      for (final participant in callState.callParticipants) {
        debugPrint('  - ${participant.name}: ${participant.publishedTracks.keys.toList()}');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          try {
            await _signalEndOnce();
            await widget.call.leave();
          } catch (e) {
            debugPrint('Error leaving call on back press: $e');
          }
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: StreamCallContainer(
          call: widget.call,
          callConnectOptions: CallConnectOptions(
            camera: TrackOption.fromSetting(enabled: widget.videoCall),
            microphone: TrackOption.enabled(),
            speakerDefaultOn: true,
          ),
          // Suppress StreamCallContainer's default Navigator.pop. All local
          // and remote disconnects go through the single guarded exit below.
          onCallDisconnected: (_) => unawaited(_exitCallScreen()),
          callContentWidgetBuilder: (context, call) {
            return Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    OptimizedColors.darkNavy,
                    OptimizedColors.mediumNavy,
                    Color(0xFF0F0F0F),
                  ],
                ),
              ),
              child: StreamCallContent(
                call: call,
                layoutMode: ParticipantLayoutMode.grid,
                callControlsWidgetBuilder: (context, call) => _buildCustomControls(),
                callAppBarWidgetBuilder: (context, call) => _buildCustomAppBar(),
                // Use default participant rendering - it handles local/remote participants automatically
              ),
            );
          },
        ),
      ),
    );
  }





  PreferredSizeWidget _buildCustomAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight + 20),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 10, left: 16, right: 16),
          child: Row(
            children: [
              // Simple back button - using native Material button for better performance
              Material(
                color: OptimizedColors.blackOverlay40,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: _endCall,
                  borderRadius: BorderRadius.circular(12),
                  child: const SizedBox(
                    width: 48,
                    height: 48,
                    child: Icon(Icons.arrow_back, color: Colors.white, size: 24),
                  ),
                ),
              ),
              
              const Spacer(),
              
              // Simplified call info
              const Text(
                'QROnly',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              
              const Spacer(),
              const SizedBox(width: 48), // Balance
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomControls() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: OptimizedColors.blackOverlay40,
            borderRadius: BorderRadius.circular(25),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Video toggle - optimized static button
              _OptimizedControlButton(
                icon: _isCameraEnabled ? Icons.videocam : Icons.videocam_off,
                isActive: _isCameraEnabled,
                isLoading: _isLoading,
                onTap: _toggleCamera,
              ),
              
              // Microphone toggle - optimized static button
              _OptimizedControlButton(
                icon: _isMicEnabled ? Icons.mic : Icons.mic_off,
                isActive: _isMicEnabled,
                isLoading: _isLoading,
                onTap: _toggleMicrophone,
              ),
              
              // End call - optimized static button
              _OptimizedControlButton(
                icon: Icons.call_end,
                isActive: false,
                isEndCall: true,
                isLoading: _isLoading,
                onTap: _endCall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Optimized toggle methods with faster state updates
  void _toggleCamera() async {
    if (_isLoading) return;
    
    // Optimistic UI update for snappy response
    final newState = !_isCameraEnabled;
    setState(() {
      _isCameraEnabled = newState;
      _isLoading = true;
    });
    
    try {
      // Toggle camera enable/disable - this will control video transmission
      await widget.call.setCameraEnabled(enabled: newState);
    } catch (e) {
      // Revert on error
      setState(() => _isCameraEnabled = !newState);
      debugPrint('Error toggling camera: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _toggleMicrophone() async {
    if (_isLoading) return;
    
    // Optimistic UI update for snappy response
    final newState = !_isMicEnabled;
    setState(() {
      _isMicEnabled = newState;
      _isLoading = true;
    });
    
    try {
      await widget.call.setMicrophoneEnabled(enabled: newState);
    } catch (e) {
      // Revert on error
      setState(() => _isMicEnabled = !newState);
      debugPrint('Error toggling microphone: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _endCall() => unawaited(_exitCallScreen(signalEnd: true, leave: true));

  Future<void> _exitCallScreen({
    bool signalEnd = false,
    bool leave = false,
  }) async {
    if (_closing) return;
    _closing = true;
    if (mounted) setState(() => _isLoading = true);

    try {
      if (signalEnd) await _signalEndOnce();
      if (leave) await widget.call.leave();
    } catch (error) {
      debugPrint('Error closing call: $error');
    }

    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _participantSubscription?.cancel();
    // Clean up call resources when leaving the screen
    unawaited(_signalEndOnce());
    if (!_closing) _leaveCallSafely();
    super.dispose();
  }

  Future<void> _signalEndOnce() async {
    if (_endSignalled) return;
    _endSignalled = true;
    try {
      await SignalingClient.end(widget.call.callCid.id);
    } catch (error) {
      // Leaving media is still important if a transient network failure keeps
      // the signalling request from reaching the Worker.
      debugPrint('Error ending call in signaling service: $error');
    }
  }

  void _leaveCallSafely() async {
    try {
      await widget.call.leave();
    } catch (error) {
      debugPrint('Error leaving call during dispose: $error');
    }
  }
}

/// Highly optimized control button that only rebuilds when its state changes
class _OptimizedControlButton extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final bool isLoading;
  final bool isEndCall;
  final VoidCallback onTap;
  
  const _OptimizedControlButton({
    required this.icon,
    required this.isActive,
    required this.isLoading,
    required this.onTap,
    this.isEndCall = false,
  });

  // Static const objects - created once, never rebuilt
  static const BorderRadius _borderRadius = BorderRadius.all(Radius.circular(30));
  static const Size _buttonSize = Size(60, 60);
  
  // Pre-calculated colors as const static
  static const Color _endCallColor = OptimizedColors.redOverlay90;
  static const Color _activeColor = OptimizedColors.greenOverlay20;
  static const Color _inactiveColor = OptimizedColors.redOverlay20;
  static const Color _endCallIconColor = Colors.white;
  static const Color _activeIconColor = OptimizedColors.primaryGreen;
  static const Color _inactiveIconColor = Colors.red;

  @override
  Widget build(BuildContext context) {
    // Calculate colors once per build
    final buttonColor = isEndCall 
        ? _endCallColor
        : isActive 
            ? _activeColor
            : _inactiveColor;
    
    final iconColor = isEndCall 
        ? _endCallIconColor
        : isActive 
            ? _activeIconColor
            : _inactiveIconColor;
    
    return Material(
      color: buttonColor,
      borderRadius: _borderRadius,
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: _borderRadius,
        child: SizedBox.fromSize(
          size: _buttonSize,
          // child: isLoading 
          //     ? const Center(
          //         child: SizedBox(
          //           width: 20,
          //           height: 20,
          //           child: CircularProgressIndicator(
          //             color: Colors.white,
          //             strokeWidth: 2,
          //           ),
          //         ),
          //       )
          //     : Icon(icon, color: iconColor, size: 28),
          child: Icon(icon, color: iconColor, size: 28),
        ),
      ),
    );
  }
  
  // Note: StatelessWidget doesn't allow overriding == and hashCode
  // Flutter automatically optimizes rebuilds based on widget properties
}
