// IAMONEAI - Fresh Start
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/iin.dart';
import '../utils/iin_generator.dart';

/// IIN Service - Simplified for personal IINs only
class IINService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Create a personal IIN for a user
  Future<String> createPersonalIIN(String uid) async {
    try {
      final iinId = IINGenerator.generatePersonalIIN();

      await _firestore.collection('iins').doc(iinId).set({
        'iinType': 'personal',
        'ownerType': 'user',
        'ownerId': uid,
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
      });

      debugPrint('Created personal IIN: $iinId for user: $uid');
      return iinId;
    } catch (e) {
      debugPrint('Error creating personal IIN: $e');
      rethrow;
    }
  }

  /// Get IIN by ID
  Future<IIN?> getIIN(String iinId) async {
    try {
      final doc = await _firestore.collection('iins').doc(iinId).get();
      if (!doc.exists) return null;
      return IIN.fromFirestore(doc);
    } catch (e) {
      debugPrint('Error getting IIN: $e');
      return null;
    }
  }

  /// Get user's active IIN from session
  Future<String?> getActiveIIN(String uid) async {
    try {
      final doc = await _firestore.collection('user_sessions').doc(uid).get();
      if (!doc.exists) return null;
      return doc.data()?['activeIinId'] as String?;
    } catch (e) {
      debugPrint('Error getting active IIN: $e');
      return null;
    }
  }

  /// Set user's active IIN
  Future<void> setActiveIIN(String uid, String iinId) async {
    try {
      await _firestore.collection('user_sessions').doc(uid).set({
        'activeIinId': iinId,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error setting active IIN: $e');
      rethrow;
    }
  }
}
