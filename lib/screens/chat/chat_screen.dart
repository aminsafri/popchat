import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:pointycastle/asymmetric/api.dart' as pc;

import 'session_info_screen.dart';

class ChatScreen extends StatefulWidget {
  final String sessionCode;
  final String alternativeName;

  ChatScreen({
    required this.sessionCode,
    required this.alternativeName,
  });

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final storage = const FlutterSecureStorage();

  final TextEditingController _messageController = TextEditingController();

  StreamSubscription<DocumentSnapshot>? _sessionSubscription;
  bool isParticipant = true;
  bool hasLeftSession = false;

  // Encryption
  encrypt.Key? groupKey;
  int keyVersion = 1;

  // Real name / Verification
  bool _isUserVerified = false;
  String _passportName = '';

  @override
  void initState() {
    super.initState();
    // Attempt to initialize the group key; no pop-up on error.
    _initializeGroupKey().then((_) => _testAESEncryptionDecryption());
    _listenToSessionChanges();
    _fetchUserVerificationStatus();
    _testRSAEncryptionDecryption(); // Optional demonstration
  }

  // --------------------------------------------------------------------------
  // VERIFICATION STATUS
  // --------------------------------------------------------------------------
  Future<void> _fetchUserVerificationStatus() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final doc = await _firestore.collection('users').doc(user.uid).get();
    if (!doc.exists) return;

    final data = doc.data() ?? {};
    setState(() {
      _isUserVerified = data['passportVerified'] ?? false;
      _passportName = data['passportName'] ?? '';
    });
  }

  // Example: RSA test (placeholder)
  Future<void> _testRSAEncryptionDecryption() async {
    // For demonstration or debugging
  }

  // AES test
  Future<void> _testAESEncryptionDecryption() async {
    if (groupKey == null) return;
    final testMsg = "Hello AES test!";
    final iv = encrypt.IV.fromSecureRandom(16);
    final encrypter =
    encrypt.Encrypter(encrypt.AES(groupKey!, mode: encrypt.AESMode.cbc));
    final encrypted = encrypter.encrypt(testMsg, iv: iv);
    final decrypted = encrypter.decrypt(encrypted, iv: iv);
    if (testMsg == decrypted) {
      debugPrint("AES test success!");
    } else {
      debugPrint("AES test failed!");
    }
  }

  // --------------------------------------------------------------------------
  // PRIVATE KEY
  // --------------------------------------------------------------------------
  Future<String?> _getOrFetchPrivateKey() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    return await storage.read(key: 'privateKey');
  }

  // --------------------------------------------------------------------------
  // INITIALIZE GROUP KEY
  // --------------------------------------------------------------------------
  Future<void> _initializeGroupKey() async {
    try {
      final sessionDoc = await _firestore
          .collection('chat_sessions')
          .doc(widget.sessionCode)
          .get();

      if (!sessionDoc.exists) {
        _showSessionEndedDialog();
        return;
      }

      final sessionData = sessionDoc.data() as Map<String, dynamic>;

      // Retrieve the nested encryptedGroupKeys
      final rawEncKeys = sessionData['encryptedGroupKeys'];
      if (rawEncKeys == null) {
        throw Exception('No encryptedGroupKeys found in session.');
      }
      final typedEncKeys = Map<String, dynamic>.from(rawEncKeys);

      keyVersion = sessionData['keyVersion'] ?? 1;
      final versionString = '$keyVersion';

      if (!typedEncKeys.containsKey(versionString)) {
        throw Exception(
            'encryptedGroupKeys missing submap for keyVersion=$versionString');
      }

      final rawVersionMap = typedEncKeys[versionString];
      final versionMap = Map<String, dynamic>.from(rawVersionMap);

      final userId = _auth.currentUser!.uid;
      final encKeyBase64 = versionMap[userId] as String?;

      if (encKeyBase64 == null || encKeyBase64.isEmpty) {
        throw Exception(
            'Encrypted group key is null or empty (version=$versionString, userId=$userId)');
      }

      // Check if we already have the group key in local storage
      final groupKeyStorageKey = 'groupKey_${widget.sessionCode}_$keyVersion';
      final localKey = await storage.read(key: groupKeyStorageKey);
      if (localKey != null) {
        setState(() {
          groupKey = encrypt.Key(base64.decode(localKey));
        });
        debugPrint('Loaded group key v$keyVersion from local storage.');
        return;
      }

      // Otherwise, decrypt with user's private key
      final privateKeyPem = await _getOrFetchPrivateKey();
      if (privateKeyPem == null) {
        throw Exception('No private key found for user in local storage.');
      }

      final parser = encrypt.RSAKeyParser();
      final privateKey = parser.parse(privateKeyPem) as pc.RSAPrivateKey;

      final encrypter = encrypt.Encrypter(encrypt.RSA(
        privateKey: privateKey,
        encoding: encrypt.RSAEncoding.PKCS1,
      ));
      final encKey = encrypt.Encrypted.fromBase64(encKeyBase64);
      final decryptedBytes = encrypter.decryptBytes(encKey);

      if (decryptedBytes.isEmpty) {
        throw Exception('Decrypted group key is empty for version=$keyVersion.');
      }
      if (decryptedBytes.length != 32) {
        throw Exception(
            'Invalid group key length: ${decryptedBytes.length}. Expected 32 bytes.');
      }

      final newGroupKey = encrypt.Key(Uint8List.fromList(decryptedBytes));

      await storage.write(
        key: groupKeyStorageKey,
        value: base64.encode(newGroupKey.bytes),
      );
      if (!mounted) return;

      setState(() {
        groupKey = newGroupKey;
      });
      debugPrint('Group key (version=$keyVersion) initialized successfully.');
    } catch (e) {
      // Instead of popping up an error dialog and returning to home,
      // we'll just log the error and leave groupKey = null
      // so messages show "Unable to decrypt message."
      debugPrint('Error initializing group key: $e');
      setState(() {
        groupKey = null; // Force groupKey to null on error
      });
      // No pop-up or forced navigation
      // If desired, you could display a small banner or do nothing.
    }
  }

  // --------------------------------------------------------------------------
  // SESSION CHANGES LISTENER
  // --------------------------------------------------------------------------
  void _listenToSessionChanges() {
    _sessionSubscription = _firestore
        .collection('chat_sessions')
        .doc(widget.sessionCode)
        .snapshots()
        .listen((snapshot) async {
      if (!mounted) return;
      if (!snapshot.exists) {
        _showSessionEndedDialog();
        return;
      }

      final sessionData = snapshot.data() as Map<String, dynamic>;
      final participants = sessionData['participants'] ?? [];
      final leftParticipants = sessionData['leftParticipants'] ?? [];
      final newKeyVersion = sessionData['keyVersion'] ?? 1;

      final currentUid = _auth.currentUser!.uid;
      // Check participant status
      if (!participants.contains(currentUid)) {
        setState(() {
          isParticipant = false;
          hasLeftSession = false;
        });
      } else if (leftParticipants.contains(currentUid)) {
        setState(() {
          isParticipant = true;
          hasLeftSession = true;
        });
      } else {
        setState(() {
          isParticipant = true;
          hasLeftSession = false;
        });
      }

      // Re-init group key if version changed
      if (newKeyVersion != keyVersion) {
        keyVersion = newKeyVersion;
        if (isParticipant && !hasLeftSession) {
          await _initializeGroupKey();
        }
      }
    });
  }

  // --------------------------------------------------------------------------
  // SHARE REAL NAME
  // --------------------------------------------------------------------------
  Future<void> _shareRealName() async {
    if (!_isUserVerified || _passportName.isEmpty) return;

    final user = _auth.currentUser;
    if (user == null) return;
    final userId = user.uid;
    await _firestore
        .collection('chat_sessions')
        .doc(widget.sessionCode)
        .collection('messages')
        .add({
      'senderId': userId,
      'senderName': _passportName,
      'timestamp': Timestamp.now(),
      'verifiedShare': true,
      'encryptedContent': null,
    });
  }

  // --------------------------------------------------------------------------
  // ENCRYPT & DECRYPT MESSAGES
  // --------------------------------------------------------------------------
  Future<String> encryptGroupMessage(String msg, encrypt.Key groupKey) async {
    final iv = encrypt.IV.fromSecureRandom(16);
    final encrypter =
    encrypt.Encrypter(encrypt.AES(groupKey, mode: encrypt.AESMode.cbc));
    final encrypted = encrypter.encrypt(msg, iv: iv);
    return jsonEncode({
      'cipherText': encrypted.base64,
      'iv': iv.base64,
    });
  }

  Future<String> decryptGroupMessage(
      String encMsgJson, int messageKeyVersion) async {
    try {
      final neededKeyStr = await storage.read(
          key: 'groupKey_${widget.sessionCode}_$messageKeyVersion');
      if (neededKeyStr == null) {
        debugPrint('Missing group key for version=$messageKeyVersion');
        return 'Unable to decrypt (no local key)';
      }
      final neededKey = encrypt.Key(base64.decode(neededKeyStr));

      final map = jsonDecode(encMsgJson) as Map<String, dynamic>;
      if (!map.containsKey('cipherText') || !map.containsKey('iv')) {
        throw Exception('Encrypted JSON missing fields');
      }

      final enc = encrypt.Encrypted.fromBase64(map['cipherText']);
      final iv = encrypt.IV.fromBase64(map['iv']);
      final encrypter =
      encrypt.Encrypter(encrypt.AES(neededKey, mode: encrypt.AESMode.cbc));
      return encrypter.decrypt(enc, iv: iv);
    } catch (e) {
      debugPrint('Decryption error: $e');
      return 'Unable to decrypt message';
    }
  }

  // --------------------------------------------------------------------------
  // SEND MESSAGE
  // --------------------------------------------------------------------------
  Future<void> _sendMessage() async {
    // 1) Don’t return if groupKey is null. Only check if message is empty.
    if (_messageController.text.trim().isEmpty) return;

    final user = _auth.currentUser;
    if (user == null) return;

    final userId = user.uid;
    final sessionDoc = await _firestore
        .collection('chat_sessions')
        .doc(widget.sessionCode)
        .get();

    // 2) Session ended check
    if (!sessionDoc.exists) {
      _showSessionEndedDialog();
      return;
    }

    final sessionData = sessionDoc.data() as Map<String, dynamic>;
    final altNames = Map<String, dynamic>.from(sessionData['alternativeNames'] ?? {});
    final senderName = altNames[userId] ?? 'Unknown';

    final msg = _messageController.text.trim();
    final localKeyVersion = sessionData['keyVersion'] ?? 1;

    // 3) Determine if we have an AES key. If so, encrypt; otherwise fallback to plaintext.
    String? encryptedContent;
    int usedKeyVersion = 0; // 0 indicates no encryption used

    if (groupKey != null) {
      // Normal encryption path
      encryptedContent = await encryptGroupMessage(msg, groupKey!);
      usedKeyVersion = localKeyVersion;
    } else {
      // Fallback: groupKey == null -> send unencrypted
      encryptedContent = null;
    }

    // 4) Write message to Firestore
    await _firestore
        .collection('chat_sessions')
        .doc(widget.sessionCode)
        .collection('messages')
        .add({
      'senderId': userId,
      'senderName': senderName,
      'timestamp': Timestamp.now(),
      // If unencrypted, store plaintext in a separate field
      // or store it under 'plainText', etc.
      'plainText': groupKey == null ? msg : null,
      'encryptedContent': encryptedContent,
      'keyVersion': usedKeyVersion,
      'verifiedShare': false,
    });

    // 5) Update unread counts
    final participants = sessionData['participants'] ?? [];
    final unreadCounts = Map<String, dynamic>.from(sessionData['unreadCounts'] ?? {});

    for (final pid in participants) {
      if (pid != userId) {
        unreadCounts[pid] = (unreadCounts[pid] ?? 0) + 1;
      }
    }

    await _firestore.collection('chat_sessions').doc(widget.sessionCode).update({
      'lastMessage': groupKey == null ? 'Plaintext Message' : 'Encrypted Message',
      'lastMessageTime': Timestamp.now(),
      'unreadCounts': unreadCounts,
    });

    _messageController.clear();
  }


  // --------------------------------------------------------------------------
  // MESSAGES STREAM
  // --------------------------------------------------------------------------
  Stream<QuerySnapshot> _messagesStream() {
    return _firestore
        .collection('chat_sessions')
        .doc(widget.sessionCode)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  // --------------------------------------------------------------------------
  // BUILD
  // --------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final currentUserId = _auth.currentUser?.uid ?? '';

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SessionInfoScreen(sessionCode: widget.sessionCode),
            ),
          ),
          child: Text(
            'Session ${widget.sessionCode}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        backgroundColor: const Color(0xFF0088cc), // Telegram-like blue
        elevation: 0,
      ),
      body: Container(
        color: Colors.grey[100],
        child: Column(
          children: [
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _messagesStream(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(
                      child: Text('Error: ${snap.error}'),
                    );
                  }
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final docs = snap.data!.docs;
                  return ListView.builder(
                    reverse: true,
                    itemCount: docs.length,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 10),
                    itemBuilder: (ctx, index) {
                      final messageData =
                      docs[index].data() as Map<String, dynamic>;
                      final isMe = messageData['senderId'] == currentUserId;
                      final isShare = messageData['verifiedShare'] ?? false;

                      if (isShare) {
                        // Real-name share message bubble
                        final realName =
                            messageData['senderName'] ?? 'Unknown';
                        return _buildVerifiedShareBubble(realName, isMe);
                      }

                      // Normal encrypted message
                      return FutureBuilder<String>(
                        future: _decryptFuture(messageData),
                        builder: (ctx2, snap2) {
                          final decryptedText =
                              snap2.data ?? 'Decrypting...';
                          return _buildMessageBubble(
                            text: decryptedText,
                            senderName:
                            messageData['senderName'] ?? 'Unknown',
                            isMe: isMe,
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
            const Divider(height: 1),
            if (isParticipant && !hasLeftSession)
              _buildInputArea()
            else if (hasLeftSession)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('You have left this session.'),
              )
            else
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('You are no longer a participant in this session.'),
              ),
          ],
        ),
      ),
    );
  }

  // Decrypt in a separate function
  Future<String> _decryptFuture(Map<String, dynamic> msg) async {
    // Check if there's a plainText field (i.e., unencrypted message).
    final plainContent = msg['plainText'] as String?;
    if (plainContent != null && plainContent.isNotEmpty) {
      // This is an unencrypted message. Return it directly.
      return plainContent;
    }

    // Otherwise, proceed with normal decryption logic
    final encContent = msg['encryptedContent'] as String?;
    if (encContent == null || encContent.isEmpty) {
      // No encryption, no plain text => empty string or unknown
      return '';
    }

    // Attempt to decrypt
    final v = msg['keyVersion'] ?? 1;
    return await decryptGroupMessage(encContent, v);
  }


  // Verified share bubble
  Widget _buildVerifiedShareBubble(String realName, bool isMe) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isMe ? Colors.green[50] : Colors.orange[50],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              realName,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.verified, color: Colors.blue, size: 16),
          ],
        ),
      ),
    );
  }

  // Normal message bubble
  Widget _buildMessageBubble({
    required String text,
    required String senderName,
    required bool isMe,
  }) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color:
          isMe ? const Color(0xFF0088cc).withOpacity(0.15) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: isMe
              ? Border.all(color: const Color(0xFF0088cc), width: 1)
              : Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          crossAxisAlignment:
          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              senderName,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  // Input area
  Widget _buildInputArea() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: const InputDecoration(
                  hintText: 'Send a message',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding:
                  EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.send, color: Color(0xFF0088cc)),
              onPressed: _sendMessage,
            ),
          ]),
          const SizedBox(height: 8),
          // Share Real Name Button
          if (_isUserVerified)
            ElevatedButton.icon(
              icon: const Icon(Icons.verified_user, color: Colors.white),
              label: const Text('Share My Real Name'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0088cc),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: _shareRealName,
            )
          else
            Tooltip(
              message: 'Passport not verified',
              child: ElevatedButton.icon(
                icon: const Icon(Icons.cancel),
                label: const Text('Share My Real Name'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: null,
              ),
            ),
        ],
      ),
    );
  }

  // Session ended
  void _showSessionEndedDialog() {
    _sessionSubscription?.cancel();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Session Ended'),
        content: const Text('This session has ended or been deleted.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _sessionSubscription?.cancel();
    super.dispose();
  }
}
