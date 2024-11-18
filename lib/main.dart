// lib/main.dart

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart'; // Ensure this is configured properly
import 'package:firebase_auth/firebase_auth.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'additional_info_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options:
    DefaultFirebaseOptions.currentPlatform, // Replace with your Firebase options
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
            return Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          if (snapshot.hasData) {
            // Check if user has displayName set
            if (snapshot.data!.displayName == null ||
                snapshot.data!.displayName!.isEmpty) {
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
