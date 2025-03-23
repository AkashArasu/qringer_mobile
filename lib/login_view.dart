import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_libphonenumber/flutter_libphonenumber.dart'
    as formatnum;
import 'package:qringer_mobile_stream_io/home_view.dart';
import 'package:qringer_mobile_stream_io/utils/app_init.dart';
import 'dart:developer' as developer;

import 'package:qringer_mobile_stream_io/utils/user.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'package:qringer_mobile_stream_io/verify_view.dart';

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  late final TextEditingController _phoneNumberController;
  late final TextEditingController _nameController;
  late final User? user;
  late final firebase_auth.FirebaseAuth auth;
  late final String token;
  bool _isLoading = false;
  String? _verificationId;

  @override
  void initState() {
    _phoneNumberController = TextEditingController();
    _nameController = TextEditingController();
    // auth = firebase_auth.FirebaseAuth.instance;
    // formatnum.init();
    super.initState();
  }

  @override
  void dispose() {
    _phoneNumberController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<String> fetchToken(String userId) async {
    try {
      final response = await http.post(
        Uri.parse('https://token-server.takash-arasu.workers.dev/token'),
        body: jsonEncode({"userId": userId})
      );
      if (response.statusCode == 200) {
        // If the server did return a 200 OK response,
        // then parse the JSON.
        // print("It comes till here !!!");
        return response.body;
      } else {
        throw Exception('Failed to load token: ${response.statusCode}');
      }
    } catch (e) {
      // If the server did not return a 200 OK response,
      // then throw an exception.
      throw Exception(e.toString());
    }
  }

  Future<void> _verifyPhoneNumber() async {
    setState(() {
      _isLoading = true;
    });

    final userId = _phoneNumberController.text.trim();
    final formattedUserId = formatnum.formatNumberSync("+1 $userId");
    final name = _nameController.text.trim();

    try {
      await auth.verifyPhoneNumber(
        phoneNumber: formattedUserId,
        verificationCompleted:
            (firebase_auth.PhoneAuthCredential credential) async {
          await auth.signInWithCredential(credential);
          token = await fetchToken(userId);
          user = User.createUser(
            userId: userId,
            name: name,
            role: 'user',
            token: token,
          );

          await AppInitializer.storeUser(user!);
          await AppInitializer.init(user!);

          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => const HomeView(),
              ),
            );
          }
        },
        verificationFailed: (firebase_auth.FirebaseAuthException e) {
          setState(() {
            _isLoading = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Verification failed: ${e.message}')),
          );
        },
        codeSent: (String verificationId, int? forceResendingToken) async {
          setState(() {
            _isLoading = false;
            _verificationId = verificationId;
          });

          // Navigate to OTP verification screen
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => OTPVerificationScreen(
                phoneNumber: userId,
                verificationId: verificationId,
                onVerified: () {
                  // Navigate to home screen or next screen after successful verification
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (context) => const HomeView(),
                    ),
                  );
                },
              ),
            ),
          );
        },
        codeAutoRetrievalTimeout: (String verificationId) async {
          _verificationId = verificationId;
        },
        timeout: const Duration(seconds: 60),
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Verification failed: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ButtonStyle buttonStyle = ElevatedButton.styleFrom(
        backgroundColor: Colors.green,
        foregroundColor: Colors.black87,
        minimumSize: const Size(double.infinity, 40));

    return Scaffold(
      appBar: AppBar(
        title: const Text("QR icon"), //insert qr ringer icon here
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Card.filled(
            color: Colors.black87,
            shape: const RoundedRectangleBorder(
              side: BorderSide(color: Colors.green, width: 2.0),
              borderRadius: BorderRadius.all(Radius.circular(20.0)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(15.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                // mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Welcome",
                      style: TextStyle(color: Colors.white, fontSize: 20.0)),
                  const SizedBox(height: 30),
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        hintText: "First Name",
                        contentPadding:
                            const EdgeInsets.fromLTRB(15.0, 0, 0, 0)),
                    onTapOutside: (_) {
                      FocusScope.of(context).unfocus();
                    },
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _phoneNumberController,
                    decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        hintText: "Phone number",
                        contentPadding:
                            const EdgeInsets.fromLTRB(15.0, 0, 0, 0)),
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    onTapOutside: (_) {
                      FocusScope.of(context).unfocus();
                    },
                  ),
                  const SizedBox(
                    height: 30,
                  ),
                  ElevatedButton(
                      style: buttonStyle,
                      onPressed: () async {
                        final userId = _phoneNumberController.text.trim();
                        final name = _nameController.text.trim();
                        token = await fetchToken(userId);
                        print("Token: $token");
                        user = User.createUser(
                          userId: userId,
                          name: name,
                          role: 'user',
                          token: token,
                        );

                        await AppInitializer.storeUser(user!);
                        await AppInitializer.init(user!);

                        if (context.mounted) {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (context) => const HomeView(),
                            ),
                          );
                        }
                      },
                      child: _isLoading
                          ? const CircularProgressIndicator()
                          : const Text("Login")),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
