// IAMONEAI - Admin Auth Wrapper
// Handles auth state persistence for admin panel
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/admin_config_service.dart';
import 'admin_login_screen.dart';
import 'admin_dashboard.dart';

class AdminAuthWrapper extends StatelessWidget {
  const AdminAuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Show loading while checking auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFFFAFAFA),
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF1A1A1A)),
            ),
          );
        }

        // Not logged in - show login screen
        if (!snapshot.hasData || snapshot.data == null) {
          return const AdminLoginScreen();
        }

        // Logged in - check if admin
        return FutureBuilder<bool>(
          future: AdminConfigService().isAdmin(snapshot.data!.uid),
          builder: (context, adminSnapshot) {
            // Show loading while checking admin status
            if (adminSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                backgroundColor: Color(0xFFFAFAFA),
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: Color(0xFF1A1A1A)),
                      SizedBox(height: 16),
                      Text(
                        'Verifying admin access...',
                        style: TextStyle(color: Color(0xFF666666)),
                      ),
                    ],
                  ),
                ),
              );
            }

            // Is admin - show dashboard
            if (adminSnapshot.hasData && adminSnapshot.data == true) {
              return const AdminDashboard();
            }

            // Not admin - show access denied and logout
            return Scaffold(
              backgroundColor: const Color(0xFFFAFAFA),
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.block,
                      size: 64,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Access Denied',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'You do not have admin privileges.',
                      style: TextStyle(color: Color(0xFF666666)),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () async {
                        await FirebaseAuth.instance.signOut();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A1A1A),
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Sign Out'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
