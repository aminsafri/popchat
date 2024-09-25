// lib/signup_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SignUpScreen extends StatefulWidget {
  @override
  _SignUpScreenState createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  final _formKey = GlobalKey<FormState>();
  String email = '';
  String nickname = '';
  String password = '';
  String errorMessage = '';

  Future<void> _signUp() async {
    try {
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Save the nickname to Firestore
      await _firestore.collection('users').doc(userCredential.user?.uid).set({
        'nickname': nickname,
        'email': email,
      });

      Navigator.pushReplacementNamed(context, '/home');
    } on FirebaseAuthException catch (e) {
      setState(() {
        errorMessage = e.message ?? 'An error occurred.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: Text('Sign Up')),
        body: Padding(
            padding: EdgeInsets.all(16.0),
            child: Form(
                key: _formKey,
                child: Column(children: [
                  TextFormField(
                    decoration: InputDecoration(labelText: 'Email'),
                    validator: (value) {
                      if (value == null || value.isEmpty)
                        return 'Please enter email';
                      return null;
                    },
                    onChanged: (value) => email = value,
                  ),
                  TextFormField(
                    decoration: InputDecoration(labelText: 'Nickname'),
                    validator: (value) {
                      if (value == null || value.isEmpty)
                        return 'Please enter nickname';
                      return null;
                    },
                    onChanged: (value) => nickname = value,
                  ),
                  TextFormField(
                    decoration: InputDecoration(labelText: 'Password'),
                    obscureText: true,
                    validator: (value) {
                      if (value == null || value.length < 6)
                        return 'Password must be at least 6 characters';
                      return null;
                    },
                    onChanged: (value) => password = value,
                  ),
                  SizedBox(height: 20),
                  ElevatedButton(
                      onPressed: () {
                        if (_formKey.currentState?.validate() ?? false) {
                          _signUp();
                        }
                      },
                      child: Text('Sign Up')),
                  SizedBox(height: 10),
                  Text(errorMessage,
                      style: TextStyle(color: Colors.red)),
                  TextButton(
                      onPressed: () {
                        Navigator.pushReplacementNamed(context, '/login');
                      },
                      child: Text('Already have an account? Log in'))
                ]))));
  }
}
