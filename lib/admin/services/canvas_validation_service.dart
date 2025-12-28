// IAMONEAI - Canvas Validation Service
// Validates visual logic pipelines for common issues

/// Severity levels for validation issues
enum ValidationSeverity {
  error,   // Pipeline cannot execute
  warning, // Pipeline may not work as expected
  info,    // Suggestion for improvement
}

/// Types of validation issues
enum ValidationIssueType {
  disconnectedNode,
  missingRequiredInput,
  cycleDetected,
  orphanWire,
  emptyPipeline,
  noOutputNode,
  duplicateConnection,
  invalidWireType,
}

/// A single validation issue
class ValidationIssue {
  final ValidationIssueType type;
  final ValidationSeverity severity;
  final String message;
  final String? elementId;
  final String? elementType; // 'node', 'wire', 'lane'
  final String? suggestion;

  const ValidationIssue({
    required this.type,
    required this.severity,
    required this.message,
    this.elementId,
    this.elementType,
    this.suggestion,
  });

  @override
  String toString() => '[$severity] $message';
}

/// Result of validation
class ValidationResult {
  final bool isValid;
  final List<ValidationIssue> issues;
  final int errorCount;
  final int warningCount;
  final int infoCount;

  ValidationResult({
    required this.isValid,
    required this.issues,
  })  : errorCount = issues.where((i) => i.severity == ValidationSeverity.error).length,
        warningCount = issues.where((i) => i.severity == ValidationSeverity.warning).length,
        infoCount = issues.where((i) => i.severity == ValidationSeverity.info).length;

  /// Get issues for a specific element
  List<ValidationIssue> getIssuesForElement(String elementId) {
    return issues.where((i) => i.elementId == elementId).toList();
  }

  /// Get the highest severity issue for an element
  ValidationSeverity? getHighestSeverityForElement(String elementId) {
    final elementIssues = getIssuesForElement(elementId);
    if (elementIssues.isEmpty) return null;

    if (elementIssues.any((i) => i.severity == ValidationSeverity.error)) {
      return ValidationSeverity.error;
    }
    if (elementIssues.any((i) => i.severity == ValidationSeverity.warning)) {
      return ValidationSeverity.warning;
    }
    return ValidationSeverity.info;
  }
}

/// Node data for validation
class ValidationNode {
  final String id;
  final String name;
  final String templateId;
  final List<ValidationPort> inputPorts;
  final List<ValidationPort> outputPorts;

  const ValidationNode({
    required this.id,
    required this.name,
    required this.templateId,
    required this.inputPorts,
    required this.outputPorts,
  });
}

/// Port data for validation
class ValidationPort {
  final String key;
  final String label;
  final bool required;

  const ValidationPort({
    required this.key,
    required this.label,
    required this.required,
  });
}

/// Wire data for validation
class ValidationWire {
  final String id;
  final String fromNodeId;
  final String fromPortKey;
  final String toNodeId;
  final String toPortKey;

  const ValidationWire({
    required this.id,
    required this.fromNodeId,
    required this.fromPortKey,
    required this.toNodeId,
    required this.toPortKey,
  });
}

/// Service for validating canvas pipelines
class CanvasValidationService {
  /// Validate the entire canvas
  ValidationResult validate({
    required List<ValidationNode> nodes,
    required List<ValidationWire> wires,
  }) {
    final issues = <ValidationIssue>[];

    // Check for empty pipeline
    if (nodes.isEmpty) {
      issues.add(const ValidationIssue(
        type: ValidationIssueType.emptyPipeline,
        severity: ValidationSeverity.warning,
        message: 'Pipeline is empty',
        suggestion: 'Add nodes to create a pipeline',
      ));
      return ValidationResult(isValid: true, issues: issues);
    }

    // Run all validation checks
    issues.addAll(_checkDisconnectedNodes(nodes, wires));
    issues.addAll(_checkMissingRequiredInputs(nodes, wires));
    issues.addAll(_checkCycles(nodes, wires));
    issues.addAll(_checkOrphanWires(nodes, wires));
    issues.addAll(_checkDuplicateConnections(wires));

    // Pipeline is valid if there are no errors
    final isValid = !issues.any((i) => i.severity == ValidationSeverity.error);

    return ValidationResult(isValid: isValid, issues: issues);
  }

  /// Check for nodes with no connections
  List<ValidationIssue> _checkDisconnectedNodes(
    List<ValidationNode> nodes,
    List<ValidationWire> wires,
  ) {
    final issues = <ValidationIssue>[];

    for (final node in nodes) {
      final hasInput = wires.any((w) => w.toNodeId == node.id);
      final hasOutput = wires.any((w) => w.fromNodeId == node.id);

      // First node in pipeline might not have inputs
      // Last node in pipeline might not have outputs
      // But a node with neither is definitely disconnected
      if (!hasInput && !hasOutput && nodes.length > 1) {
        issues.add(ValidationIssue(
          type: ValidationIssueType.disconnectedNode,
          severity: ValidationSeverity.warning,
          message: '${node.name} is not connected to the pipeline',
          elementId: node.id,
          elementType: 'node',
          suggestion: 'Connect this node to other nodes or remove it',
        ));
      }
    }

    return issues;
  }

  /// Check for missing required inputs
  List<ValidationIssue> _checkMissingRequiredInputs(
    List<ValidationNode> nodes,
    List<ValidationWire> wires,
  ) {
    final issues = <ValidationIssue>[];

    for (final node in nodes) {
      for (final port in node.inputPorts) {
        if (port.required) {
          final isConnected = wires.any(
            (w) => w.toNodeId == node.id && w.toPortKey == port.key,
          );

          if (!isConnected) {
            // Check if this is the first node (entry point)
            final hasAnyInput = wires.any((w) => w.toNodeId == node.id);
            if (hasAnyInput) {
              // Node has some inputs but missing this required one
              issues.add(ValidationIssue(
                type: ValidationIssueType.missingRequiredInput,
                severity: ValidationSeverity.error,
                message: '${node.name} is missing required input: ${port.label}',
                elementId: node.id,
                elementType: 'node',
                suggestion: 'Connect a wire to the ${port.label} input',
              ));
            }
          }
        }
      }
    }

    return issues;
  }

  /// Check for cycles in the pipeline using DFS
  List<ValidationIssue> _checkCycles(
    List<ValidationNode> nodes,
    List<ValidationWire> wires,
  ) {
    final issues = <ValidationIssue>[];

    // Build adjacency list
    final adjacency = <String, List<String>>{};
    for (final node in nodes) {
      adjacency[node.id] = [];
    }
    for (final wire in wires) {
      adjacency[wire.fromNodeId]?.add(wire.toNodeId);
    }

    // DFS to detect cycles
    final visited = <String>{};
    final recursionStack = <String>{};
    final cycleNodes = <String>{};

    bool dfs(String nodeId) {
      visited.add(nodeId);
      recursionStack.add(nodeId);

      for (final neighbor in adjacency[nodeId] ?? []) {
        if (!visited.contains(neighbor)) {
          if (dfs(neighbor)) {
            cycleNodes.add(nodeId);
            return true;
          }
        } else if (recursionStack.contains(neighbor)) {
          cycleNodes.add(nodeId);
          cycleNodes.add(neighbor);
          return true;
        }
      }

      recursionStack.remove(nodeId);
      return false;
    }

    for (final node in nodes) {
      if (!visited.contains(node.id)) {
        dfs(node.id);
      }
    }

    // Report cycle issues
    if (cycleNodes.isNotEmpty) {
      issues.add(ValidationIssue(
        type: ValidationIssueType.cycleDetected,
        severity: ValidationSeverity.error,
        message: 'Cycle detected in pipeline involving ${cycleNodes.length} node(s)',
        suggestion: 'Remove connections that create circular dependencies',
      ));

      for (final nodeId in cycleNodes) {
        final node = nodes.firstWhere((n) => n.id == nodeId);
        issues.add(ValidationIssue(
          type: ValidationIssueType.cycleDetected,
          severity: ValidationSeverity.error,
          message: '${node.name} is part of a cycle',
          elementId: nodeId,
          elementType: 'node',
        ));
      }
    }

    return issues;
  }

  /// Check for wires connected to non-existent nodes
  List<ValidationIssue> _checkOrphanWires(
    List<ValidationNode> nodes,
    List<ValidationWire> wires,
  ) {
    final issues = <ValidationIssue>[];
    final nodeIds = nodes.map((n) => n.id).toSet();

    for (final wire in wires) {
      if (!nodeIds.contains(wire.fromNodeId)) {
        issues.add(ValidationIssue(
          type: ValidationIssueType.orphanWire,
          severity: ValidationSeverity.error,
          message: 'Wire connected to missing source node',
          elementId: wire.id,
          elementType: 'wire',
          suggestion: 'Remove this orphan wire',
        ));
      }

      if (!nodeIds.contains(wire.toNodeId)) {
        issues.add(ValidationIssue(
          type: ValidationIssueType.orphanWire,
          severity: ValidationSeverity.error,
          message: 'Wire connected to missing target node',
          elementId: wire.id,
          elementType: 'wire',
          suggestion: 'Remove this orphan wire',
        ));
      }
    }

    return issues;
  }

  /// Check for duplicate connections
  List<ValidationIssue> _checkDuplicateConnections(List<ValidationWire> wires) {
    final issues = <ValidationIssue>[];
    final seen = <String>{};

    for (final wire in wires) {
      final key = '${wire.fromNodeId}:${wire.fromPortKey}->${wire.toNodeId}:${wire.toPortKey}';

      if (seen.contains(key)) {
        issues.add(ValidationIssue(
          type: ValidationIssueType.duplicateConnection,
          severity: ValidationSeverity.warning,
          message: 'Duplicate connection detected',
          elementId: wire.id,
          elementType: 'wire',
          suggestion: 'Remove the duplicate wire',
        ));
      } else {
        seen.add(key);
      }
    }

    return issues;
  }
}

/// Auto-layout algorithm for organizing nodes
class CanvasAutoLayout {
  static const double nodeWidth = 180;
  static const double nodeHeight = 80;
  static const double horizontalGap = 60;
  static const double verticalGap = 40;
  static const double laneHeight = 120;
  static const double startX = 80;
  static const double startY = 30;

  /// Calculate new positions for all nodes using a layered layout
  Map<String, ({double x, double y})> calculateLayout({
    required List<ValidationNode> nodes,
    required List<ValidationWire> wires,
  }) {
    if (nodes.isEmpty) return {};

    // Build adjacency lists
    final outgoing = <String, List<String>>{};
    final incoming = <String, List<String>>{};

    for (final node in nodes) {
      outgoing[node.id] = [];
      incoming[node.id] = [];
    }

    for (final wire in wires) {
      outgoing[wire.fromNodeId]?.add(wire.toNodeId);
      incoming[wire.toNodeId]?.add(wire.fromNodeId);
    }

    // Assign layers using topological sort
    final layers = _assignLayers(nodes, outgoing, incoming);

    // Position nodes within layers
    return _positionNodes(layers);
  }

  /// Assign nodes to layers based on dependencies
  Map<int, List<String>> _assignLayers(
    List<ValidationNode> nodes,
    Map<String, List<String>> outgoing,
    Map<String, List<String>> incoming,
  ) {
    final nodeLayer = <String, int>{};
    final layers = <int, List<String>>{};

    // Find entry nodes (no incoming edges)
    final entryNodes = nodes
        .where((n) => incoming[n.id]?.isEmpty ?? true)
        .map((n) => n.id)
        .toList();

    // If no entry nodes, just use the first node
    if (entryNodes.isEmpty && nodes.isNotEmpty) {
      entryNodes.add(nodes.first.id);
    }

    // BFS to assign layers
    final queue = <String>[];
    for (final nodeId in entryNodes) {
      nodeLayer[nodeId] = 0;
      queue.add(nodeId);
    }

    while (queue.isNotEmpty) {
      final nodeId = queue.removeAt(0);
      final currentLayer = nodeLayer[nodeId]!;

      for (final nextId in outgoing[nodeId] ?? []) {
        final nextLayer = currentLayer + 1;

        if (!nodeLayer.containsKey(nextId) || nodeLayer[nextId]! < nextLayer) {
          nodeLayer[nextId] = nextLayer;
          if (!queue.contains(nextId)) {
            queue.add(nextId);
          }
        }
      }
    }

    // Handle any unassigned nodes (disconnected)
    for (final node in nodes) {
      if (!nodeLayer.containsKey(node.id)) {
        // Find the rightmost layer and add it there
        final maxLayer = nodeLayer.values.isEmpty ? 0 : nodeLayer.values.reduce((a, b) => a > b ? a : b);
        nodeLayer[node.id] = maxLayer + 1;
      }
    }

    // Group nodes by layer
    for (final entry in nodeLayer.entries) {
      layers.putIfAbsent(entry.value, () => []);
      layers[entry.value]!.add(entry.key);
    }

    return layers;
  }

  /// Position nodes within their assigned layers
  Map<String, ({double x, double y})> _positionNodes(Map<int, List<String>> layers) {
    final positions = <String, ({double x, double y})>{};

    // Sort layer keys
    final sortedLayers = layers.keys.toList()..sort();

    for (final layerIndex in sortedLayers) {
      final layerNodes = layers[layerIndex]!;
      final x = startX + layerIndex * (nodeWidth + horizontalGap);

      for (var i = 0; i < layerNodes.length; i++) {
        final y = startY + i * (nodeHeight + verticalGap);
        positions[layerNodes[i]] = (x: x, y: y);
      }
    }

    return positions;
  }
}
