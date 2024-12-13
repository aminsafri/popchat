// lib/chat_screen.dart

import 'dart:async';
import 'dart:convert';
import 'package:basic_utils/basic_utils.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'session_info_screen.dart';
import 'package:encrypt/encrypt.dart' as encrypt; // Aliased import
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/asymmetric/api.dart' show RSAPrivateKey; // Import RSAPrivateKey
import 'dart:typed_data';


class ChatScreen extends StatefulWidget {
  final String sessionCode;
  final String alternativeName;

  ChatScreen({required this.sessionCode, required this.alternativeName});

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  final TextEditingController _messageController = TextEditingController();

  StreamSubscription<DocumentSnapshot>? _sessionSubscription;

  bool isParticipant = true;
  bool hasLeftSession = false;

  final storage = FlutterSecureStorage();

  encrypt.Key? groupKey; // Use encrypt.Key
  int keyVersion = 1;

  @override
  void initState() {
    super.initState();
    _initializeGroupKey();
    _listenToSessionChanges();
  }

  Future<void> _initializeGroupKey() async {
    DocumentSnapshot sessionDoc = await _firestore
        .collection('chat_sessions')
        .doc(widget.sessionCode)
        .get();

    if (!sessionDoc.exists) {
      _showSessionEndedDialog();
      return;
    }

    Map<String, dynamic> sessionData = sessionDoc.data() as Map<String, dynamic>;
    Map<String, dynamic> encryptedGroupKeys = Map<String, String>.from(sessionData['encryptedGroupKeys'] ?? {});
    keyVersion = sessionData['keyVersion'] ?? 1;

    String? encryptedGroupKeyBase64 = encryptedGroupKeys[_auth.currentUser!.uid];

    if (encryptedGroupKeyBase64 == null) {
      _showNoAccessDialog();
      return;
    }

    // Check if group key is already stored
    String groupKeyStorageKey = 'groupKey_${widget.sessionCode}_$keyVersion';
    String? storedGroupKeyBase64 = await storage.read(key: groupKeyStorageKey);

    if (storedGroupKeyBase64 != null) {
      // Load group key from storage
      setState(() {
        groupKey = encrypt.Key(base64.decode(storedGroupKeyBase64));
      });
    } else {
      // Decrypt group key
      var decryptedGroupKey = await decryptGroupKey(encryptedGroupKeyBase64);

      // Store group key securely
      await storage.write(key: groupKeyStorageKey, value: base64.encode(decryptedGroupKey.bytes));

      setState(() {
        groupKey = decryptedGroupKey;
      });
    }
  }


  Future<encrypt.Key> decryptGroupKey(String encryptedGroupKeyBase64) async {
    String? privateKeyPem = await storage.read(key: 'privateKey');
    if (privateKeyPem == null) {
      throw Exception('Private key not found');
    }

    RSAPrivateKey privateKey = CryptoUtils.rsaPrivateKeyFromPem(privateKeyPem);

    final encrypter = encrypt.Encrypter(encrypt.RSA(privateKey: privateKey));
    final encryptedGroupKey = encrypt.Encrypted.fromBase64(encryptedGroupKeyBase64);
    final decryptedBytes = encrypter.decryptBytes(encryptedGroupKey);

    // Convert decryptedBytes (List<int>) to Uint8List
    return encrypt.Key(Uint8List.fromList(decryptedBytes));
  }



  void _listenToSessionChanges() {
    _sessionSubscription = _firestore
        .collection('chat_sessions')
        .doc(widget.sessionCode)
        .snapshots()
        .listen((snapshot) async {
      if (!snapshot.exists) {
        // Session no longer exists
        _showSessionEndedDialog();
      } else {
        Map<String, dynamic> sessionData = snapshot.data() as Map<String, dynamic>;
        List<dynamic> participants = sessionData['participants'] ?? [];
        List<dynamic> leftParticipants = sessionData['leftParticipants'] ?? [];

        int newKeyVersion = sessionData['keyVersion'] ?? 1;
        if (newKeyVersion != keyVersion) {
          keyVersion = newKeyVersion;
          await _initializeGroupKey(); // Re-initialize group key
        }

        if (!participants.contains(_auth.currentUser!.uid)) {
          // User is no longer a participant (e.g., kicked)
          setState(() {
            isParticipant = false;
            hasLeftSession = false; // Not applicable
          });
        } else if (leftParticipants.contains(_auth.currentUser!.uid)) {
          // User has left the session
          setState(() {
            isParticipant = true;
            hasLeftSession = true;
          });
        } else {
          // User is an active participant
          setState(() {
            isParticipant = true;
            hasLeftSession = false;
          });
        }
      }
    });
  }

  Future<String> encryptGroupMessage(String message, encrypt.Key groupKey) async {
    final iv = encrypt.IV.fromSecureRandom(16); // Use encrypt.IV
    final encrypter = encrypt.Encrypter(encrypt.AES(groupKey, mode: encrypt.AESMode.cbc)); // Use encrypt.AESMode
    final encrypted = encrypter.encrypt(message, iv: iv);
    return jsonEncode({
      'cipherText': encrypted.base64,
      'iv': iv.base64,
    });
  }

  String decryptGroupMessage(String encryptedMessageJson, encrypt.Key groupKey) {
    final Map<String, dynamic> messageMap = jsonDecode(encryptedMessageJson);
    final encrypted = encrypt.Encrypted.fromBase64(messageMap['cipherText']);
    final iv = encrypt.IV.fromBase64(messageMap['iv']);
    final encrypter = encrypt.Encrypter(encrypt.AES(groupKey, mode: encrypt.AESMode.cbc));
    final decrypted = encrypter.decrypt(encrypted, iv: iv);
    return decrypted;
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty || groupKey == null) return;

    if (_auth.currentUser == null) {
      // Handle unauthenticated state
      return;
    }
    String userId = _auth.currentUser!.uid;

    DocumentSnapshot sessionDoc = await _firestore
        .collection('chat_sessions')
        .doc(widget.sessionCode)
        .get();
    if (!sessionDoc.exists) {
      // Session does not exist
      _showSessionEndedDialog();
      return;
    }

    Map<String, dynamic> sessionData =
    sessionDoc.data() as Map<String, dynamic>;

    Map<String, dynamic> alternativeNames =
    Map<String, dynamic>.from(sessionData['alternativeNames'] ?? {});
    String senderName = alternativeNames[userId] ?? 'Unknown';

    String messageContent = _messageController.text.trim();

    // Encrypt message content
    String encryptedMessage = await encryptGroupMessage(messageContent, groupKey!);

    // Create message document
    await _firestore
        .collection('chat_sessions')
        .doc(widget.sessionCode)
        .collection('messages')
        .add({
      'senderId': userId,
      'senderName': senderName,
      'timestamp': Timestamp.now(),
      'encryptedContent': encryptedMessage, // Store encrypted message
    });

    // Update last message, timestamp, and unread counts
    List<dynamic> participants = sessionData['participants'] ?? [];

    Map<String, dynamic> unreadCounts =
    Map<String, dynamic>.from(sessionData['unreadCounts'] ?? {});

    // Increment unread count for other participants
    for (String participantId in participants) {
      if (participantId != userId) {
        unreadCounts[participantId] = (unreadCounts[participantId] ?? 0) + 1;
      }
    }

    await _firestore
        .collection('chat_sessions')
        .doc(widget.sessionCode)
        .update({
      'lastMessage': 'Encrypted Message',
      'lastMessageTime': Timestamp.now(),
      'unreadCounts': unreadCounts,
    });

    _messageController.clear();
  }

  Stream<QuerySnapshot> _messagesStream() {
    return _firestore
        .collection('chat_sessions')
        .doc(widget.sessionCode)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  @override
  void dispose() {
    _sessionSubscription?.cancel();
    super.dispose();
  }

  void _showSessionEndedDialog() {
    _sessionSubscription?.cancel();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Session Ended'),
        content: Text('This session has ended or been deleted.'),
        actions: [
          TextButton(
            child: Text('OK'),
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Go back to previous screen
            },
          ),
        ],
      ),
    );
  }

  void _showNoAccessDialog() {
    _sessionSubscription?.cancel();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Access Denied'),
        content: Text('You do not have access to this session.'),
        actions: [
          TextButton(
            child: Text('OK'),
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Go back to previous screen
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String currentUserId = _auth.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () {
            // Navigate to the session info screen
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => SessionInfoScreen(
                  sessionCode: widget.sessionCode,
                ),
              ),
            );
          },
          child: Text('Session ${widget.sessionCode}'),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _messagesStream(),
              builder: (context, snapshot) {
                if (!snapshot.hasData || groupKey == null) return CircularProgressIndicator();
                List<DocumentSnapshot> docs = snapshot.data!.docs;

                return ListView.builder(
                  reverse: true,
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    Map<String, dynamic> message =
                    docs[index].data() as Map<String, dynamic>;

                    bool isMe = message['senderId'] == currentUserId;

                    String encryptedContent = message['encryptedContent'];
                    String decryptedContent = '';

                    try {
                      decryptedContent = decryptGroupMessage(encryptedContent, groupKey!);
                    } catch (e) {
                      decryptedContent = 'Failed to decrypt message';
                    }

                    return ListTile(
                      title: Align(
                        alignment:
                        isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          padding: EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isMe ? Colors.blue[200] : Colors.grey[300],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            decryptedContent,
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                      subtitle: Align(
                        alignment:
                        isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Text(
                          message['senderName'],
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Divider(height: 1.0),
          if (isParticipant && !hasLeftSession)
          // Show message input
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8.0),
              color: Theme.of(context).cardColor,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration:
                      InputDecoration.collapsed(hintText: 'Send a message'),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.send),
                    onPressed: _sendMessage,
                  ),
                ],
              ),
            )
          else if (hasLeftSession)
          // User has left the session
            Container(
              padding: EdgeInsets.all(16.0),
              alignment: Alignment.center,
              child: Text('You have left this session.'),
            )
          else
          // User is not a participant (e.g., kicked)
            Container(
              padding: EdgeInsets.all(16.0),
              alignment: Alignment.center,
              child: Text('You are no longer a participant in this session.'),
            ),
        ],
      ),
    );
  }
}
