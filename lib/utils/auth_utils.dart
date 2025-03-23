import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AuthUtils {
  // static Future<UserCredential> signUp(
  //     String email, String password, BuildContext context) async {
  //   try {
  //     // Create user with email and password
  //     UserCredential userCredential =
  //         await FirebaseAuth.instance.createUserWithEmailAndPassword(
  //       email: email,
  //       password: password,
  //     );
  //       // Show success message
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       const SnackBar(content: Text('Registration successful!')),
  //     );
  //     return userCredential;
  //   } on FirebaseAuthException catch (e) {
  //     // Handle errors
  //     if (e.code == 'email-already-in-use') {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         const SnackBar(content: Text('Email already in use')),
  //       );
  //     }
  //   } catch (e) {
  //     // Handle other errors
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       SnackBar(content: Text('An error occurred: $e')),
  //     );
  //   }
  // }

static Future<void> signOut() async {
  try {
    await FirebaseAuth.instance.signOut(); // Sign out from Firebase
  } catch (e) {
    print("Error signing out: $e"); // Handle potential errors
  }
}

}



