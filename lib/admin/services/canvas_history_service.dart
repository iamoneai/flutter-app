// IAMONEAI - Canvas History Service
// Manages undo/redo operations for the visual logic builder

import 'dart:convert';
import 'dart:ui' show Offset;

/// Types of canvas operations that can be undone/redone
enum CanvasOperationType {
  addNode,
  removeNode,
  moveNode,
  updateNodeProperties,
  addWire,
  removeWire,
  addLane,
  removeLane,
  moveLane,
  updateLaneProperties,
  multipleOperations, // For batch operations
}

/// Represents a single undoable operation
class CanvasOperation {
  final CanvasOperationType type;
  final String? elementId;
  final Map<String, dynamic> beforeState;
  final Map<String, dynamic> afterState;
  final DateTime timestamp;
  final String description;

  CanvasOperation({
    required this.type,
    this.elementId,
    required this.beforeState,
    required this.afterState,
    String? description,
  })  : timestamp = DateTime.now(),
        description = description ?? _getDefaultDescription(type);

  static String _getDefaultDescription(CanvasOperationType type) {
    switch (type) {
      case CanvasOperationType.addNode:
        return 'Add node';
      case CanvasOperationType.removeNode:
        return 'Remove node';
      case CanvasOperationType.moveNode:
        return 'Move node';
      case CanvasOperationType.updateNodeProperties:
        return 'Update node properties';
      case CanvasOperationType.addWire:
        return 'Add connection';
      case CanvasOperationType.removeWire:
        return 'Remove connection';
      case CanvasOperationType.addLane:
        return 'Add lane';
      case CanvasOperationType.removeLane:
        return 'Remove lane';
      case CanvasOperationType.moveLane:
        return 'Move lane';
      case CanvasOperationType.updateLaneProperties:
        return 'Update lane properties';
      case CanvasOperationType.multipleOperations:
        return 'Multiple changes';
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'elementId': elementId,
      'beforeState': beforeState,
      'afterState': afterState,
      'timestamp': timestamp.toIso8601String(),
      'description': description,
    };
  }

  factory CanvasOperation.fromMap(Map<String, dynamic> map) {
    return CanvasOperation(
      type: CanvasOperationType.values.firstWhere(
        (t) => t.name == map['type'],
        orElse: () => CanvasOperationType.multipleOperations,
      ),
      elementId: map['elementId'],
      beforeState: Map<String, dynamic>.from(map['beforeState'] ?? {}),
      afterState: Map<String, dynamic>.from(map['afterState'] ?? {}),
      description: map['description'],
    );
  }
}

/// Callback type for when history state changes
typedef HistoryChangeCallback = void Function(bool canUndo, bool canRedo);

/// Service for managing canvas history (undo/redo)
class CanvasHistoryService {
  final List<CanvasOperation> _undoStack = [];
  final List<CanvasOperation> _redoStack = [];

  static const int maxHistorySize = 50;

  HistoryChangeCallback? onHistoryChange;

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  int get undoCount => _undoStack.length;
  int get redoCount => _redoStack.length;

  /// Get the description of the next undo operation
  String? get undoDescription => _undoStack.isNotEmpty ? _undoStack.last.description : null;

  /// Get the description of the next redo operation
  String? get redoDescription => _redoStack.isNotEmpty ? _redoStack.last.description : null;

  /// Push a new operation onto the undo stack
  void push(CanvasOperation operation) {
    _undoStack.add(operation);

    // Clear redo stack when new operation is performed
    _redoStack.clear();

    // Limit history size
    while (_undoStack.length > maxHistorySize) {
      _undoStack.removeAt(0);
    }

    _notifyChange();
  }

  /// Convenience method to record an add node operation
  void recordAddNode(Map<String, dynamic> nodeState) {
    push(CanvasOperation(
      type: CanvasOperationType.addNode,
      elementId: nodeState['id'] as String?,
      beforeState: {},
      afterState: nodeState,
    ));
  }

  /// Convenience method to record a remove node operation
  void recordRemoveNode(Map<String, dynamic> nodeState) {
    push(CanvasOperation(
      type: CanvasOperationType.removeNode,
      elementId: nodeState['id'] as String?,
      beforeState: nodeState,
      afterState: {},
    ));
  }

  /// Convenience method to record a move node operation
  void recordMoveNode(String nodeId, double oldX, double oldY, double newX, double newY) {
    push(CanvasOperation(
      type: CanvasOperationType.moveNode,
      elementId: nodeId,
      beforeState: {'x': oldX, 'y': oldY},
      afterState: {'x': newX, 'y': newY},
    ));
  }

  /// Convenience method to record an add wire operation
  void recordAddWire(Map<String, dynamic> wireState) {
    push(CanvasOperation(
      type: CanvasOperationType.addWire,
      elementId: wireState['id'] as String?,
      beforeState: {},
      afterState: wireState,
    ));
  }

  /// Convenience method to record a remove wire operation
  void recordRemoveWire(Map<String, dynamic> wireState) {
    push(CanvasOperation(
      type: CanvasOperationType.removeWire,
      elementId: wireState['id'] as String?,
      beforeState: wireState,
      afterState: {},
    ));
  }

  /// Convenience method to record an add lane operation
  void recordAddLane(Map<String, dynamic> laneState) {
    push(CanvasOperation(
      type: CanvasOperationType.addLane,
      elementId: laneState['id'] as String?,
      beforeState: {},
      afterState: laneState,
    ));
  }

  /// Convenience method to record a remove lane operation
  void recordRemoveLane(Map<String, dynamic> laneState) {
    push(CanvasOperation(
      type: CanvasOperationType.removeLane,
      elementId: laneState['id'] as String?,
      beforeState: laneState,
      afterState: {},
    ));
  }

  /// Pop the last operation from the undo stack and return it
  CanvasOperation? undo() {
    if (!canUndo) return null;

    final operation = _undoStack.removeLast();
    _redoStack.add(operation);

    _notifyChange();
    return operation;
  }

  /// Pop the last operation from the redo stack and return it
  CanvasOperation? redo() {
    if (!canRedo) return null;

    final operation = _redoStack.removeLast();
    _undoStack.add(operation);

    _notifyChange();
    return operation;
  }

  /// Clear all history
  void clear() {
    _undoStack.clear();
    _redoStack.clear();
    _notifyChange();
  }

  /// Get a list of recent operations (for display)
  List<CanvasOperation> getRecentOperations({int count = 10}) {
    final start = _undoStack.length > count ? _undoStack.length - count : 0;
    return _undoStack.sublist(start);
  }

  void _notifyChange() {
    onHistoryChange?.call(canUndo, canRedo);
  }

  /// Serialize history to JSON (for persistence)
  String toJson() {
    return jsonEncode({
      'undoStack': _undoStack.map((op) => op.toMap()).toList(),
      'redoStack': _redoStack.map((op) => op.toMap()).toList(),
    });
  }

  /// Load history from JSON
  void fromJson(String json) {
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;

      _undoStack.clear();
      _redoStack.clear();

      for (final op in (data['undoStack'] as List? ?? [])) {
        _undoStack.add(CanvasOperation.fromMap(op as Map<String, dynamic>));
      }

      for (final op in (data['redoStack'] as List? ?? [])) {
        _redoStack.add(CanvasOperation.fromMap(op as Map<String, dynamic>));
      }

      _notifyChange();
    } catch (e) {
      // Ignore invalid JSON
    }
  }
}

/// Clipboard data for copy/paste operations
class CanvasClipboard {
  static final CanvasClipboard _instance = CanvasClipboard._internal();
  factory CanvasClipboard() => _instance;
  CanvasClipboard._internal();

  List<Map<String, dynamic>>? _copiedNodes;
  List<Map<String, dynamic>>? _copiedWires;
  Offset? _copyOrigin;

  bool get hasContent => _copiedNodes != null && _copiedNodes!.isNotEmpty;
  int get nodeCount => _copiedNodes?.length ?? 0;

  /// Copy nodes and their connecting wires
  void copy({
    required List<Map<String, dynamic>> nodes,
    required List<Map<String, dynamic>> wires,
    required Offset origin,
  }) {
    _copiedNodes = nodes.map((n) => Map<String, dynamic>.from(n)).toList();
    _copiedWires = wires.map((w) => Map<String, dynamic>.from(w)).toList();
    _copyOrigin = origin;
  }

  /// Get copied content with offset applied
  ({List<Map<String, dynamic>> nodes, List<Map<String, dynamic>> wires})? paste({
    required Offset targetPosition,
    required String Function() generateId,
  }) {
    if (!hasContent || _copiedNodes == null) return null;

    final offset = _copyOrigin != null
        ? targetPosition - _copyOrigin!
        : Offset.zero;

    // Create ID mapping for nodes
    final idMapping = <String, String>{};

    // Clone nodes with new IDs and positions
    final pastedNodes = _copiedNodes!.map((node) {
      final oldId = node['id'] as String;
      final newId = generateId();
      idMapping[oldId] = newId;

      return {
        ...node,
        'id': newId,
        'x': (node['x'] as num) + offset.dx,
        'y': (node['y'] as num) + offset.dy,
      };
    }).toList();

    // Clone wires with updated node references
    final pastedWires = <Map<String, dynamic>>[];
    if (_copiedWires != null) {
      for (final wire in _copiedWires!) {
        final fromId = wire['fromNodeId'] as String;
        final toId = wire['toNodeId'] as String;

        // Only include wires where both nodes are in the paste set
        if (idMapping.containsKey(fromId) && idMapping.containsKey(toId)) {
          pastedWires.add({
            ...wire,
            'id': generateId(),
            'fromNodeId': idMapping[fromId],
            'toNodeId': idMapping[toId],
          });
        }
      }
    }

    return (nodes: pastedNodes, wires: pastedWires);
  }

  void clear() {
    _copiedNodes = null;
    _copiedWires = null;
    _copyOrigin = null;
  }
}
