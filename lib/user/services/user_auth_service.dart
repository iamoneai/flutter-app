// IAMONEAI - Fresh Start
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';
import 'user_onboarding_service.dart';

/// User Authentication Service
/// Handles email/password and Google sign-in
class UserAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final UserOnboardingService _onboardingService = UserOnboardingService();

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Sign in with email and password
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

  /// Sign in with Google
  Future<Map<String, dynamic>?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        return null;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;

      if (user == null) return null;

      // Check if user is already onboarded
      final isOnboarded = await _onboardingService.isUserOnboarded(user.uid);

      if (!isOnboarded) {
        // New Google user - initialize them
        final nameParts = (user.displayName ?? '').split(' ');
        final firstName = nameParts.isNotEmpty ? nameParts.first : '';
        final lastName =
            nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';

        final personalIinId = await _onboardingService.initializeNewUser(
          uid: user.uid,
          displayName: user.displayName ?? user.email?.split('@').first ?? '',
          email: user.email ?? '',
          firstName: firstName,
          lastName: lastName,
        );

        return {
          'user': user,
          'personalIinId': personalIinId,
          'isNewUser': true,
        };
      }

      // Existing user
      final profile = await _onboardingService.getUserProfile(user.uid);
      return {
        'user': user,
        'personalIinId': profile?['personalIinId'],
        'isNewUser': false,
      };
    } catch (e) {
      debugPrint('Google sign in error: $e');
      rethrow;
    }
  }

  /// Register new user with email and password
  Future<Map<String, dynamic>> registerUser({
    required String email,
    required String password,
    required String fullName,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final user = credential.user;
      if (user == null) {
        throw Exception('Failed to create user account');
      }

      await user.updateDisplayName(fullName);

      final nameParts = fullName.trim().split(' ');
      final firstName = nameParts.isNotEmpty ? nameParts.first : '';
      final lastName =
          nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';

      final personalIinId = await _onboardingService.initializeNewUser(
        uid: user.uid,
        displayName: fullName.trim(),
        email: email.trim().toLowerCase(),
        firstName: firstName,
        lastName: lastName,
      );

      return {
        'user': user,
        'personalIinId': personalIinId,
      };
    } on FirebaseAuthException catch (e) {
      throw _handleAuthError(e);
    }
  }

  /// Sign out
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  /// Check if user has completed registration
  Future<bool> hasCompletedRegistration(String uid) async {
    return await _onboardingService.isUserOnboarded(uid);
  }

  /// Get user profile
  Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    return await _onboardingService.getUserProfile(uid);
  }

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
