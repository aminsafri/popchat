// lib/main.dart

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/additional_info_screen.dart';
import 'screens/splash_screen.dart'; // Import SplashScreen

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Activate Firebase App Check (optional)
  await FirebaseAppCheck.instance.activate();

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
      // Remove initialRoute since we're using home
      // initialRoute: '/', // Remove this line
      routes: {
        '/home': (context) => HomeScreen(),
        '/login': (context) => LoginScreen(),
        '/additional_info': (context) => AdditionalInfoScreen(user: FirebaseAuth.instance.currentUser!),
        // Remove '/' route to avoid conflict
        // '/': (context) => SplashScreen(), // Remove this line
      },
      home: StreamBuilder<User?>(
        stream: _auth.userChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return SplashScreen(); // Show SplashScreen while waiting
          }

          if (snapshot.hasData) {
            // Check if user has a displayName set
            final user = snapshot.data!;
            if (user.displayName == null || user.displayName!.isEmpty) {
              return AdditionalInfoScreen(user: user);
            } else {
              return HomeScreen();
            }
          }

          // If no user is logged in, show LoginScreen
          return LoginScreen();
        },
      ),
    );
  }
}
