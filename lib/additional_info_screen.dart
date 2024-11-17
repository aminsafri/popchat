// lib/additional_info_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'home_screen.dart';

class AdditionalInfoScreen extends StatefulWidget {
  final User user;

  AdditionalInfoScreen({required this.user});

  @override
  State<AdditionalInfoScreen> createState() => _AdditionalInfoScreenState();
}

class _AdditionalInfoScreenState extends State<AdditionalInfoScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _formKey = GlobalKey<FormState>();
  String displayName = '';
  bool isLoading = false;
  String errorMessage = '';

  Future<void> _saveUserInfo() async {
    setState(() {
      isLoading = true;
      errorMessage = '';
    });

    try {
      // Update user profile
      await widget.user.updateDisplayName(displayName);

      // Save user data to Firestore
      await _firestore.collection('users').doc(widget.user.uid).set({
        'displayName': displayName,
        'phoneNumber': widget.user.phoneNumber,
      });

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => HomeScreen()),
      );
    } catch (e) {
      setState(() {
        isLoading = false;
        errorMessage = 'Failed to save user info: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: Text('Additional Information')),
        body: Padding(
            padding: EdgeInsets.all(16.0),
            child: Form(
                key: _formKey,
                child: Column(children: [
                  Text(
                    'Enter your display name',
                    style: TextStyle(fontSize: 16),
                  ),
                  SizedBox(height: 20),
                  TextFormField(
                    decoration: InputDecoration(labelText: 'Display Name'),
                    validator: (value) {
                      if (value == null || value.isEmpty)
                        return 'Please enter display name';
                      return null;
                    },
                    onChanged: (value) => displayName = value.trim(),
                  ),
                  SizedBox(height: 20),
                  isLoading
                      ? CircularProgressIndicator()
                      : ElevatedButton(
                      onPressed: () {
                        if (_formKey.currentState?.validate() ?? false) {
                          _saveUserInfo();
                        }
                      },
                      child: Text('Continue')),
                  SizedBox(height: 10),
                  Text(errorMessage, style: TextStyle(color: Colors.red)),
                ]))));
  }
}
