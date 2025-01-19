// lib/screens/settings/settings_screen.dart

import 'package:flutter/material.dart';
import 'passport_verification_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Minimal example
    return Scaffold(
      appBar: AppBar(title: Text("Settings")),
      body: ListView(
        children: [
          ListTile(
            title: Text("Passport Verification"),
            subtitle: Text("Verify your identity via passport"),
            trailing: Icon(Icons.arrow_forward_ios),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => PassportVerificationScreen()),
              );
            },
          ),
          // more settings...
        ],
      ),
    );
  }
}
