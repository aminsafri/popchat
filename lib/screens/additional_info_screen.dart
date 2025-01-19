// lib/screens/additional_info_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:basic_utils/basic_utils.dart';
import 'package:pointycastle/asymmetric/api.dart' show RSAPublicKey, RSAPrivateKey;
import 'package:flutter/foundation.dart'; // For compute
import 'home_screen.dart';

/// **Important Note:**
///
/// **Security Warning:**
///
/// Storing private keys in Firestore is **insecure** and **strongly discouraged** for production applications.
/// Private keys should **never** be exposed or stored in backend services. Instead, use device-specific secure storage
/// solutions such as **Keychain** for iOS or **Keystore** for Android.
///
/// The following implementation stores the private key in Firestore for demonstration purposes only.
/// **Do not** adopt this practice in real-world applications.

class AdditionalInfoScreen extends StatefulWidget {
  final User user;
  const AdditionalInfoScreen({Key? key, required this.user}) : super(key: key);

  @override
  State<AdditionalInfoScreen> createState() => _AdditionalInfoScreenState();
}

class _AdditionalInfoScreenState extends State<AdditionalInfoScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _formKey = GlobalKey<FormState>();
  final storage = const FlutterSecureStorage();

  String displayName = '';
  bool isLoading = false;
  String errorMessage = '';

  @override
  void initState() {
    super.initState();
    // Optionally, you can pre-fetch or initialize any data here
  }

  /// Generates an RSA key pair and returns their PEM-encoded strings
  /// Runs in a separate isolate to prevent blocking the UI
  static Future<Map<String, String>> _generateRSAKeyPairIsolate(int keySize) async {
    // Generate RSA key pair using basic_utils
    final keyPair = CryptoUtils.generateRSAKeyPair(keySize: keySize);

    final publicKey = keyPair.publicKey as RSAPublicKey;
    final privateKey = keyPair.privateKey as RSAPrivateKey;

    // Encode keys to PEM format
    final publicKeyPem = CryptoUtils.encodeRSAPublicKeyToPemPkcs1(publicKey);
    final privateKeyPem = CryptoUtils.encodeRSAPrivateKeyToPemPkcs1(privateKey);
    print(publicKeyPem);
    print(privateKeyPem);

    return {
      'publicKeyPem': publicKeyPem,
      'privateKeyPem': privateKeyPem,
    };
  }

  /// Reconstructs a single-line PEM string into proper PEM format with headers, footers, and line breaks.
  String reconstructPem(String pem, String keyType) {
    // Remove existing headers and footers if any
    pem = pem.replaceAll('-----BEGIN $keyType-----', '');
    pem = pem.replaceAll('-----END $keyType-----', '');

    // Remove any existing line breaks or spaces
    pem = pem.replaceAll('\n', '').replaceAll('\r', '').replaceAll(' ', '');

    // Insert line breaks every 64 characters
    final buffer = StringBuffer();
    for (int i = 0; i < pem.length; i += 64) {
      int end = (i + 64 < pem.length) ? i + 64 : pem.length;
      buffer.writeln(pem.substring(i, end));
    }

    return '-----BEGIN $keyType-----\n${buffer.toString()}-----END $keyType-----';
  }

  /// Generates and stores RSA key pair
  Future<void> _generateAndStoreRSAKeyPair(String uid) async {
    try {
      // Generate RSA key pair in a separate isolate
      final keyPairMap = await compute(_generateRSAKeyPairIsolate, 2048);

      final publicKeyPem = keyPairMap['publicKeyPem']!;
      final privateKeyPem = keyPairMap['privateKeyPem']!;

      // Ensure proper PEM formatting
      if (!privateKeyPem.contains('-----BEGIN RSA PRIVATE KEY-----') ||
          !privateKeyPem.contains('-----END RSA PRIVATE KEY-----')) {
        throw 'Private key PEM format is incorrect.';
      }

      if (!publicKeyPem.contains('-----BEGIN RSA PUBLIC KEY-----') ||
          !publicKeyPem.contains('-----END RSA PUBLIC KEY-----')) {
        throw 'Public key PEM format is incorrect.';
      }

      // Store PRIVATE key locally
      await storage.write(key: 'privateKey', value: privateKeyPem);

      // **Security Risk Removed:** Do not store private key in Firestore
      // await _firestore.collection('usersPrivateKeys').doc(uid).set({
      //   'privateKey': privateKeyPem,
      // });

      // Store PUBLIC key in Firestore "users/{uid}"
      await _firestore.collection('users').doc(uid).set({
        'publicKey': publicKeyPem,
      }, SetOptions(merge: true));
    } catch (e) {
      throw 'Error generating/storing RSA key pair: $e';
    }
  }

  /// Saves user information and generates RSA keys
  Future<void> _saveUserInfo() async {
    setState(() {
      isLoading = true;
      errorMessage = '';
    });

    try {
      // 1) Update user’s displayName in Firebase Auth
      await widget.user.updateDisplayName(displayName);

      // 2) Reload user to ensure displayName is updated
      await widget.user.reload();
      final updatedUser = FirebaseAuth.instance.currentUser;
      if (updatedUser == null) {
        throw 'User is null after reload.';
      }

      // 3) Save Firestore "users" document
      await _firestore.collection('users').doc(updatedUser.uid).set({
        'displayName': displayName,
        'phoneNumber': updatedUser.phoneNumber,
      }, SetOptions(merge: true));

      // 4) Generate and store RSA key pair
      await _generateAndStoreRSAKeyPair(updatedUser.uid);

      // 5) Navigation to HomeScreen
      setState(() => isLoading = false);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => HomeScreen()),
      );
    } catch (e) {
      setState(() {
        isLoading = false;
        errorMessage = 'Failed to save user info: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Additional Information'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : Form(
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
                  if (value == null || value.isEmpty) {
                    return 'Please enter a display name';
                  }
                  return null;
                },
                onChanged: (value) => displayName = value.trim(),
              ),
              const SizedBox(height: 20),
              if (errorMessage.isNotEmpty) ...[
                Text(
                  errorMessage,
                  style: const TextStyle(color: Colors.red),
                ),
                const SizedBox(height: 10),
              ],
              ElevatedButton(
                onPressed: () {
                  if (_formKey.currentState?.validate() ?? false) {
                    _saveUserInfo();
                  }
                },
                child: const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
