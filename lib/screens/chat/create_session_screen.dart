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

    // 3) Build nested `encryptedGroupKeys`
    // We'll store version '1' in a submap
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
      'encryptedGroupKeys': encryptedGroupKeysByVersion, // nested
      'keyVersion': 1, // start at 1
    };

    // 5) Save session in Firestore
    await _firestore.collection('chat_sessions').doc(sessionCode).set(sessionData);

    // 6) Store group key locally for the creator
    await storage.write(
      key: 'groupKey_${sessionCode}_1',
      value: base64.encode(groupKey.bytes),
    );

    // 7) Navigate to chat
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
      appBar: AppBar(title: const Text('Create Chat Session')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                decoration: const InputDecoration(labelText: 'Session Title'),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Please enter a session title';
                  return null;
                },
                onChanged: (value) => sessionTitle = value,
              ),
              TextFormField(
                decoration: const InputDecoration(labelText: 'Alternative Display Name'),
                onChanged: (value) => alternativeName = value,
              ),
              if (_sessionImage != null)
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  height: 150,
                  child: Image.file(_sessionImage!),
                ),
              TextButton.icon(
                icon: const Icon(Icons.image),
                label: const Text('Select Session Image'),
                onPressed: _pickSessionImage,
              ),
              TextFormField(
                decoration: const InputDecoration(labelText: 'Maximum Participants'),
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
              DropdownButtonFormField<Duration>(
                decoration: const InputDecoration(labelText: 'Session Duration'),
                value: sessionDuration,
                items: const [
                  DropdownMenuItem(child: Text('30 Minutes'), value: Duration(minutes: 30)),
                  DropdownMenuItem(child: Text('1 Hour'), value: Duration(hours: 1)),
                  DropdownMenuItem(child: Text('2 Hours'), value: Duration(hours: 2)),
                  DropdownMenuItem(child: Text('1 Day'), value: Duration(days: 1)),
                ],
                onChanged: (value) => setState(() => sessionDuration = value!),
              ),
              SwitchListTile(
                title: const Text('Require Secret Key'),
                value: requiresSecretKey,
                onChanged: (value) => setState(() => requiresSecretKey = value),
              ),
              if (requiresSecretKey)
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Secret Key'),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Please enter a secret key';
                    return null;
                  },
                  onChanged: (value) => secretKey = value,
                ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _createSession,
                child: const Text('Create Session'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
