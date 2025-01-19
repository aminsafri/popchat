// lib/screens/chat/session_info_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:basic_utils/basic_utils.dart';
import 'package:pointycastle/asymmetric/api.dart' show RSAPublicKey;
import 'dart:convert';

class SessionInfoScreen extends StatefulWidget {
  final String sessionCode;

  SessionInfoScreen({required this.sessionCode});

  @override
  _SessionInfoScreenState createState() => _SessionInfoScreenState();
}

class _SessionInfoScreenState extends State<SessionInfoScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final storage = FlutterSecureStorage();

  Map<String, dynamic>? sessionData;
  bool isLoading = true;
  bool isOwner = false;
  String currentUserId = '';
  bool hasLeftSession = false;

  @override
  void initState() {
    super.initState();
    currentUserId = _auth.currentUser!.uid;
    _fetchSessionData();
  }

  Future<void> _fetchSessionData() async {
    DocumentSnapshot doc = await _firestore.collection('chat_sessions').doc(widget.sessionCode).get();
    if (doc.exists) {
      setState(() {
        sessionData = doc.data() as Map<String, dynamic>;
        isOwner = sessionData!['ownerId'] == currentUserId;
        isLoading = false;
      });
    } else {
      // Handle session not found
      setState(() {
        isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session not found')),
      );
    }
  }

  // Key generation and encryption methods
  encrypt.Key generateGroupKey() {
    return encrypt.Key.fromSecureRandom(32); // 256-bit key
  }

  /// Helper method to format PEM string with line breaks
  String reconstructPem(String pem, String keyType) {
    // Remove headers and footers if present
    pem = pem.replaceAll('-----BEGIN RSA PUBLIC KEY-----', '');
    pem = pem.replaceAll('-----END RSA PUBLIC KEY-----', '');
    // Insert line breaks every 64 characters
    final buffer = StringBuffer();
    for (int i = 0; i < pem.length; i += 64) {
      int end = (i + 64 < pem.length) ? i + 64 : pem.length;
      buffer.writeln(pem.substring(i, end));
    }
    return '-----BEGIN RSA PUBLIC KEY-----\n${buffer.toString()}-----END RSA PUBLIC KEY-----';
  }

  Future<String> encryptGroupKeyForParticipant(String participantPublicKeyPem, encrypt.Key groupKey) async {
    // Ensure proper PEM formatting
    if (!participantPublicKeyPem.contains('-----BEGIN RSA PUBLIC KEY-----') ||
        !participantPublicKeyPem.contains('-----END RSA PUBLIC KEY-----')) {
      participantPublicKeyPem = reconstructPem(participantPublicKeyPem, 'RSA PUBLIC KEY');
    }

    RSAPublicKey publicKey = CryptoUtils.rsaPublicKeyFromPem(participantPublicKeyPem);

    final encrypter = encrypt.Encrypter(encrypt.RSA(
      publicKey: publicKey,
      encoding: encrypt.RSAEncoding.PKCS1, // Ensure PKCS1 padding
    ));
    final encryptedGroupKey = encrypter.encryptBytes(groupKey.bytes);
    return encryptedGroupKey.base64;
  }

  Future<void> _kickMember(String userId) async {
    if (!isOwner) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only the owner can kick members')),
      );
      return;
    }

    // Remove user from participants
    List<dynamic> participants = List.from(sessionData!['participants']);
    participants.remove(userId);

    // Remove user from alternativeNames
    Map<String, dynamic> alternativeNames = Map<String, dynamic>.from(sessionData!['alternativeNames']);
    alternativeNames.remove(userId);

    // Update Firestore
    await _firestore.collection('chat_sessions').doc(widget.sessionCode).update({
      'participants': participants,
      'alternativeNames': alternativeNames,
    });

    // Update group key for remaining participants
    await _updateGroupKeyForParticipants(participants);

    // Update local state
    setState(() {
      sessionData!['participants'] = participants;
      sessionData!['alternativeNames'] = alternativeNames;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Member kicked')),
    );
  }

  Future<void> _updateGroupKeyForParticipants(List<dynamic> participants) async {
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
    int keyVersion = (sessionData!['keyVersion'] ?? 1) + 1;

    // Update session data
    await _firestore.collection('chat_sessions').doc(widget.sessionCode).update({
      'encryptedGroupKeys': encryptedGroupKeys,
      'keyVersion': keyVersion,
    });

    // Store new group key for current user (if still a participant)
    if (participants.contains(currentUserId)) {
      await storage.write(
          key: 'groupKey_${widget.sessionCode}_$keyVersion', value: base64.encode(newGroupKey.bytes));
    }
  }

  Future<void> _leaveSession() async {
    String userId = _auth.currentUser!.uid;

    if (isOwner) {
      // Transfer ownership
      List<dynamic> participants = List.from(sessionData!['participants']);
      List<dynamic> remainingParticipants = List.from(participants);
      remainingParticipants.remove(userId); // Exclude the owner

      if (remainingParticipants.isNotEmpty) {
        // Assign new owner
        String newOwnerId = remainingParticipants.first;
        await _firestore.collection('chat_sessions').doc(widget.sessionCode).update({
          'ownerId': newOwnerId,
          'leftParticipants': FieldValue.arrayUnion([userId]),
          // Do not remove the owner from participants
        });

        // Update group key for remaining participants
        await _updateGroupKeyForParticipants(remainingParticipants);
      } else {
        // Delete the session if no participants left
        await _firestore.collection('chat_sessions').doc(widget.sessionCode).delete();
      }
    } else {
      // Regular participant leaving
      await _firestore.collection('chat_sessions').doc(widget.sessionCode).update({
        'leftParticipants': FieldValue.arrayUnion([userId]),
      });

      // Remove user from participants list
      List<dynamic> participants = List.from(sessionData!['participants']);
      participants.remove(userId);

      // Update group key for remaining participants
      await _updateGroupKeyForParticipants(participants);
    }

    // Update local state
    setState(() {
      hasLeftSession = true;
      isOwner = false; // The user is no longer the owner
    });

    Navigator.pop(context); // Close SessionInfoScreen
    Navigator.pop(context); // Close ChatScreen
  }

  Future<void> _deleteSession() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> deletedSessions = prefs.getStringList('deletedSessions') ?? [];
    deletedSessions.add(widget.sessionCode);
    await prefs.setStringList('deletedSessions', deletedSessions);

    Navigator.pop(context); // Close SessionInfoScreen
    Navigator.pop(context); // Close ChatScreen
  }

  Future<void> _confirmKickMember(String userId, String displayName) async {
    bool confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kick Member'),
        content: Text('Are you sure you want to kick $displayName?'),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context, false),
          ),
          TextButton(
            child: const Text('Kick'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    ) ??
        false;

    if (confirm) {
      await _kickMember(userId);
    }
  }

  Future<void> _confirmLeaveSession() async {
    bool confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Session'),
        content: const Text('Are you sure you want to leave this session?'),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context, false),
          ),
          TextButton(
            child: const Text('Leave'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    ) ??
        false;

    if (confirm) {
      await _leaveSession();
    }
  }

  Future<void> _confirmDeleteSession() async {
    bool confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Session'),
        content: const Text('Are you sure you want to delete this session from your chat list?'),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context, false),
          ),
          TextButton(
            child: const Text('Delete'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    ) ??
        false;

    if (confirm) {
      await _deleteSession();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Session Info'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (sessionData == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Session Info'),
        ),
        body: const Center(child: Text('Session not found')),
      );
    }

    List<dynamic> participants = sessionData!['participants'];
    Map<String, dynamic> alternativeNames = sessionData!['alternativeNames'];
    Timestamp createdAtTimestamp = sessionData!['createdAt'];
    DateTime createdAt = createdAtTimestamp.toDate();
    bool isParticipant = participants.contains(currentUserId);
    hasLeftSession = sessionData!['leftParticipants']?.contains(currentUserId) ?? false;
    isOwner = sessionData!['ownerId'] == currentUserId;

    // Get session title and code
    String sessionTitle = sessionData!['sessionTitle'] ?? 'Session ${widget.sessionCode}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session Info'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Session title
            Text(
              sessionTitle,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            // Session code
            Text(
              'Session Code: ${widget.sessionCode}',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            // Created at
            Text(
              'Created At: ${DateFormat.yMMMd().add_jm().format(createdAt)}',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            // Participants List
            const Text(
              'Participants:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: participants.length,
                itemBuilder: (context, index) {
                  String participantId = participants[index];
                  String participantName = alternativeNames[participantId] ?? 'Unknown';
                  bool hasLeft = sessionData!['leftParticipants']?.contains(participantId) ?? false;

                  return ListTile(
                    title: Text(
                      participantName,
                      style: TextStyle(
                        decoration: hasLeft ? TextDecoration.lineThrough : null,
                        color: hasLeft ? Colors.grey : Colors.black,
                      ),
                    ),
                    trailing: isOwner && participantId != currentUserId && !hasLeft
                        ? IconButton(
                      icon: const Icon(Icons.remove_circle, color: Colors.red),
                      onPressed: () => _confirmKickMember(participantId, participantName),
                    )
                        : null,
                  );
                },
              ),
            ),
            // Leave or Delete Session Button
            if (isParticipant && !hasLeftSession) ...[
              // Show "Leave Session" button
              if (isOwner)
                ElevatedButton(
                  onPressed: _confirmLeaveSession,
                  child: const Text('Leave Session (Transfer Ownership)'),
                )
              else
                ElevatedButton(
                  onPressed: _confirmLeaveSession,
                  child: const Text('Leave Session'),
                ),
            ] else ...[
              ElevatedButton(
                onPressed: _confirmDeleteSession,
                child: const Text('Delete Session'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
