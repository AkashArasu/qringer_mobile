import 'dart:developer' as developer;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'utils/auth_utils.dart';

class RegisterView extends StatefulWidget {
  const RegisterView({super.key});
  @override
  State<RegisterView> createState() => _RegisterViewState();
}

class _RegisterViewState extends State<RegisterView> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isObscurePassword = true;
  bool _isObscureConfirmPassword = true;

  late bool _showPasswordValidationError;
  late bool _showConfirmPasswordValidationError;
  late bool _showEmailValidationError;

  final _formKey = GlobalKey<FormState>();
  final fieldPasswordKey = GlobalKey<FormFieldState>();
  final fieldConfirmPasswordKey = GlobalKey<FormFieldState>();
  final fieldEmailKey = GlobalKey<FormFieldState>();

  late FocusNode _passwordFocusNode;
  late FocusNode _confirmPasswordFocusNode;
  late FocusNode _emailFocusNode;

  @override
  void initState() {
    super.initState();
    _passwordFocusNode = FocusNode();
    _confirmPasswordFocusNode = FocusNode();
    _emailFocusNode = FocusNode();

    _passwordFocusNode.addListener(() {
      if (!_passwordFocusNode.hasFocus) {
        setState(() {
          _showPasswordValidationError = false;
          fieldPasswordKey.currentState!.validate();
        });
      } else {
        if (!_showPasswordValidationError) {
          setState(() {
            _showPasswordValidationError = true;
            fieldPasswordKey.currentState!.validate();
          });
        }
      }
    });

    _confirmPasswordFocusNode.addListener(() {
      if (!_confirmPasswordFocusNode.hasFocus) {
        setState(() {
          _showConfirmPasswordValidationError = false;
          fieldConfirmPasswordKey.currentState!.validate();
        });
      } else {
        if (!_showConfirmPasswordValidationError) {
          setState(() {
            _showConfirmPasswordValidationError = true;
            fieldConfirmPasswordKey.currentState!.validate();
          });
        }
      }
    });

    _emailFocusNode.addListener(() {
      if (!_emailFocusNode.hasFocus) {
        setState(() {
          _showEmailValidationError = false;
          fieldEmailKey.currentState!.validate();
        });
      } else {
        if (!_showEmailValidationError) {
          setState(() {
            _showEmailValidationError = true;
            fieldEmailKey.currentState!.validate();
          });
        }
      }
    });
  }

  void signUp(String email, String password) async {
    try {
      // Create user with email and password
      UserCredential userCredential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      if (!mounted) return;
      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registration successful!')),
      );

      // Optionally, navigate to another screen after successful registration
      // Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => HomeScreen()));
    } on FirebaseAuthException catch (e) {
      // Handle errors
      if (!mounted) return;
      if (e.code == 'email-already-in-use') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email already in use')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Registration failed: ${e.message}')),
        );
      }
    } catch (e) {
      // Handle other errors
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('An error occurred: $e')),
      );
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _passwordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
    _emailFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ButtonStyle buttonStyle = ElevatedButton.styleFrom(
        backgroundColor: Colors.green,
        foregroundColor: Colors.black87,
        minimumSize: const Size(double.infinity, 40));

    return Scaffold(
      appBar: AppBar(
        title: const Text("Register"),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Card.filled(
            color: Colors.grey[800],
            shape: const RoundedRectangleBorder(
              side: BorderSide(color: Colors.green, width: 2.0),
              borderRadius: BorderRadius.all(Radius.circular(20.0)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(15.0),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  // mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("Register",
                        style: TextStyle(color: Colors.white, fontSize: 20.0)),
                    const SizedBox(height: 30),
                    TextFormField(
                      controller: _emailController,
                      focusNode: _emailFocusNode,
                      key: fieldEmailKey,
                      decoration: InputDecoration(
                        hintText: 'Email',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding:
                            const EdgeInsets.fromLTRB(15.0, 0, 0, 0),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      onChanged: (value) {
                        _emailController.text = value;
                        _showEmailValidationError = true;
                        fieldEmailKey.currentState!.validate();
                      }, // Use email keyboard type
                      validator: (value) {
                        if (!_showEmailValidationError) return null;

                        if (value == null || value.isEmpty) {
                          return 'Please enter your email';
                        }
                        if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                            .hasMatch(value)) {
                          return 'Please enter a valid email address';
                        }
                        return null;
                      },
                      onTapOutside: (_) {
                        FocusScope.of(context).unfocus();
                      },
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _passwordController,
                      focusNode: _passwordFocusNode,
                      key: fieldPasswordKey,
                      obscureText: _isObscurePassword,
                      decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          hintText: "Password",
                          suffixIcon: IconButton(
                            // ignore: dead_code
                            icon: Icon(_isObscurePassword
                                ? Icons.visibility
                                : Icons.visibility_off),
                            onPressed: () {
                              setState(() {
                                _isObscurePassword = !_isObscurePassword;
                              });
                            },
                          ),
                          contentPadding:
                              const EdgeInsets.fromLTRB(15.0, 0, 0, 0)),
                      onChanged: (value) {
                        _passwordController.text = value;
                        _showPasswordValidationError = true;
                        fieldPasswordKey.currentState!.validate();
                      },
                      validator: (value) {
                        if (!_showPasswordValidationError) return null;

                        if (value == null || value.isEmpty) {
                          return 'Please enter a password';
                        }
                        if (value.length < 8) {
                          return 'Password must be at least 8 characters long';
                        }
                        if (!value.contains(RegExp(r'[A-Z]'))) {
                          return 'Password must contain at least one uppercase letter';
                        }
                        if (!value.contains(RegExp(r'[a-z]'))) {
                          return 'Password must contain at least one lowercase letter';
                        }
                        if (!value.contains(RegExp(r'[0-9]'))) {
                          return 'Password must contain at least one number';
                        }
                        if (!value
                            .contains(RegExp(r'[!@#$%^&*(),.?":{}|<>_]'))) {
                          return 'Password must contain at least one special character';
                        }
                        return null;
                      },
                      onTapOutside: (_) {
                        FocusScope.of(context).unfocus();
                      },
                    ),
                    const SizedBox(
                      height: 20,
                    ),
                    TextFormField(
                      focusNode: _confirmPasswordFocusNode,
                      key: fieldConfirmPasswordKey,
                      obscureText: _isObscureConfirmPassword,
                      controller: _confirmPasswordController,
                      decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          hintText: "Confirm Password",
                          suffixIcon: IconButton(
                            icon: Icon(_isObscureConfirmPassword
                                ? Icons.visibility
                                : Icons.visibility_off),
                            onPressed: () {
                              setState(() {
                                _isObscureConfirmPassword =
                                    !_isObscureConfirmPassword;
                              });
                            },
                          ),
                          contentPadding:
                              const EdgeInsets.fromLTRB(15.0, 0, 0, 0)),
                      onChanged: (value) {
                        _confirmPasswordController.text = value;

                        _showConfirmPasswordValidationError = true;

                        fieldConfirmPasswordKey.currentState!.validate();
                      },
                      validator: (value) {
                        if (!_showConfirmPasswordValidationError) return null;
                        if (value == null || value.isEmpty) {
                          return 'Please confirm your password';
                        }
                        if (value != _passwordController.text) {
                          return 'Passwords do not match';
                        }
                        return null;
                      },
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
                          setState(() {
                            _showPasswordValidationError = true;
                            _showConfirmPasswordValidationError = true;
                          });

                          if (fieldEmailKey.currentState!.validate() &&
                              fieldPasswordKey.currentState!.validate() &&
                              fieldConfirmPasswordKey.currentState!
                                  .validate()) {
                            // await AuthUtils.signUp(_emailController.text.trim(),
                            //     _passwordController.text.trim(), context);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please fill all the fields correctly')),
                            );
                          }
                        },
                        child: const Text("Register")),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
