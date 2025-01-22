// lib/screens/settings/settings_screen.dart

import 'package:flutter/material.dart';
import 'passport_verification_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Modern AppBar with brand color
      appBar: AppBar(
        title: const Text(
          'PopChat - Settings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF0088cc),
        elevation: 0,
      ),
      body: Container(
        color: Colors.grey[100],
        child: ListView(
          children: [
            // Example: A Card to group settings
            Card(
              margin: const EdgeInsets.all(16),
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.book_sharp, color: Color(0xFF0088cc)),
                    title: const Text('Passport Verification'),
                    subtitle: const Text('Verify your identity via passport'),
                    trailing: const Icon(Icons.arrow_forward_ios, color: Colors.grey),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const PassportVerificationScreen()),
                      );
                    },
                  ),
                  // Add a Divider if you have more settings below
                  // const Divider(height: 1),
                  // More settings can go here...
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
