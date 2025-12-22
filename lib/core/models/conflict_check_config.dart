import 'package:cloud_firestore/cloud_firestore.dart';

// ═══════════════════════════════════════════════════════════
// MAIN CONFIG CLASS
// ═══════════════════════════════════════════════════════════

class ConflictCheckConfig {
  final bool enabled;
  final double stageNumber;
  final String stageName;
  final SimilaritySettings similarity;
  final ConflictLLMSettings llm;
  final List<String> categories;
  final ConflictBehaviorSettings behavior;
  final String promptTemplate;
  final DateTime? updatedAt;
  final String? updatedBy;

  ConflictCheckConfig({
    required this.enabled,
    required this.stageNumber,
    required this.stageName,
    required this.similarity,
    required this.llm,
    required this.categories,
    required this.behavior,
    required this.promptTemplate,
    this.updatedAt,
    this.updatedBy,
  });

  factory ConflictCheckConfig.defaults() {
    return ConflictCheckConfig(
      enabled: true,
      stageNumber: 6.5,
      stageName: 'Conflict Check',
      similarity: SimilaritySettings.defaults(),
      llm: ConflictLLMSettings.defaults(),
      categories: [
        'location',
        'job',
        'relationship',
        'name',
        'preference',
        'personal_info',
      ],
      behavior: ConflictBehaviorSettings.defaults(),
      promptTemplate: _defaultPromptTemplate,
    );
  }

  factory ConflictCheckConfig.fromFirestore(Map<String, dynamic> data) {
    return ConflictCheckConfig(
      enabled: data['enabled'] ?? true,
      stageNumber: (data['stageNumber'] ?? 6.5).toDouble(),
      stageName: data['stageName'] ?? 'Conflict Check',
      similarity: SimilaritySettings.fromFirestore(data['similarity'] ?? {}),
      llm: ConflictLLMSettings.fromFirestore(data['llm'] ?? {}),
      categories: _parseCategories(data['categories']),
      behavior: ConflictBehaviorSettings.fromFirestore(data['behavior'] ?? {}),
      promptTemplate: data['promptTemplate'] ?? _defaultPromptTemplate,
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      updatedBy: data['updatedBy'],
    );
  }

  static List<String> _parseCategories(dynamic data) {
    if (data == null) {
      return ['location', 'job', 'relationship', 'name', 'preference', 'personal_info'];
    }
    if (data is List) {
      return data.map((e) => e.toString()).toList();
    }
    return ['location', 'job', 'relationship', 'name', 'preference', 'personal_info'];
  }

  Map<String, dynamic> toFirestore() {
    return {
      'enabled': enabled,
      'stageNumber': stageNumber,
      'stageName': stageName,
      'similarity': similarity.toFirestore(),
      'llm': llm.toFirestore(),
      'categories': categories,
      'behavior': behavior.toFirestore(),
      'promptTemplate': promptTemplate,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': updatedBy,
    };
  }

  ConflictCheckConfig copyWith({
    bool? enabled,
    double? stageNumber,
    String? stageName,
    SimilaritySettings? similarity,
    ConflictLLMSettings? llm,
    List<String>? categories,
    ConflictBehaviorSettings? behavior,
    String? promptTemplate,
    String? updatedBy,
  }) {
    return ConflictCheckConfig(
      enabled: enabled ?? this.enabled,
      stageNumber: stageNumber ?? this.stageNumber,
      stageName: stageName ?? this.stageName,
      similarity: similarity ?? this.similarity,
      llm: llm ?? this.llm,
      categories: categories ?? this.categories,
      behavior: behavior ?? this.behavior,
      promptTemplate: promptTemplate ?? this.promptTemplate,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }
}

// ═══════════════════════════════════════════════════════════
// SIMILARITY SETTINGS
// ═══════════════════════════════════════════════════════════

class SimilaritySettings {
  final double threshold;
  final String algorithm; // 'keyword' | 'semantic' | 'hybrid'
  final int maxCandidates;

  SimilaritySettings({
    required this.threshold,
    required this.algorithm,
    required this.maxCandidates,
  });

  factory SimilaritySettings.defaults() {
    return SimilaritySettings(
      threshold: 0.75,
      algorithm: 'keyword',
      maxCandidates: 10,
    );
  }

  factory SimilaritySettings.fromFirestore(Map<String, dynamic> data) {
    return SimilaritySettings(
      threshold: (data['threshold'] ?? 0.75).toDouble(),
      algorithm: data['algorithm'] ?? 'keyword',
      maxCandidates: data['maxCandidates'] ?? 10,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'threshold': threshold,
      'algorithm': algorithm,
      'maxCandidates': maxCandidates,
    };
  }

  SimilaritySettings copyWith({
    double? threshold,
    String? algorithm,
    int? maxCandidates,
  }) {
    return SimilaritySettings(
      threshold: threshold ?? this.threshold,
      algorithm: algorithm ?? this.algorithm,
      maxCandidates: maxCandidates ?? this.maxCandidates,
    );
  }
}

// ═══════════════════════════════════════════════════════════
// LLM SETTINGS
// ═══════════════════════════════════════════════════════════

class ConflictLLMSettings {
  final String provider;
  final String model;
  final double temperature;
  final int maxTokens;

  ConflictLLMSettings({
    required this.provider,
    required this.model,
    required this.temperature,
    required this.maxTokens,
  });

  factory ConflictLLMSettings.defaults() {
    return ConflictLLMSettings(
      provider: 'gemini',
      model: 'gemini-2.0-flash-exp',
      temperature: 0.2,
      maxTokens: 200,
    );
  }

  factory ConflictLLMSettings.fromFirestore(Map<String, dynamic> data) {
    return ConflictLLMSettings(
      provider: data['provider'] ?? 'gemini',
      model: data['model'] ?? 'gemini-2.0-flash-exp',
      temperature: (data['temperature'] ?? 0.2).toDouble(),
      maxTokens: data['maxTokens'] ?? 200,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'provider': provider,
      'model': model,
      'temperature': temperature,
      'maxTokens': maxTokens,
    };
  }

  ConflictLLMSettings copyWith({
    String? provider,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    return ConflictLLMSettings(
      provider: provider ?? this.provider,
      model: model ?? this.model,
      temperature: temperature ?? this.temperature,
      maxTokens: maxTokens ?? this.maxTokens,
    );
  }
}

// ═══════════════════════════════════════════════════════════
// BEHAVIOR SETTINGS
// ═══════════════════════════════════════════════════════════

class ConflictBehaviorSettings {
  final bool autoResolveUpdates;
  final bool skipDuplicates;
  final bool askForAllConflicts;
  final bool logAllChecks;

  ConflictBehaviorSettings({
    required this.autoResolveUpdates,
    required this.skipDuplicates,
    required this.askForAllConflicts,
    required this.logAllChecks,
  });

  factory ConflictBehaviorSettings.defaults() {
    return ConflictBehaviorSettings(
      autoResolveUpdates: false,
      skipDuplicates: true,
      askForAllConflicts: true,
      logAllChecks: true,
    );
  }

  factory ConflictBehaviorSettings.fromFirestore(Map<String, dynamic> data) {
    return ConflictBehaviorSettings(
      autoResolveUpdates: data['autoResolveUpdates'] ?? false,
      skipDuplicates: data['skipDuplicates'] ?? true,
      askForAllConflicts: data['askForAllConflicts'] ?? true,
      logAllChecks: data['logAllChecks'] ?? true,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'autoResolveUpdates': autoResolveUpdates,
      'skipDuplicates': skipDuplicates,
      'askForAllConflicts': askForAllConflicts,
      'logAllChecks': logAllChecks,
    };
  }

  ConflictBehaviorSettings copyWith({
    bool? autoResolveUpdates,
    bool? skipDuplicates,
    bool? askForAllConflicts,
    bool? logAllChecks,
  }) {
    return ConflictBehaviorSettings(
      autoResolveUpdates: autoResolveUpdates ?? this.autoResolveUpdates,
      skipDuplicates: skipDuplicates ?? this.skipDuplicates,
      askForAllConflicts: askForAllConflicts ?? this.askForAllConflicts,
      logAllChecks: logAllChecks ?? this.logAllChecks,
    );
  }
}

// ═══════════════════════════════════════════════════════════
// CONFLICT TYPES
// ═══════════════════════════════════════════════════════════

enum ConflictType {
  conflict,
  update,
  addition,
  duplicate,
  none,
}

extension ConflictTypeExtension on ConflictType {
  String get value {
    switch (this) {
      case ConflictType.conflict:
        return 'CONFLICT';
      case ConflictType.update:
        return 'UPDATE';
      case ConflictType.addition:
        return 'ADDITION';
      case ConflictType.duplicate:
        return 'DUPLICATE';
      case ConflictType.none:
        return 'NONE';
    }
  }

  String get description {
    switch (this) {
      case ConflictType.conflict:
        return 'Contradictory information that needs clarification';
      case ConflictType.update:
        return 'New information that replaces old (temporal change)';
      case ConflictType.addition:
        return 'Complementary information, both can coexist';
      case ConflictType.duplicate:
        return 'Same information, no action needed';
      case ConflictType.none:
        return 'No relationship detected';
    }
  }

  static ConflictType fromString(String value) {
    switch (value.toUpperCase()) {
      case 'CONFLICT':
        return ConflictType.conflict;
      case 'UPDATE':
        return ConflictType.update;
      case 'ADDITION':
        return ConflictType.addition;
      case 'DUPLICATE':
        return ConflictType.duplicate;
      default:
        return ConflictType.none;
    }
  }
}

// ═══════════════════════════════════════════════════════════
// DEFAULT PROMPT TEMPLATE
// ═══════════════════════════════════════════════════════════

const String _defaultPromptTemplate = '''You are analyzing whether two pieces of information about a user conflict.

EXISTING MEMORY: {{existing}}
NEW INFORMATION: {{new}}

Determine the relationship between these. Respond with exactly one of:
- CONFLICT: They directly contradict each other (e.g., "lives in NYC" vs "lives in Miami")
- UPDATE: The new info is a temporal update to old info (e.g., job change, moved locations)
- ADDITION: They can both be true simultaneously (e.g., two different hobbies)
- DUPLICATE: They express the same information

Respond in JSON format:
{
  "type": "CONFLICT|UPDATE|ADDITION|DUPLICATE",
  "confidence": 0.0-1.0,
  "reason": "Brief explanation"
}''';
