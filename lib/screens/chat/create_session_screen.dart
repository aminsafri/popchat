// lib/screens/chat/create_session_screen.dart

import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:basic_utils/basic_utils.dart';
import 'package:pointycastle/asymmetric/api.dart' show RSAPublicKey;
import 'dart:convert';

import 'chat_screen.dart';

class CreateSessionScreen extends StatefulWidget {
  @override
  _CreateSessionScreenState createState() => _CreateSessionScreenState();
}

class _CreateSessionScreenState extends State<CreateSessionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  int maxParticipants = 10;
  Duration sessionDuration = const Duration(hours: 1);
  bool requiresSecretKey = false;
  String secretKey = '';
  String alternativeName = '';
  String sessionTitle = '';
  File? _sessionImage;
  String? _sessionImageUrl;

  final storage = const FlutterSecureStorage();

  encrypt.Key generateGroupKey() {
    return encrypt.Key.fromSecureRandom(32); // 256-bit key
  }

  /// Helper method to format public key PEM if missing headers
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

  Future<String> encryptGroupKeyForParticipant(String publicKeyPem, encrypt.Key groupKey) async {
    // Ensure proper PEM formatting
    if (!publicKeyPem.contains('-----BEGIN RSA PUBLIC KEY-----') ||
        !publicKeyPem.contains('-----END RSA PUBLIC KEY-----')) {
      publicKeyPem = reconstructPem(publicKeyPem, 'RSA PUBLIC KEY');
    }

    final parsedKey = CryptoUtils.rsaPublicKeyFromPem(publicKeyPem);
    final encrypter = encrypt.Encrypter(encrypt.RSA(
      publicKey: parsedKey,
      encoding: encrypt.RSAEncoding.PKCS1,
    ));
    final encryptedGroupKey = encrypter.encryptBytes(groupKey.bytes);
    return encryptedGroupKey.base64;
  }

  Future<void> _createSession() async {
    if (!_formKey.currentState!.validate()) return;

    final userId = _auth.currentUser!.uid;
    final sessionCode = await _generateUniqueSessionCode(6);

    // Calculate expiry
    final expiryTime = DateTime.now().add(sessionDuration);

    // Upload session image if selected
    if (_sessionImage != null) {
      _sessionImageUrl = await _uploadSessionImage(_sessionImage!, sessionCode);
    }
    _sessionImageUrl ??= '';

    // 1) Generate group key
    final groupKey = generateGroupKey();

    // 2) Encrypt group key for the owner
    final ownerDoc = await _firestore.collection('users').doc(userId).get();
    final ownerPublicKeyPem = ownerDoc['publicKey'] as String;
    final encryptedGroupKeyForOwner = await encryptGroupKeyForParticipant(ownerPublicKeyPem, groupKey);

    // 3) Build nested `encryptedGroupKeys` (version 1)
    final encryptedGroupKeysByVersion = {
      "1": {
        userId: encryptedGroupKeyForOwner,
      }
    };

    // 4) Create session data
    final sessionData = {
      'ownerId': userId,
      'sessionTitle': sessionTitle,
      'sessionImageUrl': _sessionImageUrl,
      'maxParticipants': maxParticipants,
      'expiryTime': Timestamp.fromDate(expiryTime),
      'createdAt': Timestamp.now(),
      'requiresSecretKey': requiresSecretKey,
      'secretKey': requiresSecretKey ? secretKey : null,
      'participants': [userId],
      'alternativeNames': {
        userId: alternativeName.isNotEmpty ? alternativeName : _auth.currentUser!.displayName,
      },
      'unreadCounts': {},
      'leftParticipants': [],
      'encryptedGroupKeys': encryptedGroupKeysByVersion,
      'keyVersion': 1,
    };

    // 5) Save session in Firestore
    await _firestore.collection('chat_sessions').doc(sessionCode).set(sessionData);

    // 6) Store the group key locally for the creator
    await storage.write(
      key: 'groupKey_${sessionCode}_1',
      value: base64.encode(groupKey.bytes),
    );

    // 7) Navigate to the chat screen
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          sessionCode: sessionCode,
          alternativeName: alternativeName,
        ),
      ),
    );
  }

  Future<String> _generateUniqueSessionCode(int length) async {
    String code;
    bool exists = true;
    do {
      code = _generateCode(length);
      final doc = await _firestore.collection('chat_sessions').doc(code).get();
      exists = doc.exists;
    } while (exists);
    return code;
  }

  String _generateCode(int length) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rand = Random.secure();
    return List.generate(length, (index) => chars[rand.nextInt(chars.length)]).join();
  }

  Future<void> _pickSessionImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _sessionImage = File(pickedFile.path);
      });
    }
  }

  Future<String> _uploadSessionImage(File imageFile, String sessionCode) async {
    try {
      final fileName = '$sessionCode.jpg';
      final storageReference = FirebaseStorage.instance.ref().child('session_images/$fileName');
      final uploadTask = storageReference.putFile(imageFile);
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();
      print('Download URL: $downloadUrl');
      return downloadUrl;
    } on FirebaseException catch (e) {
      print('Firebase Exception: ${e.code} - ${e.message}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to upload session image: ${e.message}')),
      );
      return '';
    } catch (e) {
      print('Unknown error uploading session image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to upload session image.')),
      );
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Modern AppBar with a brand color
      appBar: AppBar(
        title: const Text(
          'PopChat - New Session',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF0088cc), // Telegram-like blue
        elevation: 0,
      ),
      // Solid background color for reduced eye strain
      body: Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.grey[100],
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: SingleChildScrollView(
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
                      Text(
                        'Create Chat Session',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Session Title
                      TextFormField(
                        decoration: InputDecoration(
                          labelText: 'Session Title',
                          hintText: 'Enter a descriptive title',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter a session title';
                          }
                          return null;
                        },
                        onChanged: (value) => sessionTitle = value,
                      ),
                      const SizedBox(height: 16),
                      // Alternative Display Name
                      TextFormField(
                        decoration: InputDecoration(
                          labelText: 'Alternative Display Name',
                          hintText: 'Optional alias in this session',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) => alternativeName = value,
                      ),
                      const SizedBox(height: 16),
                      // Session Image Preview
                      if (_sessionImage != null)
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 10),
                          height: 150,
                          child: Image.file(_sessionImage!),
                        ),
                      // Pick Image Button
                      TextButton.icon(
                        icon: const Icon(Icons.image, color: Color(0xFF0088cc)),
                        label: const Text('Select Session Image',
                            style: TextStyle(color: Color(0xFF0088cc))),
                        onPressed: _pickSessionImage,
                      ),
                      const SizedBox(height: 16),
                      // Maximum Participants
                      TextFormField(
                        decoration: InputDecoration(
                          labelText: 'Maximum Participants',
                          border: OutlineInputBorder(),
                        ),
                        initialValue: '10',
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          final val = int.tryParse(value!);
                          if (val == null || val < 1) {
                            return 'Enter a valid number > 0';
                          }
                          return null;
                        },
                        onChanged: (value) => maxParticipants = int.parse(value),
                      ),
                      const SizedBox(height: 16),
                      // Session Duration
                      DropdownButtonFormField<Duration>(
                        decoration: InputDecoration(
                          labelText: 'Session Duration',
                          border: OutlineInputBorder(),
                        ),
                        value: sessionDuration,
                        items: const [
                          DropdownMenuItem(
                              child: Text('30 Minutes'),
                              value: Duration(minutes: 30)),
                          DropdownMenuItem(
                              child: Text('1 Hour'),
                              value: Duration(hours: 1)),
                          DropdownMenuItem(
                              child: Text('2 Hours'),
                              value: Duration(hours: 2)),
                          DropdownMenuItem(
                              child: Text('1 Day'),
                              value: Duration(days: 1)),
                        ],
                        onChanged: (value) => setState(() => sessionDuration = value!),
                      ),
                      const SizedBox(height: 16),
                      // Requires Secret Key
                      SwitchListTile(
                        title: const Text('Require Secret Key?'),
                        activeColor: const Color(0xFF0088cc),
                        value: requiresSecretKey,
                        onChanged: (value) => setState(() => requiresSecretKey = value),
                      ),
                      if (requiresSecretKey)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: TextFormField(
                            decoration: InputDecoration(
                              labelText: 'Secret Key',
                              hintText: 'Enter secret key for session',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter a secret key';
                              }
                              return null;
                            },
                            onChanged: (value) => secretKey = value,
                          ),
                        ),
                      const SizedBox(height: 20),
                      // Create Session Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            if (_formKey.currentState!.validate()) {
                              _createSession();
                            }
                          },
                          icon: const Icon(Icons.check_circle, color: Colors.white),
                          label: const Text(
                            'Create Session',
                            style: TextStyle(
                              fontSize: 18, // Increased font size for better readability
                              fontWeight: FontWeight.bold, // Bold font weight for emphasis
                              color: Colors.white, // Ensures high contrast against the button's background
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0088cc), // Telegram-like blue for the button's background
                            padding: const EdgeInsets.symmetric(vertical: 16), // Increased vertical padding for a larger touch target
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12), // Rounded corners for a modern look
                            ),
                            elevation: 5, // Slight elevation for depth
                            shadowColor: Colors.black26, // Subtle shadow for better visibility
                          ),
                        ),
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
