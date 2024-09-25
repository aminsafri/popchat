// lib/create_session_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';

class CreateSessionScreen extends StatefulWidget {
  @override
  _CreateSessionScreenState createState() => _CreateSessionScreenState();
}

class _CreateSessionScreenState extends State<CreateSessionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  int maxParticipants = 10;
  Duration sessionDuration = Duration(hours: 1);
  bool requiresSecretKey = false;
  String secretKey = '';
  String alternativeName = '';

  Future<void> _createSession() async {
    if (!_formKey.currentState!.validate()) return;

    String sessionCode = await generateUniqueSessionCode(6);
    String ownerId = _auth.currentUser!.uid;

    DateTime expiryTime = DateTime.now().add(sessionDuration);

    Map<String, dynamic> sessionData = {
      'ownerId': ownerId,
      'maxParticipants': maxParticipants,
      'expiryTime': Timestamp.fromDate(expiryTime),
      'createdAt': Timestamp.now(),
      'requiresSecretKey': requiresSecretKey,
      'secretKey': requiresSecretKey ? secretKey : null,
      'participants': [ownerId],
      'alternativeNames': {
        ownerId: alternativeName.isNotEmpty ? alternativeName : _auth.currentUser!.email,
      },
      'unreadCounts': {}, // Initialize unreadCounts
    };

    await _firestore.collection('chat_sessions').doc(sessionCode).set(sessionData);

    // Navigate to the chat screen
    Navigator.pushReplacementNamed(context, '/chat', arguments: {
      'sessionCode': sessionCode,
      'alternativeName': alternativeName,
    });
  }

  // Existing generateUniqueCode method
  String generateUniqueCode(int length) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    Random random = Random.secure();
    return List.generate(length, (index) => chars[random.nextInt(chars.length)]).join();
  }

  // New generateUniqueSessionCode method
  Future<String> generateUniqueSessionCode(int length) async {
    String code;
    bool exists = true;

    do {
      code = generateUniqueCode(length);
      // Check if the code already exists in Firestore
      var doc = await _firestore.collection('chat_sessions').doc(code).get();
      exists = doc.exists;
    } while (exists);

    return code;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: Text('Create Chat Session')),
        body: Padding(
            padding: EdgeInsets.all(16.0),
            child: Form(
                key: _formKey,
                child: ListView(children: [
                  TextFormField(
                    decoration: InputDecoration(labelText: 'Alternative Display Name'),
                    onChanged: (value) => alternativeName = value,
                  ),
                  TextFormField(
                    decoration: InputDecoration(labelText: 'Maximum Participants'),
                    initialValue: '10',
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      int? val = int.tryParse(value!);
                      if (val == null || val < 1) {
                        return 'Enter a valid number greater than 0';
                      }
                      return null;
                    },
                    onChanged: (value) => maxParticipants = int.parse(value),
                  ),
                  DropdownButtonFormField<Duration>(
                    decoration: InputDecoration(labelText: 'Session Duration'),
                    value: sessionDuration,
                    items: [
                      DropdownMenuItem(
                          child: Text('30 Minutes'), value: Duration(minutes: 30)),
                      DropdownMenuItem(
                          child: Text('1 Hour'), value: Duration(hours: 1)),
                      DropdownMenuItem(
                          child: Text('2 Hours'), value: Duration(hours: 2)),
                      DropdownMenuItem(
                          child: Text('1 Day'), value: Duration(days: 1)),
                    ],
                    onChanged: (value) => setState(() => sessionDuration = value!),
                  ),
                  SwitchListTile(
                    title: Text('Require Secret Key'),
                    value: requiresSecretKey,
                    onChanged: (value) => setState(() => requiresSecretKey = value),
                  ),
                  if (requiresSecretKey)
                    TextFormField(
                      decoration: InputDecoration(labelText: 'Secret Key'),
                      validator: (value) {
                        if (value == null || value.isEmpty)
                          return 'Please enter a secret key';
                        return null;
                      },
                      onChanged: (value) => secretKey = value,
                    ),
                  SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _createSession,
                    child: Text('Create Session'),
                  ),
                ]))));
  }
}
