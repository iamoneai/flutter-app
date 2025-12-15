import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class UserSettingsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ============================================
  // USER SETTINGS
  // ============================================

  /// Get user settings
  Future<Map<String, dynamic>?> getUserSettings(String uid) async {
    try {
      final doc = await _firestore.doc('users/$uid/settings/preferences').get();
      return doc.data();
    } catch (e) {
      debugPrint('Error getting user settings: $e');
      return null;
    }
  }

  /// Stream user settings for real-time updates
  Stream<Map<String, dynamic>?> getUserSettingsStream(String uid) {
    return _firestore
        .doc('users/$uid/settings/preferences')
        .snapshots()
        .map((snap) => snap.data());
  }

  /// Save user settings
  Future<void> saveUserSettings(String uid, Map<String, dynamic> settings) async {
    try {
      await _firestore.doc('users/$uid/settings/preferences').set({
        ...settings,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error saving user settings: $e');
      rethrow;
    }
  }

  /// Update specific setting fields
  Future<void> updateUserSettings(String uid, Map<String, dynamic> updates) async {
    try {
      await _firestore.doc('users/$uid/settings/preferences').update({
        ...updates,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error updating user settings: $e');
      rethrow;
    }
  }

  // ============================================
  // USER CATEGORIES
  // ============================================

  /// Get all user categories as a stream
  Stream<List<Map<String, dynamic>>> getUserCategoriesStream(String uid) {
    return _firestore
        .collection('users/$uid/categories')
        .orderBy('priority')
        .snapshots()
        .map((snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  /// Get all user categories
  Future<List<Map<String, dynamic>>> getUserCategories(String uid) async {
    try {
      final snapshot = await _firestore
          .collection('users/$uid/categories')
          .orderBy('priority')
          .get();
      return snapshot.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    } catch (e) {
      debugPrint('Error getting user categories: $e');
      return [];
    }
  }

  /// Create a new custom category
  Future<String> createCategory(String uid, Map<String, dynamic> category) async {
    try {
      final docRef = await _firestore.collection('users/$uid/categories').add({
        ...category,
        'type': 'custom',
        'sourceAdminId': null,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return docRef.id;
    } catch (e) {
      debugPrint('Error creating category: $e');
      rethrow;
    }
  }

  /// Update an existing category
  Future<void> updateCategory(
    String uid,
    String categoryId,
    Map<String, dynamic> data, {
    bool wasInherited = false,
  }) async {
    try {
      final updateData = {
        ...data,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // If was inherited, mark as modified
      if (wasInherited) {
        updateData['type'] = 'modified';
      }

      await _firestore.doc('users/$uid/categories/$categoryId').update(updateData);
    } catch (e) {
      debugPrint('Error updating category: $e');
      rethrow;
    }
  }

  /// Delete a category (only custom categories can be deleted)
  Future<void> deleteCategory(String uid, String categoryId) async {
    try {
      await _firestore.doc('users/$uid/categories/$categoryId').delete();
    } catch (e) {
      debugPrint('Error deleting category: $e');
      rethrow;
    }
  }

  /// Toggle category active state
  Future<void> toggleCategory(String uid, String categoryId, bool isActive) async {
    try {
      await _firestore.doc('users/$uid/categories/$categoryId').update({
        'isActive': isActive,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error toggling category: $e');
      rethrow;
    }
  }

  /// Reset a modified category back to admin defaults
  Future<void> resetCategoryToDefault(
    String uid,
    String categoryId,
    String sourceAdminId,
  ) async {
    try {
      // Fetch original admin category
      final adminDoc = await _firestore
          .doc('admin/config/categories/$sourceAdminId')
          .get();

      if (!adminDoc.exists) {
        throw Exception('Original admin category not found');
      }

      final adminData = adminDoc.data()!;
      await _firestore.doc('users/$uid/categories/$categoryId').update({
        'name': adminData['name'],
        'description': adminData['description'],
        'keywords': List<String>.from(adminData['keywords'] ?? []),
        'primaryLlm': adminData['primaryLlm'],
        'fallbackLlm': adminData['fallbackLlm'],
        'priority': adminData['priority'],
        'type': 'inherited',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error resetting category: $e');
      rethrow;
    }
  }

  /// Get original admin category data for comparison
  Future<Map<String, dynamic>?> getAdminCategory(String adminCategoryId) async {
    try {
      final doc = await _firestore
          .doc('admin/config/categories/$adminCategoryId')
          .get();
      return doc.data();
    } catch (e) {
      debugPrint('Error getting admin category: $e');
      return null;
    }
  }

  // ============================================
  // SYNC WITH ADMIN
  // ============================================

  /// Check for new admin categories that user doesn't have
  Future<Map<String, dynamic>> checkAdminUpdates(String uid) async {
    try {
      final userCats = await _firestore.collection('users/$uid/categories').get();
      final adminCats = await _firestore
          .collection('admin')
          .doc('config')
          .collection('categories')
          .get();

      final userSourceIds = userCats.docs
          .map((d) => d.data()['sourceAdminId'])
          .where((id) => id != null)
          .toSet();

      final newAdminCats = adminCats.docs
          .where((d) => !userSourceIds.contains(d.id))
          .toList();

      return {
        'newCategories': newAdminCats.map((d) => {'id': d.id, ...d.data()}).toList(),
        'totalAdmin': adminCats.docs.length,
        'totalUser': userCats.docs.length,
      };
    } catch (e) {
      debugPrint('Error checking admin updates: $e');
      return {
        'newCategories': [],
        'totalAdmin': 0,
        'totalUser': 0,
      };
    }
  }

  /// Sync selected admin categories to user
  Future<void> syncNewAdminCategories(String uid, List<String> adminCategoryIds) async {
    try {
      for (var adminId in adminCategoryIds) {
        final adminDoc = await _firestore
            .doc('admin/config/categories/$adminId')
            .get();

        if (!adminDoc.exists) continue;

        final data = adminDoc.data()!;
        await _firestore.collection('users/$uid/categories').add({
          'name': data['name'],
          'description': data['description'],
          'keywords': List<String>.from(data['keywords'] ?? []),
          'primaryLlm': data['primaryLlm'],
          'fallbackLlm': data['fallbackLlm'],
          'priority': data['priority'],
          'type': 'inherited',
          'sourceAdminId': adminId,
          'isActive': true,
          'contextFilter': 'all',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('Error syncing admin categories: $e');
      rethrow;
    }
  }

  // ============================================
  // EFFECTIVE CATEGORIES (for Smart Router)
  // ============================================

  /// Get active categories sorted by priority for routing
  Future<List<Map<String, dynamic>>> getEffectiveCategories(String uid) async {
    try {
      final snapshot = await _firestore
          .collection('users/$uid/categories')
          .where('isActive', isEqualTo: true)
          .get();

      final categories = snapshot.docs.map((d) => {'id': d.id, ...d.data()}).toList();

      // Sort by: custom first, then modified, then inherited
      // Within each type, sort by priority (HIGH > MEDIUM > LOW)
      categories.sort((a, b) {
        final typeOrder = {'custom': 0, 'modified': 1, 'inherited': 2};
        final priorityOrder = {'HIGH': 0, 'MEDIUM': 1, 'LOW': 2};

        final typeCompare = (typeOrder[a['type']] ?? 2).compareTo(typeOrder[b['type']] ?? 2);
        if (typeCompare != 0) return typeCompare;

        return (priorityOrder[a['priority']] ?? 2).compareTo(priorityOrder[b['priority']] ?? 2);
      });

      return categories;
    } catch (e) {
      debugPrint('Error getting effective categories: $e');
      return [];
    }
  }

  // ============================================
  // PRIVACY & DATA MANAGEMENT
  // ============================================

  /// Export all user data
  Future<Map<String, dynamic>> exportUserData(String uid) async {
    try {
      // Get user profile
      final userDoc = await _firestore.collection('users').doc(uid).get();

      // Get settings
      final settingsDoc = await _firestore.doc('users/$uid/settings/preferences').get();

      // Get categories
      final categoriesSnap = await _firestore.collection('users/$uid/categories').get();
      final categories = categoriesSnap.docs.map((d) => d.data()).toList();

      // Get memories if they exist
      List<Map<String, dynamic>> memories = [];
      try {
        final memoriesSnap = await _firestore.collection('users/$uid/memories').get();
        memories = memoriesSnap.docs.map((d) => d.data()).toList();
      } catch (e) {
        // Memories collection might not exist
      }

      // Get chat history if it exists
      List<Map<String, dynamic>> chatHistory = [];
      try {
        final chatSnap = await _firestore
            .collection('users/$uid/chats')
            .orderBy('createdAt', descending: true)
            .limit(100)
            .get();
        chatHistory = chatSnap.docs.map((d) => d.data()).toList();
      } catch (e) {
        // Chat collection might not exist
      }

      return {
        'exportedAt': DateTime.now().toIso8601String(),
        'profile': userDoc.data(),
        'settings': settingsDoc.data(),
        'categories': categories,
        'memories': memories,
        'chatHistory': chatHistory,
      };
    } catch (e) {
      debugPrint('Error exporting user data: $e');
      rethrow;
    }
  }

  /// Delete all user data (DANGEROUS!)
  Future<void> deleteAllUserData(String uid) async {
    try {
      // Delete categories
      final categoriesSnap = await _firestore.collection('users/$uid/categories').get();
      for (var doc in categoriesSnap.docs) {
        await doc.reference.delete();
      }

      // Delete settings
      try {
        await _firestore.doc('users/$uid/settings/preferences').delete();
      } catch (e) {
        // Settings might not exist
      }

      // Delete memories
      try {
        final memoriesSnap = await _firestore.collection('users/$uid/memories').get();
        for (var doc in memoriesSnap.docs) {
          await doc.reference.delete();
        }
      } catch (e) {
        // Memories might not exist
      }

      // Delete chats
      try {
        final chatsSnap = await _firestore.collection('users/$uid/chats').get();
        for (var doc in chatsSnap.docs) {
          await doc.reference.delete();
        }
      } catch (e) {
        // Chats might not exist
      }

      // Finally delete user profile
      await _firestore.collection('users').doc(uid).delete();
    } catch (e) {
      debugPrint('Error deleting user data: $e');
      rethrow;
    }
  }

  /// Get available LLM options
  List<Map<String, String>> getAvailableLlms() {
    return [
      {'id': 'claude-haiku', 'name': 'Claude Haiku', 'provider': 'claude'},
      {'id': 'claude-sonnet', 'name': 'Claude Sonnet', 'provider': 'claude'},
      {'id': 'gpt-4o-mini', 'name': 'GPT-4o Mini', 'provider': 'openai'},
      {'id': 'gpt-4o', 'name': 'GPT-4o', 'provider': 'openai'},
      {'id': 'gemini-flash', 'name': 'Gemini Flash', 'provider': 'gemini'},
      {'id': 'gemini-pro', 'name': 'Gemini Pro', 'provider': 'gemini'},
    ];
  }
}
