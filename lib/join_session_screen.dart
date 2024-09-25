// lib/join_session_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class JoinSessionScreen extends StatefulWidget {
  @override
  _JoinSessionScreenState createState() => _JoinSessionScreenState();
}

class _JoinSessionScreenState extends State<JoinSessionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String sessionCode = '';
  String secretKey = '';
  String alternativeName = '';
  String errorMessage = '';

  Future<void> _joinSession() async {
    if (!_formKey.currentState!.validate()) return;

    DocumentSnapshot sessionDoc =
    await _firestore.collection('chat_sessions').doc(sessionCode).get();

    if (!sessionDoc.exists) {
      setState(() => errorMessage = 'Session not found');
      return;
    }

    Map<String, dynamic> sessionData = sessionDoc.data() as Map<String, dynamic>;

    // Check if session has expired
    Timestamp expiryTime = sessionData['expiryTime'];
    if (expiryTime.toDate().isBefore(DateTime.now())) {
      setState(() => errorMessage = 'Session has expired');
      return;
    }

    // Check if secret key is required
    if (sessionData['requiresSecretKey'] == true) {
      if (secretKey != sessionData['secretKey']) {
        setState(() => errorMessage = 'Invalid secret key');
        return;
      }
    }

    // Check if max participants reached
    List<dynamic> participants = sessionData['participants'];
    int maxParticipants = sessionData['maxParticipants'];
    if (participants.length >= maxParticipants) {
      setState(() => errorMessage = 'Session is full');
      return;
    }

    String userId = _auth.currentUser!.uid;

    // Add user to participants
    participants.add(userId);

    // Update alternative names
    Map<String, dynamic> alternativeNames =
    Map<String, dynamic>.from(sessionData['alternativeNames']);
    alternativeNames[userId] = alternativeName.isNotEmpty
        ? alternativeName
        : _auth.currentUser!.email;

    await _firestore.collection('chat_sessions').doc(sessionCode).update({
      'participants': participants,
      'alternativeNames': alternativeNames,
    });

    // Navigate to the chat screen
    Navigator.pushReplacementNamed(context, '/chat', arguments: {
      'sessionCode': sessionCode,
      'alternativeName': alternativeName,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: Text('Join Chat Session')),
        body: Padding(
            padding: EdgeInsets.all(16.0),
            child: Form(
                key: _formKey,
                child: ListView(children: [
                  TextFormField(
                    decoration: InputDecoration(labelText: 'Session Code'),
                    validator: (value) {
                      if (value == null || value.isEmpty)
                        return 'Please enter session code';
                      return null;
                    },
                    onChanged: (value) => sessionCode = value.toUpperCase(),
                  ),
                  TextFormField(
                    decoration: InputDecoration(labelText: 'Alternative Display Name'),
                    onChanged: (value) => alternativeName = value,
                  ),
                  // Secret key field will be shown if required after validation
                  TextFormField(
                    decoration: InputDecoration(labelText: 'Secret Key (if required)'),
                    onChanged: (value) => secretKey = value,
                  ),
                  SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _joinSession,
                    child: Text('Join Session'),
                  ),
                  SizedBox(height: 10),
                  Text(
                    errorMessage,
                    style: TextStyle(color: Colors.red),
                  ),
                ]))));
  }
}
