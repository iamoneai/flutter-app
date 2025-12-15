import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LLMRoutingScreen extends StatefulWidget {
  const LLMRoutingScreen({super.key});

  @override
  State<LLMRoutingScreen> createState() => _LLMRoutingScreenState();
}

class _LLMRoutingScreenState extends State<LLMRoutingScreen> {
  final _firestore = FirebaseFirestore.instance;
  bool _loading = true;
  bool _saving = false;

  // Claude models
  String _claudeModel = 'claude-3-haiku-20240307';
  int _claudeMaxTokens = 1024;
  
  // OpenAI models
  String _openaiModel = 'gpt-4o-mini';
  int _openaiMaxTokens = 1024;
  
  // Gemini models
  String _geminiModel = 'gemini-2.0-flash-exp';
  int _geminiMaxTokens = 1024;
  
  // Default provider
  String _defaultProvider = 'claude';
  
  // Metadata
  DateTime? _updatedAt;

  // Available models
  final List<String> _claudeModels = [
    'claude-3-5-sonnet-20241022',
    'claude-3-5-haiku-20241022',
    'claude-3-sonnet-20240229',
    'claude-3-haiku-20240307',
    'claude-3-opus-20240229',
  ];
  
  final List<String> _openaiModels = [
    'gpt-4o',
    'gpt-4o-mini',
    'gpt-4-turbo',
    'gpt-4',
    'gpt-3.5-turbo',
  ];
  
  final List<String> _geminiModels = [
    'gemini-2.0-flash-exp',
    'gemini-1.5-flash',
    'gemini-1.5-flash-8b',
    'gemini-1.5-pro',
  ];

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    setState(() => _loading = true);
    try {
      final doc = await _firestore
          .collection('admin')
          .doc('config')
          .collection('settings')
          .doc('llm')
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        final claude = data['claude'] as Map<String, dynamic>? ?? {};
        final openai = data['openai'] as Map<String, dynamic>? ?? {};
        final gemini = data['gemini'] as Map<String, dynamic>? ?? {};

        _claudeModel = claude['model'] ?? 'claude-3-haiku-20240307';
        _claudeMaxTokens = claude['max_tokens'] ?? 1024;
        _openaiModel = openai['model'] ?? 'gpt-4o-mini';
        _openaiMaxTokens = openai['max_tokens'] ?? 1024;
        _geminiModel = gemini['model'] ?? 'gemini-2.0-flash-exp';
        _geminiMaxTokens = gemini['max_tokens'] ?? 1024;
        _defaultProvider = data['default_provider'] ?? 'claude';
        _updatedAt = (data['updatedAt'] as Timestamp?)?.toDate();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading: $e'), backgroundColor: Colors.red),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _saveConfig() async {
    setState(() => _saving = true);
    try {
      await _firestore
          .collection('admin')
          .doc('config')
          .collection('settings')
          .doc('llm')
          .set({
        'claude': {
          'model': _claudeModel,
          'max_tokens': _claudeMaxTokens,
        },
        'openai': {
          'model': _openaiModel,
          'max_tokens': _openaiMaxTokens,
        },
        'gemini': {
          'model': _geminiModel,
          'max_tokens': _geminiMaxTokens,
        },
        'default_provider': _defaultProvider,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('LLM config saved!'), backgroundColor: Colors.green),
        );
        _loadConfig();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: Color(0xFF7c3aed)));

    return Container(
      color: const Color(0xFF0f0f1a),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.route, size: 32, color: Color(0xFF7c3aed)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('LLM Routing Configuration', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                      Text('Configure model versions and settings for each provider', style: TextStyle(color: Colors.grey[500])),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _saving ? null : _saveConfig,
                  icon: _saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save),
                  label: Text(_saving ? 'Saving...' : 'Save Config'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7c3aed),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Default Provider
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1a1a2e),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2a2a3e).withValues(alpha: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.star, color: Colors.amber[600]),
                      const SizedBox(width: 8),
                      const Text('Default Provider', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Used when no category matches', style: TextStyle(color: Colors.grey[500])),
                  const SizedBox(height: 16),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'claude', label: Text('Claude'), icon: Icon(Icons.circle, color: Colors.purple)),
                      ButtonSegment(value: 'openai', label: Text('OpenAI'), icon: Icon(Icons.circle, color: Colors.green)),
                      ButtonSegment(value: 'gemini', label: Text('Gemini'), icon: Icon(Icons.circle, color: Colors.blue)),
                    ],
                    selected: {_defaultProvider},
                    onSelectionChanged: (s) => setState(() => _defaultProvider = s.first),
                    style: ButtonStyle(
                      foregroundColor: WidgetStateProperty.all(Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

          // Three columns for providers
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Claude
              Expanded(child: _buildProviderCard(
                'Claude (Anthropic)',
                Colors.purple,
                Icons.psychology,
                _claudeModel,
                _claudeModels,
                (v) => setState(() => _claudeModel = v!),
                _claudeMaxTokens,
                (v) => setState(() => _claudeMaxTokens = v),
                'Best for: Code, reasoning, analysis',
              )),
              const SizedBox(width: 16),
              
              // OpenAI
              Expanded(child: _buildProviderCard(
                'OpenAI (GPT)',
                Colors.green,
                Icons.auto_awesome,
                _openaiModel,
                _openaiModels,
                (v) => setState(() => _openaiModel = v!),
                _openaiMaxTokens,
                (v) => setState(() => _openaiMaxTokens = v),
                'Best for: General tasks, creative writing',
              )),
              const SizedBox(width: 16),
              
              // Gemini
              Expanded(child: _buildProviderCard(
                'Google (Gemini)',
                Colors.blue,
                Icons.diamond,
                _geminiModel,
                _geminiModels,
                (v) => setState(() => _geminiModel = v!),
                _geminiMaxTokens,
                (v) => setState(() => _geminiMaxTokens = v),
                'Best for: Fast responses, embeddings, multimodal',
              )),
            ],
          ),
          const SizedBox(height: 24),

            // Info card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF6366f1).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF6366f1).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Color(0xFF6366f1)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('How Routing Works', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF6366f1))),
                        const SizedBox(height: 4),
                        Text(
                          '1. Message is classified by keywords (Categories screen)\n'
                          '2. Primary LLM for that category is used\n'
                          '3. If it fails, Fallback LLM is tried\n'
                          '4. Model versions configured here are used for each provider',
                          style: TextStyle(color: Colors.grey[400], fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            if (_updatedAt != null) ...[
              const SizedBox(height: 16),
              Text(
                'Last updated: ${_updatedAt!.month}/${_updatedAt!.day}/${_updatedAt!.year} ${_updatedAt!.hour}:${_updatedAt!.minute.toString().padLeft(2, '0')}',
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProviderCard(
    String title,
    Color color,
    IconData icon,
    String currentModel,
    List<String> models,
    ValueChanged<String?> onModelChanged,
    int maxTokens,
    ValueChanged<int> onTokensChanged,
    String description,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a2e),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2a2a3e).withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(description, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
          Divider(height: 24, color: const Color(0xFF2a2a3e).withValues(alpha: 0.5)),

          const Text('Model Version', style: TextStyle(fontWeight: FontWeight.w500, color: Colors.white)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: models.contains(currentModel) ? currentModel : models.first,
            dropdownColor: const Color(0xFF1a1a2e),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              isDense: true,
              filled: true,
              fillColor: const Color(0xFF0f0f1a),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: const Color(0xFF2a2a3e).withValues(alpha: 0.5)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: color),
              ),
            ),
            items: models.map((m) => DropdownMenuItem(
              value: m,
              child: Text(m, style: const TextStyle(fontSize: 13)),
            )).toList(),
            onChanged: onModelChanged,
          ),
          const SizedBox(height: 16),

          const Text('Max Tokens', style: TextStyle(fontWeight: FontWeight.w500, color: Colors.white)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: color,
                    inactiveTrackColor: const Color(0xFF2a2a3e),
                    thumbColor: color,
                    overlayColor: color.withValues(alpha: 0.2),
                  ),
                  child: Slider(
                    value: maxTokens.toDouble(),
                    min: 256,
                    max: 4096,
                    divisions: 15,
                    onChanged: (v) => onTokensChanged(v.round()),
                  ),
                ),
              ),
              SizedBox(
                width: 60,
                child: Text(maxTokens.toString(), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
