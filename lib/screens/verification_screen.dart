// lib/screens/verification_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'additional_info_screen.dart';

class VerificationScreen extends StatefulWidget {
  final String verificationId;
  final String phoneNumber;

  VerificationScreen({
    required this.verificationId,
    required this.phoneNumber,
  });

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
        // Navigate to AdditionalInfoScreen
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
      // Modern AppBar
      appBar: AppBar(
        title: const Text('PopChat - Verify'),
        centerTitle: true,
        backgroundColor: const Color(0xFF0265FF),
        elevation: 0,
      ),
      // Gradient Background for a modern look
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF0265FF),
              Color(0xFF3CAEFF),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Card(
              elevation: 6,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header text
                      Text(
                        'Verify Your Phone',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800],
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Subheader with phone number
                      Text(
                        'Enter the OTP sent to:',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Highlight phone number
                      Text(
                        widget.phoneNumber,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 20),
                      // OTP Entry Field
                      TextFormField(
                        decoration: const InputDecoration(
                          labelText: 'OTP',
                          hintText: '6-digit code',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter the OTP';
                          }
                          if (value.length < 4) {
                            return 'OTP must be at least 4 digits';
                          }
                          return null;
                        },
                        onChanged: (value) => smsCode = value.trim(),
                      ),
                      const SizedBox(height: 20),

                      // Verify Button or Loading Indicator
                      if (isLoading)
                        const CircularProgressIndicator()
                      else
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              if (_formKey.currentState?.validate() ?? false) {
                                _signInWithPhoneNumber();
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0265FF),
                              elevation: 5,
                              padding: const EdgeInsets.symmetric(
                                vertical: 16,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              'Verify',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 10),
                      // Error Message
                      if (errorMessage.isNotEmpty)
                        Text(
                          errorMessage,
                          style: const TextStyle(color: Colors.red),
                          textAlign: TextAlign.center,
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
}
