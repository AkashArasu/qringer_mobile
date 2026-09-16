import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'package:flutter_libphonenumber/flutter_libphonenumber.dart'
    as formatnum;
import 'package:qringer_mobile_stream_io/home_view.dart';
import 'package:qringer_mobile_stream_io/utils/app_init.dart';

import 'package:qringer_mobile_stream_io/utils/user.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'package:qringer_mobile_stream_io/verify_view.dart';
import 'package:qringer_mobile_stream_io/utils/app_theme.dart';
import 'package:qringer_mobile_stream_io/utils/app_keys.dart';

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> with TickerProviderStateMixin {
  late final TextEditingController _phoneNumberController;
  late final TextEditingController _nameController;
  late final firebase_auth.FirebaseAuth auth;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _phoneNumberController = TextEditingController();
    _nameController = TextEditingController();
    auth = firebase_auth.FirebaseAuth.instance;

    // Initialize animations
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));

    // Start animation
    _animationController.forward();

    // Initialize formatnum
    formatnum.init();
  }

  @override
  void dispose() {
    _phoneNumberController.dispose();
    _nameController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> fetchHomeownerSession(String displayName) async {
    try {
      final firebaseUser = auth.currentUser;
      if (firebaseUser == null)
        throw Exception('Phone authentication is required');
      final idToken = await firebaseUser.getIdToken();
      final response = await http.post(
        Uri.parse('${AppKeys.signalingBaseUrl}/v1/homeowner/session'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json'
        },
        body: jsonEncode({'displayName': displayName}),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception(
          'Unable to create homeowner session (${response.statusCode}): '
          '${response.body}',
        );
      }
    } catch (e) {
      // If the server did not return a 200 OK response,
      // then throw an exception.
      throw Exception(e.toString());
    }
  }

  Future<void> _verifyPhoneNumber() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your name'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_phoneNumberController.text.trim().length != 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid 10-digit phone number'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final userId = _phoneNumberController.text.trim();
    final formattedPhoneNumber = formatnum.formatNumberSync("+1 $userId");
    final name = _nameController.text.trim();

    try {
      await auth.verifyPhoneNumber(
        phoneNumber: formattedPhoneNumber,
        verificationCompleted:
            (firebase_auth.PhoneAuthCredential credential) async {
          // Auto verification completed
          await auth.signInWithCredential(credential);
          await _completeAuthentication(userId, name);
        },
        verificationFailed: (firebase_auth.FirebaseAuthException e) {
          setState(() {
            _isLoading = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Verification failed: ${e.message}'),
              backgroundColor: Colors.red,
            ),
          );
        },
        codeSent: (String verificationId, int? forceResendingToken) async {
          setState(() {
            _isLoading = false;
          });

          // Navigate to OTP verification screen
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => OTPVerificationScreen(
                  phoneNumber: formattedPhoneNumber,
                  verificationId: verificationId,
                  onVerified: () async {
                    await _completeAuthentication(userId, name);
                  },
                ),
              ),
            );
          }
        },
        codeAutoRetrievalTimeout: (_) async {},
        timeout: const Duration(seconds: 60),
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Verification failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _completeAuthentication(String userId, String name) async {
    try {
      final session = await fetchHomeownerSession(name);
      final user = User.createUser(
        // Firebase UID is the account identity; phone numbers never appear in
        // public QR links or Stream user identifiers.
        userId: session['homeownerId'] as String,
        name: name,
        role: 'user',
        token: session['streamToken'] as String,
      );

      await AppInitializer.storeUser(user);
      await AppInitializer.storePropertyId(session['propertyId'] as String);
      await AppInitializer.init(user);

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => const HomeView(),
          ),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Authentication failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppTheme.backgroundGradient,
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Logo/Icon Section
                      Container(
                        width: 120,
                        height: 120,
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
                              color: Colors.green.withValues(alpha: .3),
                              blurRadius: 20,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.qr_code_2,
                          size: 60,
                          color: Colors.white,
                        ),
                      ),

                      const SizedBox(height: 40),

                      // Welcome Text
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [
                            Colors.green,
                            Colors.lightGreen,
                            Colors.teal,
                          ],
                        ).createShader(bounds),
                        child: const Text(
                          'QROnly',
                          style: TextStyle(
                            fontSize: 42,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 2,
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      Text(
                        'Digital Doorbell Revolution',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[400],
                          letterSpacing: 1,
                        ),
                      ),

                      const SizedBox(height: 60),

                      // Input Fields
                      _buildInputField(
                        controller: _nameController,
                        hintText: 'Full Name',
                        icon: Icons.person_outline,
                        keyboardType: TextInputType.name,
                      ),

                      const SizedBox(height: 24),

                      _buildInputField(
                        controller: _phoneNumberController,
                        hintText: 'Phone Number',
                        icon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                        prefix: '+1 ',
                      ),

                      const SizedBox(height: 40),

                      // Login Button
                      _buildLoginButton(),

                      const SizedBox(height: 32),

                      // Footer text
                      Text(
                        'Secure authentication via SMS',
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? prefix,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.cyan.withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              inputFormatters: inputFormatters,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 16,
                ),
                prefixIcon: Icon(
                  icon,
                  color: Colors.cyan.withOpacity(0.7),
                ),
                prefixText: prefix,
                prefixStyle: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
              ),
              onTapOutside: (_) {
                FocusScope.of(context).unfocus();
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginButton() {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            Colors.green.withOpacity(0.8),
            Colors.teal.withOpacity(0.8),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _isLoading ? null : _verifyPhoneNumber,
          child: Center(
            child: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      strokeWidth: 2,
                    ),
                  )
                : const Text(
                    'Get OTP',
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
}
