// lib/login_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'verification_screen.dart';

class LoginScreen extends StatefulWidget {
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _auth = FirebaseAuth.instance;

  final _formKey = GlobalKey<FormState>();
  String phoneNumber = '';
  bool isLoading = false;
  String errorMessage = '';

  Future<void> _verifyPhoneNumber() async {
    setState(() {
      isLoading = true;
      errorMessage = '';
    });

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Auto-retrieval or instant validation has completed
          await _auth.signInWithCredential(credential);
          // No need to navigate manually; StreamBuilder will handle it
        },
        verificationFailed: (FirebaseAuthException e) {
          setState(() {
            isLoading = false;
            errorMessage = e.message ?? 'An error occurred.';
          });
        },
        codeSent: (String verificationId, int? resendToken) {
          setState(() {
            isLoading = false;
          });
          // Navigate to verification screen
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => VerificationScreen(
                verificationId: verificationId,
                phoneNumber: phoneNumber,
              ),
            ),
          );
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          setState(() {
            isLoading = false;
          });
        },
      );
    } catch (e) {
      setState(() {
        isLoading = false;
        errorMessage = 'Failed to Verify Phone Number: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: Text('Log In')),
        body: Padding(
            padding: EdgeInsets.all(16.0),
            child: Form(
                key: _formKey,
                child: Column(children: [
                  TextFormField(
                    decoration: InputDecoration(labelText: 'Phone Number'),
                    keyboardType: TextInputType.phone,
                    validator: (value) {
                      if (value == null || value.isEmpty)
                        return 'Please enter phone number';
                      return null;
                    },
                    onChanged: (value) => phoneNumber = value.trim(),
                  ),
                  SizedBox(height: 20),
                  isLoading
                      ? CircularProgressIndicator()
                      : ElevatedButton(
                      onPressed: () {
                        if (_formKey.currentState?.validate() ?? false) {
                          _verifyPhoneNumber();
                        }
                      },
                      child: Text('Verify Phone Number')),
                  SizedBox(height: 10),
                  Text(errorMessage, style: TextStyle(color: Colors.red)),
                ]))));
  }
}
