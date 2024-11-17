// lib/main.dart

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart'; // Ensure this is configured properly
import 'package:firebase_auth/firebase_auth.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'verification_screen.dart';
import 'chat_screen.dart'; // Import the chat screen
import 'additional_info_screen.dart'; // If you're using it

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform, // Replace with your Firebase options
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
      // Remove the home property to use initialRoute instead
      initialRoute: '/',
      routes: {
        '/': (context) => StreamBuilder<User?>(
          stream: _auth.authStateChanges(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting)
              return Center(child: CircularProgressIndicator());
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
        '/home': (context) => HomeScreen(),
        // Add other routes if needed
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/chat') {
          final args = settings.arguments as Map<String, dynamic>;
          return MaterialPageRoute(
            builder: (context) => ChatScreen(
              sessionCode: args['sessionCode'],
              alternativeName: args['alternativeName'],
            ),
          );
        }
        // Handle other routes if necessary
        return null; // Let the framework handle unknown routes
      },
    );
  }
}
