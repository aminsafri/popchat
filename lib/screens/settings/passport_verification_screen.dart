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
  // collapse multiple spaces, then trim
  namePortion = namePortion.replaceAll(RegExp(r'\s+'), ' ').trim();
  return namePortion;
}

class PassportVerificationScreen extends StatefulWidget {
  const PassportVerificationScreen({Key? key}) : super(key: key);

  @override
  State<PassportVerificationScreen> createState() =>
      _PassportVerificationScreenState();
}

class _PassportVerificationScreenState
    extends State<PassportVerificationScreen> {
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

  /// Check user's passport verification status in Firestore
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

  /// Prompt user to pick an image from camera or gallery, then process
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

  /// Process the image using ML Kit to extract MRZ lines
  Future<void> _processImageForMRZ(String imagePath) async {
    try {
      final textRecognizer = TextRecognizer();
      final inputImage = InputImage.fromFilePath(imagePath);

      final recognizedText = await textRecognizer.processImage(inputImage);

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
      // final String line2 = mrzCandidates[1]; // might not be needed for the name
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

  /// Save the verification result to Firestore
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

  /// Cancel or go back
  void _cancelVerification() {
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Modern AppBar with brand color
      appBar: AppBar(
        title: const Text(
          'PopChat - Passport Verification',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF0088cc),
        elevation: 0,
      ),
      // Light background
      body: Container(
        color: Colors.grey[100],
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Card(
              elevation: 6,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    if (_errorMessage.isNotEmpty) ...[
                      Text(
                        _errorMessage,
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (_isVerified) ...[
                      const Text(
                        'Passport Verified',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Real Name: $_formattedName',
                        style: const TextStyle(fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0088cc),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding:
                          const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text(
                          'Back',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ] else ...[
                      const Text(
                        'Verification Status: Not Verified',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Extracted Name:\n$_formattedName',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment:
                        MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton.icon(
                            icon: const Icon(Icons.camera_alt,
                                color: Colors.white),
                            label: const Text('Camera'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0088cc),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: () =>
                                _pickAndProcessImage(fromCamera: true),
                          ),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.photo_library,
                                color: Colors.white),
                            label: const Text('Gallery'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0088cc),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: () =>
                                _pickAndProcessImage(fromCamera: false),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      if (_formattedName.isNotEmpty)
                        ElevatedButton(
                          onPressed: _saveVerification,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0088cc),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(
                                vertical: 14, horizontal: 24),
                          ),
                          child: const Text(
                            'Verify Passport',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),
                      OutlinedButton(
                        onPressed: _cancelVerification,
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          side: const BorderSide(
                            color: Colors.grey,
                            width: 1,
                          ),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
