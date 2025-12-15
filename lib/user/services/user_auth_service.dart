import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'user_onboarding_service.dart';

class UserAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final UserOnboardingService _onboardingService = UserOnboardingService();

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Auth state stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Sign in with email and password
  Future<UserCredential> signInWithEmail(String email, String password) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return credential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthError(e);
    }
  }

  // Register new user with email and password
  Future<Map<String, dynamic>> registerUser({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  }) async {
    try {
      // Create Firebase Auth user
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final user = credential.user;
      if (user == null) {
        throw Exception('Failed to create user account');
      }

      // Update display name
      await user.updateDisplayName('$firstName $lastName');

      // Generate IIN via Cloud Function
      String? iin;
      try {
        final callable = _functions.httpsCallable('registerUser');
        final result = await callable.call({
          'email': email.trim().toLowerCase(),
          'firstName': firstName.trim(),
          'lastName': lastName.trim(),
        });
        iin = result.data['iin'] as String?;
      } catch (e) {
        debugPrint('Cloud function error: $e');
        // Generate local IIN if function fails
        iin = _generateLocalIIN();
      }

      // Initialize user with onboarding service (creates profile + copies admin categories/settings)
      await _onboardingService.initializeNewUser(
        uid: user.uid,
        displayName: '$firstName $lastName'.trim(),
        email: email.trim().toLowerCase(),
        iin: iin ?? '',
        firstName: firstName.trim(),
        lastName: lastName.trim(),
      );

      return {
        'user': user,
        'iin': iin,
      };
    } on FirebaseAuthException catch (e) {
      throw _handleAuthError(e);
    }
  }

  // Generate local IIN if cloud function fails
  String _generateLocalIIN() {
    final now = DateTime.now();
    final year = (now.year % 100).toString().padLeft(2, '0');
    final random1 = (now.millisecondsSinceEpoch % 10000).toString().padLeft(4, '0');
    final random2 = (now.microsecondsSinceEpoch % 10000).toString().padLeft(4, '0');
    final check = ((int.parse(random1) + int.parse(random2)) % 10000).toString().padLeft(4, '0');
    return '$year$random1$random2$check';
  }

  // Sign out
  Future<void> signOut() async {
    await _auth.signOut();
  }

  // Get user profile from Firestore
  Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      return doc.data();
    } catch (e) {
      debugPrint('Error getting user profile: $e');
      return null;
    }
  }

  // Check if user has completed registration (has IIN)
  Future<bool> hasCompletedRegistration(String uid) async {
    final profile = await getUserProfile(uid);
    return profile != null && profile['iin'] != null;
  }

  // Check if user is onboarded, if not, run onboarding
  Future<void> ensureUserOnboarded(String uid) async {
    final isOnboarded = await _onboardingService.isUserOnboarded(uid);
    if (!isOnboarded) {
      debugPrint('User not onboarded, running onboarding for: $uid');
      await _onboardingService.onboardExistingUser(uid);
    }
  }

  // Send password reset email
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw _handleAuthError(e);
    }
  }

  // Handle Firebase Auth errors
  String _handleAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'operation-not-allowed':
        return 'Email/password sign in is not enabled.';
      case 'weak-password':
        return 'Password is too weak. Use at least 8 characters.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'invalid-credential':
        return 'Invalid email or password.';
      default:
        return e.message ?? 'An error occurred. Please try again.';
    }
  }
}
