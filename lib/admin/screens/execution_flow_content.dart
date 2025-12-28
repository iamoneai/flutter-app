// IAMONEAI - Execution Flow Content
// 3-column layout for managing pipeline stage execution flows
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../services/llm_config_service.dart';
import '../services/stage_config_service.dart';
import '../services/flow_config_service.dart';

// ============================================================================
// DATA STRUCTURES
// ============================================================================

/// Stage field definition (what a stage outputs)
class StageField {
  final String key;
  final String label;
  final String type;
  final bool required;
  final String description;

  const StageField({
    required this.key,
    required this.label,
    required this.type,
    required this.required,
    required this.description,
  });
}

/// Stage control definition (configurable settings)
class StageControl {
  final String key;
  final String label;
  final String type;
  final dynamic defaultValue;
  final List<String>? options;
  final double? min;
  final double? max;
  final String description;

  const StageControl({
    required this.key,
    required this.label,
    required this.type,
    required this.defaultValue,
    this.options,
    this.min,
    this.max,
    required this.description,
  });
}

/// Pipeline stage definition
class PipelineStage {
  final String id;
  final int number;
  final String name;
  final String description;
  final List<StageField> fields;
  final List<StageControl> controls;
  bool enabled;

  PipelineStage({
    required this.id,
    required this.number,
    required this.name,
    required this.description,
    required this.fields,
    required this.controls,
    this.enabled = true,
  });

  PipelineStage copyWith({bool? enabled}) {
    return PipelineStage(
      id: id,
      number: number,
      name: name,
      description: description,
      fields: fields,
      controls: controls,
      enabled: enabled ?? this.enabled,
    );
  }
}

// FlowType, FlowRole, and FlowConfig are now in flow_config_service.dart

// ============================================================================
// FALLBACK STAGES (used when Firebase unavailable)
// ============================================================================

final List<PipelineStage> _fallbackStages = [
  PipelineStage(
    id: 'stage_input_analysis', number: 1, name: 'Input Analysis',
    description: 'Parse, sanitize, detect language',
    fields: const [
      StageField(key: 'normalized_text', label: 'Normalized Text', type: 'string', required: true, description: 'Cleaned input'),
      StageField(key: 'language', label: 'Language', type: 'string', required: true, description: 'Detected language code'),
      StageField(key: 'flags', label: 'Flags', type: 'array', required: false, description: 'Warning flags'),
    ],
    controls: const [
      StageControl(key: 'max_length', label: 'Max Length', type: 'number', defaultValue: 2000, min: 100, max: 10000, description: 'Max input characters'),
      StageControl(key: 'sanitize_html', label: 'Sanitize HTML', type: 'toggle', defaultValue: true, description: 'Strip HTML tags'),
    ],
  ),
  PipelineStage(
    id: 'stage_classifier', number: 2, name: 'Classifier',
    description: 'Classify message type and confidence',
    fields: const [
      StageField(key: 'class', label: 'Class', type: 'string', required: true, description: 'Message classification'),
      StageField(key: 'confidence', label: 'Confidence', type: 'float', required: true, description: '0.0 to 1.0'),
    ],
    controls: const [
      StageControl(key: 'min_confidence', label: 'Min Confidence', type: 'number', defaultValue: 0.5, min: 0, max: 1, description: 'Below this = unknown'),
    ],
  ),
  PipelineStage(
    id: 'stage_confidence_gate', number: 3, name: 'Confidence Gate',
    description: 'Route based on confidence threshold',
    fields: const [
      StageField(key: 'route', label: 'Route', type: 'string', required: true, description: 'fast_path | normal | clarify | escalate'),
    ],
    controls: const [
      StageControl(key: 'fast_path_threshold', label: 'Fast Path >=', type: 'number', defaultValue: 0.85, min: 0, max: 1, description: 'Skip reasoning LLM'),
    ],
  ),
  PipelineStage(
    id: 'stage_intent_resolution', number: 4, name: 'Intent Resolution',
    description: 'Determine specific intent and entities',
    fields: const [
      StageField(key: 'intent', label: 'Intent', type: 'string', required: true, description: 'Primary intent'),
      StageField(key: 'entities', label: 'Entities', type: 'array', required: false, description: 'Extracted entities'),
    ],
    controls: const [
      StageControl(key: 'extract_entities', label: 'Extract Entities', type: 'toggle', defaultValue: true, description: 'Pull out entities'),
    ],
  ),
  PipelineStage(
    id: 'stage_memory_query', number: 5, name: 'Memory Query',
    description: 'Search existing user memories',
    fields: const [
      StageField(key: 'memories', label: 'Memories', type: 'array', required: true, description: 'Retrieved memories'),
    ],
    controls: const [
      StageControl(key: 'max_memories', label: 'Max Memories', type: 'number', defaultValue: 10, min: 1, max: 50, description: 'Max to fetch'),
    ],
  ),
  PipelineStage(
    id: 'stage_memory_extraction', number: 6, name: 'Memory Extraction',
    description: 'Extract facts, preferences from message',
    fields: const [
      StageField(key: 'facts', label: 'Facts', type: 'array', required: false, description: 'Extracted facts'),
      StageField(key: 'preferences', label: 'Preferences', type: 'array', required: false, description: 'Extracted preferences'),
    ],
    controls: const [
      StageControl(key: 'extract_facts', label: 'Extract Facts', type: 'toggle', defaultValue: true, description: 'Extract factual info'),
    ],
  ),
  PipelineStage(
    id: 'stage_conflict_check', number: 7, name: 'Conflict Check',
    description: 'Compare new vs existing memories',
    fields: const [
      StageField(key: 'has_conflict', label: 'Has Conflict', type: 'boolean', required: true, description: 'Conflict detected'),
    ],
    controls: const [
      StageControl(key: 'auto_resolve', label: 'Auto Resolve', type: 'toggle', defaultValue: false, description: 'Auto-update on conflict'),
    ],
  ),
  PipelineStage(
    id: 'stage_ui_decision', number: 8, name: 'UI Decision',
    description: 'Determine if UI component needed',
    fields: const [
      StageField(key: 'needs_ui', label: 'Needs UI', type: 'boolean', required: true, description: 'Should show UI'),
    ],
    controls: const [
      StageControl(key: 'ui_mode', label: 'UI Mode', type: 'select', defaultValue: 'auto', options: ['always', 'never', 'auto'], description: 'When to show UI'),
    ],
  ),
  PipelineStage(
    id: 'stage_component_selection', number: 9, name: 'Component Selection',
    description: 'Select appropriate UI component',
    fields: const [
      StageField(key: 'component', label: 'Component', type: 'string', required: true, description: 'Selected component type'),
    ],
    controls: const [
      StageControl(key: 'default_component', label: 'Default Component', type: 'select', defaultValue: 'card', options: ['chart', 'card', 'list', 'table'], description: 'Fallback component'),
    ],
  ),
  PipelineStage(
    id: 'stage_trust_evaluation', number: 10, name: 'Trust Evaluation',
    description: 'Score trustworthiness of extracted data',
    fields: const [
      StageField(key: 'trust_score', label: 'Trust Score', type: 'float', required: true, description: '0.0 to 1.0'),
    ],
    controls: const [
      StageControl(key: 'min_trust_score', label: 'Min Trust Score', type: 'number', defaultValue: 0.7, min: 0, max: 1, description: 'Below = do not save'),
    ],
  ),
  PipelineStage(
    id: 'stage_save_decision', number: 11, name: 'Save Decision',
    description: 'Decide whether to save memory',
    fields: const [
      StageField(key: 'should_save', label: 'Should Save', type: 'boolean', required: true, description: 'Save this memory'),
    ],
    controls: const [
      StageControl(key: 'require_confirmation', label: 'Require Confirmation', type: 'toggle', defaultValue: false, description: 'Ask user before save'),
    ],
  ),
  PipelineStage(
    id: 'stage_context_injection', number: 12, name: 'Context Injection',
    description: 'Build final prompt with all context',
    fields: const [
      StageField(key: 'final_prompt', label: 'Final Prompt', type: 'string', required: true, description: 'Complete LLM prompt'),
      StageField(key: 'token_count', label: 'Token Count', type: 'number', required: false, description: 'Estimated tokens'),
    ],
    controls: const [
      StageControl(key: 'max_context_tokens', label: 'Max Context Tokens', type: 'number', defaultValue: 4000, min: 1000, max: 16000, description: 'Token limit'),
    ],
  ),
  PipelineStage(
    id: 'stage_llm_response', number: 13, name: 'LLM Response',
    description: 'Generate response text',
    fields: const [
      StageField(key: 'response', label: 'Response', type: 'string', required: true, description: 'Generated response'),
      StageField(key: 'tokens_used', label: 'Tokens Used', type: 'number', required: false, description: 'Actual tokens'),
    ],
    controls: const [
      StageControl(key: 'tone', label: 'Tone', type: 'select', defaultValue: 'friendly', options: ['friendly', 'professional', 'casual'], description: 'Response tone'),
    ],
  ),
  PipelineStage(
    id: 'stage_ui_generation', number: 14, name: 'UI Generation',
    description: 'Generate UI component JSON',
    fields: const [
      StageField(key: 'component_json', label: 'Component JSON', type: 'object', required: true, description: 'UI component definition'),
    ],
    controls: const [
      StageControl(key: 'animate', label: 'Animate', type: 'toggle', defaultValue: true, description: 'Enable animations'),
    ],
  ),
  PipelineStage(
    id: 'stage_post_response_log', number: 15, name: 'Post-Response Log',
    description: 'Log analytics, save memory async',
    fields: const [
      StageField(key: 'logged', label: 'Logged', type: 'boolean', required: true, description: 'Successfully logged'),
    ],
    controls: const [
      StageControl(key: 'async_mode', label: 'Async Mode', type: 'toggle', defaultValue: true, description: 'Non-blocking logging'),
    ],
  ),
];

// Flows are now loaded from Firebase via FlowConfigService

// ============================================================================
// MAIN WIDGET
// ============================================================================

class ExecutionFlowContent extends StatefulWidget {
  const ExecutionFlowContent({super.key});

  @override
  State<ExecutionFlowContent> createState() => _ExecutionFlowContentState();
}

class _ExecutionFlowContentState extends State<ExecutionFlowContent> {
  // Data
  late Map<String, PipelineStage> _stagesMap;

  // Flows from Firebase
  final FlowConfigService _flowConfigService = FlowConfigService();
  List<FlowConfig> _flows = [];
  bool _isLoadingFlows = true;

  // Stages from Firebase
  final StageConfigService _stageConfigService = StageConfigService();
  List<PipelineStage> _stages = [];
  bool _isLoadingStages = true;

  // LLM Providers from Firebase (only enabled + showInRouting)
  final LLMConfigService _llmConfigService = LLMConfigService();
  List<LLMProviderConfig> _llmProviders = [];
  bool _isLoadingProviders = true;

  // Selection state
  String? _selectedFlowId;
  String? _selectedStageId;

  // Drag state
  String? _draggingStageId;
  String? _dragOverFlowId;

  // Column widths (adjustable)
  double _columnAWidth = 230;
  double _columnCWidth = 350;

  // Test panel state
  bool _isTestPanelCollapsed = true;
  double _testPanelHeightRatio = 0.35;
  final TextEditingController _testInputController = TextEditingController();
  bool _isRunningTest = false;
  Map<String, dynamic>? _testResult;
  double _responseColumnRatio = 0.33;
  double _metadataColumnRatio = 0.33;

  // Dirty flag
  bool _isDirty = false;

  // Stage control values (key: stageId, value: {controlKey: value})
  Map<String, Map<String, dynamic>> _stageControlValues = {};

  @override
  void initState() {
    super.initState();
    _stagesMap = {};
    _loadFlows();
    _loadStages();
    _loadLLMProviders();
  }

  /// Load flows from Firebase
  Future<void> _loadFlows() async {
    try {
      final flows = await _flowConfigService.getFlows();
      if (mounted) {
        setState(() {
          _flows = flows;
          _isLoadingFlows = false;
        });
      }
      debugPrint('Loaded ${_flows.length} flows from Firebase');
    } catch (e) {
      debugPrint('Error loading flows: $e');
      if (mounted) {
        setState(() {
          _flows = [];
          _isLoadingFlows = false;
        });
      }
    }
  }

  /// Load stages from Firebase
  Future<void> _loadStages() async {
    try {
      // First check if we need to initialize default stages
      await _stageConfigService.initializeDefaultStages();

      final stageConfigs = await _stageConfigService.getStages();

      if (mounted) {
        setState(() {
          _stages = stageConfigs.map((config) => _stageConfigToLocal(config)).toList();
          _stagesMap = {for (var s in _stages) s.id: s};
          _isLoadingStages = false;
          _initStageControlValuesFromConfigs(stageConfigs);
        });
      }
      debugPrint('Loaded ${_stages.length} stages from Firebase');
    } catch (e) {
      debugPrint('Error loading stages: $e');
      // Fall back to hardcoded stages
      if (mounted) {
        setState(() {
          _stages = List.from(_fallbackStages);
          _stagesMap = {for (var s in _stages) s.id: s};
          _isLoadingStages = false;
          _initStageControlValues();
        });
      }
    }
  }

  /// Convert StageConfig from Firebase to local PipelineStage
  PipelineStage _stageConfigToLocal(StageConfig config) {
    return PipelineStage(
      id: config.id,
      number: config.order,
      name: config.name,
      description: config.description,
      fields: config.fields.map((f) => StageField(
        key: f.key,
        label: f.label,
        type: f.type,
        required: f.required,
        description: f.description,
      )).toList(),
      controls: config.controls.map((c) => StageControl(
        key: c.key,
        label: c.label,
        type: c.type,
        defaultValue: c.defaultValue,
        options: c.options,
        min: c.min,
        max: c.max,
        description: c.description,
      )).toList(),
      enabled: config.enabled,
    );
  }

  /// Convert local PipelineStage to StageConfig for Firebase
  StageConfig _localToStageConfig(PipelineStage stage) {
    return StageConfig(
      id: stage.id,
      order: stage.number,
      name: stage.name,
      description: stage.description,
      fields: stage.fields.map((f) => StageFieldConfig(
        key: f.key,
        label: f.label,
        type: f.type,
        required: f.required,
        description: f.description,
      )).toList(),
      controls: stage.controls.map((c) => StageControlConfig(
        key: c.key,
        label: c.label,
        type: c.type,
        defaultValue: c.defaultValue,
        options: c.options,
        min: c.min,
        max: c.max,
        description: c.description,
      )).toList(),
      controlValues: _stageControlValues[stage.id] ?? {},
      enabled: stage.enabled,
    );
  }

  /// Initialize control values from Firebase configs (uses saved values if available)
  void _initStageControlValuesFromConfigs(List<StageConfig> configs) {
    for (var config in configs) {
      _stageControlValues[config.id] = {};
      // First set defaults
      for (var control in config.controls) {
        _stageControlValues[config.id]![control.key] = control.defaultValue;
      }
      // Then override with saved values
      for (var entry in config.controlValues.entries) {
        _stageControlValues[config.id]![entry.key] = entry.value;
      }
    }
  }

  /// Initialize control values with defaults (fallback when Firebase unavailable)
  void _initStageControlValues() {
    for (var stage in _stages) {
      _stageControlValues[stage.id] = {};
      for (var control in stage.controls) {
        _stageControlValues[stage.id]![control.key] = control.defaultValue;
      }
    }
  }

  /// Get control value for a stage
  dynamic _getControlValue(String stageId, String controlKey, dynamic defaultValue) {
    return _stageControlValues[stageId]?[controlKey] ?? defaultValue;
  }

  /// Set control value for a stage
  void _setControlValue(String stageId, String controlKey, dynamic value) {
    setState(() {
      _stageControlValues[stageId] ??= {};
      _stageControlValues[stageId]![controlKey] = value;
      _isDirty = true;
    });
    // Save to Firebase
    _saveStageControlValue(stageId, controlKey, value);
  }

  Future<void> _saveStageControlValue(String stageId, String controlKey, dynamic value) async {
    final controlValues = Map<String, dynamic>.from(_stageControlValues[stageId] ?? {});
    controlValues[controlKey] = value;
    final success = await _stageConfigService.updateStageFields(stageId, {'controlValues': controlValues});
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save setting'), backgroundColor: Colors.orange),
      );
    }
  }

  Future<void> _loadLLMProviders() async {
    try {
      // Get all providers and filter by isEnabled AND showInRouting
      final allProviders = await _llmConfigService.getProviders();
      final routingProviders = allProviders.where((p) => p.isEnabled && p.showInRouting).toList();
      if (mounted) {
        setState(() {
          _llmProviders = routingProviders;
          _isLoadingProviders = false;
        });
      }
      debugPrint('Loaded ${routingProviders.length} routing LLM providers out of ${allProviders.length} total');
    } catch (e) {
      debugPrint('Error loading LLM providers: $e');
      if (mounted) {
        setState(() => _isLoadingProviders = false);
      }
    }
  }

  @override
  void dispose() {
    _testInputController.dispose();
    super.dispose();
  }

  // Count how many times a stage appears across all flows
  int _getStageAssignmentCount(String stageId) {
    int count = 0;
    for (var flow in _flows) {
      if (flow.stageIds.contains(stageId)) count++;
    }
    return count;
  }

  // Get all assigned stage IDs
  Set<String> get _assignedStageIds {
    return _flows.expand((f) => f.stageIds).toSet();
  }

  // Get stage by ID
  PipelineStage? _getStage(String id) => _stagesMap[id];

  // Get flow containing a stage
  FlowConfig? _getFlowForStage(String stageId) {
    try {
      return _flows.firstWhere((f) => f.stageIds.contains(stageId));
    } catch (_) {
      return null;
    }
  }

  // Add stage to flow
  void _addStageToFlow(String stageId, String flowId, {int? index}) {
    setState(() {
      final targetFlow = _flows.firstWhere((f) => f.id == flowId);
      if (!targetFlow.stageIds.contains(stageId)) {
        if (index != null && index < targetFlow.stageIds.length) {
          targetFlow.stageIds.insert(index, stageId);
        } else {
          targetFlow.stageIds.add(stageId);
        }
        _isDirty = true;
      }
    });
  }

  // Remove stage from flow with confirmation
  void _confirmRemoveStageFromFlow(String stageId, String flowId) {
    final stage = _getStage(stageId);
    final flow = _flows.firstWhere((f) => f.id == flowId);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Stage'),
        content: Text('Remove "${stage?.name ?? stageId}" from "${flow.name}" flow?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                flow.stageIds.remove(stageId);
                _selectedStageId = null;
                _isDirty = true;
              });
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // Reorder stage within flow
  void _reorderStageInFlow(String flowId, int oldIndex, int newIndex) {
    setState(() {
      final flow = _flows.firstWhere((f) => f.id == flowId);
      if (newIndex > oldIndex) newIndex--;
      final stageId = flow.stageIds.removeAt(oldIndex);
      flow.stageIds.insert(newIndex, stageId);
      _isDirty = true;
    });
  }

  // Reorder flows
  void _reorderFlows(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final flow = _flows.removeAt(oldIndex);
      _flows.insert(newIndex, flow);
      // Update positions using copyWith since position is final
      for (int i = 0; i < _flows.length; i++) {
        _flows[i] = _flows[i].copyWith(position: i + 1);
      }
      _isDirty = true;
    });
  }

  // Toggle flow expanded/collapsed
  void _toggleFlowExpanded(String flowId) {
    setState(() {
      final flow = _flows.firstWhere((f) => f.id == flowId);
      flow.isExpanded = !flow.isExpanded;
    });
  }

  // Show add flow dialog
  void _showAddFlowDialog() {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    FlowType selectedType = FlowType.rules;
    FlowRole selectedRole = FlowRole.executor;
    String selectedIcon = '📋';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add New Flow'),
          content: SizedBox(
            width: 450,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Flow Name', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<FlowType>(
                        value: selectedType,
                        decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
                        items: FlowType.values.map((t) => DropdownMenuItem(value: t, child: Text(t.name))).toList(),
                        onChanged: (v) => setDialogState(() => selectedType = v!),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: DropdownButtonFormField<FlowRole>(
                        value: selectedRole,
                        decoration: const InputDecoration(labelText: 'Role', border: OutlineInputBorder()),
                        items: FlowRole.values.map((r) => DropdownMenuItem(value: r, child: Text(r.name))).toList(),
                        onChanged: (v) => setDialogState(() => selectedRole = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedIcon,
                  decoration: const InputDecoration(labelText: 'Icon', border: OutlineInputBorder()),
                  items: ['📋', '🤖', '➡️', '🗄️', '🧠', '📝', '⚡', '🔧', '🎯', '💡']
                      .map((i) => DropdownMenuItem(value: i, child: Text(i))).toList(),
                  onChanged: (v) => setDialogState(() => selectedIcon = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.trim().isNotEmpty) {
                  _addNewFlow(
                    nameController.text.trim(),
                    descController.text.trim(),
                    selectedType,
                    selectedRole,
                    selectedIcon,
                  );
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00AA66)),
              child: const Text('Add', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // Add new flow to Firebase
  Future<void> _addNewFlow(String name, String description, FlowType type, FlowRole role, String icon) async {
    final flowId = FlowConfigService.generateFlowId(name);
    final newPosition = _flows.length + 1;

    // Default config based on type
    Map<String, dynamic> config;
    switch (type) {
      case FlowType.llm:
        config = {
          'provider': _llmProviders.isNotEmpty ? _llmProviders.first.provider : 'groq',
          'model': _llmProviders.isNotEmpty ? _llmProviders.first.defaultModel : 'llama-3.3-70b-versatile',
          'temperature': 0.5,
          'max_tokens': 1024,
          'timeout_ms': 5000,
        };
        break;
      case FlowType.database:
        config = {'primary_source': 'firestore', 'timeout_ms': 3000, 'cache_results': true};
        break;
      case FlowType.passthrough:
        config = {'source_flow': '', 'fields_to_use': []};
        break;
      default:
        config = {'execution_mode': 'sequential', 'on_error': 'continue', 'timeout_ms': 500};
    }

    final newFlow = FlowConfig(
      id: flowId,
      name: name,
      description: description,
      icon: icon,
      color: '#4CAF50',
      position: newPosition,
      enabled: true,
      type: type,
      role: role,
      stageIds: [],
      config: config,
    );

    final success = await _flowConfigService.createFlow(newFlow);
    if (success) {
      setState(() {
        _flows.add(newFlow);
        _selectedFlowId = flowId;
        _selectedStageId = null;
      });
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to create flow'), backgroundColor: Colors.red),
      );
    }
  }

  // Show delete flow dialog (requires typing "delete")
  void _showDeleteFlowDialog(FlowConfig flow) {
    final confirmController = TextEditingController();
    bool canDelete = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.warning, color: Colors.red),
              const SizedBox(width: 8),
              Text('Delete Flow: ${flow.name}'),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Are you sure you want to delete "${flow.name}"?'),
                const SizedBox(height: 8),
                Text('This action cannot be undone.', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                const SizedBox(height: 16),
                const Text('Type "delete" to confirm:', style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                TextField(
                  controller: confirmController,
                  decoration: const InputDecoration(hintText: 'delete', border: OutlineInputBorder()),
                  onChanged: (value) {
                    setDialogState(() => canDelete = value.toLowerCase() == 'delete');
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: canDelete ? () {
                _deleteFlow(flow);
                Navigator.pop(context);
              } : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                disabledBackgroundColor: Colors.grey[300],
              ),
              child: const Text('Delete', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // Delete flow from Firebase
  Future<void> _deleteFlow(FlowConfig flow) async {
    final success = await _flowConfigService.deleteFlow(flow.id);
    if (success) {
      setState(() {
        _flows.removeWhere((f) => f.id == flow.id);
        if (_selectedFlowId == flow.id) _selectedFlowId = null;
        // Update positions
        for (int i = 0; i < _flows.length; i++) {
          _flows[i] = _flows[i].copyWith(position: i + 1);
        }
      });
      // Save updated positions
      _flowConfigService.updateFlowPositions(_flows);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to delete flow'), backgroundColor: Colors.red),
      );
    }
  }

  // Update flow in Firebase
  Future<void> _updateFlowInFirebase(FlowConfig flow) async {
    final success = await _flowConfigService.updateFlow(flow);
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update flow'), backgroundColor: Colors.red),
      );
    }
  }

  // Helper to update a flow property in the local list
  void _updateFlowProperty(String flowId, FlowConfig Function(FlowConfig) updater) {
    setState(() {
      final index = _flows.indexWhere((f) => f.id == flowId);
      if (index != -1) {
        _flows[index] = updater(_flows[index]);
        _isDirty = true;
      }
    });
  }

  // Save (now saves all flows to Firebase)
  void _save() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All changes are auto-saved to Firebase'), backgroundColor: Colors.green),
    );
  }

  // Gateway API URL
  static const String _gatewayUrl = 'https://iamoneai-gateway-qqkntitb3a-uc.a.run.app';

  // Run test
  Future<void> _runTest() async {
    if (_testInputController.text.trim().isEmpty) return;

    setState(() {
      _isRunningTest = true;
      _testResult = null;
    });

    try {
      // Call the real pipeline API
      final response = await http.post(
        Uri.parse('$_gatewayUrl/api/pipeline/test'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'message': _testInputController.text}),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() {
          _testResult = result;
          _isRunningTest = false;
        });
      } else {
        setState(() {
          _testResult = {
            'error': 'API Error: ${response.statusCode}',
            'body': response.body,
          };
          _isRunningTest = false;
        });
      }
    } catch (e) {
      setState(() {
        _testResult = {'error': e.toString()};
        _isRunningTest = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header bar
        _buildHeader(),
        // Main content with test panel
        Expanded(
          child: _isTestPanelCollapsed
              ? Column(
                  children: [
                    Expanded(child: _buildMainContent()),
                    _buildCollapsedTestBar(),
                  ],
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final testHeight = constraints.maxHeight * _testPanelHeightRatio;
                    final mainHeight = constraints.maxHeight - testHeight - 8;
                    return Column(
                      children: [
                        SizedBox(height: mainHeight, child: _buildMainContent()),
                        _buildHorizontalDivider(),
                        SizedBox(height: testHeight, child: _buildTestPanel()),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ============================================================================
  // HEADER
  // ============================================================================

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFFF8F9FA),
        border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
      ),
      child: Row(
        children: [
          const Text('⚡', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          const Text(
            'EXECUTION FLOW',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A), letterSpacing: 1),
          ),
          const SizedBox(width: 16),
          if (_isDirty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('Unsaved', style: TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.w500)),
            ),
          const Spacer(),
          // Expand/Collapse all flows
          IconButton(
            onPressed: () {
              setState(() {
                final allExpanded = _flows.every((f) => f.isExpanded);
                for (var flow in _flows) {
                  flow.isExpanded = !allExpanded;
                }
              });
            },
            icon: Icon(
              _flows.every((f) => f.isExpanded) ? Icons.unfold_less : Icons.unfold_more,
              color: const Color(0xFF666666),
              size: 20,
            ),
            tooltip: _flows.every((f) => f.isExpanded) ? 'Collapse All' : 'Expand All',
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _showAddFlowDialog,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add Flow'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF666666),
              side: const BorderSide(color: Color(0xFFCCCCCC)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: _isDirty ? _save : null,
            icon: const Icon(Icons.save, size: 16),
            label: const Text('Save'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00AA66),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFCCCCCC),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // MAIN CONTENT (3 columns)
  // ============================================================================

  Widget _buildMainContent() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Column A: Stage List
        SizedBox(width: _columnAWidth, child: _buildColumnA()),
        // Divider A-B
        _buildVerticalDivider(
          onDrag: (delta) {
            setState(() {
              _columnAWidth = (_columnAWidth + delta).clamp(180.0, 350.0);
            });
          },
        ),
        // Column B: Flow Groups
        Expanded(child: _buildColumnB()),
        // Divider B-C
        _buildVerticalDivider(
          onDrag: (delta) {
            setState(() {
              _columnCWidth = (_columnCWidth - delta).clamp(280.0, 500.0);
            });
          },
        ),
        // Column C: Settings Panel
        SizedBox(width: _columnCWidth, child: _buildColumnC()),
      ],
    );
  }

  Widget _buildVerticalDivider({required Function(double) onDrag}) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
        child: Container(
          width: 8,
          color: const Color(0xFFF0F0F0),
          child: const Center(
            child: Icon(Icons.drag_indicator, size: 12, color: Color(0xFFCCCCCC)),
          ),
        ),
      ),
    );
  }

  Widget _buildHorizontalDivider() {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      child: GestureDetector(
        onVerticalDragUpdate: (details) {
          setState(() {
            final delta = details.delta.dy / context.size!.height;
            _testPanelHeightRatio = (_testPanelHeightRatio - delta).clamp(0.15, 0.85);
          });
        },
        child: Container(
          height: 8,
          color: const Color(0xFFF0F0F0),
          child: const Center(
            child: Icon(Icons.drag_indicator, size: 12, color: Color(0xFFCCCCCC)),
          ),
        ),
      ),
    );
  }

  // ============================================================================
  // COLUMN A: STAGE LIST
  // ============================================================================

  Widget _buildColumnA() {
    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFFF8F9FA),
              border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('STAGES', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF666666), letterSpacing: 0.5)),
                      const SizedBox(height: 2),
                      Text('${_stages.length} stages', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _showAddStageDialog,
                  icon: const Icon(Icons.add_circle_outline, size: 20),
                  color: const Color(0xFF00AA66),
                  tooltip: 'Add Stage',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.all(10),
              buildDefaultDragHandles: false,
              itemCount: _stages.length,
              onReorder: _reorderStages,
              itemBuilder: (context, index) {
                final stage = _stages[index];
                final assignmentCount = _getStageAssignmentCount(stage.id);
                return ReorderableDragStartListener(
                  key: ValueKey(stage.id),
                  index: index,
                  child: _buildStageListItem(stage, assignmentCount, index),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _reorderStages(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final stage = _stages.removeAt(oldIndex);
      _stages.insert(newIndex, stage);
      // Update stage numbers
      for (int i = 0; i < _stages.length; i++) {
        _stages[i] = PipelineStage(
          id: _stages[i].id,
          number: i + 1,
          name: _stages[i].name,
          description: _stages[i].description,
          fields: _stages[i].fields,
          controls: _stages[i].controls,
          enabled: _stages[i].enabled,
        );
        _stagesMap[_stages[i].id] = _stages[i];
      }
      _isDirty = true;
    });
    // Save order to Firebase
    _saveStageOrders();
  }

  Future<void> _saveStageOrders() async {
    final stageConfigs = _stages.map((s) => _localToStageConfig(s)).toList();
    final success = await _stageConfigService.updateStageOrders(stageConfigs);
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save stage order'), backgroundColor: Colors.red),
      );
    }
  }

  void _showAddStageDialog() {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Stage'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Stage Name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descController,
                decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.trim().isNotEmpty) {
                _addNewStage(nameController.text.trim(), descController.text.trim());
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00AA66)),
            child: const Text('Add', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _addNewStage(String name, String description) async {
    // Generate a clean ID from name (lowercase, underscores)
    final cleanName = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
    final newId = cleanName.isNotEmpty ? cleanName : 'stage_${DateTime.now().millisecondsSinceEpoch}';
    final newNumber = _stages.length + 1;
    final newStage = PipelineStage(
      id: newId,
      number: newNumber,
      name: name,
      description: description,
      fields: const [],
      controls: const [],
      enabled: true,
    );

    // Save to Firebase first
    final stageConfig = _localToStageConfig(newStage);
    final success = await _stageConfigService.createStage(stageConfig);

    if (success) {
      setState(() {
        _stages.add(newStage);
        _stagesMap[newId] = newStage;
        _isDirty = true;
      });
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to create stage'), backgroundColor: Colors.red),
      );
    }
  }

  void _showEditStageDialog(PipelineStage stage) {
    final nameController = TextEditingController(text: stage.name);
    final descController = TextEditingController(text: stage.description);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit Stage ${stage.number}'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Stage Name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descController,
                decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.trim().isNotEmpty) {
                _updateStage(stage, nameController.text.trim(), descController.text.trim());
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2196F3)),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _updateStage(PipelineStage stage, String name, String description) async {
    final index = _stages.indexWhere((s) => s.id == stage.id);
    if (index >= 0) {
      final updatedStage = PipelineStage(
        id: stage.id,
        number: stage.number,
        name: name,
        description: description,
        fields: stage.fields,
        controls: stage.controls,
        enabled: stage.enabled,
      );

      // Save to Firebase
      final stageConfig = _localToStageConfig(updatedStage);
      final success = await _stageConfigService.updateStage(stageConfig);

      if (success) {
        setState(() {
          _stages[index] = updatedStage;
          _stagesMap[stage.id] = updatedStage;
          _isDirty = true;
        });
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update stage'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showDeleteStageDialog(PipelineStage stage) {
    final confirmController = TextEditingController();
    bool canDelete = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.warning, color: Colors.red),
              const SizedBox(width: 8),
              Text('Delete Stage ${stage.number}'),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Are you sure you want to delete "${stage.name}"?'),
                const SizedBox(height: 8),
                Text(
                  'This stage will be removed from all flows.',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
                const SizedBox(height: 16),
                const Text('Type "delete" to confirm:', style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                TextField(
                  controller: confirmController,
                  decoration: const InputDecoration(
                    hintText: 'delete',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    setDialogState(() {
                      canDelete = value.toLowerCase() == 'delete';
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: canDelete ? () {
                _deleteStage(stage);
                Navigator.pop(context);
              } : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                disabledBackgroundColor: Colors.grey[300],
              ),
              child: const Text('Delete', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteStage(PipelineStage stage) async {
    // Delete from Firebase first
    final success = await _stageConfigService.deleteStage(stage.id);

    if (success) {
      setState(() {
        // Remove from all flows
        for (var flow in _flows) {
          flow.stageIds.remove(stage.id);
        }
        // Remove from stages list
        _stages.removeWhere((s) => s.id == stage.id);
        _stagesMap.remove(stage.id);
        // Renumber stages
        for (int i = 0; i < _stages.length; i++) {
          _stages[i] = PipelineStage(
            id: _stages[i].id,
            number: i + 1,
            name: _stages[i].name,
            description: _stages[i].description,
            fields: _stages[i].fields,
            controls: _stages[i].controls,
            enabled: _stages[i].enabled,
          );
          _stagesMap[_stages[i].id] = _stages[i];
        }
        if (_selectedStageId == stage.id) {
          _selectedStageId = null;
        }
        _isDirty = true;
      });
      // Update order in Firebase for remaining stages
      _saveStageOrders();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to delete stage'), backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildStageListItem(PipelineStage stage, int assignmentCount, int index) {
    final isAssigned = assignmentCount > 0;
    final isDuplicate = assignmentCount > 1;

    return Draggable<String>(
      data: stage.id,
      onDragStarted: () => setState(() => _draggingStageId = stage.id),
      onDragEnd: (_) => setState(() => _draggingStageId = null),
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 22, height: 22,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
                child: Center(child: Text('${stage.number}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)))),
              ),
              const SizedBox(width: 8),
              Text(stage.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: _buildStageChip(stage, isAssigned, isDuplicate, assignmentCount, index)),
      child: _buildStageChip(stage, isAssigned, isDuplicate, assignmentCount, index),
    );
  }

  Widget _buildStageChip(PipelineStage stage, bool isAssigned, bool isDuplicate, int count, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isDuplicate
            ? const Color(0xFFFFF3E0)
            : isAssigned
                ? const Color(0xFFF0F0F0)
                : Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isDuplicate
              ? const Color(0xFFFF9800)
              : isAssigned
                  ? const Color(0xFFE0E0E0)
                  : const Color(0xFFCCCCCC),
        ),
      ),
      child: Row(
        children: [
          // Drag handle
          const Icon(Icons.drag_indicator, size: 14, color: Color(0xFFCCCCCC)),
          const SizedBox(width: 4),
          // Stage number
          Container(
            width: 22, height: 22,
            decoration: BoxDecoration(
              color: isDuplicate
                  ? const Color(0xFFFF9800)
                  : isAssigned
                      ? const Color(0xFFCCCCCC)
                      : const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Text(
                '${stage.number}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isDuplicate || !isAssigned ? Colors.white : const Color(0xFF666666),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Stage name
          Expanded(
            child: Tooltip(
              message: '${stage.name}\n${stage.description}${isDuplicate ? '\n(In $count flows)' : ''}',
              child: Text(
                stage.name,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: isAssigned ? const Color(0xFF666666) : const Color(0xFF1A1A1A),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          // Assignment badge
          if (isDuplicate)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFF9800),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('$count', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
            )
          else if (isAssigned)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.check_circle, size: 12, color: Color(0xFF00AA66)),
            ),
          // Action menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 16, color: Color(0xFF999999)),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            onSelected: (value) {
              switch (value) {
                case 'edit':
                  _showEditStageDialog(stage);
                  break;
                case 'delete':
                  _showDeleteStageDialog(stage);
                  break;
                case 'move_up':
                  if (index > 0) _reorderStages(index, index - 1);
                  break;
                case 'move_down':
                  if (index < _stages.length - 1) _reorderStages(index, index + 2);
                  break;
              }
            },
            itemBuilder: (context) => [
              if (index > 0)
                const PopupMenuItem(value: 'move_up', child: Row(children: [Icon(Icons.arrow_upward, size: 16), SizedBox(width: 8), Text('Move Up')])),
              if (index < _stages.length - 1)
                const PopupMenuItem(value: 'move_down', child: Row(children: [Icon(Icons.arrow_downward, size: 16), SizedBox(width: 8), Text('Move Down')])),
              const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 16, color: Colors.blue), SizedBox(width: 8), Text('Edit', style: TextStyle(color: Colors.blue))])),
              const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 16, color: Colors.red), SizedBox(width: 8), Text('Delete', style: TextStyle(color: Colors.red))])),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // COLUMN B: FLOW GROUPS
  // ============================================================================

  Widget _buildColumnB() {
    return Container(
      color: const Color(0xFFF5F5F5),
      child: ReorderableListView.builder(
        padding: const EdgeInsets.all(16),
        buildDefaultDragHandles: false,
        itemCount: _flows.length,
        onReorder: _reorderFlows,
        itemBuilder: (context, index) {
          return ReorderableDragStartListener(
            key: ValueKey(_flows[index].id),
            index: index,
            child: _buildFlowCard(_flows[index]),
          );
        },
      ),
    );
  }

  Widget _buildFlowCard(FlowConfig flow) {
    final isSelected = _selectedFlowId == flow.id;
    final isDragOver = _dragOverFlowId == flow.id;

    return DragTarget<String>(
      onWillAccept: (stageId) {
        if (stageId == null) return false;
        setState(() => _dragOverFlowId = flow.id);
        return true;
      },
      onLeave: (_) => setState(() => _dragOverFlowId = null),
      onAccept: (stageId) {
        _addStageToFlow(stageId, flow.id);
        setState(() => _dragOverFlowId = null);
      },
      builder: (context, candidateData, rejectedData) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDragOver ? const Color(0xFF2196F3) : isSelected ? const Color(0xFF1A1A1A) : const Color(0xFFE0E0E0),
              width: isDragOver || isSelected ? 2 : 1,
            ),
            boxShadow: isSelected ? [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))] : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildFlowHeader(flow, isSelected),
              if (flow.isExpanded) ...[
                _buildFlowStages(flow),
                if (isDragOver || flow.stageIds.isEmpty) _buildDropZone(flow, isDragOver),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildFlowHeader(FlowConfig flow, bool isSelected) {
    return InkWell(
      onTap: () {
        setState(() {
          _selectedFlowId = flow.id;
          _selectedStageId = null;
        });
      },
      borderRadius: BorderRadius.only(
        topLeft: const Radius.circular(9),
        topRight: const Radius.circular(9),
        bottomLeft: Radius.circular(flow.isExpanded ? 0 : 9),
        bottomRight: Radius.circular(flow.isExpanded ? 0 : 9),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1A1A1A) : const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(9),
            topRight: const Radius.circular(9),
            bottomLeft: Radius.circular(flow.isExpanded ? 0 : 9),
            bottomRight: Radius.circular(flow.isExpanded ? 0 : 9),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.drag_indicator, size: 16, color: isSelected ? Colors.white54 : const Color(0xFFCCCCCC)),
            const SizedBox(width: 8),
            Text(flow.icon, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Flow ${flow.position} › ${flow.name}',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : const Color(0xFF1A1A1A)),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white.withOpacity(0.15) : _getFlowTypeColor(flow.type).withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _getFlowTypeName(flow.type),
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isSelected ? Colors.white70 : _getFlowTypeColor(flow.type)),
              ),
            ),
            // Show LLM badge for LLM-type flows
            if (flow.type == FlowType.llm && flow.config['provider'] != null) ...[
              const SizedBox(width: 6),
              Builder(
                builder: (context) {
                  final providerId = flow.config['provider'] as String?;
                  final provider = _llmProviders.where((p) => p.id == providerId).firstOrNull;
                  final providerName = provider?.name ?? providerId ?? 'Unknown';
                  final providerColor = provider?.getBrandColor() ?? Colors.blue;

                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isSelected ? providerColor.withOpacity(0.3) : providerColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: providerColor.withOpacity(0.3), width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (provider != null)
                          Icon(provider.getIcon(), size: 10, color: isSelected ? Colors.white70 : providerColor)
                        else
                          Icon(Icons.memory, size: 10, color: isSelected ? Colors.white70 : providerColor),
                        const SizedBox(width: 4),
                        Text(
                          providerName,
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: isSelected ? Colors.white70 : providerColor),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
            const SizedBox(width: 4),
            // Expand/Collapse button
            IconButton(
              onPressed: () => _toggleFlowExpanded(flow.id),
              icon: Icon(
                flow.isExpanded ? Icons.expand_less : Icons.expand_more,
                size: 18,
                color: isSelected ? Colors.white54 : const Color(0xFF666666),
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              tooltip: flow.isExpanded ? 'Collapse' : 'Expand',
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, size: 18, color: isSelected ? Colors.white54 : const Color(0xFF999999)),
              onSelected: (value) {
                switch (value) {
                  case 'delete':
                    _showDeleteFlowDialog(flow);
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(children: [Icon(Icons.delete, size: 16, color: Colors.red), SizedBox(width: 8), Text('Delete', style: TextStyle(color: Colors.red))]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlowStages(FlowConfig flow) {
    if (flow.stageIds.isEmpty) return const SizedBox.shrink();

    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      buildDefaultDragHandles: false,
      itemCount: flow.stageIds.length,
      onReorder: (oldIndex, newIndex) => _reorderStageInFlow(flow.id, oldIndex, newIndex),
      itemBuilder: (context, index) {
        final stageId = flow.stageIds[index];
        final stage = _getStage(stageId);
        if (stage == null) return const SizedBox.shrink();

        return ReorderableDragStartListener(
          key: ValueKey('${flow.id}_$stageId'),
          index: index,
          child: _buildFlowStageCard(flow, stage),
        );
      },
    );
  }

  Widget _buildFlowStageCard(FlowConfig flow, PipelineStage stage) {
    final isSelected = _selectedStageId == stage.id && _selectedFlowId == flow.id;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedStageId = stage.id;
          _selectedFlowId = flow.id;
        });
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE3F2FD) : Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isSelected ? const Color(0xFF2196F3) : const Color(0xFFE0E0E0)),
        ),
        child: Row(
          children: [
            const Icon(Icons.drag_indicator, size: 14, color: Color(0xFFCCCCCC)),
            const SizedBox(width: 6),
            Container(
              width: 22, height: 22,
              decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(4)),
              child: Center(child: Text('${stage.number}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white))),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(stage.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF1A1A1A)))),
            SizedBox(
              width: 36, height: 20,
              child: Switch(
                value: stage.enabled,
                onChanged: (value) {
                  setState(() {
                    _stagesMap[stage.id] = stage.copyWith(enabled: value);
                    _isDirty = true;
                  });
                },
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                activeColor: const Color(0xFF00AA66),
              ),
            ),
            const SizedBox(width: 4),
            InkWell(
              onTap: () {
                setState(() {
                  _selectedStageId = stage.id;
                  _selectedFlowId = flow.id;
                });
              },
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.settings, size: 16, color: isSelected ? const Color(0xFF2196F3) : const Color(0xFF999999)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropZone(FlowConfig flow, bool isDragOver) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 4, 10, 10),
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: isDragOver ? const Color(0xFFE3F2FD) : const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isDragOver ? const Color(0xFF2196F3) : const Color(0xFFE0E0E0), style: isDragOver ? BorderStyle.solid : BorderStyle.none),
      ),
      child: Center(
        child: Text(isDragOver ? 'Drop here' : 'Drop stage here', style: TextStyle(fontSize: 12, color: isDragOver ? const Color(0xFF2196F3) : const Color(0xFF999999))),
      ),
    );
  }

  Color _getFlowTypeColor(FlowType type) {
    switch (type) {
      case FlowType.rules: return const Color(0xFF9C27B0);
      case FlowType.llm: return const Color(0xFF2196F3);
      case FlowType.passthrough: return const Color(0xFF4CAF50);
      case FlowType.database: return const Color(0xFFFF9800);
    }
  }

  String _getFlowTypeName(FlowType type) {
    switch (type) {
      case FlowType.rules: return 'Rules';
      case FlowType.llm: return 'LLM';
      case FlowType.passthrough: return 'Pass';
      case FlowType.database: return 'DB';
    }
  }

  // ============================================================================
  // COLUMN C: SETTINGS PANEL
  // ============================================================================

  Widget _buildColumnC() {
    return Container(
      color: Colors.white,
      child: _selectedStageId != null
          ? _buildStageSettings()
          : _selectedFlowId != null
              ? _buildFlowSettings()
              : _buildNoSelection(),
    );
  }

  Widget _buildNoSelection() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.touch_app_outlined, size: 48, color: Color(0xFFE0E0E0)),
          SizedBox(height: 12),
          Text('Select a Flow or Stage', style: TextStyle(fontSize: 14, color: Color(0xFF999999))),
          SizedBox(height: 4),
          Text('to configure', style: TextStyle(fontSize: 12, color: Color(0xFFCCCCCC))),
        ],
      ),
    );
  }

  Widget _buildFlowSettings() {
    final flow = _flows.firstWhere((f) => f.id == _selectedFlowId);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(flow.icon, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('FLOW SETTINGS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF999999), letterSpacing: 0.5)),
                    Text('Flow ${flow.position} › ${flow.name}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildTextField(label: 'Name', value: flow.name, onChanged: (value) {
            _updateFlowProperty(flow.id, (f) => f.copyWith(name: value));
          }),
          const SizedBox(height: 16),
          _buildDropdown(
            label: 'Type', value: flow.type.name,
            items: FlowType.values.map((t) => t.name).toList(),
            icons: const ['📋', '🤖', '➡️', '🗄️'],
            onChanged: (value) {
              final newType = FlowType.values.firstWhere((t) => t.name == value);
              final newIcon = const {'rules': '📋', 'llm': '🤖', 'passthrough': '➡️', 'database': '🗄️'}[value] ?? '📋';
              _updateFlowProperty(flow.id, (f) => f.copyWith(type: newType, icon: newIcon));
            },
          ),
          const SizedBox(height: 16),
          _buildToggle(label: 'Enabled', value: flow.enabled, onChanged: (value) {
            _updateFlowProperty(flow.id, (f) => f.copyWith(enabled: value));
          }),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          Text('${_getFlowTypeName(flow.type).toUpperCase()} SETTINGS', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF999999), letterSpacing: 0.5)),
          const SizedBox(height: 16),
          _buildFlowTypeSettings(flow),
        ],
      ),
    );
  }

  Widget _buildFlowTypeSettings(FlowConfig flow) {
    switch (flow.type) {
      case FlowType.rules:
        return Column(children: [
          _buildDropdown(label: 'Execution Mode', value: flow.config['execution_mode'] ?? 'sequential', items: const ['sequential', 'parallel'], onChanged: (v) { setState(() { flow.config['execution_mode'] = v; _isDirty = true; }); }),
          const SizedBox(height: 16),
          _buildDropdown(label: 'On Error', value: flow.config['on_error'] ?? 'continue', items: const ['continue', 'stop', 'fallback'], onChanged: (v) { setState(() { flow.config['on_error'] = v; _isDirty = true; }); }),
        ]);
      case FlowType.llm:
        // Get provider IDs and names from Firebase
        final providerIds = _llmProviders.map((p) => p.id).toList();
        final providerLabels = _llmProviders.map((p) => p.name).toList();
        final currentProvider = flow.config['provider'] ?? 'groq';

        // Get models for selected provider
        final selectedProvider = _llmProviders.where((p) => p.id == currentProvider).firstOrNull;
        final models = selectedProvider?.models ?? [];
        final defaultModel = selectedProvider?.defaultModel ?? '';

        return Column(children: [
          if (_isLoadingProviders)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_llmProviders.isEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning, color: Colors.orange, size: 18),
                  SizedBox(width: 8),
                  Expanded(child: Text('No LLM providers enabled. Enable them in LLMs Status page.', style: TextStyle(fontSize: 12, color: Colors.orange))),
                ],
              ),
            )
          else ...[
            _buildDropdown(
              label: 'Provider',
              value: providerIds.contains(currentProvider) ? currentProvider : (providerIds.isNotEmpty ? providerIds.first : ''),
              items: providerIds,
              itemLabels: providerLabels,
              onChanged: (v) {
                setState(() {
                  flow.config['provider'] = v;
                  // Clear model when provider changes - will use default
                  flow.config.remove('model');
                  _isDirty = true;
                });
              },
            ),
            const SizedBox(height: 12),
            // Show default model info
            if (selectedProvider != null)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: selectedProvider.getBrandColor().withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: selectedProvider.getBrandColor().withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(selectedProvider.getIcon(), size: 16, color: selectedProvider.getBrandColor()),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Default Model: $defaultModel', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: selectedProvider.getBrandColor())),
                          Text('Available: ${models.join(", ")}', style: const TextStyle(fontSize: 10, color: Color(0xFF666666))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 16),
          _buildNumberField(label: 'Temperature', value: (flow.config['temperature'] ?? 0.7).toDouble(), min: 0, max: 2, onChanged: (v) { setState(() { flow.config['temperature'] = v; _isDirty = true; }); }),
          const SizedBox(height: 16),
          _buildNumberField(label: 'Max Tokens', value: (flow.config['max_tokens'] ?? 1024).toDouble(), min: 100, max: 16000, onChanged: (v) { setState(() { flow.config['max_tokens'] = v.toInt(); _isDirty = true; }); }),
        ]);
      case FlowType.passthrough:
        return _buildDropdown(
          label: 'Source Flow', value: flow.config['source_flow_id'] ?? '',
          items: _flows.where((f) => f.id != flow.id).map((f) => f.id).toList(),
          itemLabels: _flows.where((f) => f.id != flow.id).map((f) => 'Flow ${f.position} - ${f.name}').toList(),
          onChanged: (v) { setState(() { flow.config['source_flow_id'] = v; _isDirty = true; }); },
        );
      case FlowType.database:
        return Column(children: [
          _buildDropdown(label: 'Primary Source', value: flow.config['primary_source'] ?? 'firestore', items: const ['firestore', 'redis', 'pinecone'], onChanged: (v) { setState(() { flow.config['primary_source'] = v; _isDirty = true; }); }),
          const SizedBox(height: 16),
          _buildToggle(label: 'Cache Results', value: flow.config['cache_results'] ?? true, onChanged: (v) { setState(() { flow.config['cache_results'] = v; _isDirty = true; }); }),
        ]);
    }
  }

  Widget _buildStageSettings() {
    final stage = _getStage(_selectedStageId!);
    if (stage == null) return _buildNoSelection();
    final flow = _getFlowForStage(stage.id);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(6)),
                child: Center(child: Text('${stage.number}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('STAGE SETTINGS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF999999), letterSpacing: 0.5)),
                    Text(stage.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (flow != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(4)),
              child: Text('In Flow: ${flow.icon} ${flow.name}', style: const TextStyle(fontSize: 12, color: Color(0xFF666666))),
            ),
          const SizedBox(height: 16),
          _buildToggle(label: 'Enabled', value: stage.enabled, onChanged: (v) { setState(() { _stagesMap[stage.id] = stage.copyWith(enabled: v); _isDirty = true; }); }),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          const Text('OUTPUT FIELDS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF999999), letterSpacing: 0.5)),
          const SizedBox(height: 12),
          ...stage.fields.map((field) => _buildFieldItem(field)),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          const Text('QUICK SETTINGS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF999999), letterSpacing: 0.5)),
          const SizedBox(height: 16),
          ...stage.controls.map((control) => Padding(padding: const EdgeInsets.only(bottom: 16), child: _buildControlItem(stage.id, control))),
          const SizedBox(height: 24),
          if (flow != null)
            OutlinedButton.icon(
              onPressed: () => _confirmRemoveStageFromFlow(stage.id, flow.id),
              icon: const Icon(Icons.remove_circle_outline, size: 16),
              label: const Text('Remove from Flow'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
            ),
        ],
      ),
    );
  }

  Widget _buildFieldItem(StageField field) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: const Color(0xFFFAFAFA), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFFE0E0E0))),
      child: Row(
        children: [
          Icon(field.required ? Icons.check_box : Icons.check_box_outline_blank, size: 18, color: field.required ? const Color(0xFF00AA66) : const Color(0xFFCCCCCC)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(field.key, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A))),
                Text(field.description, style: const TextStyle(fontSize: 11, color: Color(0xFF999999))),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: const Color(0xFFE0E0E0), borderRadius: BorderRadius.circular(3)),
            child: Text(field.type, style: const TextStyle(fontSize: 10, color: Color(0xFF666666))),
          ),
        ],
      ),
    );
  }

  Widget _buildControlItem(String stageId, StageControl control) {
    switch (control.type) {
      case 'toggle':
        final boolValue = _getControlValue(stageId, control.key, control.defaultValue) as bool;
        return _buildToggle(
          label: control.label,
          value: boolValue,
          description: control.description,
          onChanged: (v) => _setControlValue(stageId, control.key, v),
        );
      case 'number':
        final numValue = (_getControlValue(stageId, control.key, control.defaultValue) as num).toDouble();
        return _buildNumberField(
          label: control.label,
          value: numValue,
          min: control.min ?? 0,
          max: control.max ?? 100,
          description: control.description,
          onChanged: (v) => _setControlValue(stageId, control.key, v),
        );
      case 'select':
        final strValue = _getControlValue(stageId, control.key, control.defaultValue) as String;
        return _buildDropdown(
          label: control.label,
          value: strValue,
          items: control.options ?? [],
          description: control.description,
          onChanged: (v) => _setControlValue(stageId, control.key, v),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  // ============================================================================
  // TEST PANEL
  // ============================================================================

  Widget _buildCollapsedTestBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      decoration: BoxDecoration(color: const Color(0xFF2D2D2D), borderRadius: BorderRadius.circular(8)),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _isTestPanelCollapsed = false),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: const Row(
              children: [
                Icon(Icons.science_outlined, color: Colors.white70, size: 18),
                SizedBox(width: 10),
                Text('Test Panel', style: TextStyle(fontSize: 13, color: Colors.white70, fontWeight: FontWeight.w500)),
                Spacer(),
                Icon(Icons.expand_less, color: Colors.white54, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTestPanel() {
    return Container(
      decoration: const BoxDecoration(color: Color(0xFF2D2D2D), borderRadius: BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12))),
      child: Column(
        children: [
          // Test panel header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF444444)))),
            child: Row(
              children: [
                const Icon(Icons.science_outlined, color: Colors.white70, size: 18),
                const SizedBox(width: 10),
                const Text('Test Panel', style: TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                  child: const Text('Uses flow LLM settings', style: TextStyle(fontSize: 10, color: Colors.white54)),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => setState(() => _isTestPanelCollapsed = true),
                  icon: const Icon(Icons.expand_more, color: Colors.white54, size: 20),
                  tooltip: 'Collapse',
                ),
              ],
            ),
          ),
          // Input bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _testInputController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Enter test message...',
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                      filled: true,
                      fillColor: const Color(0xFF3D3D3D),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onSubmitted: (_) => _runTest(),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _isRunningTest ? null : _runTest,
                  icon: _isRunningTest
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.play_arrow, size: 18),
                  label: Text(_isRunningTest ? 'Running...' : 'Run Test'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00AA66),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
          // Results area
          Expanded(
            child: _testResult == null
                ? const Center(child: Text('Run a test to see results', style: TextStyle(color: Colors.white38, fontSize: 13)))
                : _buildTestResults(),
          ),
        ],
      ),
    );
  }

  Widget _buildTestResults() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final responseWidth = constraints.maxWidth * _responseColumnRatio;
        final metadataWidth = constraints.maxWidth * _metadataColumnRatio;
        final jsonWidth = constraints.maxWidth - responseWidth - metadataWidth - 16;

        return Row(
          children: [
            SizedBox(width: responseWidth, child: _buildResponseColumn()),
            _buildTestVerticalDivider(onDrag: (delta) {
              setState(() {
                final d = delta / constraints.maxWidth;
                _responseColumnRatio = (_responseColumnRatio + d).clamp(0.2, 0.5);
              });
            }),
            SizedBox(width: metadataWidth, child: _buildMetadataColumn()),
            _buildTestVerticalDivider(onDrag: (delta) {
              setState(() {
                final d = delta / constraints.maxWidth;
                _metadataColumnRatio = (_metadataColumnRatio + d).clamp(0.2, 0.5);
              });
            }),
            Expanded(child: _buildJsonColumn()),
          ],
        );
      },
    );
  }

  Widget _buildTestVerticalDivider({required Function(double) onDrag}) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
        child: Container(width: 8, color: const Color(0xFF3D3D3D), child: const Center(child: Icon(Icons.drag_indicator, size: 10, color: Color(0xFF666666)))),
      ),
    );
  }

  Widget _buildResponseColumn() {
    final response = _testResult?['response'] ?? '';
    final latency = _testResult?['latency_ms'] ?? 0;

    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('RESPONSE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white54, letterSpacing: 0.5)),
              const SizedBox(width: 8),
              _buildCopyButton(response.toString()),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFF00AA66).withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                child: Text('${latency}ms', style: const TextStyle(fontSize: 10, color: Color(0xFF00AA66), fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFF3D3D3D), borderRadius: BorderRadius.circular(8)),
              child: SingleChildScrollView(
                child: Text(response.toString(), style: const TextStyle(fontSize: 13, color: Colors.white, height: 1.5)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataColumn() {
    final stages = _testResult?['stages'] as Map<String, dynamic>? ?? {};

    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('METADATA BY STAGE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white54, letterSpacing: 0.5)),
              const SizedBox(width: 8),
              _buildCopyButton(const JsonEncoder.withIndent('  ').convert(stages)),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFF3D3D3D), borderRadius: BorderRadius.circular(8)),
              child: ListView(
                children: stages.entries.map((entry) {
                  final stageData = entry.value as Map<String, dynamic>;
                  final stageName = stageData['name'] ?? entry.key;
                  final latency = stageData['latency_ms'] ?? 0;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2D2D2D),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF444444)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(4)),
                              child: Text(entry.key.replaceAll('stage_', ''), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(stageName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white))),
                            Text('${latency}ms', style: const TextStyle(fontSize: 10, color: Colors.white38)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...stageData.entries.where((e) => e.key != 'name' && e.key != 'latency_ms').map((field) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 80,
                                  child: Text(field.key, style: const TextStyle(fontSize: 11, color: Colors.white38)),
                                ),
                                Expanded(
                                  child: Text(
                                    _formatValue(field.value),
                                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatValue(dynamic value) {
    if (value is List) {
      return value.isEmpty ? '[]' : value.map((e) => e.toString()).join(', ');
    }
    if (value is Map) {
      return jsonEncode(value);
    }
    return value.toString();
  }

  Widget _buildJsonColumn() {
    final jsonStr = const JsonEncoder.withIndent('  ').convert(_testResult);
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('FULL JSON', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white54, letterSpacing: 0.5)),
              const SizedBox(width: 8),
              _buildCopyButton(jsonStr),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFF3D3D3D), borderRadius: BorderRadius.circular(8)),
              child: SingleChildScrollView(
                child: SelectableText(
                  jsonStr,
                  style: const TextStyle(fontSize: 11, color: Colors.white70, fontFamily: 'monospace'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCopyButton(String content) {
    return InkWell(
      onTap: () {
        Clipboard.setData(ClipboardData(text: content));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Copied to clipboard'),
            duration: Duration(seconds: 1),
            backgroundColor: Color(0xFF00AA66),
          ),
        );
      },
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.copy, size: 12, color: Colors.white54),
            SizedBox(width: 4),
            Text('Copy', style: TextStyle(fontSize: 10, color: Colors.white54)),
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // FORM CONTROLS
  // ============================================================================

  Widget _buildTextField({required String label, required String value, String? description, required Function(String) onChanged}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF666666))),
        const SizedBox(height: 6),
        TextField(
          controller: TextEditingController(text: value),
          onChanged: onChanged,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
          ),
        ),
        if (description != null) ...[const SizedBox(height: 4), Text(description, style: const TextStyle(fontSize: 11, color: Color(0xFF999999)))],
      ],
    );
  }

  Widget _buildNumberField({required String label, required double value, required double min, required double max, String? description, required Function(double) onChanged}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF666666))),
            const Spacer(),
            Text(value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A))),
          ],
        ),
        const SizedBox(height: 6),
        SliderTheme(
          data: SliderThemeData(trackHeight: 4, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8), activeTrackColor: const Color(0xFF1A1A1A), inactiveTrackColor: const Color(0xFFE0E0E0), thumbColor: const Color(0xFF1A1A1A)),
          child: Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged),
        ),
        if (description != null) Text(description, style: const TextStyle(fontSize: 11, color: Color(0xFF999999))),
      ],
    );
  }

  Widget _buildDropdown({required String label, required String value, required List<String> items, List<String>? itemLabels, List<String>? icons, String? description, required Function(String) onChanged}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF666666))),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE0E0E0)), borderRadius: BorderRadius.circular(6)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: items.contains(value) ? value : (items.isNotEmpty ? items.first : null),
              isExpanded: true,
              icon: const Icon(Icons.expand_more, size: 18),
              style: const TextStyle(fontSize: 13, color: Color(0xFF1A1A1A)),
              items: items.asMap().entries.map((entry) {
                final i = entry.key;
                final item = entry.value;
                return DropdownMenuItem(
                  value: item,
                  child: Row(
                    children: [
                      if (icons != null && i < icons.length) ...[Text(icons[i]), const SizedBox(width: 8)],
                      Text(itemLabels != null && i < itemLabels.length ? itemLabels[i] : item),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (v) { if (v != null) onChanged(v); },
            ),
          ),
        ),
        if (description != null) ...[const SizedBox(height: 4), Text(description, style: const TextStyle(fontSize: 11, color: Color(0xFF999999)))],
      ],
    );
  }

  Widget _buildToggle({required String label, required bool value, String? description, required Function(bool) onChanged}) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF1A1A1A))),
              if (description != null) Text(description, style: const TextStyle(fontSize: 11, color: Color(0xFF999999))),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged, activeColor: const Color(0xFF00AA66)),
      ],
    );
  }
}
