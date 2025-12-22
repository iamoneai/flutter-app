import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class ConflictCheckContent extends StatefulWidget {
  const ConflictCheckContent({super.key});

  @override
  State<ConflictCheckContent> createState() => _ConflictCheckContentState();
}

class _ConflictCheckContentState extends State<ConflictCheckContent> {
  bool _isLoading = true;
  bool _isSaving = false;
  Map<String, dynamic> _config = {};

  // Test state
  final TextEditingController _iinController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  bool _isTesting = false;
  Map<String, dynamic>? _testResult;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _iinController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    setState(() => _isLoading = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('config')
          .doc('pipeline')
          .collection('stages')
          .doc('conflict_check')
          .get();

      if (doc.exists && doc.data() != null) {
        setState(() {
          _config = doc.data()!;
        });
      } else {
        // Use defaults
        _config = _getDefaults();
      }
    } catch (e) {
      _showError('Failed to load config: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Map<String, dynamic> _getDefaults() {
    return {
      'enabled': true,
      'stageNumber': 6.5,
      'stageName': 'Conflict Check',
      'similarity': {
        'threshold': 0.75,
        'algorithm': 'keyword',
        'maxCandidates': 10,
      },
      'llm': {
        'provider': 'gemini',
        'model': 'gemini-2.0-flash-exp',
        'temperature': 0.2,
        'maxTokens': 200,
      },
      'categories': ['location', 'job', 'relationship', 'name', 'preference', 'personal_info'],
      'behavior': {
        'autoResolveUpdates': false,
        'skipDuplicates': true,
        'askForAllConflicts': true,
        'logAllChecks': true,
      },
    };
  }

  Future<void> _saveConfig() async {
    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance
          .collection('config')
          .doc('pipeline')
          .collection('stages')
          .doc('conflict_check')
          .set({
        ..._config,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _showSuccess('Configuration saved');
    } catch (e) {
      _showError('Failed to save: $e');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('⑥.5 Conflict Check'),
            Text(
              'config/pipeline/stages/conflict_check',
              style: TextStyle(fontSize: 12, color: Colors.orange[300]),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveConfig,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: const Text('Save'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildOverviewCard(),
            const SizedBox(height: 24),
            _buildSimilarityCard(),
            const SizedBox(height: 24),
            _buildLLMCard(),
            const SizedBox(height: 24),
            _buildCategoriesCard(),
            const SizedBox(height: 24),
            _buildBehaviorCard(),
            const SizedBox(height: 24),
            _buildPipelineCard(),
            const SizedBox(height: 24),
            _buildTestCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewCard() {
    final enabled = _config['enabled'] ?? true;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.compare_arrows, color: Colors.orange[400]),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Stage Overview', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('Detect conflicts between new and existing memories', style: TextStyle(fontSize: 14, color: Colors.grey)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            // Enable toggle
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Stage Enabled', style: TextStyle(fontWeight: FontWeight.w500)),
                    Text('Enable conflict detection between memories', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
                Switch(
                  value: enabled,
                  onChanged: (value) {
                    setState(() {
                      _config['enabled'] = value;
                    });
                  },
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Info box
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[100]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange[700], size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'This stage runs after Memory Extraction (⑥) and before Curiosity Module (⑦). It checks if newly extracted memories conflict with existing ones.',
                      style: TextStyle(fontSize: 13, color: Colors.orange[800]),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSimilarityCard() {
    final similarity = _config['similarity'] ?? {};
    final threshold = (similarity['threshold'] ?? 0.75).toDouble();
    final algorithm = similarity['algorithm'] ?? 'keyword';
    final maxCandidates = (similarity['maxCandidates'] ?? 10).toDouble();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.search, color: Colors.blue[400]),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Similarity Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('Configure how memories are matched', style: TextStyle(fontSize: 14, color: Colors.grey)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            // Algorithm
            const Text('Matching Algorithm', style: TextStyle(fontWeight: FontWeight.w500)),
            Text('How to find similar memories', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: algorithm,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'keyword', child: Text('Keyword Matching (Fast)')),
                DropdownMenuItem(value: 'semantic', child: Text('Semantic Similarity (Accurate)')),
                DropdownMenuItem(value: 'hybrid', child: Text('Hybrid (Both methods)')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _config['similarity'] = {...similarity, 'algorithm': value};
                  });
                }
              },
            ),
            const SizedBox(height: 24),

            // Threshold
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Similarity Threshold', style: TextStyle(fontWeight: FontWeight.w500)),
                    Text('Min similarity to consider a match (0.5-1.0)', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
                Text(
                  threshold.toStringAsFixed(2),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            Slider(
              value: threshold,
              min: 0.5,
              max: 1.0,
              divisions: 10,
              onChanged: (value) {
                setState(() {
                  _config['similarity'] = {...similarity, 'threshold': value};
                });
              },
            ),
            const SizedBox(height: 16),

            // Max candidates
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Max Candidates', style: TextStyle(fontWeight: FontWeight.w500)),
                    Text('Max memories to compare against (1-50)', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
                Text(
                  maxCandidates.round().toString(),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            Slider(
              value: maxCandidates,
              min: 1,
              max: 50,
              divisions: 49,
              onChanged: (value) {
                setState(() {
                  _config['similarity'] = {...similarity, 'maxCandidates': value.round()};
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLLMCard() {
    final llm = _config['llm'] ?? {};
    final provider = llm['provider'] ?? 'gemini';
    final model = llm['model'] ?? 'gemini-2.0-flash-exp';
    final temperature = (llm['temperature'] ?? 0.2).toDouble();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.psychology, color: Colors.purple[400]),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('LLM Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('Configure LLM for conflict determination', style: TextStyle(fontSize: 14, color: Colors.grey)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            // Provider
            const Text('Provider', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: provider,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'gemini', child: Text('Gemini')),
                DropdownMenuItem(value: 'openai', child: Text('OpenAI')),
                DropdownMenuItem(value: 'anthropic', child: Text('Anthropic')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _config['llm'] = {...llm, 'provider': value};
                  });
                }
              },
            ),
            const SizedBox(height: 16),

            // Model
            const Text('Model', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: model,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'gemini-2.0-flash-exp',
              ),
              onChanged: (value) {
                setState(() {
                  _config['llm'] = {...llm, 'model': value};
                });
              },
            ),
            const SizedBox(height: 16),

            // Temperature
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Temperature', style: TextStyle(fontWeight: FontWeight.w500)),
                    Text('Lower = more deterministic (0.0-1.0)', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
                Text(
                  temperature.toStringAsFixed(2),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            Slider(
              value: temperature,
              min: 0.0,
              max: 1.0,
              divisions: 20,
              onChanged: (value) {
                setState(() {
                  _config['llm'] = {...llm, 'temperature': value};
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoriesCard() {
    final categories = List<String>.from(_config['categories'] ?? []);
    final allCategories = ['location', 'job', 'relationship', 'name', 'preference', 'personal_info', 'event', 'goal'];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.category, color: Colors.green[400]),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Conflict Categories', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('Which memory types to check for conflicts', style: TextStyle(fontSize: 14, color: Colors.grey)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: allCategories.map((cat) {
                final isSelected = categories.contains(cat);
                return FilterChip(
                  label: Text(cat),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        categories.add(cat);
                      } else {
                        categories.remove(cat);
                      }
                      _config['categories'] = categories;
                    });
                  },
                  selectedColor: Colors.green[100],
                  checkmarkColor: Colors.green[700],
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBehaviorCard() {
    final behavior = _config['behavior'] ?? {};

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune, color: Colors.indigo[400]),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Behavior Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('Configure how conflicts are handled', style: TextStyle(fontSize: 14, color: Colors.grey)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            _buildToggle(
              'Auto-Resolve Updates',
              'Automatically accept UPDATE conflicts without asking',
              behavior['autoResolveUpdates'] ?? false,
              (value) => setState(() {
                _config['behavior'] = {...behavior, 'autoResolveUpdates': value};
              }),
            ),
            const SizedBox(height: 16),

            _buildToggle(
              'Skip Duplicates',
              'Skip saving if DUPLICATE detected',
              behavior['skipDuplicates'] ?? true,
              (value) => setState(() {
                _config['behavior'] = {...behavior, 'skipDuplicates': value};
              }),
            ),
            const SizedBox(height: 16),

            _buildToggle(
              'Ask for All Conflicts',
              'Always ask user to resolve CONFLICT type',
              behavior['askForAllConflicts'] ?? true,
              (value) => setState(() {
                _config['behavior'] = {...behavior, 'askForAllConflicts': value};
              }),
            ),
            const SizedBox(height: 16),

            _buildToggle(
              'Log All Checks',
              'Log even when no conflict is found',
              behavior['logAllChecks'] ?? true,
              (value) => setState(() {
                _config['behavior'] = {...behavior, 'logAllChecks': value};
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggle(String label, String description, bool value, ValueChanged<bool> onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
              Text(description, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }

  Widget _buildPipelineCard() {
    return Card(
      color: Colors.orange[50],
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_tree, color: Colors.orange[700]),
                const SizedBox(width: 12),
                Text(
                  'Pipeline Flow',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange[800]),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('⑥ Memory Extraction → Extracts new memories from user input',
                style: TextStyle(fontSize: 14, color: Colors.orange[900])),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[300]!),
              ),
              child: Row(
                children: [
                  Text('⑥.5 Conflict Check',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.orange[900])),
                  const SizedBox(width: 8),
                  Text('→ Checks for conflicts with existing memories',
                      style: TextStyle(fontSize: 14, color: Colors.orange[900])),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text('⑦ Curiosity Module → Asks clarification questions (including conflict resolution)',
                style: TextStyle(fontSize: 14, color: Colors.orange[900])),
          ],
        ),
      ),
    );
  }

  Widget _buildTestCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.science, color: Colors.teal[400]),
                    const SizedBox(width: 12),
                    const Text('Test Stage', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('LIVE', style: TextStyle(color: Colors.green[800], fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            const Text('IIN (required)', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(
              controller: _iinController,
              decoration: const InputDecoration(
                hintText: 'XXXX-XXXX-XXXX-XXXX',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            const Text('Memory Content to Test', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(
              controller: _contentController,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'User lives in New York...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isTesting ? null : _runTest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isTesting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Run Test', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 24),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Results', style: TextStyle(fontWeight: FontWeight.w500)),
                if (_testResult != null)
                  InkWell(
                    onTap: () {
                      final jsonString = const JsonEncoder.withIndent('  ').convert(_testResult);
                      Clipboard.setData(ClipboardData(text: jsonString));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Results copied!'), duration: Duration(seconds: 1)),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.copy, size: 14, color: Colors.blue[800]),
                          const SizedBox(width: 4),
                          Text('Copy', style: TextStyle(color: Colors.blue[800], fontWeight: FontWeight.w500, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 200, maxHeight: 400),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: _testResult != null
                  ? SingleChildScrollView(
                      child: SelectableText(
                        const JsonEncoder.withIndent('  ').convert(_testResult),
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                      ),
                    )
                  : Center(
                      child: Text('Enter IIN and content, then click "Run Test"', style: TextStyle(color: Colors.grey[500])),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runTest() async {
    if (_iinController.text.isEmpty) {
      _showError('IIN is required');
      return;
    }
    if (_contentController.text.isEmpty) {
      _showError('Content is required');
      return;
    }

    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    try {
      // Create a mock extracted memory to test conflict detection
      final mockMemory = {
        'tempId': 'test_${DateTime.now().millisecondsSinceEpoch}',
        'content': _contentController.text.trim(),
        'type': 'fact',
        'confidence': 0.9,
      };

      final response = await http.post(
        Uri.parse('https://pipelinechat-qqkntitb3a-uc.a.run.app'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'iin': _iinController.text.trim(),
          'message': _contentController.text.trim(),
        }),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        // Extract conflict check info from stages
        final stages = result['stageSummary'] as List?;
        final conflictStage = stages?.firstWhere(
          (s) => s['name'] == 'Conflict Check',
          orElse: () => null,
        );

        setState(() => _testResult = {
          'fullResponse': result,
          'conflictStage': conflictStage,
          'note': 'Check stageSummary for Conflict Check details',
        });
      } else {
        setState(() => _testResult = {
          'error': 'Request failed',
          'statusCode': response.statusCode,
          'body': response.body,
        });
      }
    } catch (e) {
      setState(() => _testResult = {'error': e.toString()});
    } finally {
      setState(() => _isTesting = false);
    }
  }
}
