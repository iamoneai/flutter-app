import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_login_screen.dart';
import 'user_dashboard.dart';
import '../services/user_auth_service.dart';

class UserAuthWrapper extends StatelessWidget {
  const UserAuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        // Loading state
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen();
        }

        // Not logged in
        if (!authSnapshot.hasData || authSnapshot.data == null) {
          return const UserLoginScreen();
        }

        final user = authSnapshot.data!;

        // Check if user has completed registration (has IIN) and ensure onboarding
        return FutureBuilder<DocumentSnapshot>(
          future: _ensureOnboardingAndGetProfile(user.uid),
          builder: (context, userSnapshot) {
            // Loading user data
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const _LoadingScreen();
            }

            // Error loading user data
            if (userSnapshot.hasError) {
              return _ErrorScreen(
                message: 'Error loading profile',
                onRetry: () {
                  // Trigger rebuild
                  (context as Element).markNeedsBuild();
                },
              );
            }

            // Check if user document exists and has IIN
            if (userSnapshot.hasData && userSnapshot.data!.exists) {
              final userData = userSnapshot.data!.data() as Map<String, dynamic>?;

              if (userData != null && userData['iin'] != null) {
                // User is fully registered - show dashboard
                return const UserDashboard();
              }
            }

            // User logged in but no profile/IIN - show login screen
            // This handles edge cases where auth exists but Firestore data doesn't
            return const UserLoginScreen();
          },
        );
      },
    );
  }

  /// Ensures the user is onboarded and returns their profile document
  Future<DocumentSnapshot> _ensureOnboardingAndGetProfile(String uid) async {
    // Ensure user is onboarded (creates categories/settings if missing)
    await UserAuthService().ensureUserOnboarded(uid);

    // Return the user profile document
    return FirebaseFirestore.instance.collection('users').doc(uid).get();
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0f0f1a),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated logo
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF7c3aed), Color(0xFF6366f1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF7c3aed).withValues(alpha: 0.4),
                    blurRadius: 20,
                    spreadRadius: 3,
                  ),
                ],
              ),
              child: const Icon(
                Icons.psychology,
                size: 44,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 32),
            const CircularProgressIndicator(
              color: Color(0xFF7c3aed),
              strokeWidth: 3,
            ),
            const SizedBox(height: 24),
            Text(
              'Loading...',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorScreen({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0f0f1a),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.error_outline,
                  size: 48,
                  color: Colors.red[400],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7c3aed),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Retry'),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                },
                child: Text(
                  'Sign Out',
                  style: TextStyle(color: Colors.grey[500]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
