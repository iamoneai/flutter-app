// IAMONEAI - Fresh Start
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../core/utils/iin_generator.dart';

/// Simplified User Onboarding Service
/// Creates user profile and Personal IIN only
class UserOnboardingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Initialize a new user - creates profile and IIN
  Future<String> initializeNewUser({
    required String uid,
    required String displayName,
    required String email,
    String? firstName,
    String? lastName,
  }) async {
    try {
      // 1. Generate Personal IIN (20AA-YYMM-XXXX-XXXX)
      final personalIinId = IINGenerator.generatePersonalIIN();

      // 2. Create user profile
      await _firestore.collection('users').doc(uid).set({
        'displayName': displayName,
        'email': email.toLowerCase(),
        'personalIinId': personalIinId,
        'firstName': firstName,
        'lastName': lastName,
        'role': 'user',
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // 3. Create IIN document
      await _firestore.collection('iins').doc(personalIinId).set({
        'iinType': 'personal',
        'ownerType': 'user',
        'ownerId': uid,
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 4. Set active IIN in user session
      await _firestore.collection('user_sessions').doc(uid).set({
        'activeIinId': personalIinId,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      debugPrint('User initialized: $uid with IIN: $personalIinId');
      return personalIinId;
    } catch (e) {
      debugPrint('Error during user initialization: $e');
      rethrow;
    }
  }

  /// Check if user exists in Firestore
  Future<bool> isUserOnboarded(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (!doc.exists) return false;
      return doc.data()?['personalIinId'] != null;
    } catch (e) {
      debugPrint('Error checking onboarding status: $e');
      return false;
    }
  }

  /// Get user profile
  Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      return doc.data();
    } catch (e) {
      debugPrint('Error getting user profile: $e');
      return null;
    }
  }
}
