// IAMONEAI - Admin Profile Service
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/admin_profile.dart';

class AdminProfileService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static final AdminProfileService _instance = AdminProfileService._internal();
  factory AdminProfileService() => _instance;
  AdminProfileService._internal();

  AdminProfile? _cachedProfile;
  AdminProfile? get currentProfile => _cachedProfile;

  /// Get admin profile by UID
  Future<AdminProfile?> getProfile(String uid) async {
    try {
      final doc = await _firestore.collection('admin_profiles').doc(uid).get();
      if (!doc.exists) return null;

      _cachedProfile = AdminProfile.fromFirestore(doc);
      return _cachedProfile;
    } catch (e) {
      debugPrint('Error getting admin profile: $e');
      return null;
    }
  }

  /// Create or update admin profile
  Future<AdminProfile> saveProfile({
    required String uid,
    required String email,
    required String firstName,
    required String lastName,
    String? iin,
  }) async {
    try {
      final now = DateTime.now();
      final existingDoc = await _firestore.collection('admin_profiles').doc(uid).get();

      final profile = AdminProfile(
        uid: uid,
        email: email,
        firstName: firstName,
        lastName: lastName,
        iin: iin,
        createdAt: existingDoc.exists
            ? (existingDoc.data()?['createdAt'] as Timestamp?)?.toDate() ?? now
            : now,
        updatedAt: now,
      );

      await _firestore.collection('admin_profiles').doc(uid).set(
        profile.toFirestore(),
        SetOptions(merge: true),
      );

      _cachedProfile = profile;
      debugPrint('Admin profile saved for $email');
      return profile;
    } catch (e) {
      debugPrint('Error saving admin profile: $e');
      rethrow;
    }
  }

  /// Update just the IIN
  Future<void> updateIIN(String uid, String iin) async {
    try {
      await _firestore.collection('admin_profiles').doc(uid).update({
        'iin': iin,
        'updatedAt': Timestamp.now(),
      });

      if (_cachedProfile?.uid == uid) {
        _cachedProfile = _cachedProfile!.copyWith(iin: iin);
      }
      debugPrint('IIN updated for admin $uid');
    } catch (e) {
      debugPrint('Error updating IIN: $e');
      rethrow;
    }
  }

  /// Stream profile changes
  Stream<AdminProfile?> profileStream(String uid) {
    return _firestore
        .collection('admin_profiles')
        .doc(uid)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return null;
      _cachedProfile = AdminProfile.fromFirestore(doc);
      return _cachedProfile;
    });
  }

  /// Clear cached profile (on logout)
  void clearCache() {
    _cachedProfile = null;
  }
}
