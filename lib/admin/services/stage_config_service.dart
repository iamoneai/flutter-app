// IAMONEAI - Stage Config Service
// Manages pipeline stages in Firebase: config/pipeline/stages
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Stage field definition
class StageFieldConfig {
  final String key;
  final String label;
  final String type;
  final bool required;
  final String description;

  StageFieldConfig({
    required this.key,
    required this.label,
    required this.type,
    required this.required,
    required this.description,
  });

  factory StageFieldConfig.fromMap(Map<String, dynamic> map) {
    return StageFieldConfig(
      key: map['key'] ?? '',
      label: map['label'] ?? '',
      type: map['type'] ?? 'string',
      required: map['required'] ?? false,
      description: map['description'] ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'key': key,
    'label': label,
    'type': type,
    'required': required,
    'description': description,
  };
}

/// Stage control definition
class StageControlConfig {
  final String key;
  final String label;
  final String type;
  final dynamic defaultValue;
  final List<String>? options;
  final double? min;
  final double? max;
  final String description;

  StageControlConfig({
    required this.key,
    required this.label,
    required this.type,
    required this.defaultValue,
    this.options,
    this.min,
    this.max,
    required this.description,
  });

  factory StageControlConfig.fromMap(Map<String, dynamic> map) {
    return StageControlConfig(
      key: map['key'] ?? '',
      label: map['label'] ?? '',
      type: map['type'] ?? 'toggle',
      defaultValue: map['defaultValue'],
      options: map['options'] != null ? List<String>.from(map['options']) : null,
      min: (map['min'] as num?)?.toDouble(),
      max: (map['max'] as num?)?.toDouble(),
      description: map['description'] ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'key': key,
    'label': label,
    'type': type,
    'defaultValue': defaultValue,
    if (options != null) 'options': options,
    if (min != null) 'min': min,
    if (max != null) 'max': max,
    'description': description,
  };
}

/// Pipeline stage configuration from Firebase
class StageConfig {
  final String id;
  final int order;
  final String name;
  final String description;
  final List<StageFieldConfig> fields;
  final List<StageControlConfig> controls;
  final Map<String, dynamic> controlValues;
  final bool enabled;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  StageConfig({
    required this.id,
    required this.order,
    required this.name,
    required this.description,
    required this.fields,
    required this.controls,
    Map<String, dynamic>? controlValues,
    this.enabled = true,
    this.createdAt,
    this.updatedAt,
  }) : controlValues = controlValues ?? {};

  factory StageConfig.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return StageConfig(
      id: doc.id,
      order: data['order'] ?? 0,
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      fields: (data['fields'] as List<dynamic>?)
          ?.map((f) => StageFieldConfig.fromMap(f as Map<String, dynamic>))
          .toList() ?? [],
      controls: (data['controls'] as List<dynamic>?)
          ?.map((c) => StageControlConfig.fromMap(c as Map<String, dynamic>))
          .toList() ?? [],
      controlValues: Map<String, dynamic>.from(data['controlValues'] ?? {}),
      enabled: data['enabled'] ?? true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'order': order,
    'name': name,
    'description': description,
    'fields': fields.map((f) => f.toMap()).toList(),
    'controls': controls.map((c) => c.toMap()).toList(),
    'controlValues': controlValues,
    'enabled': enabled,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  StageConfig copyWith({
    int? order,
    String? name,
    String? description,
    List<StageFieldConfig>? fields,
    List<StageControlConfig>? controls,
    Map<String, dynamic>? controlValues,
    bool? enabled,
  }) {
    return StageConfig(
      id: id,
      order: order ?? this.order,
      name: name ?? this.name,
      description: description ?? this.description,
      fields: fields ?? this.fields,
      controls: controls ?? this.controls,
      controlValues: controlValues ?? this.controlValues,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}

/// Service to manage pipeline stages in Firebase
class StageConfigService {
  static final StageConfigService _instance = StageConfigService._internal();
  factory StageConfigService() => _instance;
  StageConfigService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _stagesRef =>
      _db.collection('config').doc('pipeline').collection('stages');

  /// Get all stages ordered by order field
  Future<List<StageConfig>> getStages() async {
    try {
      final snapshot = await _stagesRef.get();
      final stages = snapshot.docs
          .map((doc) => StageConfig.fromFirestore(doc))
          .toList();
      stages.sort((a, b) => a.order.compareTo(b.order));
      return stages;
    } catch (e) {
      debugPrint('Error loading stages: $e');
      return [];
    }
  }

  /// Get a single stage by ID
  Future<StageConfig?> getStage(String id) async {
    try {
      final doc = await _stagesRef.doc(id).get();
      if (doc.exists) {
        return StageConfig.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      debugPrint('Error loading stage $id: $e');
      return null;
    }
  }

  /// Create a new stage
  Future<bool> createStage(StageConfig stage) async {
    try {
      final data = stage.toFirestore();
      data['createdAt'] = FieldValue.serverTimestamp();
      await _stagesRef.doc(stage.id).set(data);
      return true;
    } catch (e) {
      debugPrint('Error creating stage: $e');
      return false;
    }
  }

  /// Update an existing stage
  Future<bool> updateStage(StageConfig stage) async {
    try {
      await _stagesRef.doc(stage.id).update(stage.toFirestore());
      return true;
    } catch (e) {
      debugPrint('Error updating stage: $e');
      return false;
    }
  }

  /// Update only specific fields of a stage
  Future<bool> updateStageFields(String id, Map<String, dynamic> fields) async {
    try {
      fields['updatedAt'] = FieldValue.serverTimestamp();
      await _stagesRef.doc(id).update(fields);
      return true;
    } catch (e) {
      debugPrint('Error updating stage fields: $e');
      return false;
    }
  }

  /// Update stage order (batch update multiple stages)
  Future<bool> updateStageOrders(List<StageConfig> stages) async {
    try {
      final batch = _db.batch();
      for (final stage in stages) {
        batch.update(_stagesRef.doc(stage.id), {
          'order': stage.order,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      return true;
    } catch (e) {
      debugPrint('Error updating stage orders: $e');
      return false;
    }
  }

  /// Delete a stage
  Future<bool> deleteStage(String id) async {
    try {
      await _stagesRef.doc(id).delete();
      return true;
    } catch (e) {
      debugPrint('Error deleting stage: $e');
      return false;
    }
  }

  /// Initialize default stages if none exist
  Future<void> initializeDefaultStages() async {
    try {
      final existing = await _stagesRef.limit(1).get();
      if (existing.docs.isNotEmpty) {
        debugPrint('Stages already exist, skipping initialization');
        return;
      }

      debugPrint('Initializing default stages...');
      final batch = _db.batch();

      final defaultStages = _getDefaultStages();
      for (final stage in defaultStages) {
        final data = stage.toFirestore();
        data['createdAt'] = FieldValue.serverTimestamp();
        batch.set(_stagesRef.doc(stage.id), data);
      }

      await batch.commit();
      debugPrint('Default stages initialized');
    } catch (e) {
      debugPrint('Error initializing default stages: $e');
    }
  }

  List<StageConfig> _getDefaultStages() {
    return [
      StageConfig(
        id: 'stage_input_analysis', order: 1, name: 'Input Analysis',
        description: 'Analyzes and preprocesses user input',
        fields: [
          StageFieldConfig(key: 'raw_input', label: 'Raw Input', type: 'string', required: true, description: 'Original user message'),
          StageFieldConfig(key: 'normalized_input', label: 'Normalized', type: 'string', required: true, description: 'Cleaned input text'),
          StageFieldConfig(key: 'language', label: 'Language', type: 'string', required: false, description: 'Detected language code'),
        ],
        controls: [
          StageControlConfig(key: 'normalize_text', label: 'Normalize Text', type: 'toggle', defaultValue: true, description: 'Clean and normalize input'),
          StageControlConfig(key: 'detect_language', label: 'Detect Language', type: 'toggle', defaultValue: true, description: 'Auto-detect input language'),
        ],
      ),
      StageConfig(
        id: 'stage_classifier', order: 2, name: 'Classifier',
        description: 'Classifies intent and extracts entities',
        fields: [
          StageFieldConfig(key: 'intent', label: 'Intent', type: 'string', required: true, description: 'Classified intent'),
          StageFieldConfig(key: 'confidence', label: 'Confidence', type: 'number', required: true, description: 'Classification confidence'),
          StageFieldConfig(key: 'entities', label: 'Entities', type: 'array', required: false, description: 'Extracted entities'),
        ],
        controls: [
          StageControlConfig(key: 'min_confidence', label: 'Min Confidence', type: 'number', defaultValue: 0.7, min: 0.0, max: 1.0, description: 'Minimum confidence threshold'),
        ],
      ),
      StageConfig(
        id: 'stage_intent_resolution', order: 3, name: 'Intent Resolution',
        description: 'Resolves and validates user intent',
        fields: [
          StageFieldConfig(key: 'resolved_intent', label: 'Resolved Intent', type: 'string', required: true, description: 'Final resolved intent'),
          StageFieldConfig(key: 'sub_intents', label: 'Sub-Intents', type: 'array', required: false, description: 'Secondary intents'),
        ],
        controls: [
          StageControlConfig(key: 'allow_multi_intent', label: 'Allow Multi-Intent', type: 'toggle', defaultValue: false, description: 'Process multiple intents'),
        ],
      ),
      StageConfig(
        id: 'stage_confidence_gate', order: 4, name: 'Confidence Gate',
        description: 'Gates processing based on confidence thresholds',
        fields: [
          StageFieldConfig(key: 'passed', label: 'Passed', type: 'boolean', required: true, description: 'Whether gate passed'),
          StageFieldConfig(key: 'action', label: 'Action', type: 'string', required: true, description: 'Gate action taken'),
        ],
        controls: [
          StageControlConfig(key: 'threshold', label: 'Threshold', type: 'number', defaultValue: 0.8, min: 0.0, max: 1.0, description: 'Confidence threshold'),
          StageControlConfig(key: 'fallback_action', label: 'Fallback Action', type: 'select', defaultValue: 'clarify', options: ['clarify', 'escalate', 'default_response'], description: 'Action when below threshold'),
        ],
      ),
      StageConfig(
        id: 'stage_memory_query', order: 5, name: 'Memory Query',
        description: 'Queries user memory and context',
        fields: [
          StageFieldConfig(key: 'memories', label: 'Memories', type: 'array', required: false, description: 'Retrieved memories'),
          StageFieldConfig(key: 'relevance_scores', label: 'Relevance', type: 'array', required: false, description: 'Memory relevance scores'),
        ],
        controls: [
          StageControlConfig(key: 'max_memories', label: 'Max Memories', type: 'number', defaultValue: 10, min: 1, max: 50, description: 'Maximum memories to retrieve'),
          StageControlConfig(key: 'min_relevance', label: 'Min Relevance', type: 'number', defaultValue: 0.5, min: 0.0, max: 1.0, description: 'Minimum relevance score'),
        ],
      ),
      StageConfig(
        id: 'stage_memory_extraction', order: 6, name: 'Memory Extraction',
        description: 'Extracts memories from conversation',
        fields: [
          StageFieldConfig(key: 'extracted_memories', label: 'Extracted', type: 'array', required: false, description: 'Newly extracted memories'),
          StageFieldConfig(key: 'memory_type', label: 'Type', type: 'string', required: false, description: 'Memory category'),
        ],
        controls: [
          StageControlConfig(key: 'extract_facts', label: 'Extract Facts', type: 'toggle', defaultValue: true, description: 'Extract factual information'),
          StageControlConfig(key: 'extract_preferences', label: 'Extract Preferences', type: 'toggle', defaultValue: true, description: 'Extract user preferences'),
        ],
      ),
      StageConfig(
        id: 'stage_save_decision', order: 7, name: 'Save Decision',
        description: 'Decides what to save to memory',
        fields: [
          StageFieldConfig(key: 'should_save', label: 'Should Save', type: 'boolean', required: true, description: 'Whether to save'),
          StageFieldConfig(key: 'save_items', label: 'Items', type: 'array', required: false, description: 'Items to save'),
        ],
        controls: [
          StageControlConfig(key: 'auto_save', label: 'Auto Save', type: 'toggle', defaultValue: true, description: 'Automatically save important info'),
        ],
      ),
      StageConfig(
        id: 'stage_llm_response', order: 8, name: 'LLM Response',
        description: 'Generates response using LLM',
        fields: [
          StageFieldConfig(key: 'response', label: 'Response', type: 'string', required: true, description: 'Generated response'),
          StageFieldConfig(key: 'tokens_used', label: 'Tokens', type: 'number', required: false, description: 'Tokens consumed'),
        ],
        controls: [
          StageControlConfig(key: 'stream_response', label: 'Stream Response', type: 'toggle', defaultValue: true, description: 'Stream response tokens'),
        ],
      ),
      StageConfig(
        id: 'stage_trust_evaluation', order: 9, name: 'Trust Evaluation',
        description: 'Evaluates trust and safety',
        fields: [
          StageFieldConfig(key: 'trust_score', label: 'Trust Score', type: 'number', required: true, description: 'Calculated trust score'),
          StageFieldConfig(key: 'flags', label: 'Flags', type: 'array', required: false, description: 'Safety flags'),
        ],
        controls: [
          StageControlConfig(key: 'strict_mode', label: 'Strict Mode', type: 'toggle', defaultValue: false, description: 'Enable strict safety checks'),
        ],
      ),
      StageConfig(
        id: 'stage_context_injection', order: 10, name: 'Context Injection',
        description: 'Injects context into prompt',
        fields: [
          StageFieldConfig(key: 'context', label: 'Context', type: 'string', required: true, description: 'Injected context'),
          StageFieldConfig(key: 'context_tokens', label: 'Tokens', type: 'number', required: false, description: 'Context token count'),
        ],
        controls: [
          StageControlConfig(key: 'max_context_tokens', label: 'Max Tokens', type: 'number', defaultValue: 2000, min: 100, max: 8000, description: 'Maximum context tokens'),
        ],
      ),
      StageConfig(
        id: 'stage_post_response_log', order: 11, name: 'Post-Response Log',
        description: 'Logs response and metrics',
        fields: [
          StageFieldConfig(key: 'logged', label: 'Logged', type: 'boolean', required: true, description: 'Whether logged successfully'),
          StageFieldConfig(key: 'log_id', label: 'Log ID', type: 'string', required: false, description: 'Log entry ID'),
        ],
        controls: [
          StageControlConfig(key: 'log_full_response', label: 'Log Full Response', type: 'toggle', defaultValue: true, description: 'Log complete response'),
          StageControlConfig(key: 'log_metrics', label: 'Log Metrics', type: 'toggle', defaultValue: true, description: 'Log performance metrics'),
        ],
      ),
    ];
  }
}
