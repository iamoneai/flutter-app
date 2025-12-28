// IAMONEAI - Flow Config Service
// Manages pipeline flows in Firebase: config/pipeline/flows
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Flow type enum
enum FlowType { rules, llm, passthrough, database }

/// Flow role enum
enum FlowRole { executor, orchestrator, router, reasoning, logger }

/// Pipeline flow configuration from Firebase
class FlowConfig {
  final String id;
  final String name;
  final String description;
  final String icon;
  final String color;
  final int position;
  final bool enabled;
  final FlowType type;
  final FlowRole role;
  final List<String> stageIds;
  final Map<String, dynamic> config;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // UI state (not persisted)
  bool isExpanded;

  FlowConfig({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    required this.position,
    required this.enabled,
    required this.type,
    required this.role,
    required this.stageIds,
    required this.config,
    this.createdAt,
    this.updatedAt,
    this.isExpanded = true,
  });

  factory FlowConfig.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return FlowConfig(
      id: doc.id,
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      icon: data['icon'] ?? '📋',
      color: data['color'] ?? '#666666',
      position: data['position'] ?? 0,
      enabled: data['enabled'] ?? true,
      type: _parseFlowType(data['type']),
      role: _parseFlowRole(data['role']),
      stageIds: List<String>.from(data['stageIds'] ?? []),
      config: Map<String, dynamic>.from(data['config'] ?? {}),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'id': id,
    'name': name,
    'description': description,
    'icon': icon,
    'color': color,
    'position': position,
    'enabled': enabled,
    'type': type.name,
    'role': role.name,
    'stageIds': stageIds,
    'config': config,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  static FlowType _parseFlowType(String? type) {
    switch (type) {
      case 'rules': return FlowType.rules;
      case 'llm': return FlowType.llm;
      case 'passthrough': return FlowType.passthrough;
      case 'database': return FlowType.database;
      default: return FlowType.rules;
    }
  }

  static FlowRole _parseFlowRole(String? role) {
    switch (role) {
      case 'executor': return FlowRole.executor;
      case 'orchestrator': return FlowRole.orchestrator;
      case 'router': return FlowRole.router;
      case 'reasoning': return FlowRole.reasoning;
      case 'logger': return FlowRole.logger;
      default: return FlowRole.executor;
    }
  }

  /// Get color as Color object
  Color getColor() {
    try {
      final hex = color.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (e) {
      return const Color(0xFF666666);
    }
  }

  FlowConfig copyWith({
    String? name,
    String? description,
    String? icon,
    String? color,
    int? position,
    bool? enabled,
    FlowType? type,
    FlowRole? role,
    List<String>? stageIds,
    Map<String, dynamic>? config,
    bool? isExpanded,
  }) {
    return FlowConfig(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      position: position ?? this.position,
      enabled: enabled ?? this.enabled,
      type: type ?? this.type,
      role: role ?? this.role,
      stageIds: stageIds ?? List.from(this.stageIds),
      config: config ?? Map.from(this.config),
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      isExpanded: isExpanded ?? this.isExpanded,
    );
  }
}

/// Service to manage pipeline flows in Firebase
class FlowConfigService {
  static final FlowConfigService _instance = FlowConfigService._internal();
  factory FlowConfigService() => _instance;
  FlowConfigService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _flowsRef =>
      _db.collection('config').doc('pipeline').collection('flows');

  /// Get all flows ordered by position
  Future<List<FlowConfig>> getFlows() async {
    try {
      final snapshot = await _flowsRef.get();
      final flows = snapshot.docs
          .map((doc) => FlowConfig.fromFirestore(doc))
          .toList();
      flows.sort((a, b) => a.position.compareTo(b.position));
      return flows;
    } catch (e) {
      debugPrint('Error loading flows: $e');
      return [];
    }
  }

  /// Get a single flow by ID
  Future<FlowConfig?> getFlow(String id) async {
    try {
      final doc = await _flowsRef.doc(id).get();
      if (doc.exists) {
        return FlowConfig.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      debugPrint('Error loading flow $id: $e');
      return null;
    }
  }

  /// Create a new flow
  Future<bool> createFlow(FlowConfig flow) async {
    try {
      final data = flow.toFirestore();
      data['createdAt'] = FieldValue.serverTimestamp();
      await _flowsRef.doc(flow.id).set(data);
      return true;
    } catch (e) {
      debugPrint('Error creating flow: $e');
      return false;
    }
  }

  /// Update an existing flow
  Future<bool> updateFlow(FlowConfig flow) async {
    try {
      await _flowsRef.doc(flow.id).update(flow.toFirestore());
      return true;
    } catch (e) {
      debugPrint('Error updating flow: $e');
      return false;
    }
  }

  /// Update only specific fields of a flow
  Future<bool> updateFlowFields(String id, Map<String, dynamic> fields) async {
    try {
      fields['updatedAt'] = FieldValue.serverTimestamp();
      await _flowsRef.doc(id).update(fields);
      return true;
    } catch (e) {
      debugPrint('Error updating flow fields: $e');
      return false;
    }
  }

  /// Update flow positions (batch update multiple flows)
  Future<bool> updateFlowPositions(List<FlowConfig> flows) async {
    try {
      final batch = _db.batch();
      for (final flow in flows) {
        batch.update(_flowsRef.doc(flow.id), {
          'position': flow.position,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      return true;
    } catch (e) {
      debugPrint('Error updating flow positions: $e');
      return false;
    }
  }

  /// Delete a flow
  Future<bool> deleteFlow(String id) async {
    try {
      await _flowsRef.doc(id).delete();
      return true;
    } catch (e) {
      debugPrint('Error deleting flow: $e');
      return false;
    }
  }

  /// Stream of all flows (for real-time updates)
  Stream<List<FlowConfig>> streamFlows() {
    return _flowsRef
        .snapshots()
        .map((snapshot) {
          final flows = snapshot.docs
              .map((doc) => FlowConfig.fromFirestore(doc))
              .toList();
          flows.sort((a, b) => a.position.compareTo(b.position));
          return flows;
        });
  }

  /// Generate a flow ID from name
  static String generateFlowId(String name) {
    final cleanName = name.toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return 'flow_$cleanName';
  }
}
