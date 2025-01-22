// lib/screens/login_screen.dart

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

  String countryCode = '+60'; // Default country code (e.g. Malaysia)
  String restOfNumber = '';   // The rest of the phone number after country code

  bool isLoading = false;
  String errorMessage = '';

  /// Combines [countryCode] and [restOfNumber] into a full phone number
  String get fullPhoneNumber => '$countryCode$restOfNumber';

  /// Initiates phone number verification
  Future<void> _verifyPhoneNumber() async {
    setState(() {
      isLoading = true;
      errorMessage = '';
    });

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: fullPhoneNumber,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Auto-retrieval or instant validation is available
          await _auth.signInWithCredential(credential);
          // The StreamBuilder in main.dart will handle navigation
        },
        verificationFailed: (FirebaseAuthException e) {
          if (mounted) {
            setState(() {
              isLoading = false;
              errorMessage = e.message ?? 'An error occurred.';
            });
          }
        },
        codeSent: (String verificationId, int? resendToken) {
          if (mounted) {
            setState(() => isLoading = false);

            // Navigate to VerificationScreen
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => VerificationScreen(
                  verificationId: verificationId,
                  phoneNumber: fullPhoneNumber,
                ),
              ),
            );
          }
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          if (mounted) {
            setState(() => isLoading = false);
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
          errorMessage = 'Failed to Verify Phone Number: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // A more modern-looking AppBar
      appBar: AppBar(
        title: const Text('PopChat - Login'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: const Color(0xFF0265FF), // A bright modern color
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        // Modern background color or gradient
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
              // Card adds a more modern "elevated" look
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 6,
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // A nice heading
                      Text(
                        'Log In With Phone',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Country code + rest of phone number in a row
                      Row(
                        children: [
                          // Dropdown for country code
                          Expanded(
                            flex: 3,
                            child: _buildCountryCodeDropdown(),
                          ),
                          const SizedBox(width: 8),
                          // Phone number text field
                          Expanded(
                            flex: 7,
                            child: TextFormField(
                              decoration: const InputDecoration(
                                labelText: 'Phone Number',
                                hintText: '123456789',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.phone,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter your phone number';
                                }
                                return null;
                              },
                              onChanged: (value) => restOfNumber = value.trim(),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Loading indicator or button
                      if (isLoading)
                        const CircularProgressIndicator()
                      else
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              if (_formKey.currentState?.validate() ?? false) {
                                _verifyPhoneNumber();
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: const Color(0xFF0265FF),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ), // Button background color
                              elevation: 5, // Adds shadow for depth
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min, // Wraps content tightly
                              children: [
                                Icon(Icons.phone, color: Colors.white),
                                const SizedBox(width: 8),
                                Text(
                                  'Verify Phone Number',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),

                        ),

                      const SizedBox(height: 10),
                      // Error message
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

  /// Builds a simple dropdown for selecting the country code
  Widget _buildCountryCodeDropdown() {
    // List of commonly used country codes
    final countryCodes = <String>['+1', '+44', '+60', '+65', '+91'];

    return DropdownButtonFormField<String>(
      decoration: const InputDecoration(
        labelText: 'Country Code',
        border: OutlineInputBorder(),
      ),
      value: countryCode,
      items: countryCodes.map((code) {
        return DropdownMenuItem<String>(
          value: code,
          child: Text(code),
        );
      }).toList(),
      onChanged: (value) {
        setState(() {
          countryCode = value ?? '+60';
        });
      },
    );
  }
}
