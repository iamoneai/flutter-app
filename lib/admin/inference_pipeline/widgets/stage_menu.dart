// IAMONEAI - Inference Pipeline Stage Menu (Light Theme)
import 'package:flutter/material.dart';

// Unicode circled numbers for stage indicators (index 0 unused, stages are 1-12)
const List<String> stageCircledNumbers = [
  '',   // 0 - not used (Orchestrator is MASTER, not numbered)
  '①', '②', '③', '④', '⑤', '⑥', '⑦', '⑧', '⑨', '⑩', '⑪', '⑫',
];

class PipelineStage {
  final double number; // Use double to support fractional stages like 6.5
  final String name;
  final String shortName;
  final bool isImplemented;
  final bool isMaster;

  const PipelineStage({
    required this.number,
    required this.name,
    required this.shortName,
    this.isImplemented = false,
    this.isMaster = false,
  });

  // Helper to get display number (e.g., "⑥.5" for stage 6.5)
  String get displayNumber {
    if (isMaster || number == 0) return '';
    if (number == number.floor()) {
      // Integer stage
      final intNum = number.toInt();
      if (intNum > 0 && intNum < stageCircledNumbers.length) {
        return stageCircledNumbers[intNum];
      }
      return intNum.toString();
    } else {
      // Fractional stage (e.g., 6.5)
      final intPart = number.floor();
      final fracPart = ((number - intPart) * 10).round();
      if (intPart > 0 && intPart < stageCircledNumbers.length) {
        return '${stageCircledNumbers[intPart]}.$fracPart';
      }
      return number.toString();
    }
  }
}

const List<PipelineStage> pipelineStages = [
  PipelineStage(number: 0, name: 'Pipeline Orchestrator', shortName: 'Orchestrator', isImplemented: true, isMaster: true),
  PipelineStage(number: 1, name: 'Input Analysis', shortName: 'Input Analysis', isImplemented: true),
  PipelineStage(number: 2, name: 'Classifier', shortName: 'Classifier', isImplemented: true),
  PipelineStage(number: 3, name: 'Confidence Gate', shortName: 'Confidence Gate', isImplemented: true),
  PipelineStage(number: 4, name: 'Intent Resolution', shortName: 'Intent Resolution', isImplemented: true),
  PipelineStage(number: 5, name: 'Memory Query', shortName: 'Memory Query', isImplemented: true),
  PipelineStage(number: 6, name: 'Memory Extraction', shortName: 'Memory Extraction', isImplemented: true),
  PipelineStage(number: 6.5, name: 'Conflict Check', shortName: 'Conflict Check', isImplemented: true),
  PipelineStage(number: 6.7, name: 'Calendar/Events', shortName: 'Calendar', isImplemented: true),
  PipelineStage(number: 7, name: 'Curiosity Module', shortName: 'Curiosity Module', isImplemented: true),
  PipelineStage(number: 8, name: 'Trust Evaluation', shortName: 'Trust Evaluation', isImplemented: true),
  PipelineStage(number: 9, name: 'Save Decision', shortName: 'Save Decision', isImplemented: true),
  PipelineStage(number: 10, name: 'Context Injection', shortName: 'Context Injection', isImplemented: true),
  PipelineStage(number: 11, name: 'LLM Response', shortName: 'LLM Response', isImplemented: true),
  PipelineStage(number: 12, name: 'Post-Response Logging', shortName: 'Post-Response Log', isImplemented: true),
];

class StageMenu extends StatelessWidget {
  final double selectedStage;
  final Function(double) onStageSelected;

  const StageMenu({
    super.key,
    required this.selectedStage,
    required this.onStageSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      color: Colors.white,
      decoration: const BoxDecoration(
        border: Border(
          right: BorderSide(color: Color(0xFFE0E0E0)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFFE0E0E0)),
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.account_tree, color: Color(0xFF1A1A1A), size: 20),
                SizedBox(width: 8),
                Text(
                  'Inference Pipeline',
                  style: TextStyle(
                    color: Color(0xFF1A1A1A),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // Stage list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: pipelineStages.length,
              itemBuilder: (context, index) {
                final stage = pipelineStages[index];
                final isSelected = stage.number == selectedStage;

                return _buildStageMenuItem(stage, isSelected);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStageMenuItem(PipelineStage stage, bool isSelected) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onStageSelected(stage.number),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFFF5F5F5)
                : (stage.isMaster ? const Color(0xFFFFF8E1) : Colors.transparent),
            border: Border(
              left: BorderSide(
                color: isSelected
                    ? const Color(0xFF1A1A1A)
                    : (stage.isMaster ? const Color(0xFFFF9800) : Colors.transparent),
                width: 3,
              ),
            ),
          ),
          child: Row(
            children: [
              // Status dot or icon
              if (stage.isMaster)
                const Icon(Icons.settings_suggest, size: 16, color: Color(0xFFFF9800))
              else
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected
                        ? const Color(0xFF1A1A1A)
                        : (stage.isImplemented
                            ? const Color(0xFF4CAF50)
                            : const Color(0xFF999999)),
                  ),
                ),
              const SizedBox(width: 10),
              // Stage number (circled) for non-master stages
              if (!stage.isMaster && stage.displayNumber.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    stage.displayNumber,
                    style: TextStyle(
                      color: isSelected
                          ? const Color(0xFF1A1A1A)
                          : const Color(0xFF666666),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              // Stage name
              Expanded(
                child: Text(
                  stage.shortName,
                  style: TextStyle(
                    color: isSelected
                        ? const Color(0xFF1A1A1A)
                        : (stage.isMaster ? const Color(0xFFE65100) : const Color(0xFF666666)),
                    fontSize: 12,
                    fontWeight: (isSelected || stage.isMaster) ? FontWeight.w600 : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // MASTER badge or implementation status icon
              if (stage.isMaster)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9800),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'MASTER',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              else if (!stage.isImplemented)
                const Icon(
                  Icons.construction,
                  color: Color(0xFF999999),
                  size: 14,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
