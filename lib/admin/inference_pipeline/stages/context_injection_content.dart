import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/models/context_injection_config.dart';

class ContextInjectionContent extends StatefulWidget {
  const ContextInjectionContent({super.key});

  @override
  State<ContextInjectionContent> createState() => _ContextInjectionContentState();
}

class _ContextInjectionContentState extends State<ContextInjectionContent> {
  bool _isLoading = true;
  bool _isSaving = false;
  ContextInjectionConfig _config = ContextInjectionConfig.defaults();

  // Test state
  final TextEditingController _iinController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  bool _isTesting = false;
  Map<String, dynamic>? _testResult;

  // Prompt controllers
  final TextEditingController _systemPromptController = TextEditingController();
  final TextEditingController _memoryHeaderController = TextEditingController();
  final TextEditingController _memoryItemFormatController = TextEditingController();
  final TextEditingController _noMemoriesController = TextEditingController();
  final TextEditingController _userMessageFormatController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _iinController.dispose();
    _messageController.dispose();
    _systemPromptController.dispose();
    _memoryHeaderController.dispose();
    _memoryItemFormatController.dispose();
    _noMemoriesController.dispose();
    _userMessageFormatController.dispose();
    super.dispose();
  }

  void _initPromptControllers() {
    _systemPromptController.text = _config.prompts.systemPrompt;
    _memoryHeaderController.text = _config.prompts.memoryHeader;
    _memoryItemFormatController.text = _config.prompts.memoryItemFormat;
    _noMemoriesController.text = _config.prompts.noMemoriesText;
    _userMessageFormatController.text = _config.prompts.userMessageFormat;
  }

  Future<void> _loadConfig() async {
    setState(() => _isLoading = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('config')
          .doc('pipeline')
          .collection('stages')
          .doc('context_injection')
          .get();

      if (doc.exists && doc.data() != null) {
        setState(() {
          _config = ContextInjectionConfig.fromFirestore(doc.data()!);
        });
      }
      _initPromptControllers();
    } catch (e) {
      _showError('Failed to load config: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveConfig() async {
    setState(() => _isSaving = true);
    try {
      // Update prompts from controllers
      _config = _config.copyWith(
        prompts: _config.prompts.copyWith(
          systemPrompt: _systemPromptController.text,
          memoryHeader: _memoryHeaderController.text,
          memoryItemFormat: _memoryItemFormatController.text,
          noMemoriesText: _noMemoriesController.text,
          userMessageFormat: _userMessageFormatController.text,
        ),
      );

      await FirebaseFirestore.instance
          .collection('config')
          .doc('pipeline')
          .collection('stages')
          .doc('context_injection')
          .set(_config.toFirestore(), SetOptions(merge: true));

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
            const Text('⑩ Context Injection'),
            Text(
              'config/pipeline/stages/context_injection',
              style: TextStyle(fontSize: 12, color: Colors.purple[300]),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveConfig,
              icon: _isSaving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
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
            _buildInjectionSettingsCard(),
            const SizedBox(height: 24),
            _buildFilterSettingsCard(),
            const SizedBox(height: 24),
            _buildFormatSettingsCard(),
            const SizedBox(height: 24),
            _buildPromptTemplatesCard(),
            const SizedBox(height: 24),
            _buildTokenSettingsCard(),
            const SizedBox(height: 24),
            _build4LayerContextCard(),
            const SizedBox(height: 24),
            _buildPipelinePreviewCard(),
            const SizedBox(height: 24),
            _buildTestCard(),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // INJECTION SETTINGS CARD
  // ═══════════════════════════════════════════════════════════

  Widget _buildInjectionSettingsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.input, color: Colors.blue[400]),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Injection Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('Configure memory injection behavior', style: TextStyle(fontSize: 14, color: Colors.grey)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            _buildToggleRow(
              label: 'Injection Enabled',
              description: 'Enable memory injection into LLM prompts',
              value: _config.injection.enabled,
              onChanged: (value) {
                setState(() {
                  _config = _config.copyWith(
                    injection: _config.injection.copyWith(enabled: value),
                  );
                });
              },
            ),
            const SizedBox(height: 16),

            _buildSliderRow(
              label: 'Max Memories to Inject',
              description: 'Maximum number of memories in prompt (1-50)',
              value: _config.injection.maxMemories.toDouble(),
              min: 1,
              max: 50,
              divisions: 49,
              onChanged: (value) {
                setState(() {
                  _config = _config.copyWith(
                    injection: _config.injection.copyWith(maxMemories: value.round()),
                  );
                });
              },
            ),
            const SizedBox(height: 16),

            _buildSliderRow(
              label: 'Min Relevance Threshold',
              description: 'Only inject memories above this relevance (0-1)',
              value: _config.injection.minRelevance,
              min: 0,
              max: 1,
              divisions: 20,
              isDecimal: true,
              onChanged: (value) {
                setState(() {
                  _config = _config.copyWith(
                    injection: _config.injection.copyWith(minRelevance: value),
                  );
                });
              },
            ),
            const SizedBox(height: 16),

            const Text('Sort Memories By', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _config.injection.sortBy,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'relevance', child: Text('Relevance (most relevant first)')),
                DropdownMenuItem(value: 'recency', child: Text('Recency (newest first)')),
                DropdownMenuItem(value: 'type', child: Text('Type (grouped by type)')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _config = _config.copyWith(
                      injection: _config.injection.copyWith(sortBy: value),
                    );
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // FILTER SETTINGS CARD
  // ═══════════════════════════════════════════════════════════

  Widget _buildFilterSettingsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.filter_list, color: Colors.orange[400]),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Memory Filtering', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('Choose which memories to include', style: TextStyle(fontSize: 14, color: Colors.grey)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            const Text('Include Types', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _buildFilterChip('Facts', _config.filter.includeFacts, (v) {
                  setState(() => _config = _config.copyWith(filter: _config.filter.copyWith(includeFacts: v)));
                }),
                _buildFilterChip('Preferences', _config.filter.includePreferences, (v) {
                  setState(() => _config = _config.copyWith(filter: _config.filter.copyWith(includePreferences: v)));
                }),
                _buildFilterChip('Relationships', _config.filter.includeRelationships, (v) {
                  setState(() => _config = _config.copyWith(filter: _config.filter.copyWith(includeRelationships: v)));
                }),
                _buildFilterChip('Events', _config.filter.includeEvents, (v) {
                  setState(() => _config = _config.copyWith(filter: _config.filter.copyWith(includeEvents: v)));
                }),
                _buildFilterChip('Goals', _config.filter.includeGoals, (v) {
                  setState(() => _config = _config.copyWith(filter: _config.filter.copyWith(includeGoals: v)));
                }),
                _buildFilterChip('Todos', _config.filter.includeTodos, (v) {
                  setState(() => _config = _config.copyWith(filter: _config.filter.copyWith(includeTodos: v)));
                }),
                _buildFilterChip('Notes', _config.filter.includeNotes, (v) {
                  setState(() => _config = _config.copyWith(filter: _config.filter.copyWith(includeNotes: v)));
                }),
              ],
            ),
            const SizedBox(height: 24),

            const Text('Include Tiers', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _buildFilterChip('Working', _config.filter.includeWorkingTier, (v) {
                  setState(() => _config = _config.copyWith(filter: _config.filter.copyWith(includeWorkingTier: v)));
                }),
                _buildFilterChip('Long-term', _config.filter.includeLongtermTier, (v) {
                  setState(() => _config = _config.copyWith(filter: _config.filter.copyWith(includeLongtermTier: v)));
                }),
                _buildFilterChip('Deep', _config.filter.includeDeepTier, (v) {
                  setState(() => _config = _config.copyWith(filter: _config.filter.copyWith(includeDeepTier: v)));
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, bool selected, ValueChanged<bool> onChanged) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onChanged,
      selectedColor: Colors.blue[100],
      checkmarkColor: Colors.blue[800],
    );
  }

  // ═══════════════════════════════════════════════════════════
  // FORMAT SETTINGS CARD
  // ═══════════════════════════════════════════════════════════

  Widget _buildFormatSettingsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.format_list_bulleted, color: Colors.green[400]),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Format Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('How memories appear in prompt', style: TextStyle(fontSize: 14, color: Colors.grey)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            const Text('Memory Format', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _config.format.memoryFormat,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'bullet', child: Text('Bullet List (- memory)')),
                DropdownMenuItem(value: 'numbered', child: Text('Numbered List (1. memory)')),
                DropdownMenuItem(value: 'prose', child: Text('Prose (sentences)')),
                DropdownMenuItem(value: 'json', child: Text('JSON (structured)')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _config = _config.copyWith(
                      format: _config.format.copyWith(memoryFormat: value),
                    );
                  });
                }
              },
            ),
            const SizedBox(height: 16),

            _buildToggleRow(
              label: 'Group by Type',
              description: 'Group memories by type (facts, preferences, etc.)',
              value: _config.format.groupByType,
              onChanged: (value) {
                setState(() {
                  _config = _config.copyWith(
                    format: _config.format.copyWith(groupByType: value),
                  );
                });
              },
            ),
            const SizedBox(height: 16),

            _buildToggleRow(
              label: 'Include Metadata',
              description: 'Include dates and sources with memories',
              value: _config.format.includeMetadata,
              onChanged: (value) {
                setState(() {
                  _config = _config.copyWith(
                    format: _config.format.copyWith(includeMetadata: value),
                  );
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // PROMPT TEMPLATES CARD
  // ═══════════════════════════════════════════════════════════

  Widget _buildPromptTemplatesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.article, color: Colors.purple[400]),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Prompt Templates', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('Customize LLM prompt structure', style: TextStyle(fontSize: 14, color: Colors.grey)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            const Text('System Prompt', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(
              controller: _systemPromptController,
              maxLines: 4,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'You are IAMONEAI...',
              ),
            ),
            const SizedBox(height: 16),

            const Text('Memory Section Header', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(
              controller: _memoryHeaderController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Here is what you know about the user:',
              ),
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                const Text('Memory Item Format', style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Use {{content}} for memory text, {{type}} for type',
                  child: Icon(Icons.info_outline, size: 16, color: Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _memoryItemFormatController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '- {{content}}',
              ),
            ),
            const SizedBox(height: 16),

            const Text('No Memories Text', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(
              controller: _noMemoriesController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'You don\'t have any memories about this user yet.',
              ),
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                const Text('User Message Format', style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Use {{message}} for user input',
                  child: Icon(Icons.info_outline, size: 16, color: Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _userMessageFormatController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'User: {{message}}',
              ),
            ),
            const SizedBox(height: 16),

            TextButton.icon(
              onPressed: () {
                final defaults = PromptTemplates.defaults();
                setState(() {
                  _systemPromptController.text = defaults.systemPrompt;
                  _memoryHeaderController.text = defaults.memoryHeader;
                  _memoryItemFormatController.text = defaults.memoryItemFormat;
                  _noMemoriesController.text = defaults.noMemoriesText;
                  _userMessageFormatController.text = defaults.userMessageFormat;
                });
              },
              icon: const Icon(Icons.restore, size: 16),
              label: const Text('Reset to Defaults'),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // TOKEN SETTINGS CARD
  // ═══════════════════════════════════════════════════════════

  Widget _buildTokenSettingsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.data_usage, color: Colors.red[400]),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Token Management', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('Control context window usage', style: TextStyle(fontSize: 14, color: Colors.grey)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            _buildSliderRow(
              label: 'Max Memory Tokens',
              description: 'Maximum tokens for memory section (500-4000)',
              value: _config.tokens.maxMemoryTokens.toDouble(),
              min: 500,
              max: 4000,
              divisions: 35,
              onChanged: (value) {
                setState(() {
                  _config = _config.copyWith(
                    tokens: _config.tokens.copyWith(maxMemoryTokens: value.round()),
                  );
                });
              },
            ),
            const SizedBox(height: 16),

            _buildSliderRow(
              label: 'Reserve Response Tokens',
              description: 'Tokens reserved for LLM response (500-2000)',
              value: _config.tokens.reserveResponseTokens.toDouble(),
              min: 500,
              max: 2000,
              divisions: 15,
              onChanged: (value) {
                setState(() {
                  _config = _config.copyWith(
                    tokens: _config.tokens.copyWith(reserveResponseTokens: value.round()),
                  );
                });
              },
            ),
            const SizedBox(height: 16),

            const Text('Truncation Strategy', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _config.tokens.truncationStrategy,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'most_relevant', child: Text('Keep Most Relevant')),
                DropdownMenuItem(value: 'newest', child: Text('Keep Newest')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _config = _config.copyWith(
                      tokens: _config.tokens.copyWith(truncationStrategy: value),
                    );
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 4-LAYER CONTEXT CARD
  // ═══════════════════════════════════════════════════════════

  Widget _build4LayerContextCard() {
    return Card(
      color: Colors.indigo[50],
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.layers, color: Colors.indigo[400]),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('4-Layer Context', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('Enhanced context injection for better AI memory', style: TextStyle(fontSize: 14, color: Colors.grey)),
                  ],
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('NEW', style: TextStyle(color: Colors.green[800], fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            // Layer 1: Immediate
            _build4LayerSection(
              icon: Icons.chat_bubble_outline,
              color: Colors.blue,
              title: 'Layer 1: IMMEDIATE',
              subtitle: 'Last 10 messages from current chat session',
              tokenBudget: 400,
              children: [
                Text('Max Messages: 10', style: TextStyle(color: Colors.grey[600])),
                Text('Format: conversation', style: TextStyle(color: Colors.grey[600])),
              ],
            ),
            const SizedBox(height: 16),

            // Layer 2: Session Summary
            _build4LayerSection(
              icon: Icons.summarize,
              color: Colors.orange,
              title: 'Layer 2: SESSION SUMMARY',
              subtitle: 'AI-generated summary if chat > 20 messages',
              tokenBudget: 200,
              children: [
                Text('Threshold: 20 messages', style: TextStyle(color: Colors.grey[600])),
                Text('Summarize first: 15 messages', style: TextStyle(color: Colors.grey[600])),
                Text('Cache: enabled (30 min TTL)', style: TextStyle(color: Colors.grey[600])),
              ],
            ),
            const SizedBox(height: 16),

            // Layer 3: User Profile
            _build4LayerSection(
              icon: Icons.person_outline,
              color: Colors.green,
              title: 'Layer 3: USER PROFILE',
              subtitle: 'Semantic search of user memories',
              tokenBudget: 300,
              children: [
                Text('Max Memories: 10', style: TextStyle(color: Colors.grey[600])),
                Text('Types: fact, preference, relationship, goal', style: TextStyle(color: Colors.grey[600])),
                Text('Excludes: events (→ Layer 4)', style: TextStyle(color: Colors.grey[600])),
              ],
            ),
            const SizedBox(height: 16),

            // Layer 4: Calendar
            _build4LayerSection(
              icon: Icons.calendar_today,
              color: Colors.purple,
              title: 'Layer 4: CALENDAR',
              subtitle: 'Upcoming events within 48 hours',
              tokenBudget: 100,
              children: [
                Text('Lookahead: 48 hours', style: TextStyle(color: Colors.grey[600])),
                Text('Max Events: 10', style: TextStyle(color: Colors.grey[600])),
                Text('Format: list', style: TextStyle(color: Colors.grey[600])),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            // Token Summary
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Token Budget Summary', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildTokenBar('Layer 1', 400, Colors.blue),
                      _buildTokenBar('Layer 2', 200, Colors.orange),
                      _buildTokenBar('Layer 3', 300, Colors.green),
                      _buildTokenBar('Layer 4', 100, Colors.purple),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Budget:', style: TextStyle(fontWeight: FontWeight.w500)),
                      const Text('1000 tokens', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Max Context:', style: TextStyle(color: Colors.grey[600])),
                      Text('1500 tokens', style: TextStyle(color: Colors.grey[600])),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _build4LayerSection({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required int tokenBudget,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
                Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                const SizedBox(height: 8),
                ...children,
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('~$tokenBudget', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
          ),
        ],
      ),
    );
  }

  Widget _buildTokenBar(String label, int tokens, Color color) {
    return Column(
      children: [
        Container(
          width: 60,
          height: tokens / 10,
          decoration: BoxDecoration(
            color: color.withOpacity(0.7),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 10)),
        Text('$tokens', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  // PIPELINE PREVIEW CARD
  // ═══════════════════════════════════════════════════════════

  Widget _buildPipelinePreviewCard() {
    final enabledTypes = _config.filter.getEnabledTypes();
    final enabledTiers = _config.filter.getEnabledTiers();

    return Card(
      color: Colors.blue[50],
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.functions, color: Colors.blue[400]),
                const SizedBox(width: 12),
                const Text(
                  'Injection Pipeline',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('1. Receive memories from Memory Query', style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 4),
            Text('2. Filter by types: ${enabledTypes.join(", ")}', style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 4),
            Text('3. Filter by tiers: ${enabledTiers.join(", ")}', style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 4),
            Text('4. Filter by relevance >= ${_config.injection.minRelevance.toStringAsFixed(2)}', style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 4),
            Text('5. Sort by ${_config.injection.sortBy}', style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 4),
            Text('6. Limit to ${_config.injection.maxMemories} memories', style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 4),
            Text('7. Format as ${_config.format.memoryFormat}', style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 4),
            Text('8. Build prompt (max ${_config.tokens.maxMemoryTokens} tokens)', style: const TextStyle(fontSize: 14)),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // TEST CARD
  // ═══════════════════════════════════════════════════════════

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
                    color: Colors.orange[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('PENDING', style: TextStyle(color: Colors.orange[800], fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            const Text('IIN (required)', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _iinController,
                    decoration: const InputDecoration(
                      hintText: 'XXXX-XXXX-XXXX-XXXX',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: 'Copy IIN',
                  onPressed: () {
                    if (_iinController.text.isNotEmpty) {
                      Clipboard.setData(ClipboardData(text: _iinController.text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('IIN copied!'), duration: Duration(seconds: 1)),
                      );
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            const Text('User Message', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(
              controller: _messageController,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'Cosa sai di me? Cosa dovrei mangiare?',
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
                const Text('Generated Prompt', style: TextStyle(fontWeight: FontWeight.w500)),
                if (_testResult != null)
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(
                        text: const JsonEncoder.withIndent('  ').convert(_testResult),
                      ));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Result copied!'), duration: Duration(seconds: 1)),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.copy, size: 14, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Text('Copy', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 200, maxHeight: 500),
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
                      child: Text('Enter IIN and message, then click "Run Test"', style: TextStyle(color: Colors.grey[500])),
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
    if (_messageController.text.isEmpty) {
      _showError('User message is required');
      return;
    }

    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    try {
      final response = await http.post(
        Uri.parse('https://us-central1-app-iamoneai-c36ec.cloudfunctions.net/testContextInjection'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'iin': _iinController.text.trim(),
          'message': _messageController.text.trim(),
        }),
      );

      if (response.statusCode == 200) {
        setState(() => _testResult = jsonDecode(response.body));
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

  // ═══════════════════════════════════════════════════════════
  // HELPER WIDGETS
  // ═══════════════════════════════════════════════════════════

  Widget _buildSliderRow({
    required String label,
    required String description,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    bool isDecimal = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
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
            Text(
              isDecimal ? value.toStringAsFixed(2) : value.round().toString(),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        Slider(value: value, min: min, max: max, divisions: divisions, onChanged: onChanged),
      ],
    );
  }

  Widget _buildToggleRow({
    required String label,
    required String description,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
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
}
