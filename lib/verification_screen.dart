// lib/verification_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'additional_info_screen.dart';

class VerificationScreen extends StatefulWidget {
  final String verificationId;
  final String phoneNumber;

  VerificationScreen(
      {required this.verificationId, required this.phoneNumber});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  final _auth = FirebaseAuth.instance;

  final _formKey = GlobalKey<FormState>();
  String smsCode = '';
  bool isLoading = false;
  String errorMessage = '';

  Future<void> _signInWithPhoneNumber() async {
    setState(() {
      isLoading = true;
      errorMessage = '';
    });

    try {
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
          verificationId: widget.verificationId, smsCode: smsCode);

      UserCredential userCredential =
      await _auth.signInWithCredential(credential);

      // Check if this is a new user
      bool isNewUser = userCredential.additionalUserInfo?.isNewUser ?? false;

      if (isNewUser) {
        // Navigate to additional info screen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => AdditionalInfoScreen(
              user: userCredential.user!,
            ),
          ),
        );
      } else {
        // Existing user; no need to navigate manually
        // The StreamBuilder in main.dart will handle it
        Navigator.popUntil(context, (route) => route.isFirst);
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        isLoading = false;
        errorMessage = e.message ?? 'An error occurred.';
      });
    } catch (e) {
      setState(() {
        isLoading = false;
        errorMessage = 'Failed to sign in: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: Text('Verify OTP')),
        body: Padding(
            padding: EdgeInsets.all(16.0),
            child: Form(
                key: _formKey,
                child: Column(children: [
                  Text(
                    'Enter the OTP sent to ${widget.phoneNumber}',
                    style: TextStyle(fontSize: 16),
                  ),
                  SizedBox(height: 20),
                  TextFormField(
                    decoration: InputDecoration(labelText: 'OTP'),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty)
                        return 'Please enter OTP';
                      return null;
                    },
                    onChanged: (value) => smsCode = value.trim(),
                  ),
                  SizedBox(height: 20),
                  isLoading
                      ? CircularProgressIndicator()
                      : ElevatedButton(
                      onPressed: () {
                        if (_formKey.currentState?.validate() ?? false) {
                          _signInWithPhoneNumber();
                        }
                      },
                      child: Text('Verify')),
                  SizedBox(height: 10),
                  Text(errorMessage, style: TextStyle(color: Colors.red)),
                ]))));
  }
}
