// IAMONEAI - Visual Logic Builder Data Models
// Defines the structure for a node-based visual pipeline editor

import 'package:cloud_firestore/cloud_firestore.dart';

/// ============================================================================
/// CANVAS - The workspace containing all lanes and nodes
/// ============================================================================
class BuilderCanvas {
  final String id;
  final String name;
  final String description;
  final CanvasSettings settings;
  final List<Lane> lanes;
  final List<Wire> wires;
  final CanvasMetadata metadata;

  BuilderCanvas({
    required this.id,
    required this.name,
    this.description = '',
    required this.settings,
    required this.lanes,
    required this.wires,
    required this.metadata,
  });

  factory BuilderCanvas.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return BuilderCanvas(
      id: doc.id,
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      settings: CanvasSettings.fromMap(data['settings'] ?? {}),
      lanes: (data['lanes'] as List<dynamic>?)
          ?.map((l) => Lane.fromMap(l as Map<String, dynamic>))
          .toList() ?? [],
      wires: (data['wires'] as List<dynamic>?)
          ?.map((w) => Wire.fromMap(w as Map<String, dynamic>))
          .toList() ?? [],
      metadata: CanvasMetadata.fromMap(data['metadata'] ?? {}),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'name': name,
    'description': description,
    'settings': settings.toMap(),
    'lanes': lanes.map((l) => l.toMap()).toList(),
    'wires': wires.map((w) => w.toMap()).toList(),
    'metadata': metadata.toMap(),
    'updatedAt': FieldValue.serverTimestamp(),
  };

  BuilderCanvas copyWith({
    String? name,
    String? description,
    CanvasSettings? settings,
    List<Lane>? lanes,
    List<Wire>? wires,
    CanvasMetadata? metadata,
  }) {
    return BuilderCanvas(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      settings: settings ?? this.settings,
      lanes: lanes ?? this.lanes,
      wires: wires ?? this.wires,
      metadata: metadata ?? this.metadata,
    );
  }
}

/// Canvas-level settings
class CanvasSettings {
  final double zoom;
  final double panX;
  final double panY;
  final bool snapToGrid;
  final double gridSize;
  final bool showMinimap;
  final String theme; // 'light', 'dark', 'system'

  CanvasSettings({
    this.zoom = 1.0,
    this.panX = 0,
    this.panY = 0,
    this.snapToGrid = true,
    this.gridSize = 20,
    this.showMinimap = true,
    this.theme = 'light',
  });

  factory CanvasSettings.fromMap(Map<String, dynamic> map) {
    return CanvasSettings(
      zoom: (map['zoom'] as num?)?.toDouble() ?? 1.0,
      panX: (map['panX'] as num?)?.toDouble() ?? 0,
      panY: (map['panY'] as num?)?.toDouble() ?? 0,
      snapToGrid: map['snapToGrid'] ?? true,
      gridSize: (map['gridSize'] as num?)?.toDouble() ?? 20,
      showMinimap: map['showMinimap'] ?? true,
      theme: map['theme'] ?? 'light',
    );
  }

  Map<String, dynamic> toMap() => {
    'zoom': zoom,
    'panX': panX,
    'panY': panY,
    'snapToGrid': snapToGrid,
    'gridSize': gridSize,
    'showMinimap': showMinimap,
    'theme': theme,
  };
}

/// Canvas metadata for versioning and audit
class CanvasMetadata {
  final String version;
  final String createdBy;
  final DateTime? createdAt;
  final String lastModifiedBy;
  final DateTime? lastModifiedAt;
  final bool isPublished;
  final String? publishedVersion;

  CanvasMetadata({
    this.version = '1.0.0',
    this.createdBy = '',
    this.createdAt,
    this.lastModifiedBy = '',
    this.lastModifiedAt,
    this.isPublished = false,
    this.publishedVersion,
  });

  factory CanvasMetadata.fromMap(Map<String, dynamic> map) {
    return CanvasMetadata(
      version: map['version'] ?? '1.0.0',
      createdBy: map['createdBy'] ?? '',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      lastModifiedBy: map['lastModifiedBy'] ?? '',
      lastModifiedAt: (map['lastModifiedAt'] as Timestamp?)?.toDate(),
      isPublished: map['isPublished'] ?? false,
      publishedVersion: map['publishedVersion'],
    );
  }

  Map<String, dynamic> toMap() => {
    'version': version,
    'createdBy': createdBy,
    'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
    'lastModifiedBy': lastModifiedBy,
    'lastModifiedAt': lastModifiedAt != null ? Timestamp.fromDate(lastModifiedAt!) : null,
    'isPublished': isPublished,
    'publishedVersion': publishedVersion,
  };
}

/// ============================================================================
/// LANE - Horizontal swimlane container (maps to Flow)
/// ============================================================================
enum LaneType { rules, llm, passthrough, database }
enum LaneRole { executor, orchestrator, router, reasoning, logger }

class Lane {
  final String id;
  final String name;
  final String description;
  final String icon;
  final String color;
  final int position;
  final bool enabled;
  final bool collapsed;
  final LaneType type;
  final LaneRole role;
  final List<String> nodeIds; // Ordered list of nodes in this lane
  final LaneConfig config;
  final double height; // Visual height of the lane

  Lane({
    required this.id,
    required this.name,
    this.description = '',
    this.icon = '📋',
    this.color = '#666666',
    required this.position,
    this.enabled = true,
    this.collapsed = false,
    required this.type,
    required this.role,
    this.nodeIds = const [],
    required this.config,
    this.height = 150,
  });

  factory Lane.fromMap(Map<String, dynamic> map) {
    return Lane(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      description: map['description'] ?? '',
      icon: map['icon'] ?? '📋',
      color: map['color'] ?? '#666666',
      position: map['position'] ?? 0,
      enabled: map['enabled'] ?? true,
      collapsed: map['collapsed'] ?? false,
      type: LaneType.values.firstWhere(
        (t) => t.name == map['type'],
        orElse: () => LaneType.rules,
      ),
      role: LaneRole.values.firstWhere(
        (r) => r.name == map['role'],
        orElse: () => LaneRole.executor,
      ),
      nodeIds: List<String>.from(map['nodeIds'] ?? []),
      config: LaneConfig.fromMap(map['config'] ?? {}),
      height: (map['height'] as num?)?.toDouble() ?? 150,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'description': description,
    'icon': icon,
    'color': color,
    'position': position,
    'enabled': enabled,
    'collapsed': collapsed,
    'type': type.name,
    'role': role.name,
    'nodeIds': nodeIds,
    'config': config.toMap(),
    'height': height,
  };

  Lane copyWith({
    String? name,
    String? description,
    String? icon,
    String? color,
    int? position,
    bool? enabled,
    bool? collapsed,
    LaneType? type,
    LaneRole? role,
    List<String>? nodeIds,
    LaneConfig? config,
    double? height,
  }) {
    return Lane(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      position: position ?? this.position,
      enabled: enabled ?? this.enabled,
      collapsed: collapsed ?? this.collapsed,
      type: type ?? this.type,
      role: role ?? this.role,
      nodeIds: nodeIds ?? List.from(this.nodeIds),
      config: config ?? this.config,
      height: height ?? this.height,
    );
  }
}

/// Lane-specific configuration based on type
class LaneConfig {
  // Rules lane config
  final String? executionMode; // 'sequential', 'parallel'
  final String? onError; // 'continue', 'stop', 'fallback'
  final int? timeoutMs;

  // LLM lane config
  final String? provider;
  final String? model;
  final double? temperature;
  final int? maxTokens;
  final String? fallbackProvider;
  final String? fallbackModel;
  final String? responseFormat; // 'json', 'text'

  // Passthrough lane config
  final String? sourceLane;
  final List<String>? fieldsToUse;

  // Database lane config
  final String? primarySource;
  final String? secondarySource;
  final String? vectorSource;
  final bool? cacheResults;
  final int? cacheTtlSeconds;

  LaneConfig({
    this.executionMode,
    this.onError,
    this.timeoutMs,
    this.provider,
    this.model,
    this.temperature,
    this.maxTokens,
    this.fallbackProvider,
    this.fallbackModel,
    this.responseFormat,
    this.sourceLane,
    this.fieldsToUse,
    this.primarySource,
    this.secondarySource,
    this.vectorSource,
    this.cacheResults,
    this.cacheTtlSeconds,
  });

  factory LaneConfig.fromMap(Map<String, dynamic> map) {
    return LaneConfig(
      executionMode: map['execution_mode'],
      onError: map['on_error'],
      timeoutMs: map['timeout_ms'],
      provider: map['provider'],
      model: map['model'],
      temperature: (map['temperature'] as num?)?.toDouble(),
      maxTokens: map['max_tokens'],
      fallbackProvider: map['fallback_provider'],
      fallbackModel: map['fallback_model'],
      responseFormat: map['response_format'],
      sourceLane: map['source_lane'],
      fieldsToUse: map['fields_to_use'] != null
          ? List<String>.from(map['fields_to_use'])
          : null,
      primarySource: map['primary_source'],
      secondarySource: map['secondary_source'],
      vectorSource: map['vector_source'],
      cacheResults: map['cache_results'],
      cacheTtlSeconds: map['cache_ttl_seconds'],
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{};
    if (executionMode != null) map['execution_mode'] = executionMode;
    if (onError != null) map['on_error'] = onError;
    if (timeoutMs != null) map['timeout_ms'] = timeoutMs;
    if (provider != null) map['provider'] = provider;
    if (model != null) map['model'] = model;
    if (temperature != null) map['temperature'] = temperature;
    if (maxTokens != null) map['max_tokens'] = maxTokens;
    if (fallbackProvider != null) map['fallback_provider'] = fallbackProvider;
    if (fallbackModel != null) map['fallback_model'] = fallbackModel;
    if (responseFormat != null) map['response_format'] = responseFormat;
    if (sourceLane != null) map['source_lane'] = sourceLane;
    if (fieldsToUse != null) map['fields_to_use'] = fieldsToUse;
    if (primarySource != null) map['primary_source'] = primarySource;
    if (secondarySource != null) map['secondary_source'] = secondarySource;
    if (vectorSource != null) map['vector_source'] = vectorSource;
    if (cacheResults != null) map['cache_results'] = cacheResults;
    if (cacheTtlSeconds != null) map['cache_ttl_seconds'] = cacheTtlSeconds;
    return map;
  }
}

/// ============================================================================
/// NODE - Individual processing unit (maps to Stage)
/// ============================================================================
enum NodeCategory { logic, ai, router, data, custom }

class Node {
  final String id;
  final String templateId; // Reference to node template (e.g., 'stage_classifier')
  final String name;
  final String description;
  final String icon;
  final String color;
  final NodeCategory category;
  final NodePosition position;
  final NodeSize size;
  final bool enabled;
  final bool locked; // Prevent editing
  final List<Port> inputPorts;
  final List<Port> outputPorts;
  final Map<String, dynamic> properties; // Configurable values
  final NodeState state; // Runtime state for visual feedback

  Node({
    required this.id,
    required this.templateId,
    required this.name,
    this.description = '',
    this.icon = '⚙️',
    this.color = '#666666',
    required this.category,
    required this.position,
    this.size = const NodeSize(),
    this.enabled = true,
    this.locked = false,
    this.inputPorts = const [],
    this.outputPorts = const [],
    this.properties = const {},
    this.state = const NodeState(),
  });

  factory Node.fromMap(Map<String, dynamic> map) {
    return Node(
      id: map['id'] ?? '',
      templateId: map['templateId'] ?? '',
      name: map['name'] ?? '',
      description: map['description'] ?? '',
      icon: map['icon'] ?? '⚙️',
      color: map['color'] ?? '#666666',
      category: NodeCategory.values.firstWhere(
        (c) => c.name == map['category'],
        orElse: () => NodeCategory.logic,
      ),
      position: NodePosition.fromMap(map['position'] ?? {}),
      size: NodeSize.fromMap(map['size'] ?? {}),
      enabled: map['enabled'] ?? true,
      locked: map['locked'] ?? false,
      inputPorts: (map['inputPorts'] as List<dynamic>?)
          ?.map((p) => Port.fromMap(p as Map<String, dynamic>))
          .toList() ?? [],
      outputPorts: (map['outputPorts'] as List<dynamic>?)
          ?.map((p) => Port.fromMap(p as Map<String, dynamic>))
          .toList() ?? [],
      properties: Map<String, dynamic>.from(map['properties'] ?? {}),
      state: NodeState.fromMap(map['state'] ?? {}),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'templateId': templateId,
    'name': name,
    'description': description,
    'icon': icon,
    'color': color,
    'category': category.name,
    'position': position.toMap(),
    'size': size.toMap(),
    'enabled': enabled,
    'locked': locked,
    'inputPorts': inputPorts.map((p) => p.toMap()).toList(),
    'outputPorts': outputPorts.map((p) => p.toMap()).toList(),
    'properties': properties,
    'state': state.toMap(),
  };

  Node copyWith({
    String? templateId,
    String? name,
    String? description,
    String? icon,
    String? color,
    NodeCategory? category,
    NodePosition? position,
    NodeSize? size,
    bool? enabled,
    bool? locked,
    List<Port>? inputPorts,
    List<Port>? outputPorts,
    Map<String, dynamic>? properties,
    NodeState? state,
  }) {
    return Node(
      id: id,
      templateId: templateId ?? this.templateId,
      name: name ?? this.name,
      description: description ?? this.description,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      category: category ?? this.category,
      position: position ?? this.position,
      size: size ?? this.size,
      enabled: enabled ?? this.enabled,
      locked: locked ?? this.locked,
      inputPorts: inputPorts ?? this.inputPorts,
      outputPorts: outputPorts ?? this.outputPorts,
      properties: properties ?? Map.from(this.properties),
      state: state ?? this.state,
    );
  }
}

/// Node position on the canvas
class NodePosition {
  final double x;
  final double y;

  const NodePosition({this.x = 0, this.y = 0});

  factory NodePosition.fromMap(Map<String, dynamic> map) {
    return NodePosition(
      x: (map['x'] as num?)?.toDouble() ?? 0,
      y: (map['y'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {'x': x, 'y': y};

  NodePosition copyWith({double? x, double? y}) {
    return NodePosition(x: x ?? this.x, y: y ?? this.y);
  }
}

/// Node dimensions
class NodeSize {
  final double width;
  final double height;

  const NodeSize({this.width = 200, this.height = 100});

  factory NodeSize.fromMap(Map<String, dynamic> map) {
    return NodeSize(
      width: (map['width'] as num?)?.toDouble() ?? 200,
      height: (map['height'] as num?)?.toDouble() ?? 100,
    );
  }

  Map<String, dynamic> toMap() => {'width': width, 'height': height};
}

/// Runtime state for visual feedback
class NodeState {
  final bool isRunning;
  final bool hasError;
  final bool isComplete;
  final String? errorMessage;
  final int? executionTimeMs;
  final Map<String, dynamic>? lastOutput;

  const NodeState({
    this.isRunning = false,
    this.hasError = false,
    this.isComplete = false,
    this.errorMessage,
    this.executionTimeMs,
    this.lastOutput,
  });

  factory NodeState.fromMap(Map<String, dynamic> map) {
    return NodeState(
      isRunning: map['isRunning'] ?? false,
      hasError: map['hasError'] ?? false,
      isComplete: map['isComplete'] ?? false,
      errorMessage: map['errorMessage'],
      executionTimeMs: map['executionTimeMs'],
      lastOutput: map['lastOutput'] != null
          ? Map<String, dynamic>.from(map['lastOutput'])
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
    'isRunning': isRunning,
    'hasError': hasError,
    'isComplete': isComplete,
    'errorMessage': errorMessage,
    'executionTimeMs': executionTimeMs,
    'lastOutput': lastOutput,
  };
}

/// ============================================================================
/// PORT - Connection point on a node
/// ============================================================================
enum PortDirection { input, output }
enum PortDataType { string, number, boolean, array, object, any }

class Port {
  final String id;
  final String key; // Field key (e.g., 'normalized_text')
  final String label;
  final PortDirection direction;
  final PortDataType dataType;
  final bool required;
  final String description;
  final dynamic defaultValue;
  final bool allowMultiple; // Can connect multiple wires

  Port({
    required this.id,
    required this.key,
    required this.label,
    required this.direction,
    this.dataType = PortDataType.any,
    this.required = false,
    this.description = '',
    this.defaultValue,
    this.allowMultiple = false,
  });

  factory Port.fromMap(Map<String, dynamic> map) {
    return Port(
      id: map['id'] ?? '',
      key: map['key'] ?? '',
      label: map['label'] ?? '',
      direction: PortDirection.values.firstWhere(
        (d) => d.name == map['direction'],
        orElse: () => PortDirection.input,
      ),
      dataType: PortDataType.values.firstWhere(
        (t) => t.name == map['dataType'],
        orElse: () => PortDataType.any,
      ),
      required: map['required'] ?? false,
      description: map['description'] ?? '',
      defaultValue: map['defaultValue'],
      allowMultiple: map['allowMultiple'] ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'key': key,
    'label': label,
    'direction': direction.name,
    'dataType': dataType.name,
    'required': required,
    'description': description,
    'defaultValue': defaultValue,
    'allowMultiple': allowMultiple,
  };
}

/// ============================================================================
/// WIRE - Connection between ports
/// ============================================================================
enum WireStyle { bezier, straight, step }

class Wire {
  final String id;
  final String sourceNodeId;
  final String sourcePortId;
  final String targetNodeId;
  final String targetPortId;
  final String? label;
  final String color;
  final WireStyle style;
  final bool animated; // Show flow animation
  final WireCondition? condition; // Optional conditional logic

  Wire({
    required this.id,
    required this.sourceNodeId,
    required this.sourcePortId,
    required this.targetNodeId,
    required this.targetPortId,
    this.label,
    this.color = '#666666',
    this.style = WireStyle.bezier,
    this.animated = false,
    this.condition,
  });

  factory Wire.fromMap(Map<String, dynamic> map) {
    return Wire(
      id: map['id'] ?? '',
      sourceNodeId: map['sourceNodeId'] ?? '',
      sourcePortId: map['sourcePortId'] ?? '',
      targetNodeId: map['targetNodeId'] ?? '',
      targetPortId: map['targetPortId'] ?? '',
      label: map['label'],
      color: map['color'] ?? '#666666',
      style: WireStyle.values.firstWhere(
        (s) => s.name == map['style'],
        orElse: () => WireStyle.bezier,
      ),
      animated: map['animated'] ?? false,
      condition: map['condition'] != null
          ? WireCondition.fromMap(map['condition'])
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'sourceNodeId': sourceNodeId,
    'sourcePortId': sourcePortId,
    'targetNodeId': targetNodeId,
    'targetPortId': targetPortId,
    'label': label,
    'color': color,
    'style': style.name,
    'animated': animated,
    'condition': condition?.toMap(),
  };

  Wire copyWith({
    String? sourceNodeId,
    String? sourcePortId,
    String? targetNodeId,
    String? targetPortId,
    String? label,
    String? color,
    WireStyle? style,
    bool? animated,
    WireCondition? condition,
  }) {
    return Wire(
      id: id,
      sourceNodeId: sourceNodeId ?? this.sourceNodeId,
      sourcePortId: sourcePortId ?? this.sourcePortId,
      targetNodeId: targetNodeId ?? this.targetNodeId,
      targetPortId: targetPortId ?? this.targetPortId,
      label: label ?? this.label,
      color: color ?? this.color,
      style: style ?? this.style,
      animated: animated ?? this.animated,
      condition: condition ?? this.condition,
    );
  }
}

/// Conditional wire execution
class WireCondition {
  final String field; // Field to check
  final String operator; // 'eq', 'neq', 'gt', 'lt', 'gte', 'lte', 'contains', 'matches'
  final dynamic value;

  WireCondition({
    required this.field,
    required this.operator,
    required this.value,
  });

  factory WireCondition.fromMap(Map<String, dynamic> map) {
    return WireCondition(
      field: map['field'] ?? '',
      operator: map['operator'] ?? 'eq',
      value: map['value'],
    );
  }

  Map<String, dynamic> toMap() => {
    'field': field,
    'operator': operator,
    'value': value,
  };
}

/// ============================================================================
/// NODE TEMPLATE - Reusable node definitions (from stages)
/// ============================================================================
class NodeTemplate {
  final String id;
  final String name;
  final String description;
  final String icon;
  final String color;
  final NodeCategory category;
  final List<PortTemplate> inputPorts;
  final List<PortTemplate> outputPorts;
  final List<PropertyDefinition> properties;
  final bool isCustom; // User-created vs system

  NodeTemplate({
    required this.id,
    required this.name,
    this.description = '',
    this.icon = '⚙️',
    this.color = '#666666',
    required this.category,
    this.inputPorts = const [],
    this.outputPorts = const [],
    this.properties = const [],
    this.isCustom = false,
  });

  factory NodeTemplate.fromMap(Map<String, dynamic> map) {
    return NodeTemplate(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      description: map['description'] ?? '',
      icon: map['icon'] ?? '⚙️',
      color: map['color'] ?? '#666666',
      category: NodeCategory.values.firstWhere(
        (c) => c.name == map['category'],
        orElse: () => NodeCategory.logic,
      ),
      inputPorts: (map['inputPorts'] as List<dynamic>?)
          ?.map((p) => PortTemplate.fromMap(p as Map<String, dynamic>))
          .toList() ?? [],
      outputPorts: (map['outputPorts'] as List<dynamic>?)
          ?.map((p) => PortTemplate.fromMap(p as Map<String, dynamic>))
          .toList() ?? [],
      properties: (map['properties'] as List<dynamic>?)
          ?.map((p) => PropertyDefinition.fromMap(p as Map<String, dynamic>))
          .toList() ?? [],
      isCustom: map['isCustom'] ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'description': description,
    'icon': icon,
    'color': color,
    'category': category.name,
    'inputPorts': inputPorts.map((p) => p.toMap()).toList(),
    'outputPorts': outputPorts.map((p) => p.toMap()).toList(),
    'properties': properties.map((p) => p.toMap()).toList(),
    'isCustom': isCustom,
  };

  /// Create a Node instance from this template
  Node createNode(String nodeId, NodePosition position) {
    return Node(
      id: nodeId,
      templateId: id,
      name: name,
      description: description,
      icon: icon,
      color: color,
      category: category,
      position: position,
      inputPorts: inputPorts.map((pt) => pt.createPort('${nodeId}_in_${pt.key}')).toList(),
      outputPorts: outputPorts.map((pt) => pt.createPort('${nodeId}_out_${pt.key}')).toList(),
      properties: {for (var p in properties) p.key: p.defaultValue},
    );
  }
}

/// Port template for creating node ports
class PortTemplate {
  final String key;
  final String label;
  final PortDataType dataType;
  final bool required;
  final String description;
  final dynamic defaultValue;
  final bool allowMultiple;

  PortTemplate({
    required this.key,
    required this.label,
    this.dataType = PortDataType.any,
    this.required = false,
    this.description = '',
    this.defaultValue,
    this.allowMultiple = false,
  });

  factory PortTemplate.fromMap(Map<String, dynamic> map) {
    return PortTemplate(
      key: map['key'] ?? '',
      label: map['label'] ?? '',
      dataType: PortDataType.values.firstWhere(
        (t) => t.name == map['dataType'],
        orElse: () => PortDataType.any,
      ),
      required: map['required'] ?? false,
      description: map['description'] ?? '',
      defaultValue: map['defaultValue'],
      allowMultiple: map['allowMultiple'] ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
    'key': key,
    'label': label,
    'dataType': dataType.name,
    'required': required,
    'description': description,
    'defaultValue': defaultValue,
    'allowMultiple': allowMultiple,
  };

  Port createPort(String portId) {
    return Port(
      id: portId,
      key: key,
      label: label,
      direction: PortDirection.input, // Set by caller
      dataType: dataType,
      required: required,
      description: description,
      defaultValue: defaultValue,
      allowMultiple: allowMultiple,
    );
  }
}

/// Property definition for node configuration
class PropertyDefinition {
  final String key;
  final String label;
  final String type; // 'string', 'number', 'boolean', 'select', 'slider', 'color', 'code'
  final dynamic defaultValue;
  final String description;
  final bool required;
  final List<String>? options; // For 'select' type
  final double? min; // For 'number' and 'slider'
  final double? max;
  final double? step;
  final String? placeholder;
  final String? validationRegex;

  PropertyDefinition({
    required this.key,
    required this.label,
    required this.type,
    this.defaultValue,
    this.description = '',
    this.required = false,
    this.options,
    this.min,
    this.max,
    this.step,
    this.placeholder,
    this.validationRegex,
  });

  factory PropertyDefinition.fromMap(Map<String, dynamic> map) {
    return PropertyDefinition(
      key: map['key'] ?? '',
      label: map['label'] ?? '',
      type: map['type'] ?? 'string',
      defaultValue: map['defaultValue'],
      description: map['description'] ?? '',
      required: map['required'] ?? false,
      options: map['options'] != null ? List<String>.from(map['options']) : null,
      min: (map['min'] as num?)?.toDouble(),
      max: (map['max'] as num?)?.toDouble(),
      step: (map['step'] as num?)?.toDouble(),
      placeholder: map['placeholder'],
      validationRegex: map['validationRegex'],
    );
  }

  Map<String, dynamic> toMap() => {
    'key': key,
    'label': label,
    'type': type,
    'defaultValue': defaultValue,
    'description': description,
    'required': required,
    if (options != null) 'options': options,
    if (min != null) 'min': min,
    if (max != null) 'max': max,
    if (step != null) 'step': step,
    if (placeholder != null) 'placeholder': placeholder,
    if (validationRegex != null) 'validationRegex': validationRegex,
  };
}

/// ============================================================================
/// EXECUTION CONTEXT - Runtime data passed through the pipeline
/// ============================================================================
class ExecutionContext {
  final String executionId;
  final String canvasId;
  final DateTime startedAt;
  final Map<String, NodeExecutionResult> nodeResults;
  final Map<String, dynamic> globalVariables;
  final ExecutionStatus status;
  final String? currentNodeId;
  final List<String> executionPath; // Ordered list of executed nodes

  ExecutionContext({
    required this.executionId,
    required this.canvasId,
    required this.startedAt,
    this.nodeResults = const {},
    this.globalVariables = const {},
    this.status = ExecutionStatus.pending,
    this.currentNodeId,
    this.executionPath = const [],
  });

  Map<String, dynamic> toMap() => {
    'executionId': executionId,
    'canvasId': canvasId,
    'startedAt': Timestamp.fromDate(startedAt),
    'nodeResults': nodeResults.map((k, v) => MapEntry(k, v.toMap())),
    'globalVariables': globalVariables,
    'status': status.name,
    'currentNodeId': currentNodeId,
    'executionPath': executionPath,
  };
}

enum ExecutionStatus { pending, running, completed, failed, cancelled }

class NodeExecutionResult {
  final String nodeId;
  final DateTime startedAt;
  final DateTime? completedAt;
  final bool success;
  final Map<String, dynamic> outputs;
  final String? errorMessage;
  final int? executionTimeMs;

  NodeExecutionResult({
    required this.nodeId,
    required this.startedAt,
    this.completedAt,
    this.success = false,
    this.outputs = const {},
    this.errorMessage,
    this.executionTimeMs,
  });

  Map<String, dynamic> toMap() => {
    'nodeId': nodeId,
    'startedAt': Timestamp.fromDate(startedAt),
    'completedAt': completedAt != null ? Timestamp.fromDate(completedAt!) : null,
    'success': success,
    'outputs': outputs,
    'errorMessage': errorMessage,
    'executionTimeMs': executionTimeMs,
  };
}
