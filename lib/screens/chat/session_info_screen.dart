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
  final storage = const FlutterSecureStorage();

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
    final doc = await _firestore
        .collection('chat_sessions')
        .doc(widget.sessionCode)
        .get();
    if (doc.exists) {
      setState(() {
        sessionData = doc.data() as Map<String, dynamic>;
        isOwner = sessionData!['ownerId'] == currentUserId;
        isLoading = false;
      });
    } else {
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

  String reconstructPem(String pem, String keyType) {
    pem = pem.replaceAll('-----BEGIN $keyType-----', '');
    pem = pem.replaceAll('-----END $keyType-----', '');
    pem = pem.replaceAll('\n', '').replaceAll('\r', '').replaceAll(' ', '');
    final buffer = StringBuffer();
    for (int i = 0; i < pem.length; i += 64) {
      int end = (i + 64 < pem.length) ? i + 64 : pem.length;
      buffer.writeln(pem.substring(i, end));
    }
    return '-----BEGIN $keyType-----\n${buffer.toString()}-----END $keyType-----';
  }

  Future<String> encryptGroupKeyForParticipant(
      String participantPublicKeyPem, encrypt.Key groupKey) async {
    if (!participantPublicKeyPem.contains('-----BEGIN RSA PUBLIC KEY-----') ||
        !participantPublicKeyPem.contains('-----END RSA PUBLIC KEY-----')) {
      participantPublicKeyPem = reconstructPem(participantPublicKeyPem, 'RSA PUBLIC KEY');
    }

    final parsedKey = CryptoUtils.rsaPublicKeyFromPem(participantPublicKeyPem);

    final encrypter = encrypt.Encrypter(
      encrypt.RSA(
        publicKey: parsedKey,
        encoding: encrypt.RSAEncoding.PKCS1,
      ),
    );
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
    final participants = List<dynamic>.from(sessionData!['participants']);
    participants.remove(userId);

    // Remove user from alternativeNames
    final alternativeNames =
    Map<String, dynamic>.from(sessionData!['alternativeNames']);
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
    final newGroupKey = generateGroupKey();

    // Encrypt group key for all participants
    final encryptedGroupKeys = <String, String>{};

    for (final participantId in participants) {
      final userDoc =
      await _firestore.collection('users').doc(participantId).get();
      final participantPublicKeyPem = userDoc['publicKey'];
      final encryptedKey =
      await encryptGroupKeyForParticipant(participantPublicKeyPem, newGroupKey);
      encryptedGroupKeys[participantId] = encryptedKey;
    }

    // Increment key version
    final currentKeyVersion = sessionData!['keyVersion'] ?? 1;
    final newKeyVersion = currentKeyVersion + 1;

    // Update session data
    await _firestore.collection('chat_sessions').doc(widget.sessionCode).update({
      'encryptedGroupKeys': encryptedGroupKeys,
      'keyVersion': newKeyVersion,
    });

    // Store new group key for current user (if still a participant)
    if (participants.contains(currentUserId)) {
      await storage.write(
        key: 'groupKey_${widget.sessionCode}_$newKeyVersion',
        value: base64.encode(newGroupKey.bytes),
      );
    }
  }

  Future<void> _leaveSession() async {
    final userId = _auth.currentUser!.uid;

    if (isOwner) {
      // Transfer ownership
      final participants =
      List<dynamic>.from(sessionData!['participants']);
      final remainingParticipants = List<dynamic>.from(participants);
      remainingParticipants.remove(userId); // Exclude the owner

      if (remainingParticipants.isNotEmpty) {
        // Assign new owner
        final newOwnerId = remainingParticipants.first;
        await _firestore
            .collection('chat_sessions')
            .doc(widget.sessionCode)
            .update({
          'ownerId': newOwnerId,
          'leftParticipants': FieldValue.arrayUnion([userId]),
        });

        // Update group key for remaining participants
        await _updateGroupKeyForParticipants(remainingParticipants);
      } else {
        // Delete the session if no participants left
        await _firestore
            .collection('chat_sessions')
            .doc(widget.sessionCode)
            .delete();
      }
    } else {
      // Regular participant leaving
      await _firestore
          .collection('chat_sessions')
          .doc(widget.sessionCode)
          .update({
        'leftParticipants': FieldValue.arrayUnion([userId]),
      });

      // Remove user from participants list
      final participants =
      List<dynamic>.from(sessionData!['participants']);
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
    final prefs = await SharedPreferences.getInstance();
    final deletedSessions = prefs.getStringList('deletedSessions') ?? [];
    deletedSessions.add(widget.sessionCode);
    await prefs.setStringList('deletedSessions', deletedSessions);

    Navigator.pop(context); // Close SessionInfoScreen
    Navigator.pop(context); // Close ChatScreen
  }

  Future<void> _confirmKickMember(String userId, String displayName) async {
    final confirm = await showDialog<bool>(
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
    final confirm = await showDialog<bool>(
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Session'),
        content: const Text(
            'Are you sure you want to delete this session from your chat list?'),
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
          title: const Text('PopChat - Session Info'),
          centerTitle: true,
          backgroundColor: const Color(0xFF0088cc),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (sessionData == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('PopChat - Session Info'),
          centerTitle: true,
          backgroundColor: const Color(0xFF0088cc),
        ),
        body: const Center(child: Text('Session not found')),
      );
    }

    final participants = sessionData!['participants'] as List<dynamic>;
    final alternativeNames =
    Map<String, dynamic>.from(sessionData!['alternativeNames']);
    final createdAtTimestamp = sessionData!['createdAt'] as Timestamp;
    final createdAt = createdAtTimestamp.toDate();

    final isParticipant = participants.contains(currentUserId);
    hasLeftSession =
        sessionData!['leftParticipants']?.contains(currentUserId) ?? false;
    isOwner = sessionData!['ownerId'] == currentUserId;

    // Session Title and Code
    final sessionTitle =
        sessionData!['sessionTitle'] ?? 'Session ${widget.sessionCode}';

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'PopChat - Session Info',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF0088cc),
        elevation: 0,
      ),
      body: Container(
        color: Colors.grey[100],
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Session info in a Card
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Session Title
                      Text(
                        sessionTitle,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Session code
                      Text(
                        'Session Code: ${widget.sessionCode}',
                        style: TextStyle(
                            fontSize: 14, color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 8),
                      // Created at
                      Text(
                        'Created At: ${DateFormat.yMMMd().add_jm().format(createdAt)}',
                        style: TextStyle(
                            fontSize: 14, color: Colors.grey[700]),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Participants list in an expanded section
              Expanded(
                child: Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Participants:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: ListView.builder(
                            itemCount: participants.length,
                            itemBuilder: (context, index) {
                              final participantId = participants[index];
                              final participantName = alternativeNames[participantId] ?? 'Unknown';
                              final hasLeft =
                                  sessionData!['leftParticipants']
                                      ?.contains(participantId) ??
                                      false;

                              return ListTile(
                                contentPadding: const EdgeInsets.all(0),
                                title: Text(
                                  participantName,
                                  style: TextStyle(
                                    decoration: hasLeft
                                        ? TextDecoration.lineThrough
                                        : null,
                                    color:
                                    hasLeft ? Colors.grey : Colors.black87,
                                    fontSize: 14,
                                  ),
                                ),
                                trailing: (isOwner &&
                                    participantId != currentUserId &&
                                    !hasLeft)
                                    ? IconButton(
                                  icon: const Icon(Icons.person_remove,
                                      color: Colors.red),
                                  onPressed: () => _confirmKickMember(
                                      participantId, participantName),
                                )
                                    : null,
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Buttons for leaving or deleting session
              _buildActionButtons(isParticipant, hasLeftSession),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons(bool isParticipant, bool hasLeftSession) {
    if (isParticipant && !hasLeftSession) {
      // If user is still in session
      if (isOwner) {
        // Owner sees "Leave Session (Transfer Ownership)"
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _confirmLeaveSession,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0088cc),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text(
              'Leave Session (Transfer Ownership)',
              style: TextStyle(fontSize: 16, color: Colors.white),
            ),
          ),
        );
      } else {
        // Regular participant sees "Leave Session"
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _confirmLeaveSession,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0088cc),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text(
              'Leave Session',
              style: TextStyle(fontSize: 16, color: Colors.white),
            ),
          ),
        );
      }
    } else {
      // If user is not a participant or has left
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _confirmDeleteSession,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: const Text(
            'Delete Session',
            style: TextStyle(fontSize: 16, color: Colors.white),
          ),
        ),
      );
    }
  }
}
