// IAMONEAI - Pipeline Executor Service
// Simulates pipeline execution for testing visual logic flows
// Supports both simulated and live (Cloud Function) execution modes

import 'dart:async';
import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// Execution mode for the pipeline
enum ExecutionMode {
  simulated, // Local simulation with fake responses
  live,      // Call actual Cloud Functions
}

/// Execution state for a node
enum NodeExecutionState {
  idle,
  pending,
  running,
  completed,
  error,
  skipped,
}

/// Result of executing a single node
class NodeExecutionResult {
  final String nodeId;
  final String nodeName;
  final NodeExecutionState state;
  final Duration duration;
  final Map<String, dynamic> input;
  final Map<String, dynamic> output;
  final String? error;
  final DateTime timestamp;

  NodeExecutionResult({
    required this.nodeId,
    required this.nodeName,
    required this.state,
    required this.duration,
    required this.input,
    required this.output,
    this.error,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'nodeId': nodeId,
      'nodeName': nodeName,
      'state': state.name,
      'durationMs': duration.inMilliseconds,
      'input': input,
      'output': output,
      'error': error,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

/// Overall pipeline execution result
class PipelineExecutionResult {
  final bool success;
  final Duration totalDuration;
  final List<NodeExecutionResult> nodeResults;
  final Map<String, dynamic> finalOutput;
  final String? error;

  PipelineExecutionResult({
    required this.success,
    required this.totalDuration,
    required this.nodeResults,
    required this.finalOutput,
    this.error,
  });
}

/// Node info for execution
class ExecutableNode {
  final String id;
  final String name;
  final String templateId;
  final List<String> inputNodeIds;
  final List<String> outputNodeIds;

  ExecutableNode({
    required this.id,
    required this.name,
    required this.templateId,
    this.inputNodeIds = const [],
    this.outputNodeIds = const [],
  });
}

/// Wire info for execution
class ExecutableWire {
  final String fromNodeId;
  final String fromPortKey;
  final String toNodeId;
  final String toPortKey;

  ExecutableWire({
    required this.fromNodeId,
    required this.fromPortKey,
    required this.toNodeId,
    required this.toPortKey,
  });
}

/// Callback for execution state changes
typedef ExecutionCallback = void Function(String nodeId, NodeExecutionState state, NodeExecutionResult? result);

/// Service for executing visual logic pipelines
class PipelineExecutorService {
  static final PipelineExecutorService _instance = PipelineExecutorService._internal();
  factory PipelineExecutorService() => _instance;
  PipelineExecutorService._internal();

  bool _isRunning = false;
  bool _isPaused = false;
  bool _isStepping = false;
  Completer<void>? _stepCompleter;
  ExecutionMode _mode = ExecutionMode.simulated;

  // Cloud Functions instance
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  bool get isRunning => _isRunning;
  bool get isPaused => _isPaused;
  ExecutionMode get mode => _mode;

  /// Set execution mode
  void setMode(ExecutionMode mode) {
    if (!_isRunning) {
      _mode = mode;
    }
  }

  /// Execute the entire pipeline
  Future<PipelineExecutionResult> execute({
    required List<ExecutableNode> nodes,
    required List<ExecutableWire> wires,
    required Map<String, dynamic> input,
    required ExecutionCallback onNodeStateChange,
    bool stepMode = false,
  }) async {
    if (_isRunning) {
      return PipelineExecutionResult(
        success: false,
        totalDuration: Duration.zero,
        nodeResults: [],
        finalOutput: {},
        error: 'Pipeline is already running',
      );
    }

    _isRunning = true;
    _isPaused = false;
    _isStepping = stepMode;

    final startTime = DateTime.now();
    final nodeResults = <NodeExecutionResult>[];
    final nodeOutputs = <String, Map<String, dynamic>>{};

    // Initialize all nodes as pending
    for (final node in nodes) {
      onNodeStateChange(node.id, NodeExecutionState.pending, null);
    }

    try {
      // Build execution order using topological sort
      final executionOrder = _topologicalSort(nodes, wires);

      // Execute each node in order
      Map<String, dynamic> currentData = Map.from(input);

      for (final nodeId in executionOrder) {
        if (!_isRunning) break;

        // Wait for step if in step mode
        if (_isStepping && nodeResults.isNotEmpty) {
          _stepCompleter = Completer<void>();
          _isPaused = true;
          await _stepCompleter!.future;
          _isPaused = false;
        }

        final node = nodes.firstWhere((n) => n.id == nodeId);

        // Gather inputs from connected nodes
        final nodeInput = <String, dynamic>{};
        for (final wire in wires.where((w) => w.toNodeId == nodeId)) {
          if (nodeOutputs.containsKey(wire.fromNodeId)) {
            final sourceOutput = nodeOutputs[wire.fromNodeId]!;
            if (sourceOutput.containsKey(wire.fromPortKey)) {
              nodeInput[wire.toPortKey] = sourceOutput[wire.fromPortKey];
            }
          }
        }

        // If no wires connected, use pipeline input
        if (nodeInput.isEmpty) {
          nodeInput.addAll(currentData);
        }

        // Mark as running
        onNodeStateChange(node.id, NodeExecutionState.running, null);

        // Simulate node execution
        final result = await _executeNode(node, nodeInput);
        nodeResults.add(result);

        // Store outputs for downstream nodes
        nodeOutputs[node.id] = result.output;
        currentData = result.output;

        // Update state
        onNodeStateChange(node.id, result.state, result);

        if (result.state == NodeExecutionState.error) {
          _isRunning = false;
          return PipelineExecutionResult(
            success: false,
            totalDuration: DateTime.now().difference(startTime),
            nodeResults: nodeResults,
            finalOutput: currentData,
            error: result.error,
          );
        }
      }

      _isRunning = false;
      return PipelineExecutionResult(
        success: true,
        totalDuration: DateTime.now().difference(startTime),
        nodeResults: nodeResults,
        finalOutput: currentData,
      );
    } catch (e) {
      _isRunning = false;
      return PipelineExecutionResult(
        success: false,
        totalDuration: DateTime.now().difference(startTime),
        nodeResults: nodeResults,
        finalOutput: {},
        error: e.toString(),
      );
    }
  }

  /// Execute a single node
  Future<NodeExecutionResult> _executeNode(ExecutableNode node, Map<String, dynamic> input) async {
    final startTime = DateTime.now();

    try {
      Map<String, dynamic> output;

      if (_mode == ExecutionMode.live) {
        // Live execution via Cloud Functions
        output = await _executeLiveNode(node, input);
      } else {
        // Simulated execution
        final processingTime = _getProcessingTime(node.templateId);
        await Future.delayed(processingTime);
        output = _simulateNodeOutput(node, input);
      }

      return NodeExecutionResult(
        nodeId: node.id,
        nodeName: node.name,
        state: NodeExecutionState.completed,
        duration: DateTime.now().difference(startTime),
        input: input,
        output: output,
      );
    } catch (e) {
      return NodeExecutionResult(
        nodeId: node.id,
        nodeName: node.name,
        state: NodeExecutionState.error,
        duration: DateTime.now().difference(startTime),
        input: input,
        output: {},
        error: e.toString(),
      );
    }
  }

  /// Execute a node using Cloud Functions
  Future<Map<String, dynamic>> _executeLiveNode(ExecutableNode node, Map<String, dynamic> input) async {
    try {
      // Determine which function to call based on template
      final functionName = _getFunctionName(node.templateId);

      if (functionName == null) {
        // No specific function, just pass through
        return Map<String, dynamic>.from(input)
          ..['processed'] = true
          ..['node'] = node.name
          ..['mode'] = 'live';
      }

      // Call the Cloud Function
      final callable = _functions.httpsCallable(functionName);
      final result = await callable.call<Map<String, dynamic>>({
        'nodeId': node.id,
        'nodeName': node.name,
        'templateId': node.templateId,
        'input': input,
      });

      final output = Map<String, dynamic>.from(input);
      if (result.data != null) {
        output.addAll(Map<String, dynamic>.from(result.data as Map));
      }
      output['mode'] = 'live';

      return output;
    } catch (e) {
      debugPrint('Live node execution error: $e');
      // Fall back to simulation on error
      final output = _simulateNodeOutput(
        ExecutableNode(id: node.id, name: node.name, templateId: node.templateId),
        input,
      );
      output['mode'] = 'fallback';
      output['error_fallback'] = e.toString();
      return output;
    }
  }

  /// Get Cloud Function name for a template
  String? _getFunctionName(String templateId) {
    switch (templateId) {
      case 'stage_llm_response':
        return 'chat'; // Main chat function
      case 'stage_memory_query':
        return 'queryMemory';
      case 'stage_memory_extraction':
        return 'extractMemory';
      case 'stage_classifier':
        return 'classifyIntent';
      default:
        return null; // No specific function, simulate locally
    }
  }

  /// Test execution of the full chat pipeline
  Future<Map<String, dynamic>> testChatPipeline({
    required String message,
    required String userId,
    String? iinId,
  }) async {
    try {
      final callable = _functions.httpsCallable('chat');
      final result = await callable.call<Map<String, dynamic>>({
        'message': message,
        'userId': userId,
        'iinId': iinId,
        'testMode': true,
        'includeDebug': true,
      });

      return {
        'success': true,
        'data': result.data,
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }

  /// Get simulated processing time based on node type
  Duration _getProcessingTime(String templateId) {
    switch (templateId) {
      case 'stage_input_analysis':
        return const Duration(milliseconds: 150);
      case 'stage_classifier':
        return const Duration(milliseconds: 300);
      case 'stage_confidence_gate':
        return const Duration(milliseconds: 100);
      case 'stage_intent_resolution':
        return const Duration(milliseconds: 400);
      case 'stage_memory_query':
        return const Duration(milliseconds: 250);
      case 'stage_memory_extraction':
        return const Duration(milliseconds: 200);
      case 'stage_context_injection':
        return const Duration(milliseconds: 150);
      case 'stage_llm_response':
        return const Duration(milliseconds: 800);
      case 'stage_trust_evaluation':
        return const Duration(milliseconds: 200);
      case 'stage_save_decision':
        return const Duration(milliseconds: 100);
      case 'stage_post_response_log':
        return const Duration(milliseconds: 50);
      default:
        return const Duration(milliseconds: 200);
    }
  }

  /// Simulate node output based on node type
  Map<String, dynamic> _simulateNodeOutput(ExecutableNode node, Map<String, dynamic> input) {
    final output = Map<String, dynamic>.from(input);

    switch (node.templateId) {
      case 'stage_input_analysis':
        output['analyzed'] = true;
        output['tokens'] = (input['message']?.toString().split(' ').length ?? 0);
        output['language'] = 'en';
        break;
      case 'stage_classifier':
        output['classification'] = {
          'class': 'general_query',
          'confidence': 0.85,
          'alternatives': ['greeting', 'question'],
        };
        break;
      case 'stage_confidence_gate':
        output['passed'] = true;
        output['threshold'] = 0.7;
        output['actual'] = 0.85;
        break;
      case 'stage_intent_resolution':
        output['intent'] = {
          'primary': 'information_request',
          'entities': [],
          'slots': {},
        };
        break;
      case 'stage_memory_query':
        output['memories'] = [
          {'id': 'mem_1', 'content': 'Previous context...', 'score': 0.9},
        ];
        output['query_time_ms'] = 45;
        break;
      case 'stage_memory_extraction':
        output['extracted'] = {
          'facts': [],
          'preferences': [],
          'context': [],
        };
        break;
      case 'stage_context_injection':
        output['context_injected'] = true;
        output['context_tokens'] = 150;
        break;
      case 'stage_llm_response':
        output['response'] = 'This is a simulated response from the LLM.';
        output['model'] = 'llama-3.3-70b-versatile';
        output['tokens_used'] = 256;
        break;
      case 'stage_trust_evaluation':
        output['trust_score'] = 0.92;
        output['flags'] = [];
        break;
      case 'stage_save_decision':
        output['should_save'] = true;
        output['save_type'] = 'conversation';
        break;
      case 'stage_post_response_log':
        output['logged'] = true;
        output['log_id'] = 'log_${DateTime.now().millisecondsSinceEpoch}';
        break;
      default:
        output['processed'] = true;
        output['node'] = node.name;
    }

    return output;
  }

  /// Topological sort for execution order
  List<String> _topologicalSort(List<ExecutableNode> nodes, List<ExecutableWire> wires) {
    final inDegree = <String, int>{};
    final adjacency = <String, List<String>>{};

    // Initialize
    for (final node in nodes) {
      inDegree[node.id] = 0;
      adjacency[node.id] = [];
    }

    // Build graph
    for (final wire in wires) {
      adjacency[wire.fromNodeId]?.add(wire.toNodeId);
      inDegree[wire.toNodeId] = (inDegree[wire.toNodeId] ?? 0) + 1;
    }

    // Find nodes with no incoming edges
    final queue = <String>[];
    for (final entry in inDegree.entries) {
      if (entry.value == 0) {
        queue.add(entry.key);
      }
    }

    // Process
    final result = <String>[];
    while (queue.isNotEmpty) {
      final node = queue.removeAt(0);
      result.add(node);

      for (final neighbor in adjacency[node] ?? []) {
        inDegree[neighbor] = (inDegree[neighbor] ?? 1) - 1;
        if (inDegree[neighbor] == 0) {
          queue.add(neighbor);
        }
      }
    }

    // Add any remaining nodes (not connected)
    for (final node in nodes) {
      if (!result.contains(node.id)) {
        result.add(node.id);
      }
    }

    return result;
  }

  /// Continue to next step (when in step mode)
  void step() {
    if (_isStepping && _stepCompleter != null && !_stepCompleter!.isCompleted) {
      _stepCompleter!.complete();
    }
  }

  /// Stop execution
  void stop() {
    _isRunning = false;
    _isPaused = false;
    if (_stepCompleter != null && !_stepCompleter!.isCompleted) {
      _stepCompleter!.complete();
    }
  }

  /// Reset execution state
  void reset() {
    _isRunning = false;
    _isPaused = false;
    _isStepping = false;
    _stepCompleter = null;
  }
}
