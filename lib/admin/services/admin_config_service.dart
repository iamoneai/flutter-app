// IAMONEAI - Fresh Start
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Admin Configuration Service
/// Reads and writes system config to Firestore
class AdminConfigService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String _configPath = 'admin/config';

  // Default config values
  static const Map<String, dynamic> defaultConfig = {
    'llm': {
      'claudeEnabled': true,
      'gptEnabled': true,
      'geminiEnabled': true,
      'defaultProvider': 'gemini',
      'temperature': 0.7,
      'maxTokens': 1024,
    },
    'system': {
      'chatEnabled': true,
      'loggingLevel': 'info',
    },
  };

  /// Get current config (with defaults)
  /// Handles both flat keys (llm.defaultProvider) and nested (llm: {defaultProvider})
  Future<Map<String, dynamic>> getConfig() async {
    try {
      final doc = await _firestore.doc(_configPath).get();

      if (!doc.exists) {
        return defaultConfig;
      }

      final data = doc.data() ?? {};

      // Handle both flat keys (llm.defaultProvider) and nested (llm: {defaultProvider})
      final nestedLlm = data['llm'] as Map<String, dynamic>? ?? {};
      final nestedSystem = data['system'] as Map<String, dynamic>? ?? {};

      return {
        'llm': {
          'claudeEnabled': data['llm.claudeEnabled'] ?? nestedLlm['claudeEnabled'] ?? true,
          'gptEnabled': data['llm.gptEnabled'] ?? nestedLlm['gptEnabled'] ?? true,
          'geminiEnabled': data['llm.geminiEnabled'] ?? nestedLlm['geminiEnabled'] ?? true,
          'defaultProvider': data['llm.defaultProvider'] ?? nestedLlm['defaultProvider'] ?? 'gemini',
          'temperature': data['llm.temperature'] ?? nestedLlm['temperature'] ?? 0.7,
          'maxTokens': data['llm.maxTokens'] ?? nestedLlm['maxTokens'] ?? 1024,
        },
        'system': {
          'chatEnabled': data['system.chatEnabled'] ?? nestedSystem['chatEnabled'] ?? true,
          'loggingLevel': data['system.loggingLevel'] ?? nestedSystem['loggingLevel'] ?? 'info',
        },
        'updatedAt': data['updatedAt'],
        'updatedBy': data['updatedBy'],
      };
    } catch (e) {
      debugPrint('Error getting config: $e');
      return defaultConfig;
    }
  }

  /// Update LLM config
  Future<void> updateLLMConfig({
    bool? claudeEnabled,
    bool? gptEnabled,
    bool? geminiEnabled,
    String? defaultProvider,
    double? temperature,
    int? maxTokens,
    required String updatedBy,
  }) async {
    try {
      final updates = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': updatedBy,
      };

      if (claudeEnabled != null) updates['llm.claudeEnabled'] = claudeEnabled;
      if (gptEnabled != null) updates['llm.gptEnabled'] = gptEnabled;
      if (geminiEnabled != null) updates['llm.geminiEnabled'] = geminiEnabled;
      if (defaultProvider != null) {
        updates['llm.defaultProvider'] = defaultProvider;
      }
      if (temperature != null) updates['llm.temperature'] = temperature;
      if (maxTokens != null) updates['llm.maxTokens'] = maxTokens;

      await _firestore.doc(_configPath).set(updates, SetOptions(merge: true));
      debugPrint('LLM config updated by $updatedBy');
    } catch (e) {
      debugPrint('Error updating LLM config: $e');
      rethrow;
    }
  }

  /// Update system config
  Future<void> updateSystemConfig({
    bool? chatEnabled,
    String? loggingLevel,
    required String updatedBy,
  }) async {
    try {
      final updates = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': updatedBy,
      };

      if (chatEnabled != null) updates['system.chatEnabled'] = chatEnabled;
      if (loggingLevel != null) updates['system.loggingLevel'] = loggingLevel;

      await _firestore.doc(_configPath).set(updates, SetOptions(merge: true));
      debugPrint('System config updated by $updatedBy');
    } catch (e) {
      debugPrint('Error updating system config: $e');
      rethrow;
    }
  }

  /// Check if user has admin access
  /// Uses adminRole field (separate from user role)
  Future<bool> isAdmin(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (!doc.exists) return false;

      final adminRole = doc.data()?['adminRole'] as String?;
      return adminRole == 'admin' || adminRole == 'super_admin';
    } catch (e) {
      debugPrint('Error checking admin status: $e');
      return false;
    }
  }

  /// Get admin role for a user
  Future<String?> getAdminRole(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (!doc.exists) return null;
      return doc.data()?['adminRole'] as String?;
    } catch (e) {
      debugPrint('Error getting admin role: $e');
      return null;
    }
  }

  /// Stream config changes
  /// Handles both flat keys and nested structure
  Stream<Map<String, dynamic>> configStream() {
    return _firestore.doc(_configPath).snapshots().map((doc) {
      if (!doc.exists) return defaultConfig;

      final data = doc.data() ?? {};
      final nestedLlm = data['llm'] as Map<String, dynamic>? ?? {};
      final nestedSystem = data['system'] as Map<String, dynamic>? ?? {};

      return {
        'llm': {
          'claudeEnabled': data['llm.claudeEnabled'] ?? nestedLlm['claudeEnabled'] ?? true,
          'gptEnabled': data['llm.gptEnabled'] ?? nestedLlm['gptEnabled'] ?? true,
          'geminiEnabled': data['llm.geminiEnabled'] ?? nestedLlm['geminiEnabled'] ?? true,
          'defaultProvider': data['llm.defaultProvider'] ?? nestedLlm['defaultProvider'] ?? 'gemini',
          'temperature': data['llm.temperature'] ?? nestedLlm['temperature'] ?? 0.7,
          'maxTokens': data['llm.maxTokens'] ?? nestedLlm['maxTokens'] ?? 1024,
        },
        'system': {
          'chatEnabled': data['system.chatEnabled'] ?? nestedSystem['chatEnabled'] ?? true,
          'loggingLevel': data['system.loggingLevel'] ?? nestedSystem['loggingLevel'] ?? 'info',
        },
        'updatedAt': data['updatedAt'],
        'updatedBy': data['updatedBy'],
      };
    });
  }
}
