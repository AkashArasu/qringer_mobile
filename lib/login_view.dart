import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  late final TextEditingController _phoneNumberController;
  late final TextEditingController _passwordController;

  @override
  void initState() {
    _phoneNumberController = TextEditingController();
    _passwordController = TextEditingController();
    super.initState();
  }

  @override
  void dispose() {
    _phoneNumberController.dispose();
    _passwordController.dispose();
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
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        hintText: "Password",
                        contentPadding:
                            const EdgeInsets.fromLTRB(15.0, 0, 0, 0)),
                    obscureText: true,
                  ),
                  const SizedBox(
                    height: 30,
                  ),
                  ElevatedButton(
                      style: buttonStyle,
                      onPressed: () => {},
                      child: const Text("Login")),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
