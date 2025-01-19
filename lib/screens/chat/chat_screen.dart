// lib/screens/chat/chat_screen.dart

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
  encrypt.Key? groupKey; // current group's key
  int keyVersion = 1;

  // Real name
  bool _isUserVerified = false;
  String _passportName = '';

  @override
  void initState() {
    super.initState();
    _initializeGroupKey().then((_) {
      _testAESEncryptionDecryption();
    });
    _listenToSessionChanges();
    _fetchUserVerificationStatus();
    _testRSAEncryptionDecryption(); // optional
  }

  // --------------------------------------------------------------------------
  // USER VERIFICATION
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

  // Example test for RSA
  Future<void> _testRSAEncryptionDecryption() async {
    // same as your _testEncryptionDecryption()...
  }

  // Example test for AES
  Future<void> _testAESEncryptionDecryption() async {
    if (groupKey == null) return;
    final testMsg = "Hello AES test!";
    final iv = encrypt.IV.fromSecureRandom(16);
    final encrypter = encrypt.Encrypter(encrypt.AES(groupKey!, mode: encrypt.AESMode.cbc));
    final encrypted = encrypter.encrypt(testMsg, iv: iv);
    final decrypted = encrypter.decrypt(encrypted, iv: iv);
    if (testMsg == decrypted) {
      print("AES test success!");
    } else {
      print("AES test failed!");
    }
  }

  // --------------------------------------------------------------------------
  // GET / FETCH PRIVATE KEY
  // --------------------------------------------------------------------------
  Future<String?> _getOrFetchPrivateKey() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    final localKey = await storage.read(key: 'privateKey');
    return localKey;
  }

  // --------------------------------------------------------------------------
  // INITIALIZE GROUP KEY (pull the current version from Firestore)
  // --------------------------------------------------------------------------
  Future<void> _initializeGroupKey() async {
    try {
      final sessionDoc = await _firestore.collection('chat_sessions').doc(widget.sessionCode).get();
      if (!sessionDoc.exists) {
        _showSessionEndedDialog();
        return;
      }
      final sessionData = sessionDoc.data() as Map<String, dynamic>;
      final allEncKeys = sessionData['encryptedGroupKeys'] ?? {};
      keyVersion = sessionData['keyVersion'] ?? 1;

      // We look for submap => allEncKeys["1"], allEncKeys["2"], etc.
      // The user's specific base64 is in allEncKeys["keyVersion"]["uid"].

      final versionMap = (allEncKeys["$keyVersion"] ?? {}) as Map<String, dynamic>;
      final encKeyBase64 = versionMap[_auth.currentUser!.uid] as String?;
      print("DEBUG: encKeyBase64($keyVersion) = $encKeyBase64");
      if (encKeyBase64 == null || encKeyBase64.isEmpty) {
        throw Exception('No encrypted key for your user at keyVersion=$keyVersion');
      }

      // Check local secure storage
      final groupKeyStorageKey = 'groupKey_${widget.sessionCode}_$keyVersion';
      final localKey = await storage.read(key: groupKeyStorageKey);
      if (localKey != null) {
        setState(() {
          groupKey = encrypt.Key(base64.decode(localKey));
        });
        print('Loaded group key from local storage (v$keyVersion)');
        return;
      }

      // Decrypt with user's private key
      final privateKeyPem = await _getOrFetchPrivateKey();
      if (privateKeyPem == null) {
        throw Exception('No private key found in local storage.');
      }

      // parse private key
      final parser = encrypt.RSAKeyParser();
      final privateKey = parser.parse(privateKeyPem) as pc.RSAPrivateKey;

      final encrypter = encrypt.Encrypter(
        encrypt.RSA(privateKey: privateKey, encoding: encrypt.RSAEncoding.PKCS1),
      );
      final encKey = encrypt.Encrypted.fromBase64(encKeyBase64);
      final decryptedBytes = encrypter.decryptBytes(encKey);
      if (decryptedBytes.isEmpty) throw Exception("Decrypted group key is empty");
      if (decryptedBytes.length != 32) throw Exception("Invalid group key length: ${decryptedBytes.length}");
      final newGroupKey = encrypt.Key(Uint8List.fromList(decryptedBytes));

      // Save to local
      await storage.write(key: groupKeyStorageKey, value: base64.encode(newGroupKey.bytes));
      setState(() {
        groupKey = newGroupKey;
      });
      print("Group key (v$keyVersion) initialized successfully.");
    } catch (e) {
      print("Error initializing group key: $e");
      _showDecryptionErrorDialog(e.toString());
    }
  }

  // --------------------------------------------------------------------------
  // LISTEN TO SESSION CHANGES
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
      final newKeyVersion = sessionData['keyVersion'] ?? 1;
      if (newKeyVersion != keyVersion) {
        keyVersion = newKeyVersion;
        await _initializeGroupKey(); // re-init if version changed
        if (!mounted) return;
      }

      // Check if user is participant or left, etc.
      final participants = sessionData['participants'] ?? [];
      final leftParticipants = sessionData['leftParticipants'] ?? [];
      final currentUid = _auth.currentUser!.uid;
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
    });
  }

  // --------------------------------------------------------------------------
  // SHARE REAL NAME
  // --------------------------------------------------------------------------
  Future<void> _shareRealName() async {
    if (!_isUserVerified || _passportName.isEmpty) {
      return;
    }
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
  // ENCRYPT GROUP MESSAGE
  // --------------------------------------------------------------------------
  Future<String> encryptGroupMessage(String msg, encrypt.Key groupKey) async {
    final iv = encrypt.IV.fromSecureRandom(16);
    final encrypter = encrypt.Encrypter(encrypt.AES(groupKey, mode: encrypt.AESMode.cbc));
    final encrypted = encrypter.encrypt(msg, iv: iv);
    return jsonEncode({
      'cipherText': encrypted.base64,
      'iv': iv.base64,
    });
  }

  // --------------------------------------------------------------------------
  // DECRYPT GROUP MESSAGE
  // --------------------------------------------------------------------------
  Future<String> decryptGroupMessage(String encMsgJson, int messageKeyVersion) async {
    try {
      // load the correct key from local
      final neededKeyStr = await storage.read(key: 'groupKey_${widget.sessionCode}_$messageKeyVersion');
      if (neededKeyStr == null) {
        print('Missing group key for version=$messageKeyVersion');
        return 'Unable to decrypt (no local key)';
      }

      final neededKey = encrypt.Key(base64.decode(neededKeyStr));
      final map = jsonDecode(encMsgJson) as Map<String, dynamic>;
      if (!map.containsKey('cipherText') || !map.containsKey('iv')) {
        throw Exception('Encrypted JSON missing fields');
      }
      final enc = encrypt.Encrypted.fromBase64(map['cipherText']);
      final iv = encrypt.IV.fromBase64(map['iv']);
      final encrypter = encrypt.Encrypter(encrypt.AES(neededKey, mode: encrypt.AESMode.cbc));
      final decrypted = encrypter.decrypt(enc, iv: iv);
      return decrypted;
    } catch (e) {
      print('Decryption error: $e');
      return 'Unable to decrypt message';
    }
  }

  // --------------------------------------------------------------------------
  // SEND MESSAGE
  // --------------------------------------------------------------------------
  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty || groupKey == null) return;
    final user = _auth.currentUser;
    if (user == null) return;

    final userId = user.uid;
    final sessionDoc = await _firestore.collection('chat_sessions').doc(widget.sessionCode).get();
    if (!sessionDoc.exists) {
      _showSessionEndedDialog();
      return;
    }

    final sessionData = sessionDoc.data() as Map<String, dynamic>;
    final altNames = Map<String, dynamic>.from(sessionData['alternativeNames'] ?? {});
    final senderName = altNames[userId] ?? 'Unknown';

    final msg = _messageController.text.trim();
    final localKeyVersion = sessionData['keyVersion'] ?? 1;
    final encrypted = await encryptGroupMessage(msg, groupKey!);

    await _firestore
        .collection('chat_sessions')
        .doc(widget.sessionCode)
        .collection('messages')
        .add({
      'senderId': userId,
      'senderName': senderName,
      'timestamp': Timestamp.now(),
      'encryptedContent': encrypted,
      'keyVersion': localKeyVersion,
      'verifiedShare': false,
    });

    // update unread counts
    final participants = sessionData['participants'] ?? [];
    final unreadCounts = Map<String, dynamic>.from(sessionData['unreadCounts'] ?? {});
    for (final pid in participants) {
      if (pid != userId) {
        unreadCounts[pid] = (unreadCounts[pid] ?? 0) + 1;
      }
    }
    await _firestore.collection('chat_sessions').doc(widget.sessionCode).update({
      'lastMessage': 'Encrypted Message',
      'lastMessageTime': Timestamp.now(),
      'unreadCounts': unreadCounts,
    });

    _messageController.clear();
  }

  // --------------------------------------------------------------------------
  // STREAM OF MESSAGES
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
          child: Text('Session ${widget.sessionCode}'),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _messagesStream(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data!.docs;
                return ListView.builder(
                  reverse: true,
                  itemCount: docs.length,
                  itemBuilder: (ctx, index) {
                    final messageData = docs[index].data() as Map<String, dynamic>;
                    final isMe = messageData['senderId'] == currentUserId;
                    final isShare = messageData['verifiedShare'] ?? false;

                    if (isShare) {
                      // Real-name share
                      final realName = messageData['senderName'] ?? 'Unknown';
                      return _buildVerifiedShareBubble(realName, isMe);
                    }

                    // normal encrypted
                    return FutureBuilder<String>(
                      future: _decryptFuture(messageData),
                      builder: (ctx2, snap2) {
                        final decryptedText = snap2.data ?? 'Decrypting...';
                        return _buildNormalMessageBubble(
                          decryptedText,
                          messageData['senderName'] ?? 'Unknown',
                          isMe,
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          const Divider(height: 1),
          if (isParticipant && !hasLeftSession) _buildInputArea()
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
    );
  }

  // Asynchronously decrypt
  Future<String> _decryptFuture(Map<String, dynamic> msg) async {
    final encContent = msg['encryptedContent'] as String?;
    if (encContent == null || encContent.isEmpty) return '';
    final v = msg['keyVersion'] ?? 1;
    return await decryptGroupMessage(encContent, v);
  }

  Widget _buildVerifiedShareBubble(String realName, bool isMe) {
    return ListTile(
      title: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isMe ? Colors.green[50] : Colors.orange[50],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(realName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(width: 4),
              const Icon(Icons.verified, color: Colors.blue, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNormalMessageBubble(String text, String senderName, bool isMe) {
    return ListTile(
      title: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isMe ? Colors.blue[200] : Colors.grey[300],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(text, style: const TextStyle(fontSize: 16)),
        ),
      ),
      subtitle: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Text(
          senderName,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      color: Theme.of(context).cardColor,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: const InputDecoration.collapsed(hintText: 'Send a message'),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send),
              onPressed: _sendMessage,
            ),
          ]),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isUserVerified)
                ElevatedButton.icon(
                  icon: const Icon(Icons.verified_user),
                  label: const Text('Share My Real Name'),
                  onPressed: _shareRealName,
                )
              else
                Tooltip(
                  message: 'Passport not verified',
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.cancel),
                    label: const Text('Share My Real Name'),
                    onPressed: null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

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

  void _showDecryptionErrorDialog(String err) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decryption Error'),
        content: Text(err),
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
