// lib/screens/verification_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'additional_info_screen.dart';

class VerificationScreen extends StatefulWidget {
  final String verificationId;
  final String phoneNumber;

  VerificationScreen({required this.verificationId, required this.phoneNumber});

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
      final credential = PhoneAuthProvider.credential(
        verificationId: widget.verificationId,
        smsCode: smsCode,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      final isNewUser = userCredential.additionalUserInfo?.isNewUser ?? false;

      if (isNewUser) {
        // Navigate to additional info screen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => AdditionalInfoScreen(user: userCredential.user!),
          ),
        );
      } else {
        // Existing user
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
      appBar: AppBar(
        title: const Text('Verify OTP'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Text(
                'Enter the OTP sent to ${widget.phoneNumber}',
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 20),
              TextFormField(
                decoration: const InputDecoration(labelText: 'OTP'),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter OTP';
                  }
                  return null;
                },
                onChanged: (value) => smsCode = value.trim(),
              ),
              const SizedBox(height: 20),
              if (isLoading)
                const CircularProgressIndicator()
              else
                ElevatedButton(
                  onPressed: () {
                    if (_formKey.currentState?.validate() ?? false) {
                      _signInWithPhoneNumber();
                    }
                  },
                  child: const Text('Verify'),
                ),
              const SizedBox(height: 10),
              Text(errorMessage, style: const TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ),
    );
  }
}
