// IAMONEAI - Canvas Config Service
// Handles saving and loading visual logic canvases to/from Firebase

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Canvas configuration for Firebase storage
class CanvasConfig {
  final String id;
  final String name;
  final String? description;
  final List<LaneConfig> lanes;
  final List<NodeConfig> nodes;
  final List<WireConfig> wires;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, dynamic> settings;

  CanvasConfig({
    required this.id,
    required this.name,
    this.description,
    required this.lanes,
    required this.nodes,
    required this.wires,
    required this.createdAt,
    required this.updatedAt,
    this.settings = const {},
  });

  factory CanvasConfig.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CanvasConfig(
      id: doc.id,
      name: data['name'] ?? 'Untitled',
      description: data['description'],
      lanes: (data['lanes'] as List<dynamic>? ?? [])
          .map((l) => LaneConfig.fromMap(l as Map<String, dynamic>))
          .toList(),
      nodes: (data['nodes'] as List<dynamic>? ?? [])
          .map((n) => NodeConfig.fromMap(n as Map<String, dynamic>))
          .toList(),
      wires: (data['wires'] as List<dynamic>? ?? [])
          .map((w) => WireConfig.fromMap(w as Map<String, dynamic>))
          .toList(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      settings: data['settings'] as Map<String, dynamic>? ?? {},
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'description': description,
      'lanes': lanes.map((l) => l.toMap()).toList(),
      'nodes': nodes.map((n) => n.toMap()).toList(),
      'wires': wires.map((w) => w.toMap()).toList(),
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'settings': settings,
    };
  }

  CanvasConfig copyWith({
    String? name,
    String? description,
    List<LaneConfig>? lanes,
    List<NodeConfig>? nodes,
    List<WireConfig>? wires,
    Map<String, dynamic>? settings,
  }) {
    return CanvasConfig(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      lanes: lanes ?? this.lanes,
      nodes: nodes ?? this.nodes,
      wires: wires ?? this.wires,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      settings: settings ?? this.settings,
    );
  }
}

/// Lane configuration for storage
class LaneConfig {
  final String id;
  final String templateId;
  final String name;
  final String icon;
  final String color;
  final String type;
  final String role;
  final double y;
  final double height;
  final bool isCollapsed;
  final List<String> nodeIds;
  final Map<String, dynamic> config;

  LaneConfig({
    required this.id,
    required this.templateId,
    required this.name,
    required this.icon,
    required this.color,
    required this.type,
    required this.role,
    required this.y,
    required this.height,
    this.isCollapsed = false,
    this.nodeIds = const [],
    this.config = const {},
  });

  factory LaneConfig.fromMap(Map<String, dynamic> map) {
    return LaneConfig(
      id: map['id'] ?? '',
      templateId: map['templateId'] ?? '',
      name: map['name'] ?? '',
      icon: map['icon'] ?? '',
      color: map['color'] ?? '#666666',
      type: map['type'] ?? 'rules',
      role: map['role'] ?? 'executor',
      y: (map['y'] as num?)?.toDouble() ?? 0,
      height: (map['height'] as num?)?.toDouble() ?? 120,
      isCollapsed: map['isCollapsed'] ?? false,
      nodeIds: List<String>.from(map['nodeIds'] ?? []),
      config: map['config'] as Map<String, dynamic>? ?? {},
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'templateId': templateId,
      'name': name,
      'icon': icon,
      'color': color,
      'type': type,
      'role': role,
      'y': y,
      'height': height,
      'isCollapsed': isCollapsed,
      'nodeIds': nodeIds,
      'config': config,
    };
  }
}

/// Node configuration for storage
class NodeConfig {
  final String id;
  final String templateId;
  final String name;
  final String icon;
  final String color;
  final String category;
  final String? laneId;
  final double x;
  final double y;
  final double width;
  final double height;
  final List<PortConfig> inputPorts;
  final List<PortConfig> outputPorts;
  final Map<String, dynamic> properties;

  NodeConfig({
    required this.id,
    required this.templateId,
    required this.name,
    required this.icon,
    required this.color,
    required this.category,
    this.laneId,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.inputPorts = const [],
    this.outputPorts = const [],
    this.properties = const {},
  });

  factory NodeConfig.fromMap(Map<String, dynamic> map) {
    return NodeConfig(
      id: map['id'] ?? '',
      templateId: map['templateId'] ?? '',
      name: map['name'] ?? '',
      icon: map['icon'] ?? '',
      color: map['color'] ?? '#666666',
      category: map['category'] ?? 'logic',
      laneId: map['laneId'],
      x: (map['x'] as num?)?.toDouble() ?? 0,
      y: (map['y'] as num?)?.toDouble() ?? 0,
      width: (map['width'] as num?)?.toDouble() ?? 180,
      height: (map['height'] as num?)?.toDouble() ?? 80,
      inputPorts: (map['inputPorts'] as List<dynamic>? ?? [])
          .map((p) => PortConfig.fromMap(p as Map<String, dynamic>))
          .toList(),
      outputPorts: (map['outputPorts'] as List<dynamic>? ?? [])
          .map((p) => PortConfig.fromMap(p as Map<String, dynamic>))
          .toList(),
      properties: map['properties'] as Map<String, dynamic>? ?? {},
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'templateId': templateId,
      'name': name,
      'icon': icon,
      'color': color,
      'category': category,
      'laneId': laneId,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'inputPorts': inputPorts.map((p) => p.toMap()).toList(),
      'outputPorts': outputPorts.map((p) => p.toMap()).toList(),
      'properties': properties,
    };
  }
}

/// Port configuration for storage
class PortConfig {
  final String key;
  final String label;
  final String dataType;
  final bool required;

  PortConfig({
    required this.key,
    required this.label,
    required this.dataType,
    this.required = false,
  });

  factory PortConfig.fromMap(Map<String, dynamic> map) {
    return PortConfig(
      key: map['key'] ?? '',
      label: map['label'] ?? '',
      dataType: map['dataType'] ?? 'any',
      required: map['required'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'key': key,
      'label': label,
      'dataType': dataType,
      'required': required,
    };
  }
}

/// Wire configuration for storage
class WireConfig {
  final String id;
  final String fromNodeId;
  final String fromPortKey;
  final String toNodeId;
  final String toPortKey;
  final String? color;

  WireConfig({
    required this.id,
    required this.fromNodeId,
    required this.fromPortKey,
    required this.toNodeId,
    required this.toPortKey,
    this.color,
  });

  factory WireConfig.fromMap(Map<String, dynamic> map) {
    return WireConfig(
      id: map['id'] ?? '',
      fromNodeId: map['fromNodeId'] ?? '',
      fromPortKey: map['fromPortKey'] ?? '',
      toNodeId: map['toNodeId'] ?? '',
      toPortKey: map['toPortKey'] ?? '',
      color: map['color'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fromNodeId': fromNodeId,
      'fromPortKey': fromPortKey,
      'toNodeId': toNodeId,
      'toPortKey': toPortKey,
      'color': color,
    };
  }
}

/// Service for managing canvas configurations in Firebase
class CanvasConfigService {
  static final CanvasConfigService _instance = CanvasConfigService._internal();
  factory CanvasConfigService() => _instance;
  CanvasConfigService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'visual_canvases';

  /// Get all canvases
  Future<List<CanvasConfig>> getCanvases() async {
    try {
      final snapshot = await _firestore
          .collection(_collection)
          .orderBy('updatedAt', descending: true)
          .get();

      return snapshot.docs.map((doc) => CanvasConfig.fromFirestore(doc)).toList();
    } catch (e) {
      debugPrint('Error loading canvases: $e');
      return [];
    }
  }

  /// Get a single canvas by ID
  Future<CanvasConfig?> getCanvas(String id) async {
    try {
      final doc = await _firestore.collection(_collection).doc(id).get();
      if (!doc.exists) return null;
      return CanvasConfig.fromFirestore(doc);
    } catch (e) {
      debugPrint('Error loading canvas: $e');
      return null;
    }
  }

  /// Save a canvas (create or update)
  Future<String> saveCanvas(CanvasConfig canvas) async {
    try {
      if (canvas.id.isEmpty || canvas.id == 'new') {
        // Create new
        final docRef = await _firestore.collection(_collection).add(canvas.toFirestore());
        debugPrint('Created new canvas: ${docRef.id}');
        return docRef.id;
      } else {
        // Update existing
        await _firestore.collection(_collection).doc(canvas.id).set(canvas.toFirestore());
        debugPrint('Updated canvas: ${canvas.id}');
        return canvas.id;
      }
    } catch (e) {
      debugPrint('Error saving canvas: $e');
      rethrow;
    }
  }

  /// Delete a canvas
  Future<void> deleteCanvas(String id) async {
    try {
      await _firestore.collection(_collection).doc(id).delete();
      debugPrint('Deleted canvas: $id');
    } catch (e) {
      debugPrint('Error deleting canvas: $e');
      rethrow;
    }
  }

  /// Duplicate a canvas
  Future<String> duplicateCanvas(String id, String newName) async {
    try {
      final original = await getCanvas(id);
      if (original == null) throw Exception('Canvas not found');

      final duplicate = CanvasConfig(
        id: '',
        name: newName,
        description: original.description,
        lanes: original.lanes,
        nodes: original.nodes,
        wires: original.wires,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        settings: original.settings,
      );

      return await saveCanvas(duplicate);
    } catch (e) {
      debugPrint('Error duplicating canvas: $e');
      rethrow;
    }
  }

  // ============================================================================
  // SNAPSHOTS / VERSION HISTORY
  // ============================================================================

  /// Save a snapshot of the canvas
  Future<String> saveSnapshot({
    required String canvasId,
    required String snapshotName,
    required CanvasConfig canvas,
  }) async {
    try {
      final snapshotData = {
        'canvasId': canvasId,
        'name': snapshotName,
        'canvas': canvas.toFirestore(),
        'createdAt': Timestamp.fromDate(DateTime.now()),
      };

      final docRef = await _firestore
          .collection(_collection)
          .doc(canvasId)
          .collection('snapshots')
          .add(snapshotData);

      debugPrint('Saved snapshot: ${docRef.id} for canvas: $canvasId');
      return docRef.id;
    } catch (e) {
      debugPrint('Error saving snapshot: $e');
      rethrow;
    }
  }

  /// Get all snapshots for a canvas
  Future<List<CanvasSnapshot>> getSnapshots(String canvasId) async {
    try {
      final snapshot = await _firestore
          .collection(_collection)
          .doc(canvasId)
          .collection('snapshots')
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs.map((doc) => CanvasSnapshot.fromFirestore(doc)).toList();
    } catch (e) {
      debugPrint('Error loading snapshots: $e');
      return [];
    }
  }

  /// Restore a canvas from a snapshot
  Future<CanvasConfig?> restoreFromSnapshot({
    required String canvasId,
    required String snapshotId,
  }) async {
    try {
      final doc = await _firestore
          .collection(_collection)
          .doc(canvasId)
          .collection('snapshots')
          .doc(snapshotId)
          .get();

      if (!doc.exists) return null;

      final data = doc.data() as Map<String, dynamic>;
      final canvasData = data['canvas'] as Map<String, dynamic>;

      return CanvasConfig(
        id: canvasId,
        name: canvasData['name'] ?? 'Restored',
        description: canvasData['description'],
        lanes: (canvasData['lanes'] as List<dynamic>? ?? [])
            .map((l) => LaneConfig.fromMap(l as Map<String, dynamic>))
            .toList(),
        nodes: (canvasData['nodes'] as List<dynamic>? ?? [])
            .map((n) => NodeConfig.fromMap(n as Map<String, dynamic>))
            .toList(),
        wires: (canvasData['wires'] as List<dynamic>? ?? [])
            .map((w) => WireConfig.fromMap(w as Map<String, dynamic>))
            .toList(),
        createdAt: (canvasData['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        updatedAt: DateTime.now(),
        settings: canvasData['settings'] as Map<String, dynamic>? ?? {},
      );
    } catch (e) {
      debugPrint('Error restoring snapshot: $e');
      return null;
    }
  }

  /// Delete a snapshot
  Future<void> deleteSnapshot({
    required String canvasId,
    required String snapshotId,
  }) async {
    try {
      await _firestore
          .collection(_collection)
          .doc(canvasId)
          .collection('snapshots')
          .doc(snapshotId)
          .delete();
      debugPrint('Deleted snapshot: $snapshotId');
    } catch (e) {
      debugPrint('Error deleting snapshot: $e');
      rethrow;
    }
  }
}

/// Snapshot metadata
class CanvasSnapshot {
  final String id;
  final String canvasId;
  final String name;
  final DateTime createdAt;

  CanvasSnapshot({
    required this.id,
    required this.canvasId,
    required this.name,
    required this.createdAt,
  });

  factory CanvasSnapshot.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CanvasSnapshot(
      id: doc.id,
      canvasId: data['canvasId'] ?? '',
      name: data['name'] ?? 'Unnamed Snapshot',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
