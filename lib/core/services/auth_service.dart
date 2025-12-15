import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/admin_user.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Auth state stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Sign in with Google
  Future<User?> signInWithGoogle() async {
    try {
      // Trigger Google Sign In flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        // User cancelled the sign-in
        return null;
      }

      // Get auth details from Google
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      // Create Firebase credential
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase
      final userCredential = await _auth.signInWithCredential(credential);
      return userCredential.user;
    } catch (e) {
      debugPrint('Google sign in error: $e');
      rethrow;
    }
  }

  // Get admin user from users collection (unified collection)
  Future<AdminUser?> getAdminUser(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();

      if (!doc.exists) {
        return null;
      }

      final adminUser = AdminUser.fromFirestore(doc);

      // Check if user has admin role
      if (!adminUser.isAdmin) {
        return null;
      }

      return adminUser;
    } catch (e) {
      debugPrint('Error getting admin user: $e');
      return null;
    }
  }

  // Get user by email (for backward compatibility)
  Future<AdminUser?> getAdminUserByEmail(String email) async {
    try {
      final querySnapshot = await _firestore
          .collection('users')
          .where('email', isEqualTo: email.toLowerCase())
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        return null;
      }

      final adminUser = AdminUser.fromFirestore(querySnapshot.docs.first);

      // Check if user has admin role
      if (!adminUser.isAdmin) {
        return null;
      }

      return adminUser;
    } catch (e) {
      debugPrint('Error getting admin user by email: $e');
      return null;
    }
  }

  // Initialize super admin (first time setup)
  Future<void> initializeSuperAdmin(String email, String? displayName) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      // Check if user already exists
      final existingDoc = await _firestore.collection('users').doc(user.uid).get();

      if (existingDoc.exists) {
        // User exists, update role to super_admin
        await _firestore.collection('users').doc(user.uid).update({
          'role': AdminUser.roleSuperAdmin,
          'permissions': [AdminUser.permAll],
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        // Create new user with super_admin role
        await _firestore.collection('users').doc(user.uid).set({
          'email': email.toLowerCase(),
          'displayName': displayName ?? 'Super Admin',
          'firstName': displayName?.split(' ').first ?? 'Admin',
          'lastName': displayName?.split(' ').skip(1).join(' ') ?? '',
          'role': AdminUser.roleSuperAdmin,
          'status': 'ACTIVE',
          'permissions': [AdminUser.permAll],
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('Error initializing super admin: $e');
      rethrow;
    }
  }

  // Update user role
  Future<void> updateUserRole(String uid, String newRole, List<String>? permissions) async {
    try {
      final updateData = <String, dynamic>{
        'role': newRole,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (permissions != null) {
        updateData['permissions'] = permissions;
      }

      await _firestore.collection('users').doc(uid).update(updateData);
    } catch (e) {
      debugPrint('Error updating user role: $e');
      rethrow;
    }
  }

  // Sign out
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}
