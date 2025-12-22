// IAMONEAI - Inference Pipeline Admin Screen (Light Theme)
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'widgets/stage_menu.dart';
import 'widgets/placeholder_content.dart';
import 'widgets/test_panel.dart';
import 'pipeline_orchestrator_content.dart';
import 'stages/input_analysis_content.dart';
import 'stages/classifier_content.dart';
import 'stages/memory_query_content.dart';
import 'stages/memory_extraction_content.dart';
import 'stages/context_injection_content.dart';
import 'stages/llm_response_content.dart';
import 'stages/save_decision_content.dart';
import 'stages/confidence_gate_content.dart';
import 'stages/intent_resolution_content.dart';
import 'stages/trust_evaluation_content.dart';
import 'stages/post_response_log_content.dart';
import 'stages/curiosity_module_content.dart';
import 'stages/conflict_check_content.dart';
import 'stages/calendar_content.dart';

class InferencePipelineScreen extends StatefulWidget {
  const InferencePipelineScreen({super.key});

  @override
  State<InferencePipelineScreen> createState() => _InferencePipelineScreenState();
}

class _InferencePipelineScreenState extends State<InferencePipelineScreen> {
  double _selectedStage = 0;

  // Cloud Function endpoints
  static const String _baseUrl = 'https://us-central1-app-iamoneai-c36ec.cloudfunctions.net';
  static const String _inputAnalysisEndpoint = '$_baseUrl/testInputAnalysis';
  static const String _classifierEndpoint = '$_baseUrl/testClassifier';
  static const String _trustEvaluationEndpoint = '$_baseUrl/testTrustEvaluation';

  void _onStageSelected(double stage) {
    setState(() => _selectedStage = stage);
  }

  Future<Map<String, dynamic>> _testInputAnalysis(String input) async {
    try {
      final response = await http.post(
        Uri.parse(_inputAnalysisEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'message': input}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      throw Exception('Test failed: $e');
    }
  }

  Future<Map<String, dynamic>> _testClassifier(String input) async {
    try {
      final response = await http.post(
        Uri.parse(_classifierEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'message': input}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      throw Exception('Test failed: $e');
    }
  }

  Future<Map<String, dynamic>> _testTrustEvaluation(String input) async {
    try {
      final response = await http.post(
        Uri.parse(_trustEvaluationEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'content': input,
          'source': 'user_stated',
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      throw Exception('Test failed: $e');
    }
  }

  Future<Map<String, dynamic>> Function(String)? _getTestFunction(double stageNumber) {
    if (stageNumber == 1) return _testInputAnalysis;
    if (stageNumber == 2) return _testClassifier;
    if (stageNumber == 8) return _testTrustEvaluation; // Trust Evaluation
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final currentStage = pipelineStages.firstWhere(
      (s) => s.number == _selectedStage,
    );

    // Orchestrator (stage 0) has its own test panel built-in
    final bool isOrchestrator = _selectedStage == 0;

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: Row(
        children: [
          // Left: Stage Menu
          StageMenu(
            selectedStage: _selectedStage,
            onStageSelected: _onStageSelected,
          ),
          // Center: Configuration Content
          Expanded(
            child: _buildContent(currentStage),
          ),
          // Right: Test Panel (hidden for orchestrator which has its own)
          if (!isOrchestrator)
            TestPanel(
              stageNumber: _selectedStage,
              isImplemented: currentStage.isImplemented,
              onTest: _getTestFunction(_selectedStage),
            ),
        ],
      ),
    );
  }

  Widget _buildContent(PipelineStage stage) {
    // Use if-else for double comparison (supports fractional stages like 6.5)
    if (stage.number == 0) return const PipelineOrchestratorContent();
    if (stage.number == 1) return const InputAnalysisContent();
    if (stage.number == 2) return const ClassifierContent();
    if (stage.number == 3) return const ConfidenceGateContent();
    if (stage.number == 4) return const IntentResolutionContent();
    if (stage.number == 5) return const MemoryQueryContent();
    if (stage.number == 6) return const MemoryExtractionContent();
    if (stage.number == 6.5) return const ConflictCheckContent();
    if (stage.number == 6.7) return const CalendarContent();
    if (stage.number == 7) return const CuriosityModuleContent();
    if (stage.number == 8) return const TrustEvaluationContent();
    if (stage.number == 9) return const SaveDecisionContent();
    if (stage.number == 10) return const ContextInjectionContent();
    if (stage.number == 11) return const LLMResponseContent();
    if (stage.number == 12) return const PostResponseLogContent();
    return PlaceholderContent(stage: stage);
  }
}
