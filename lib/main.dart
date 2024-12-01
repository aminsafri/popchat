// lib/main.dart

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart'; // Ensure this is configured properly
import 'package:firebase_auth/firebase_auth.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'additional_info_screen.dart';
import 'package:firebase_app_check/firebase_app_check.dart'; // Import Firebase App Check

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Activate Firebase App Check
  await FirebaseAppCheck.instance.activate(
    androidProvider: AndroidProvider.debug,
    // For iOS, use .debug or .deviceCheck
    // webProvider: ReCaptchaV3Provider('YOUR_RECAPTCHA_SITE_KEY'), // For web
  );

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  final _auth = FirebaseAuth.instance;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PopChat',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: StreamBuilder<User?>(
        stream: _auth.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting)
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          if (snapshot.hasData) {
            // Check if user has displayName set
            if (snapshot.data!.displayName == null || snapshot.data!.displayName!.isEmpty) {
              return AdditionalInfoScreen(user: snapshot.data!);
            } else {
              return HomeScreen();
            }
          }
          return LoginScreen();
        },
      ),
    );
  }
}
