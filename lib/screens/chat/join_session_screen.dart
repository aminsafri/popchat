// lib/screens/chat/join_session_screen.dart

import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:basic_utils/basic_utils.dart';
import 'package:pointycastle/asymmetric/api.dart' show RSAPublicKey;

import 'chat_screen.dart';

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

  final storage = const FlutterSecureStorage();

  encrypt.Key generateGroupKey() {
    return encrypt.Key.fromSecureRandom(32); // 256-bit key
  }

  /// Helper method to format PEM if missing headers
  String reconstructPem(String pem, String keyType) {
    pem = pem.replaceAll('-----BEGIN $keyType-----', '');
    pem = pem.replaceAll('-----END $keyType-----', '');
    pem = pem.replaceAll('\n', '').replaceAll('\r', '').replaceAll(' ', '');
    final buffer = StringBuffer();
    for (int i = 0; i < pem.length; i += 64) {
      final end = (i + 64 < pem.length) ? i + 64 : pem.length;
      buffer.writeln(pem.substring(i, end));
    }
    return '-----BEGIN $keyType-----\n${buffer.toString()}-----END $keyType-----';
  }

  Future<String> encryptGroupKeyForParticipant(
      String participantPublicKeyPem, encrypt.Key groupKey) async {
    if (!participantPublicKeyPem.contains('-----BEGIN RSA PUBLIC KEY-----') ||
        !participantPublicKeyPem.contains('-----END RSA PUBLIC KEY-----')) {
      participantPublicKeyPem =
          reconstructPem(participantPublicKeyPem, 'RSA PUBLIC KEY');
    }

    final parsedKey = CryptoUtils.rsaPublicKeyFromPem(participantPublicKeyPem);
    final encrypter = encrypt.Encrypter(
      encrypt.RSA(
        publicKey: parsedKey,
        encoding: encrypt.RSAEncoding.PKCS1,
      ),
    );
    final encryptedBytes = encrypter.encryptBytes(groupKey.bytes);
    return encryptedBytes.base64;
  }

  Future<void> _joinSession() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      final sessionDoc =
      await _firestore.collection('chat_sessions').doc(sessionCode).get();
      if (!sessionDoc.exists) {
        setState(() => errorMessage = 'Session not found');
        return;
      }

      final sessionData = sessionDoc.data() as Map<String, dynamic>;

      // Check expiry
      final expiryTime = sessionData['expiryTime'] as Timestamp;
      if (expiryTime.toDate().isBefore(DateTime.now())) {
        setState(() => errorMessage = 'Session has expired');
        return;
      }

      // Check secret key
      if (sessionData['requiresSecretKey'] == true) {
        if (secretKey != sessionData['secretKey']) {
          setState(() => errorMessage = 'Invalid secret key');
          return;
        }
      }

      final userId = _auth.currentUser!.uid;

      // leftParticipants
      final leftParticipants = List<String>.from(
          sessionData['leftParticipants'] ?? []);
      if (leftParticipants.contains(userId)) {
        leftParticipants.remove(userId);
      }

      // Add user to participants if not present
      final participants =
      List<String>.from(sessionData['participants'] ?? []);
      if (!participants.contains(userId)) {
        participants.add(userId);
      }

      // Update alternativeNames
      final alternativeNames =
      Map<String, dynamic>.from(sessionData['alternativeNames'] ?? {});
      alternativeNames[userId] = alternativeName.isNotEmpty
          ? alternativeName
          : _auth.currentUser!.displayName;

      // Generate new group key
      final newGroupKey = generateGroupKey();

      // Encrypt new group key for all participants
      final newEncKeys = <String, String>{};
      for (final pid in participants) {
        final userDoc =
        await _firestore.collection('users').doc(pid).get();
        if (!userDoc.exists) continue;
        final participantPublicKeyPem = userDoc['publicKey'] as String;
        final encKeyForThisUser = await encryptGroupKeyForParticipant(
            participantPublicKeyPem, newGroupKey);
        newEncKeys[pid] = encKeyForThisUser;
      }

      // Increment key version
      int currentKeyVersion = sessionData['keyVersion'] ?? 1;
      final newKeyVersion = currentKeyVersion + 1;

      // Nested approach for storing encryptedGroupKeys
      var allEncKeys = Map<String, dynamic>.from(
          sessionData['encryptedGroupKeys'] ?? {});
      bool isAlreadyNested = false;
      for (final k in allEncKeys.keys) {
        if (k is String && allEncKeys[k] is Map) {
          isAlreadyNested = true;
          break;
        }
      }
      if (!isAlreadyNested && allEncKeys.isNotEmpty) {
        // Move old single-level map to {currentKeyVersion: oldMap}
        allEncKeys = {
          "$currentKeyVersion": allEncKeys,
        };
      } else if (allEncKeys.isEmpty) {
        allEncKeys["$currentKeyVersion"] = {};
      }

      // Now store newEncKeys under newKeyVersion
      allEncKeys["$newKeyVersion"] = newEncKeys;

      // Update Firestore
      await _firestore
          .collection('chat_sessions')
          .doc(sessionCode)
          .update({
        'participants': participants,
        'alternativeNames': alternativeNames,
        'leftParticipants': leftParticipants,
        'encryptedGroupKeys': allEncKeys,
        'keyVersion': newKeyVersion,
      });

      // Store new group key for current user
      await storage.write(
        key: 'groupKey_${sessionCode}_$newKeyVersion',
        value: base64.encode(newGroupKey.bytes),
      );

      // Navigate to chat
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            sessionCode: sessionCode,
            alternativeName: alternativeName,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error joining session: $e');
      setState(() => errorMessage = 'Failed to join session: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Modern AppBar with brand color and centered title
      appBar: AppBar(
        title: const Text(
          'PopChat - Join Session',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: const Color(0xFF0088cc),
      ),
      // Light background for reduced eye strain
      body: Container(
        color: Colors.grey[100],
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
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
                      const Text(
                        'Join a Chat Session',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Session Code
                      TextFormField(
                        decoration: const InputDecoration(
                          labelText: 'Session Code',
                          hintText: 'e.g. ABC123',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter session code';
                          }
                          return null;
                        },
                        onChanged: (value) =>
                        sessionCode = value.toUpperCase(),
                      ),
                      const SizedBox(height: 16),
                      // Alternative Display Name
                      TextFormField(
                        decoration: const InputDecoration(
                          labelText: 'Alternative Display Name',
                          hintText: 'Optional alias in this session',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) => alternativeName = value,
                      ),
                      const SizedBox(height: 16),
                      // Secret Key
                      TextFormField(
                        decoration: const InputDecoration(
                          labelText: 'Secret Key (if required)',
                          hintText: 'Enter secret key if needed',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) => secretKey = value,
                      ),
                      const SizedBox(height: 20),
                      // Join Session Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _joinSession,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0088cc),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text(
                            'Join Session',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
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
