import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'dart:ui';

class OTPVerificationScreen extends StatefulWidget {
  final String phoneNumber;
  final String verificationId;
  final Function onVerified;

  const OTPVerificationScreen({
    super.key,
    required this.phoneNumber,
    required this.verificationId,
    required this.onVerified,
  });

  @override
  State<OTPVerificationScreen> createState() => _OTPVerificationScreenState();
}

class _OTPVerificationScreenState extends State<OTPVerificationScreen> {
  final int _otpLength = 6;
  final List<FocusNode> _focusNodes = [];
  final List<TextEditingController> _controllers = [];
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isResendEnabled = false;
  bool _isVerifying = false;
  int _remainingTime = 60;
  Timer? _timer;
  String _errorMessage = '';
  late String _verificationId;

  @override
  void initState() {
    super.initState();
    _verificationId = widget.verificationId;

    // Initialize controllers and focus nodes
    for (int i = 0; i < _otpLength; i++) {
      _focusNodes.add(FocusNode());
      _controllers.add(TextEditingController());
    }

    // Start countdown for resend button
    _startCountdown();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() {
      _isResendEnabled = false;
      _remainingTime = 60;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_remainingTime > 0) {
          _remainingTime--;
        } else {
          _isResendEnabled = true;
          timer.cancel();
        }
      });
    });
  }

  String _getOtpValue() {
    return _controllers.map((controller) => controller.text).join();
  }

  Future<void> _verifyOtp() async {
    final otp = _getOtpValue();

    if (otp.length < _otpLength) {
      setState(() {
        _errorMessage = 'Please enter a valid OTP';
      });
      return;
    }

    setState(() {
      _errorMessage = '';
      _isVerifying = true;
    });

    try {
      // Create a PhoneAuthCredential with the verification ID and OTP
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _verificationId,
        smsCode: otp,
      );

      // Sign in with the credential
      await _auth.signInWithCredential(credential);

      // If we get here, authentication was successful
      if (mounted) {
        widget.onVerified();
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        _errorMessage = e.message ?? 'Invalid verification code';
        _isVerifying = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'An error occurred. Please try again.';
        _isVerifying = false;
      });
    }
  }

  Future<void> _resendOtp() async {
    if (!_isResendEnabled) return;

    // Clear fields
    for (var controller in _controllers) {
      controller.clear();
    }

    // Focus first field
    FocusScope.of(context).requestFocus(_focusNodes[0]);

    // Show loading indicator
    setState(() {
      _isResendEnabled = false;
    });

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: widget.phoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) async {
          await _auth.signInWithCredential(credential);
          if (mounted) {
            widget.onVerified();
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          setState(() {
            _errorMessage = 'Verification failed: ${e.message}';
          });
        },
        codeSent: (String verificationId, int? resendToken) {
          // Firebase creates a new verification session for each resend. Use
          // its new ID when validating the new SMS code.
          _verificationId = verificationId;
          // Reset countdown
          _startCountdown();

          // Show confirmation
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('OTP resent successfully!'),
              duration: Duration(seconds: 2),
            ),
          );
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          // Auto-retrieval timeout
        },
        timeout: const Duration(seconds: 60),
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to resend code. Please try again.';
        _isResendEnabled = true;
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();

    for (var node in _focusNodes) {
      node.dispose();
    }

    for (var controller in _controllers) {
      controller.dispose();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0B2E0B),
              Color(0xFF1A3A1A),
              Color(0xFF2D5A2D),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Custom App Bar
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(height: 40),

                        // Lock Icon
                        Container(
                          width: 80,
                          height: 80,
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
                            Icons.security,
                            size: 40,
                            color: Colors.white,
                          ),
                        ),

                        const SizedBox(height: 40),

                        ShaderMask(
                          shaderCallback: (bounds) => LinearGradient(
                            colors: [
                              Colors.green,
                              Colors.lightGreen,
                            ],
                          ).createShader(bounds),
                          child: const Text(
                            'Verification',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        Text(
                          'We sent a verification code to',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[400],
                          ),
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: 8),

                        Text(
                          widget.phoneNumber,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: 50),

                        // OTP fields
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: List.generate(
                            _otpLength,
                            (index) => _buildOtpTextField(index),
                          ),
                        ),

                        if (_errorMessage.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: Colors.red.withOpacity(0.3)),
                            ),
                            child: Text(
                              _errorMessage,
                              style: const TextStyle(
                                  color: Colors.red, fontSize: 14),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],

                        const SizedBox(height: 50),

                        // Verify button
                        _buildVerifyButton(),

                        const SizedBox(height: 32),

                        // Resend OTP option
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "Didn't receive code? ",
                              style: TextStyle(color: Colors.grey[400]),
                            ),
                            GestureDetector(
                              onTap: _isResendEnabled ? _resendOtp : null,
                              child: Text(
                                _isResendEnabled
                                    ? "Resend"
                                    : "Resend in $_remainingTime seconds",
                                style: TextStyle(
                                  color: _isResendEnabled
                                      ? Colors.cyan
                                      : Colors.grey,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 50),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVerifyButton() {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            Colors.cyan.withOpacity(0.8),
            Colors.blue.withOpacity(0.8),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.cyan.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _isVerifying ? null : _verifyOtp,
          child: Center(
            child: _isVerifying
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      strokeWidth: 2,
                    ),
                  )
                : const Text(
                    'Verify',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildOtpTextField(int index) {
    return Container(
      width: 48,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _focusNodes[index].hasFocus
              ? Colors.cyan
              : Colors.cyan.withOpacity(0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Focus(
            onKeyEvent: (node, event) {
              // Soft keyboards often report deletion through onChanged, but
              // hardware keyboards can send Backspace while this box is
              // already empty. Handle both paths so editing always moves
              // naturally to the preceding digit.
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.backspace &&
                  _controllers[index].text.isEmpty &&
                  index > 0) {
                FocusScope.of(context).requestFocus(_focusNodes[index - 1]);
                final previous = _controllers[index - 1];
                previous.selection = TextSelection.collapsed(
                  offset: previous.text.length,
                );
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: TextField(
              controller: _controllers[index],
              focusNode: _focusNodes[index],
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 1,
              decoration: const InputDecoration(
                counterText: '',
                border: InputBorder.none,
              ),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              onChanged: (value) {
                if (value.isNotEmpty && index < _otpLength - 1) {
                  FocusScope.of(context).requestFocus(_focusNodes[index + 1]);
                } else if (value.isNotEmpty && index == _otpLength - 1) {
                  _verifyOtp();
                } else if (value.isEmpty && index > 0) {
                  // Deleting the current digit moves the cursor back so the
                  // previous digit can be corrected immediately.
                  FocusScope.of(context).requestFocus(_focusNodes[index - 1]);
                  final previous = _controllers[index - 1];
                  previous.selection = TextSelection.collapsed(
                    offset: previous.text.length,
                  );
                }
              },
              onTap: () {
                _controllers[index].selection = TextSelection(
                  baseOffset: 0,
                  extentOffset: _controllers[index].text.length,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
