// IAMONEAI - Fresh Start
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/user_auth_service.dart';
import 'login_screen.dart';
import 'home_screen.dart';

/// Auth Wrapper - Routes user based on auth state
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = UserAuthService();

    return StreamBuilder<User?>(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFFFAFAFA),
            body: Center(
              child: CircularProgressIndicator(
                color: Color(0xFF1A1A1A),
              ),
            ),
          );
        }

        if (snapshot.hasData && snapshot.data != null) {
          return FutureBuilder<bool>(
            future: authService.hasCompletedRegistration(snapshot.data!.uid),
            builder: (context, registrationSnapshot) {
              if (registrationSnapshot.connectionState ==
                  ConnectionState.waiting) {
                return const Scaffold(
                  backgroundColor: Color(0xFFFAFAFA),
                  body: Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                );
              }

              if (registrationSnapshot.data == true) {
                return const HomeScreen();
              }

              // User exists in Auth but not fully registered
              return const LoginScreen();
            },
          );
        }

        return const LoginScreen();
      },
    );
  }
}
