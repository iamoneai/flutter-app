import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../core/services/iin_service.dart';
import '../../core/utils/iin_generator.dart';

class UserOnboardingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final IINService _iinService = IINService();

  /// Initialize a new user with admin default categories and settings
  /// Creates user profile and Personal IIN
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

      // 2. Create user profile with personalIinId
      await _firestore.collection('users').doc(uid).set({
        'displayName': displayName,
        'email': email.toLowerCase(),
        'personalIinId': personalIinId,
        'firstName': firstName,
        'lastName': lastName,
        'role': 'user',
        'status': 'active',
        'onboarded': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // 3. Create IIN document in /iins collection
      await _firestore.collection('iins').doc(personalIinId).set({
        'iinType': 'personal',
        'ownerType': 'user',
        'ownerId': uid,
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 4. Create IIN access mapping (user owns their personal IIN)
      await _firestore.collection('iin_access').add({
        'iinId': personalIinId,
        'uid': uid,
        'role': 'owner',
        'active': true,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 5. Set this as the active IIN in user session
      await _firestore.collection('user_sessions').doc(uid).set({
        'activeIinId': personalIinId,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      // 6. FETCH and COPY admin categories to user
      await _copyAdminCategories(uid);

      // 7. FETCH and COPY admin global settings to user
      await _copyAdminSettings(uid);

      debugPrint('User onboarding completed for: $uid with IIN: $personalIinId');
      return personalIinId;
    } catch (e) {
      debugPrint('Error during user onboarding: $e');
      rethrow;
    }
  }

  /// Copy all admin categories to user's collection
  Future<void> _copyAdminCategories(String uid) async {
    try {
      final adminCategories = await _firestore
          .collection('admin')
          .doc('config')
          .collection('categories')
          .get();

      if (adminCategories.docs.isEmpty) {
        debugPrint('No admin categories found, creating defaults');
        // Create default categories if none exist
        await _createDefaultUserCategories(uid);
        return;
      }

      for (var doc in adminCategories.docs) {
        final data = doc.data();
        await _firestore.collection('users').doc(uid).collection('categories').add({
          'name': data['name'] ?? 'Unnamed Category',
          'description': data['description'] ?? '',
          'keywords': List<String>.from(data['keywords'] ?? []),
          'primaryLlm': data['primaryLlm'] ?? 'gemini-flash',
          'fallbackLlm': data['fallbackLlm'] ?? 'gpt-4o-mini',
          'priority': data['priority'] ?? 'MEDIUM',
          'type': 'inherited', // Mark as inherited from admin
          'sourceAdminId': doc.id, // Link to original admin category
          'isActive': true,
          'contextFilter': 'all',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      debugPrint('Copied ${adminCategories.docs.length} admin categories to user');
    } catch (e) {
      debugPrint('Error copying admin categories: $e');
      // Create defaults if copy fails
      await _createDefaultUserCategories(uid);
    }
  }

  /// Create default categories if no admin categories exist
  Future<void> _createDefaultUserCategories(String uid) async {
    final defaultCategories = [
      {
        'name': 'General',
        'description': 'General conversations and questions',
        'keywords': ['help', 'question', 'explain', 'what', 'how', 'why'],
        'primaryLlm': 'gemini-flash',
        'fallbackLlm': 'gpt-4o-mini',
        'priority': 'LOW',
      },
      {
        'name': 'Code & Programming',
        'description': 'Programming, debugging, and code-related questions',
        'keywords': ['code', 'python', 'javascript', 'debug', 'programming', 'function', 'error'],
        'primaryLlm': 'claude-haiku',
        'fallbackLlm': 'gpt-4o-mini',
        'priority': 'HIGH',
      },
      {
        'name': 'Creative Writing',
        'description': 'Stories, poetry, and creative content',
        'keywords': ['write', 'story', 'poem', 'creative', 'fiction', 'narrative'],
        'primaryLlm': 'gpt-4o-mini',
        'fallbackLlm': 'claude-haiku',
        'priority': 'MEDIUM',
      },
    ];

    for (var category in defaultCategories) {
      await _firestore.collection('users').doc(uid).collection('categories').add({
        ...category,
        'type': 'inherited',
        'sourceAdminId': null,
        'isActive': true,
        'contextFilter': 'all',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Copy admin global settings to user
  Future<void> _copyAdminSettings(String uid) async {
    try {
      final adminSettings = await _firestore
          .doc('admin/config/settings/global')
          .get();

      Map<String, dynamic> settingsData = {};
      if (adminSettings.exists) {
        settingsData = adminSettings.data() ?? {};
      }

      // Get response settings if available
      final responseSettings = settingsData['response'] as Map<String, dynamic>? ?? {};
      final localeSettings = settingsData['locale'] as Map<String, dynamic>? ?? {};
      final guardrails = settingsData['guardrails'] as Map<String, dynamic>? ?? {};

      await _firestore.doc('users/$uid/settings/preferences').set({
        // Chat preferences
        'defaultContext': 'personal',
        'responseStyle': responseSettings['default_response_length'] ?? 'balanced',
        'personalityTone': responseSettings['default_style'] ?? 'friendly',
        'memoryEnabled': true,
        'autoMemorySave': true,
        'maxTokens': guardrails['max_response_length'] ?? 1024,
        'temperature': 0.7,
        'emojiUsage': responseSettings['default_emoji_usage'] ?? 'moderate',

        // LLM preferences
        'defaultLlm': 'gemini-flash',
        'fallbackLlm': 'gpt-4o-mini',

        // API Keys (user's own)
        'useOwnKeys': false,
        'openaiKey': null,
        'anthropicKey': null,
        'googleKey': null,

        // Privacy settings
        'memoryRetentionDays': 90,
        'autoDeleteHistory': false,

        // Locale settings
        'dateFormat': localeSettings['default_date_format'] ?? 'MM/DD/YYYY',
        'timeFormat': localeSettings['default_time_format'] ?? '12h',
        'timezone': localeSettings['default_timezone'] ?? 'UTC',

        // Metadata
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      debugPrint('Copied admin settings to user');
    } catch (e) {
      debugPrint('Error copying admin settings: $e');
      // Create default settings if copy fails
      await _createDefaultUserSettings(uid);
    }
  }

  /// Create default user settings
  Future<void> _createDefaultUserSettings(String uid) async {
    await _firestore.doc('users/$uid/settings/preferences').set({
      'defaultContext': 'personal',
      'responseStyle': 'balanced',
      'personalityTone': 'friendly',
      'memoryEnabled': true,
      'autoMemorySave': true,
      'maxTokens': 1024,
      'temperature': 0.7,
      'emojiUsage': 'moderate',
      'defaultLlm': 'gemini-flash',
      'fallbackLlm': 'gpt-4o-mini',
      'useOwnKeys': false,
      'openaiKey': null,
      'anthropicKey': null,
      'googleKey': null,
      'memoryRetentionDays': 90,
      'autoDeleteHistory': false,
      'dateFormat': 'MM/DD/YYYY',
      'timeFormat': '12h',
      'timezone': 'UTC',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Check if user has been onboarded
  Future<bool> isUserOnboarded(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (!doc.exists) return false;
      return doc.data()?['onboarded'] == true;
    } catch (e) {
      debugPrint('Error checking onboarding status: $e');
      return false;
    }
  }

  /// Run onboarding for existing user who hasn't been onboarded
  Future<void> onboardExistingUser(String uid) async {
    try {
      // Check if user already has categories
      final existingCategories = await _firestore
          .collection('users')
          .doc(uid)
          .collection('categories')
          .limit(1)
          .get();

      if (existingCategories.docs.isEmpty) {
        await _copyAdminCategories(uid);
      }

      // Check if user already has settings
      final existingSettings = await _firestore
          .doc('users/$uid/settings/preferences')
          .get();

      if (!existingSettings.exists) {
        await _copyAdminSettings(uid);
      }

      // Mark as onboarded
      await _firestore.collection('users').doc(uid).update({
        'onboarded': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error onboarding existing user: $e');
      rethrow;
    }
  }
}
