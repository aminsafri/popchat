// lib/create_session_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'chat_screen.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:basic_utils/basic_utils.dart';
import 'package:pointycastle/asymmetric/api.dart' show RSAPublicKey;
import 'dart:convert';

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

  Future<void> _createSession() async {
    if (!_formKey.currentState!.validate()) return;

    String sessionCode = await generateUniqueSessionCode(6);
    String ownerId = _auth.currentUser!.uid;

    DateTime expiryTime = DateTime.now().add(sessionDuration);

    // Upload the session image if one is selected
    if (_sessionImage != null) {
      _sessionImageUrl = await _uploadSessionImage(_sessionImage!, sessionCode);
    }

    // Ensure _sessionImageUrl is not null
    _sessionImageUrl ??= '';

    // Generate group key
    encrypt.Key groupKey = generateGroupKey();

    // Retrieve owner's public key from Firestore
    DocumentSnapshot ownerDoc = await _firestore.collection('users').doc(ownerId).get();
    String ownerPublicKeyPem = ownerDoc['publicKey'];

    // Encrypt group key for owner
    String encryptedGroupKey = await encryptGroupKeyForParticipant(ownerPublicKeyPem, groupKey);

    // Create encrypted group keys map
    Map<String, String> encryptedGroupKeys = {
      ownerId: encryptedGroupKey,
    };

    Map<String, dynamic> sessionData = {
      'ownerId': ownerId,
      'sessionTitle': sessionTitle,
      'sessionImageUrl': _sessionImageUrl,
      'maxParticipants': maxParticipants,
      'expiryTime': Timestamp.fromDate(expiryTime),
      'createdAt': Timestamp.now(),
      'requiresSecretKey': requiresSecretKey,
      'secretKey': requiresSecretKey ? secretKey : null,
      'participants': [ownerId],
      'alternativeNames': {
        ownerId: alternativeName.isNotEmpty ? alternativeName : _auth.currentUser!.displayName,
      },
      'unreadCounts': {},
      'leftParticipants': [],
      'encryptedGroupKeys': encryptedGroupKeys,
      'keyVersion': 1,
    };

    await _firestore.collection('chat_sessions').doc(sessionCode).set(sessionData);

    // Store the group key locally for the creator
    await storage.write(key: 'groupKey_${sessionCode}_1', value: base64.encode(groupKey.bytes));

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
  }

  String generateUniqueCode(int length) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    Random random = Random.secure();
    return List.generate(length, (index) => chars[random.nextInt(chars.length)]).join();
  }

  Future<String> generateUniqueSessionCode(int length) async {
    String code;
    bool exists = true;

    do {
      code = generateUniqueCode(length);
      // Check if the code already exists in Firestore
      var doc = await _firestore.collection('chat_sessions').doc(code).get();
      exists = doc.exists;
    } while (exists);

    return code;
  }

  // Method to pick an image
  Future<void> _pickSessionImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _sessionImage = File(pickedFile.path);
      });
    }
  }

  // Method to upload the session image to Firebase Storage
  Future<String> _uploadSessionImage(File imageFile, String sessionCode) async {
    try {
      // Create a unique file name using the session code
      String fileName = '$sessionCode.jpg';

      // Create a reference to the Firebase Storage bucket
      Reference storageReference = FirebaseStorage.instance.ref().child('session_images/$fileName');

      // Upload the file to Firebase Storage
      UploadTask uploadTask = storageReference.putFile(imageFile);

      // Wait for the upload to complete
      TaskSnapshot snapshot = await uploadTask;

      // Retrieve the download URL
      String downloadUrl = await snapshot.ref.getDownloadURL();

      // Print the download URL for debugging
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
                child: ListView(children: [
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
                  // Display selected image
                  if (_sessionImage != null)
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      height: 150,
                      child: Image.file(_sessionImage!),
                    ),
                  // Button to pick image
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
                      int? val = int.tryParse(value!);
                      if (val == null || val < 1) {
                        return 'Enter a valid number greater than 0';
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
                ]))));
  }
}
