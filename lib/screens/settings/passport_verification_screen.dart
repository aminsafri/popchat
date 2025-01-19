// lib/screens/settings/passport_verification_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Helper function for Malaysian passports: parse line1 to get name
String parseMalaysianNameLine(String line1) {
  // e.g. "P<MYSMAHATHIR<BIN<IDRUS<<<<<<"
  if (!line1.startsWith('P<') || line1.length < 6) {
    return '';
  }
  // skip "P<MYS" -> substring from index 5
  String namePortion = line1.substring(5);
  // replace all < with space
  namePortion = namePortion.replaceAll('<', ' ');
  // collapse multiple spaces, trim
  namePortion = namePortion.replaceAll(RegExp(r'\s+'), ' ').trim();
  return namePortion;
}

class PassportVerificationScreen extends StatefulWidget {
  const PassportVerificationScreen({Key? key}) : super(key: key);

  @override
  State<PassportVerificationScreen> createState() => _PassportVerificationScreenState();
}

class _PassportVerificationScreenState extends State<PassportVerificationScreen> {
  final ImagePicker _picker = ImagePicker();
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _storage = const FlutterSecureStorage();

  bool _isLoading = false;
  bool _isVerified = false;
  String _formattedName = '';
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _checkVerificationStatus();
  }

  Future<void> _checkVerificationStatus() async {
    setState(() => _isLoading = true);
    try {
      final user = _auth.currentUser;
      if (user == null) {
        setState(() {
          _isVerified = false;
          _isLoading = false;
        });
        return;
      }

      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (!doc.exists) {
        setState(() {
          _isVerified = false;
          _isLoading = false;
        });
        return;
      }
      final data = doc.data();
      final bool verified = data?['passportVerified'] ?? false;
      final String name = data?['passportName'] ?? '';

      setState(() {
        _isVerified = verified;
        _formattedName = name;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isVerified = false;
        _isLoading = false;
        _errorMessage = 'Error checking verification: $e';
      });
    }
  }

  Future<void> _pickAndProcessImage({required bool fromCamera}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      );

      if (pickedFile == null) {
        // user canceled
        setState(() => _isLoading = false);
        return;
      }

      await _processImageForMRZ(pickedFile.path);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Image pick error: $e';
      });
    }
  }

  Future<void> _processImageForMRZ(String imagePath) async {
    try {
      final textRecognizer = TextRecognizer();
      final inputImage = InputImage.fromFilePath(imagePath);

      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);

      List<String> mrzCandidates = [];
      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          final textLine = line.text;
          if (textLine.contains('<') && textLine.length > 5) {
            mrzCandidates.add(textLine);
          }
        }
      }

      if (mrzCandidates.length < 2) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Could not find 2 lines of MRZ. Please retake.';
        });
        return;
      }

      final String line1 = mrzCandidates[0];
      // final String line2 = mrzCandidates[1]; // we might not need it for the name
      final extractedName = parseMalaysianNameLine(line1);

      await textRecognizer.close();

      setState(() {
        _formattedName = extractedName;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Text recognition error: $e';
      });
    }
  }

  Future<void> _saveVerification() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      final user = _auth.currentUser;
      if (user == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'No logged in user.';
        });
        return;
      }

      await _firestore.collection('users').doc(user.uid).update({
        'passportVerified': true,
        'passportName': _formattedName,
      });

      setState(() {
        _isLoading = false;
        _isVerified = true;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error saving verification: $e';
      });
    }
  }

  void _cancelVerification() {
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Passport Verification'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_errorMessage.isNotEmpty) ...[
              Text(_errorMessage, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 10),
            ],
            if (_isVerified) ...[
              const Text('Passport Verified', style: TextStyle(color: Colors.green, fontSize: 18)),
              const SizedBox(height: 5),
              Text('Real Name: $_formattedName', style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Back'),
              )
            ] else ...[
              Text('Verification Status: Not Verified', style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 10),
              Text('Extracted Name:\n$_formattedName',
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Camera'),
                    onPressed: () => _pickAndProcessImage(fromCamera: true),
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Gallery'),
                    onPressed: () => _pickAndProcessImage(fromCamera: false),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (_formattedName.isNotEmpty)
                ElevatedButton(
                  onPressed: _saveVerification,
                  child: const Text('Verify Passport'),
                ),
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: _cancelVerification,
                child: const Text('Cancel'),
              )
            ],
          ],
        ),
      ),
    );
  }
}
