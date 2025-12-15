import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'user/screens/user_auth_wrapper.dart';
import 'user/screens/user_login_screen.dart';
import 'user/screens/user_registration_screen.dart';
import 'user/screens/user_dashboard.dart';
import 'user/screens/user_settings_screen.dart';
import 'admin/screens/admin_dashboard.dart';
import 'admin/screens/login_screen.dart' as admin;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const IAMONEAIApp());
}

class IAMONEAIApp extends StatelessWidget {
  const IAMONEAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IAMONEAI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00d9ff),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0a0a0f),
        useMaterial3: true,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const UserAuthWrapper(),
        '/user': (context) => const UserAuthWrapper(),
        '/user/login': (context) => const UserLoginScreen(),
        '/user/register': (context) => const UserRegistrationScreen(),
        '/user/home': (context) => const UserDashboard(),
        '/user/settings': (context) => const UserSettingsScreen(),
        '/admin': (context) => const AdminAuthWrapper(),
        '/admin/login': (context) => const admin.LoginScreen(),
      },
    );
  }
}

class AdminAuthWrapper extends StatelessWidget {
  const AdminAuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!snapshot.hasData) {
          // Not logged in - show admin login
          return const admin.LoginScreen();
        }

        // Check if user is admin
        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance
              .collection('users')
              .doc(snapshot.data!.uid)
              .get(),
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (userSnapshot.hasData && userSnapshot.data!.exists) {
              final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
              final role = userData?['role'] as String?;

              // Check if user has admin role
              if (role == 'super_admin' || role == 'prompt_editor' ||
                  role == 'config_editor' || role == 'viewer') {
                return const AdminDashboard();
              }
            }

            // Not an admin - show login with error
            return const admin.LoginScreen();
          },
        );
      },
    );
  }
}


