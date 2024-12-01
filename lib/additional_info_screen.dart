// lib/additional_info_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:basic_utils/basic_utils.dart';

class AdditionalInfoScreen extends StatefulWidget {
  final User user;

  AdditionalInfoScreen({required this.user});

  @override
  State<AdditionalInfoScreen> createState() => _AdditionalInfoScreenState();
}

class _AdditionalInfoScreenState extends State<AdditionalInfoScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _formKey = GlobalKey<FormState>();
  String displayName = '';
  bool isLoading = false;
  String errorMessage = '';

  final storage = FlutterSecureStorage();

  Future<void> _saveUserInfo() async {
    setState(() {
      isLoading = true;
      errorMessage = '';
    });

    try {
      // Update user profile
      print('Updating user profile...');
      await widget.user.updateDisplayName(displayName);

      // Save user data to Firestore
      print('Saving user data to Firestore...');
      await _firestore.collection('users').doc(widget.user.uid).set({
        'displayName': displayName,
        'phoneNumber': widget.user.phoneNumber,
      }, SetOptions(merge: true));

      // Generate RSA key pair and upload public key
      print('Generating and storing RSA key pair...');
      await generateAndStoreRSAKeyPair();

      print('User info saved successfully.');
      // No need to navigate manually; the StreamBuilder in main.dart will handle it
    } catch (e, stackTrace) {
      print('Error in _saveUserInfo: $e\n$stackTrace');
      setState(() {
        isLoading = false;
        if (e is FirebaseException) {
          errorMessage = 'Failed to save user info: ${e.code} - ${e.message}';
        } else {
          errorMessage = 'Failed to save user info: $e';
        }
      });
    }
  }

  Future<void> generateAndStoreRSAKeyPair() async {
    try {
      print('Generating RSA key pair...');
      AsymmetricKeyPair<PublicKey, PrivateKey> keyPair = CryptoUtils.generateRSAKeyPair(keySize: 2048);

      RSAPublicKey publicKey = keyPair.publicKey as RSAPublicKey;
      RSAPrivateKey privateKey = keyPair.privateKey as RSAPrivateKey;

      print('Encoding keys to PEM format...');
      String publicKeyPem = CryptoUtils.encodeRSAPublicKeyToPemPkcs1(publicKey);
      String privateKeyPem = CryptoUtils.encodeRSAPrivateKeyToPemPkcs1(privateKey);

      print('Storing private key securely...');
      await storage.write(key: 'privateKey', value: privateKeyPem);

      print('Uploading public key to Firestore...');
      await uploadPublicKey(publicKeyPem);

      print('RSA key pair generated and stored successfully.');
    } catch (e, stackTrace) {
      print('Error generating RSA key pair: $e\n$stackTrace');
      throw e; // Rethrow the exception to be caught in _saveUserInfo()
    }
  }

  Future<void> uploadPublicKey(String publicKeyPem) async {
    await _firestore.collection('users').doc(widget.user.uid).set({
      'publicKey': publicKeyPem,
    }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Additional Information')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              const Text(
                'Enter your display name',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 20),
              TextFormField(
                decoration: const InputDecoration(labelText: 'Display Name'),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Please enter display name';
                  return null;
                },
                onChanged: (value) => displayName = value.trim(),
              ),
              const SizedBox(height: 20),
              isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                onPressed: () {
                  if (_formKey.currentState?.validate() ?? false) {
                    _saveUserInfo();
                  }
                },
                child: const Text('Continue'),
              ),
              const SizedBox(height: 10),
              Text(errorMessage, style: const TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ),
    );
  }
}
