// IAMONEAI - Inference Pipeline Placeholder Content (Light Theme)
import 'package:flutter/material.dart';
import 'stage_menu.dart';

class PlaceholderContent extends StatelessWidget {
  final PipelineStage stage;

  const PlaceholderContent({
    super.key,
    required this.stage,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFFAFAFA),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Construction icon
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE0E0E0)),
              ),
              child: const Icon(
                Icons.construction,
                color: Color(0xFF999999),
                size: 40,
              ),
            ),
            const SizedBox(height: 24),
            // Stage name
            Text(
              'Stage ${stage.number}: ${stage.name}',
              style: const TextStyle(
                color: Color(0xFF1A1A1A),
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            // Coming soon badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.orange[200]!,
                ),
              ),
              child: Text(
                'Coming Soon',
                style: TextStyle(
                  color: Colors.orange[700],
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Description
            Text(
              _getStageDescription(stage.number),
              style: const TextStyle(
                color: Color(0xFF666666),
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String _getStageDescription(double stageNumber) {
    if (stageNumber == 2) return 'Classify user intent and determine routing';
    if (stageNumber == 3) return 'Evaluate confidence levels for decision gating';
    if (stageNumber == 4) return 'Resolve final intent from classification results';
    if (stageNumber == 5) return 'Query relevant memories for context injection';
    if (stageNumber == 6) return 'Extract memorable facts from conversations';
    if (stageNumber == 6.5) return 'Detect conflicts between new and existing memories';
    if (stageNumber == 7) return 'Trigger curiosity for incomplete information';
    if (stageNumber == 8) return 'Evaluate trust scores for memory operations';
    if (stageNumber == 9) return 'Decide whether to save extracted memories';
    if (stageNumber == 10) return 'Inject context into LLM prompts';
    if (stageNumber == 11) return 'Generate final LLM response';
    if (stageNumber == 12) return 'Log response metrics and update indexes';
    return 'Configure this pipeline stage';
  }
}
