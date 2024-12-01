// lib/join_session_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_screen.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:basic_utils/basic_utils.dart';
import 'package:pointycastle/asymmetric/api.dart' show RSAPublicKey;
import 'dart:convert';

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

  final storage = FlutterSecureStorage();

  encrypt.Key generateGroupKey() {
    return encrypt.Key.fromSecureRandom(32); // 256-bit key
  }

  Future<String> encryptGroupKeyForParticipant(String participantPublicKeyPem, encrypt.Key groupKey) async {
    RSAPublicKey publicKey = CryptoUtils.rsaPublicKeyFromPem(participantPublicKeyPem);

    final encrypter = encrypt.Encrypter(encrypt.RSA(publicKey: publicKey));
    final encryptedGroupKey = encrypter.encryptBytes(groupKey.bytes);
    return encryptedGroupKey.base64;
  }

  Future<void> _joinSession() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      DocumentSnapshot sessionDoc = await _firestore.collection('chat_sessions').doc(sessionCode).get();

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

      String userId = _auth.currentUser!.uid;

      // Check if user is already in leftParticipants
      List<dynamic> leftParticipants = sessionData['leftParticipants'] ?? [];
      if (leftParticipants.contains(userId)) {
        // Remove user from leftParticipants
        leftParticipants.remove(userId);
      }

      // Add user to participants if not already present
      List<dynamic> participants = sessionData['participants'] ?? [];
      if (!participants.contains(userId)) {
        participants.add(userId);
      }

      // Update alternative names
      Map<String, dynamic> alternativeNames = Map<String, dynamic>.from(sessionData['alternativeNames'] ?? {});
      alternativeNames[userId] = alternativeName.isNotEmpty ? alternativeName : _auth.currentUser!.displayName;

      // Generate new group key
      encrypt.Key newGroupKey = generateGroupKey();

      // Encrypt group key for all participants
      Map<String, String> encryptedGroupKeys = {};

      for (String participantId in participants) {
        // Retrieve participant's public key from Firestore
        DocumentSnapshot userDoc = await _firestore.collection('users').doc(participantId).get();
        String participantPublicKeyPem = userDoc['publicKey'];

        String encryptedGroupKey = await encryptGroupKeyForParticipant(participantPublicKeyPem, newGroupKey);
        encryptedGroupKeys[participantId] = encryptedGroupKey;
      }

      // Increment key version
      int keyVersion = (sessionData['keyVersion'] ?? 1) + 1;

      await _firestore.collection('chat_sessions').doc(sessionCode).update({
        'participants': participants,
        'alternativeNames': alternativeNames,
        'leftParticipants': leftParticipants,
        'encryptedGroupKeys': encryptedGroupKeys,
        'keyVersion': keyVersion,
      });

      // Store new group key for current user
      await storage.write(
          key: 'groupKey_${sessionCode}_$keyVersion', value: base64.encode(newGroupKey.bytes));

      // Navigate to the chat screen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ChatScreen(
            sessionCode: sessionCode,
            alternativeName: alternativeName,
          ),
        ),
      );
    } catch (e) {
      print('Error joining session: $e');
      setState(() {
        errorMessage = 'Failed to join session: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: const Text('Join Chat Session')),
        body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Form(
                key: _formKey,
                child: ListView(children: [
                  TextFormField(
                    decoration: const InputDecoration(labelText: 'Session Code'),
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'Please enter session code';
                      return null;
                    },
                    onChanged: (value) => sessionCode = value.toUpperCase(),
                  ),
                  TextFormField(
                    decoration: const InputDecoration(labelText: 'Alternative Display Name'),
                    onChanged: (value) => alternativeName = value,
                  ),
                  // Secret key field will be shown if required after validation
                  TextFormField(
                    decoration: const InputDecoration(labelText: 'Secret Key (if required)'),
                    onChanged: (value) => secretKey = value,
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _joinSession,
                    child: const Text('Join Session'),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    errorMessage,
                    style: const TextStyle(color: Colors.red),
                  ),
                ]))));
  }
}
