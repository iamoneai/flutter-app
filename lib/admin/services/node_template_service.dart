// IAMONEAI - Node Template Service
// Converts Firebase stages into visual builder node templates

import 'package:flutter/material.dart';
import 'stage_config_service.dart';
import '../models/visual_builder_models.dart';

/// Node category with metadata
class NodeCategoryInfo {
  final String id;
  final String name;
  final IconData icon;
  final String color;
  final int order;

  const NodeCategoryInfo({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.order,
  });

  Color getColor() {
    try {
      final hex = color.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (e) {
      return const Color(0xFF666666);
    }
  }
}

/// Lane template for creating lanes
class LaneTemplate {
  final String id;
  final String name;
  final String description;
  final String icon;
  final String color;
  final LaneType type;
  final LaneRole defaultRole;
  final Map<String, dynamic> defaultConfig;

  const LaneTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    required this.type,
    required this.defaultRole,
    required this.defaultConfig,
  });

  Color getColor() {
    try {
      final hex = color.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (e) {
      return const Color(0xFF666666);
    }
  }
}

/// Service to manage node templates from Firebase stages
class NodeTemplateService {
  static final NodeTemplateService _instance = NodeTemplateService._internal();
  factory NodeTemplateService() => _instance;
  NodeTemplateService._internal();

  final StageConfigService _stageService = StageConfigService();

  // Cache
  List<NodeTemplate>? _cachedTemplates;
  DateTime? _cacheTime;
  static const _cacheDuration = Duration(minutes: 5);

  /// Node categories with their metadata
  static const List<NodeCategoryInfo> categories = [
    NodeCategoryInfo(id: 'lanes', name: 'LANES', icon: Icons.view_stream, color: '#607D8B', order: 0),
    NodeCategoryInfo(id: 'logic', name: 'LOGIC NODES', icon: Icons.settings, color: '#4CAF50', order: 1),
    NodeCategoryInfo(id: 'ai', name: 'AI NODES', icon: Icons.psychology, color: '#2196F3', order: 2),
    NodeCategoryInfo(id: 'memory', name: 'MEMORY NODES', icon: Icons.memory, color: '#9C27B0', order: 3),
    NodeCategoryInfo(id: 'ui', name: 'UI NODES', icon: Icons.widgets, color: '#E91E63', order: 4),
    NodeCategoryInfo(id: 'context', name: 'CONTEXT NODES', icon: Icons.layers, color: '#607D8B', order: 5),
    NodeCategoryInfo(id: 'control', name: 'CONTROL FLOW', icon: Icons.call_split, color: '#FF9800', order: 6),
  ];

  /// Lane templates
  static const List<LaneTemplate> laneTemplates = [
    LaneTemplate(
      id: 'rules_lane',
      name: 'Rules Lane',
      description: 'Sequential or parallel rule execution',
      icon: '📋',
      color: '#4CAF50',
      type: LaneType.rules,
      defaultRole: LaneRole.executor,
      defaultConfig: {
        'execution_mode': 'sequential',
        'on_error': 'continue',
        'timeout_ms': 500,
      },
    ),
    LaneTemplate(
      id: 'llm_lane',
      name: 'LLM Lane',
      description: 'AI/LLM processing with provider selection',
      icon: '🤖',
      color: '#2196F3',
      type: LaneType.llm,
      defaultRole: LaneRole.orchestrator,
      defaultConfig: {
        'provider': 'groq',
        'model': 'llama-3.3-70b-versatile',
        'temperature': 0.3,
        'max_tokens': 1024,
        'timeout_ms': 5000,
      },
    ),
    LaneTemplate(
      id: 'router_lane',
      name: 'Router Lane',
      description: 'Route based on conditions or confidence',
      icon: '➡️',
      color: '#FF9800',
      type: LaneType.passthrough,
      defaultRole: LaneRole.router,
      defaultConfig: {
        'source_lane': '',
        'fields_to_use': ['classification.class', 'classification.confidence'],
      },
    ),
    LaneTemplate(
      id: 'data_lane',
      name: 'Data Lane',
      description: 'Database queries and data operations',
      icon: '🗄️',
      color: '#9C27B0',
      type: LaneType.database,
      defaultRole: LaneRole.executor,
      defaultConfig: {
        'primary_source': 'firestore',
        'secondary_source': 'redis',
        'timeout_ms': 3000,
        'cache_results': true,
      },
    ),
  ];

  /// Stage to category mapping
  static const Map<String, String> stageCategoryMap = {
    'stage_input_analysis': 'logic',
    'stage_classifier': 'ai',
    'stage_confidence_gate': 'logic',
    'stage_intent_resolution': 'ai',
    'stage_memory_query': 'memory',
    'stage_memory_extraction': 'memory',
    'stage_conflict_check': 'memory',
    'stage_ui_decision': 'ui',
    'stage_component_selection': 'ui',
    'stage_trust_evaluation': 'ai',
    'stage_save_decision': 'logic',
    'stage_context_injection': 'context',
    'stage_llm_response': 'ai',
    'stage_ui_generation': 'ui',
    'stage_post_response_log': 'context',
  };

  /// Stage to icon mapping
  static const Map<String, String> stageIconMap = {
    'stage_input_analysis': '📝',
    'stage_classifier': '🏷️',
    'stage_confidence_gate': '🚦',
    'stage_intent_resolution': '🎯',
    'stage_memory_query': '🔍',
    'stage_memory_extraction': '📤',
    'stage_conflict_check': '⚠️',
    'stage_ui_decision': '🖥️',
    'stage_component_selection': '🧩',
    'stage_trust_evaluation': '🛡️',
    'stage_save_decision': '⚖️',
    'stage_context_injection': '💉',
    'stage_llm_response': '💬',
    'stage_ui_generation': '🎨',
    'stage_post_response_log': '📊',
  };

  /// Get all node templates from Firebase stages
  Future<List<NodeTemplate>> getNodeTemplates({bool forceRefresh = false}) async {
    // Check cache
    if (!forceRefresh && _cachedTemplates != null && _cacheTime != null) {
      if (DateTime.now().difference(_cacheTime!) < _cacheDuration) {
        return _cachedTemplates!;
      }
    }

    try {
      final stages = await _stageService.getStages();
      final templates = stages.map((stage) => _stageToTemplate(stage)).toList();

      // Sort by order
      templates.sort((a, b) {
        final aOrder = _getStageOrder(a.id);
        final bOrder = _getStageOrder(b.id);
        return aOrder.compareTo(bOrder);
      });

      _cachedTemplates = templates;
      _cacheTime = DateTime.now();

      debugPrint('Loaded ${templates.length} node templates from Firebase');
      return templates;
    } catch (e) {
      debugPrint('Error loading node templates: $e');
      return _cachedTemplates ?? [];
    }
  }

  /// Convert a StageConfig to NodeTemplate
  NodeTemplate _stageToTemplate(StageConfig stage) {
    final categoryId = stageCategoryMap[stage.id] ?? 'logic';
    final category = _categoryFromId(categoryId);
    final icon = stageIconMap[stage.id] ?? '⚙️';
    final color = _getColorForCategory(categoryId);

    return NodeTemplate(
      id: stage.id,
      name: stage.name,
      description: stage.description,
      icon: icon,
      color: color,
      category: category,
      inputPorts: _getInputPorts(stage),
      outputPorts: _getOutputPorts(stage),
      properties: _getProperties(stage),
      isCustom: false,
    );
  }

  /// Get input ports from stage fields (required fields are inputs)
  List<PortTemplate> _getInputPorts(StageConfig stage) {
    // For most stages, the input is the previous stage's output
    // We'll define common input ports based on stage type
    final inputs = <PortTemplate>[];

    // All stages except input_analysis receive input from previous stage
    if (stage.id != 'stage_input_analysis') {
      inputs.add(PortTemplate(
        key: 'input',
        label: 'Input',
        dataType: PortDataType.object,
        required: true,
        description: 'Input from previous stage',
      ));
    }

    // Add stage-specific inputs
    switch (stage.id) {
      case 'stage_input_analysis':
        inputs.add(PortTemplate(
          key: 'raw_message',
          label: 'Raw Message',
          dataType: PortDataType.string,
          required: true,
          description: 'User message to analyze',
        ));
        break;
      case 'stage_memory_query':
        inputs.add(PortTemplate(
          key: 'query',
          label: 'Query',
          dataType: PortDataType.string,
          required: true,
          description: 'Memory search query',
        ));
        break;
      case 'stage_context_injection':
        inputs.add(PortTemplate(
          key: 'memories',
          label: 'Memories',
          dataType: PortDataType.array,
          required: false,
          description: 'Retrieved memories to inject',
        ));
        break;
    }

    return inputs;
  }

  /// Get output ports from stage fields
  List<PortTemplate> _getOutputPorts(StageConfig stage) {
    return stage.fields.map((field) => PortTemplate(
      key: field.key,
      label: field.label,
      dataType: _fieldTypeToPortType(field.type),
      required: field.required,
      description: field.description,
    )).toList();
  }

  /// Get properties from stage controls
  List<PropertyDefinition> _getProperties(StageConfig stage) {
    return stage.controls.map((control) => PropertyDefinition(
      key: control.key,
      label: control.label,
      type: _controlTypeToPropertyType(control.type),
      defaultValue: control.defaultValue,
      description: control.description,
      options: control.options,
      min: control.min,
      max: control.max,
    )).toList();
  }

  /// Convert field type to port data type
  PortDataType _fieldTypeToPortType(String fieldType) {
    switch (fieldType.toLowerCase()) {
      case 'string':
        return PortDataType.string;
      case 'number':
      case 'float':
      case 'int':
        return PortDataType.number;
      case 'boolean':
      case 'bool':
        return PortDataType.boolean;
      case 'array':
      case 'list':
        return PortDataType.array;
      case 'object':
      case 'map':
        return PortDataType.object;
      default:
        return PortDataType.any;
    }
  }

  /// Convert control type to property type
  String _controlTypeToPropertyType(String controlType) {
    switch (controlType.toLowerCase()) {
      case 'toggle':
        return 'boolean';
      case 'number':
      case 'slider':
        return 'number';
      case 'select':
      case 'dropdown':
        return 'select';
      default:
        return 'string';
    }
  }

  /// Get category enum from string ID
  NodeCategory _categoryFromId(String categoryId) {
    switch (categoryId) {
      case 'logic':
        return NodeCategory.logic;
      case 'ai':
        return NodeCategory.ai;
      case 'router':
        return NodeCategory.router;
      case 'data':
      case 'memory':
        return NodeCategory.data;
      case 'ui':
      case 'context':
        return NodeCategory.custom;
      default:
        return NodeCategory.logic;
    }
  }

  /// Get color for category
  String _getColorForCategory(String categoryId) {
    final category = categories.firstWhere(
      (c) => c.id == categoryId,
      orElse: () => categories.first,
    );
    return category.color;
  }

  /// Get stage order for sorting
  int _getStageOrder(String stageId) {
    const orderMap = {
      'stage_input_analysis': 1,
      'stage_classifier': 2,
      'stage_confidence_gate': 3,
      'stage_intent_resolution': 4,
      'stage_memory_query': 5,
      'stage_memory_extraction': 6,
      'stage_conflict_check': 7,
      'stage_ui_decision': 8,
      'stage_component_selection': 9,
      'stage_trust_evaluation': 10,
      'stage_save_decision': 11,
      'stage_context_injection': 12,
      'stage_llm_response': 13,
      'stage_ui_generation': 14,
      'stage_post_response_log': 15,
    };
    return orderMap[stageId] ?? 99;
  }

  /// Get templates grouped by category
  Future<Map<String, List<NodeTemplate>>> getTemplatesByCategory({bool forceRefresh = false}) async {
    final templates = await getNodeTemplates(forceRefresh: forceRefresh);
    final grouped = <String, List<NodeTemplate>>{};

    for (final template in templates) {
      final categoryId = stageCategoryMap[template.id] ?? 'logic';
      grouped.putIfAbsent(categoryId, () => []);
      grouped[categoryId]!.add(template);
    }

    return grouped;
  }

  /// Get category info by ID
  static NodeCategoryInfo? getCategoryInfo(String categoryId) {
    try {
      return categories.firstWhere((c) => c.id == categoryId);
    } catch (e) {
      return null;
    }
  }

  /// Clear cache
  void clearCache() {
    _cachedTemplates = null;
    _cacheTime = null;
  }
}
