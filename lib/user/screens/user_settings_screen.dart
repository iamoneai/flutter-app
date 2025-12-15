import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import '../services/user_settings_service.dart';
import '../widgets/create_category_dialog.dart';
import '../widgets/edit_category_dialog.dart';

class UserSettingsScreen extends StatefulWidget {
  const UserSettingsScreen({super.key});

  @override
  State<UserSettingsScreen> createState() => _UserSettingsScreenState();
}

class _UserSettingsScreenState extends State<UserSettingsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _settingsService = UserSettingsService();
  final _user = FirebaseAuth.instance.currentUser;

  bool _loading = true;
  bool _saving = false;

  // Settings state
  List<Map<String, dynamic>> _categories = [];

  // Chat preferences
  String _defaultContext = 'personal';
  String _responseStyle = 'balanced';
  String _personalityTone = 'friendly';
  bool _memoryEnabled = true;
  bool _autoMemorySave = true;
  int _maxTokens = 1024;
  double _temperature = 0.7;
  String _emojiUsage = 'moderate';

  // LLM preferences
  String _defaultLlm = 'gemini-flash';
  String _fallbackLlm = 'gpt-4o-mini';
  bool _useOwnKeys = false;
  final _openaiKeyController = TextEditingController();
  final _anthropicKeyController = TextEditingController();
  final _googleKeyController = TextEditingController();
  bool _showOpenaiKey = false;
  bool _showAnthropicKey = false;
  bool _showGoogleKey = false;

  // Privacy
  int _memoryRetentionDays = 90;
  bool _autoDeleteHistory = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _openaiKeyController.dispose();
    _anthropicKeyController.dispose();
    _googleKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (_user == null) return;

    setState(() => _loading = true);

    try {
      // Load settings
      final settings = await _settingsService.getUserSettings(_user.uid);
      if (settings != null) {
        _defaultContext = settings['defaultContext'] ?? 'personal';
        _responseStyle = settings['responseStyle'] ?? 'balanced';
        _personalityTone = settings['personalityTone'] ?? 'friendly';
        _memoryEnabled = settings['memoryEnabled'] ?? true;
        _autoMemorySave = settings['autoMemorySave'] ?? true;
        _maxTokens = settings['maxTokens'] ?? 1024;
        _temperature = (settings['temperature'] ?? 0.7).toDouble();
        _emojiUsage = settings['emojiUsage'] ?? 'moderate';
        _defaultLlm = settings['defaultLlm'] ?? 'gemini-flash';
        _fallbackLlm = settings['fallbackLlm'] ?? 'gpt-4o-mini';
        _useOwnKeys = settings['useOwnKeys'] ?? false;
        _openaiKeyController.text = settings['openaiKey'] ?? '';
        _anthropicKeyController.text = settings['anthropicKey'] ?? '';
        _googleKeyController.text = settings['googleKey'] ?? '';
        _memoryRetentionDays = settings['memoryRetentionDays'] ?? 90;
        _autoDeleteHistory = settings['autoDeleteHistory'] ?? false;
      }

      // Load categories
      final categories = await _settingsService.getUserCategories(_user.uid);
      _categories = categories;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading settings: $e'), backgroundColor: Colors.red),
        );
      }
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _saveSettings() async {
    if (_user == null) return;

    setState(() => _saving = true);

    try {
      await _settingsService.saveUserSettings(_user.uid, {
        'defaultContext': _defaultContext,
        'responseStyle': _responseStyle,
        'personalityTone': _personalityTone,
        'memoryEnabled': _memoryEnabled,
        'autoMemorySave': _autoMemorySave,
        'maxTokens': _maxTokens,
        'temperature': _temperature,
        'emojiUsage': _emojiUsage,
        'defaultLlm': _defaultLlm,
        'fallbackLlm': _fallbackLlm,
        'useOwnKeys': _useOwnKeys,
        'openaiKey': _openaiKeyController.text.isEmpty ? null : _openaiKeyController.text,
        'anthropicKey': _anthropicKeyController.text.isEmpty ? null : _anthropicKeyController.text,
        'googleKey': _googleKeyController.text.isEmpty ? null : _googleKeyController.text,
        'memoryRetentionDays': _memoryRetentionDays,
        'autoDeleteHistory': _autoDeleteHistory,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings saved!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving: $e'), backgroundColor: Colors.red),
        );
      }
    }

    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0f0f1a),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1a1a2e),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Settings', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _saveSettings,
            icon: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save, color: Color(0xFF7c3aed)),
            label: Text(_saving ? 'Saving...' : 'Save', style: const TextStyle(color: Color(0xFF7c3aed))),
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF7c3aed),
          labelColor: const Color(0xFF7c3aed),
          unselectedLabelColor: Colors.grey[500],
          tabs: const [
            Tab(icon: Icon(Icons.category), text: 'Categories'),
            Tab(icon: Icon(Icons.chat), text: 'Chat'),
            Tab(icon: Icon(Icons.psychology), text: 'LLM'),
            Tab(icon: Icon(Icons.privacy_tip), text: 'Privacy'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF7c3aed)))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildCategoriesTab(),
                _buildChatTab(),
                _buildLlmTab(),
                _buildPrivacyTab(),
              ],
            ),
    );
  }

  // ============================================
  // CATEGORIES TAB
  // ============================================

  Widget _buildCategoriesTab() {
    final customCategories = _categories.where((c) => c['type'] == 'custom').toList();
    final modifiedCategories = _categories.where((c) => c['type'] == 'modified').toList();
    final inheritedCategories = _categories.where((c) => c['type'] == 'inherited').toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Action buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _showCreateCategoryDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('Create New Category'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7c3aed),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _syncAdminUpdates,
                icon: const Icon(Icons.sync),
                label: const Text('Sync Updates'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF6366f1),
                  side: const BorderSide(color: Color(0xFF6366f1)),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Custom Categories
          if (customCategories.isNotEmpty) ...[
            _buildCategorySection('MY CUSTOM CATEGORIES', customCategories, Colors.blue),
            const SizedBox(height: 20),
          ],

          // Modified Categories
          if (modifiedCategories.isNotEmpty) ...[
            _buildCategorySection('MODIFIED DEFAULTS', modifiedCategories, Colors.orange),
            const SizedBox(height: 20),
          ],

          // Inherited Categories
          if (inheritedCategories.isNotEmpty) ...[
            _buildCategorySection('DEFAULT CATEGORIES', inheritedCategories, Colors.grey),
          ],

          if (_categories.isEmpty)
            Center(
              child: Column(
                children: [
                  const SizedBox(height: 60),
                  Icon(Icons.category_outlined, size: 64, color: Colors.grey[700]),
                  const SizedBox(height: 16),
                  Text('No categories yet', style: TextStyle(color: Colors.grey[500], fontSize: 16)),
                  const SizedBox(height: 8),
                  Text('Create your first category or sync from admin defaults',
                      style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCategorySection(String title, List<Map<String, dynamic>> categories, Color badgeColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 20,
              decoration: BoxDecoration(
                color: badgeColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(title, style: TextStyle(color: Colors.grey[400], fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('${categories.length}', style: TextStyle(color: badgeColor, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...categories.map((cat) => _buildCategoryCard(cat)),
      ],
    );
  }

  Widget _buildCategoryCard(Map<String, dynamic> category) {
    final type = category['type'] as String? ?? 'inherited';
    final isActive = category['isActive'] as bool? ?? true;
    final priority = category['priority'] as String? ?? 'MEDIUM';
    final keywords = List<String>.from(category['keywords'] ?? []);

    Color badgeColor;
    String badgeText;
    switch (type) {
      case 'custom':
        badgeColor = Colors.blue;
        badgeText = 'CUSTOM';
        break;
      case 'modified':
        badgeColor = Colors.orange;
        badgeText = 'MODIFIED';
        break;
      default:
        badgeColor = Colors.grey;
        badgeText = 'DEFAULT';
    }

    Color priorityColor;
    switch (priority) {
      case 'HIGH':
        priorityColor = Colors.green;
        break;
      case 'MEDIUM':
        priorityColor = Colors.yellow[700]!;
        break;
      default:
        priorityColor = Colors.grey;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a2e),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? const Color(0xFF2a2a3e).withValues(alpha: 0.5) : Colors.grey.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      category['name'] ?? 'Unnamed',
                      style: TextStyle(
                        color: isActive ? Colors.white : Colors.grey,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(badgeText, style: TextStyle(color: badgeColor, fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: priorityColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(priority, style: TextStyle(color: priorityColor, fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
              Switch(
                value: isActive,
                onChanged: (v) => _toggleCategory(category['id'], v),
                activeTrackColor: const Color(0xFF7c3aed),
              ),
            ],
          ),
          if (category['description'] != null && (category['description'] as String).isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(category['description'], style: TextStyle(color: Colors.grey[500], fontSize: 13)),
          ],
          const SizedBox(height: 12),

          // Keywords
          if (keywords.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: keywords.take(6).map((k) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366f1).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF6366f1).withValues(alpha: 0.3)),
                ),
                child: Text(k, style: const TextStyle(color: Color(0xFF6366f1), fontSize: 11)),
              )).toList(),
            ),
          const SizedBox(height: 12),

          // LLM routing
          Row(
            children: [
              _buildLlmDot(category['primaryLlm'] ?? 'gemini-flash'),
              const SizedBox(width: 4),
              Text(category['primaryLlm'] ?? 'gemini-flash', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 8),
              _buildLlmDot(category['fallbackLlm'] ?? 'gpt-4o-mini'),
              const SizedBox(width: 4),
              Text(category['fallbackLlm'] ?? 'gpt-4o-mini', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
            ],
          ),
          const SizedBox(height: 12),

          // Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (type == 'modified' && category['sourceAdminId'] != null)
                TextButton.icon(
                  onPressed: () => _resetCategory(category),
                  icon: Icon(Icons.restore, size: 16, color: Colors.orange[400]),
                  label: Text('Reset', style: TextStyle(color: Colors.orange[400], fontSize: 12)),
                ),
              TextButton.icon(
                onPressed: () => _showEditCategoryDialog(category),
                icon: Icon(Icons.edit, size: 16, color: Colors.grey[400]),
                label: Text(type == 'inherited' ? 'Customize' : 'Edit', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
              ),
              if (type == 'custom')
                TextButton.icon(
                  onPressed: () => _deleteCategory(category),
                  icon: Icon(Icons.delete, size: 16, color: Colors.red[400]),
                  label: Text('Delete', style: TextStyle(color: Colors.red[400], fontSize: 12)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLlmDot(String llm) {
    Color color;
    if (llm.contains('claude')) {
      color = Colors.purple;
    } else if (llm.contains('gpt')) {
      color = Colors.green;
    } else {
      color = Colors.blue;
    }
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  // ============================================
  // CHAT TAB
  // ============================================

  Widget _buildChatTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSection('Context & Style', [
            _buildDropdownField(
              'Default Context',
              _defaultContext,
              ['personal', 'work', 'family'],
              (v) => setState(() => _defaultContext = v!),
              icon: Icons.folder_outlined,
            ),
            const SizedBox(height: 16),
            _buildSegmentedField(
              'Response Style',
              _responseStyle,
              ['brief', 'balanced', 'detailed'],
              (v) => setState(() => _responseStyle = v),
            ),
            const SizedBox(height: 16),
            _buildSegmentedField(
              'Personality Tone',
              _personalityTone,
              ['professional', 'friendly', 'casual'],
              (v) => setState(() => _personalityTone = v),
            ),
            const SizedBox(height: 16),
            _buildDropdownField(
              'Emoji Usage',
              _emojiUsage,
              ['none', 'minimal', 'moderate', 'frequent'],
              (v) => setState(() => _emojiUsage = v!),
              icon: Icons.emoji_emotions_outlined,
            ),
          ]),
          const SizedBox(height: 24),

          _buildSection('Memory Settings', [
            SwitchListTile(
              title: const Text('Enable Memory Retrieval', style: TextStyle(color: Colors.white)),
              subtitle: Text('AI will recall relevant information from past conversations', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
              value: _memoryEnabled,
              onChanged: (v) => setState(() => _memoryEnabled = v),
              activeTrackColor: const Color(0xFF7c3aed),
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile(
              title: const Text('Auto-save Memories', style: TextStyle(color: Colors.white)),
              subtitle: Text('Automatically save important information from conversations', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
              value: _autoMemorySave,
              onChanged: (v) => setState(() => _autoMemorySave = v),
              activeTrackColor: const Color(0xFF7c3aed),
              contentPadding: EdgeInsets.zero,
            ),
          ]),
          const SizedBox(height: 24),

          _buildSection('Response Parameters', [
            _buildSliderField(
              'Max Tokens',
              _maxTokens.toDouble(),
              256,
              4096,
              (v) => setState(() => _maxTokens = v.round()),
              suffix: ' tokens',
            ),
            const SizedBox(height: 16),
            _buildSliderField(
              'Temperature (Creativity)',
              _temperature,
              0.0,
              1.0,
              (v) => setState(() => _temperature = v),
              decimals: 2,
            ),
          ]),
        ],
      ),
    );
  }

  // ============================================
  // LLM TAB
  // ============================================

  Widget _buildLlmTab() {
    final llms = _settingsService.getAvailableLlms();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSection('Default LLM Providers', [
            _buildDropdownField(
              'Primary LLM',
              _defaultLlm,
              llms.map((l) => l['id']!).toList(),
              (v) => setState(() => _defaultLlm = v!),
              icon: Icons.psychology,
              displayBuilder: (id) => llms.firstWhere((l) => l['id'] == id, orElse: () => {'name': id})['name']!,
            ),
            const SizedBox(height: 16),
            _buildDropdownField(
              'Fallback LLM',
              _fallbackLlm,
              llms.map((l) => l['id']!).toList(),
              (v) => setState(() => _fallbackLlm = v!),
              icon: Icons.replay,
              displayBuilder: (id) => llms.firstWhere((l) => l['id'] == id, orElse: () => {'name': id})['name']!,
            ),
          ]),
          const SizedBox(height: 24),

          _buildSection('Bring Your Own API Keys', [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF6366f1).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF6366f1).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Color(0xFF6366f1), size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Use your own API keys for unlimited usage. You are responsible for usage costs.',
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Use My API Keys', style: TextStyle(color: Colors.white)),
              subtitle: Text('Route requests through your own API keys', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
              value: _useOwnKeys,
              onChanged: (v) => setState(() => _useOwnKeys = v),
              activeTrackColor: const Color(0xFF7c3aed),
              contentPadding: EdgeInsets.zero,
            ),
            if (_useOwnKeys) ...[
              const Divider(color: Color(0xFF2a2a3e)),
              const SizedBox(height: 8),
              _buildApiKeyField(
                'OpenAI API Key',
                _openaiKeyController,
                _showOpenaiKey,
                (v) => setState(() => _showOpenaiKey = v),
                Colors.green,
              ),
              const SizedBox(height: 16),
              _buildApiKeyField(
                'Anthropic API Key',
                _anthropicKeyController,
                _showAnthropicKey,
                (v) => setState(() => _showAnthropicKey = v),
                Colors.purple,
              ),
              const SizedBox(height: 16),
              _buildApiKeyField(
                'Google AI API Key',
                _googleKeyController,
                _showGoogleKey,
                (v) => setState(() => _showGoogleKey = v),
                Colors.blue,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.orange[400], size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Your keys are stored securely but you\'re responsible for usage costs.',
                        style: TextStyle(color: Colors.orange[400], fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ]),
        ],
      ),
    );
  }

  Widget _buildApiKeyField(
    String label,
    TextEditingController controller,
    bool showKey,
    ValueChanged<bool> onToggle,
    Color accentColor,
  ) {
    return TextFormField(
      controller: controller,
      obscureText: !showKey,
      style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey[500]),
        prefixIcon: Icon(Icons.key, color: accentColor, size: 20),
        suffixIcon: IconButton(
          icon: Icon(showKey ? Icons.visibility_off : Icons.visibility, color: Colors.grey[600]),
          onPressed: () => onToggle(!showKey),
        ),
        filled: true,
        fillColor: const Color(0xFF0f0f1a),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: const Color(0xFF2a2a3e).withValues(alpha: 0.5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: const Color(0xFF2a2a3e).withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accentColor),
        ),
      ),
    );
  }

  // ============================================
  // PRIVACY TAB
  // ============================================

  Widget _buildPrivacyTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSection('Data Retention', [
            _buildDropdownField(
              'Memory Retention Period',
              _memoryRetentionDays.toString(),
              ['7', '30', '90', '365', '-1'],
              (v) => setState(() => _memoryRetentionDays = int.parse(v!)),
              icon: Icons.schedule,
              displayBuilder: (v) {
                switch (v) {
                  case '7': return '7 days';
                  case '30': return '30 days';
                  case '90': return '90 days';
                  case '365': return '1 year';
                  case '-1': return 'Forever';
                  default: return v;
                }
              },
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Auto-delete Chat History', style: TextStyle(color: Colors.white)),
              subtitle: Text('Automatically delete old chat history based on retention period', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
              value: _autoDeleteHistory,
              onChanged: (v) => setState(() => _autoDeleteHistory = v),
              activeTrackColor: const Color(0xFF7c3aed),
              contentPadding: EdgeInsets.zero,
            ),
          ]),
          const SizedBox(height: 24),

          _buildSection('Export & Delete', [
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _exportData,
                icon: const Icon(Icons.download),
                label: const Text('Export My Data'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF6366f1),
                  side: const BorderSide(color: Color(0xFF6366f1)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _deleteAllData,
                icon: const Icon(Icons.delete_forever),
                label: const Text('Delete All My Data'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Deleting your data is permanent and cannot be undone.',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ]),
        ],
      ),
    );
  }

  // ============================================
  // HELPER WIDGETS
  // ============================================

  Widget _buildSection(String title, List<Widget> children) {
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
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildDropdownField(
    String label,
    String value,
    List<String> options,
    ValueChanged<String?> onChanged, {
    IconData? icon,
    String Function(String)? displayBuilder,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: options.contains(value) ? value : options.first,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey[500]),
        prefixIcon: icon != null ? Icon(icon, color: Colors.grey[600], size: 20) : null,
        filled: true,
        fillColor: const Color(0xFF0f0f1a),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: const Color(0xFF2a2a3e).withValues(alpha: 0.5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: const Color(0xFF2a2a3e).withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF7c3aed)),
        ),
      ),
      dropdownColor: const Color(0xFF1a1a2e),
      style: const TextStyle(color: Colors.white),
      items: options.map((o) => DropdownMenuItem(
        value: o,
        child: Text(displayBuilder?.call(o) ?? _capitalize(o)),
      )).toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildSegmentedField(String label, String value, List<String> options, ValueChanged<String> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 13)),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: options.map((o) => ButtonSegment(
            value: o,
            label: Text(_capitalize(o)),
          )).toList(),
          selected: {value},
          onSelectionChanged: (s) => onChanged(s.first),
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return const Color(0xFF7c3aed);
              }
              return const Color(0xFF0f0f1a);
            }),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return Colors.white;
              }
              return Colors.grey[500];
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildSliderField(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged, {
    String suffix = '',
    int decimals = 0,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 13)),
            Text(
              '${value.toStringAsFixed(decimals)}$suffix',
              style: const TextStyle(color: Color(0xFF7c3aed), fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: const Color(0xFF7c3aed),
            inactiveTrackColor: const Color(0xFF2a2a3e),
            thumbColor: const Color(0xFF7c3aed),
            overlayColor: const Color(0xFF7c3aed).withValues(alpha: 0.2),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  String _capitalize(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  // ============================================
  // CATEGORY ACTIONS
  // ============================================

  void _showCreateCategoryDialog() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => const CreateCategoryDialog(),
    );

    if (result != null && _user != null) {
      try {
        await _settingsService.createCategory(_user.uid, result);
        _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Category created!'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  void _showEditCategoryDialog(Map<String, dynamic> category) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => EditCategoryDialog(category: category),
    );

    if (result != null && _user != null) {
      try {
        final wasInherited = category['type'] == 'inherited';
        await _settingsService.updateCategory(_user.uid, category['id'], result, wasInherited: wasInherited);
        _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Category updated!'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  void _toggleCategory(String categoryId, bool isActive) async {
    if (_user == null) return;
    try {
      await _settingsService.toggleCategory(_user.uid, categoryId, isActive);
      _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _resetCategory(Map<String, dynamic> category) async {
    if (_user == null || category['sourceAdminId'] == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        title: const Text('Reset to Default?', style: TextStyle(color: Colors.white)),
        content: const Text('This will restore the original admin settings for this category.', style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _settingsService.resetCategoryToDefault(_user.uid, category['id'], category['sourceAdminId']);
        _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Category reset to default!'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  void _deleteCategory(Map<String, dynamic> category) async {
    if (_user == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        title: const Text('Delete Category?', style: TextStyle(color: Colors.white)),
        content: Text('Are you sure you want to delete "${category['name']}"?', style: const TextStyle(color: Colors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _settingsService.deleteCategory(_user.uid, category['id']);
        _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Category deleted!'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  void _syncAdminUpdates() async {
    if (_user == null) return;

    try {
      final updates = await _settingsService.checkAdminUpdates(_user.uid);
      final newCategories = updates['newCategories'] as List;

      if (newCategories.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No new categories available'), backgroundColor: Colors.blue),
          );
        }
        return;
      }

      if (!mounted) return;

      final selectedIds = await showDialog<List<String>>(
        context: context,
        builder: (ctx) => _SyncDialog(newCategories: newCategories.cast<Map<String, dynamic>>()),
      );

      if (!mounted) return;
      if (selectedIds != null && selectedIds.isNotEmpty) {
        await _settingsService.syncNewAdminCategories(_user.uid, selectedIds);
        _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Added ${selectedIds.length} categories!'), backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ============================================
  // PRIVACY ACTIONS
  // ============================================

  void _exportData() async {
    if (_user == null) return;

    try {
      final data = await _settingsService.exportUserData(_user.uid);
      final jsonString = const JsonEncoder.withIndent('  ').convert(data);

      await Clipboard.setData(ClipboardData(text: jsonString));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Data copied to clipboard!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _deleteAllData() async {
    if (_user == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.red[400]),
            const SizedBox(width: 12),
            const Text('Delete All Data?', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('This will permanently delete:', style: TextStyle(color: Colors.grey)),
            SizedBox(height: 12),
            Text('• All your settings', style: TextStyle(color: Colors.white)),
            Text('• All your categories', style: TextStyle(color: Colors.white)),
            Text('• All your memories', style: TextStyle(color: Colors.white)),
            Text('• All your chat history', style: TextStyle(color: Colors.white)),
            SizedBox(height: 12),
            Text('This action CANNOT be undone!', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete Everything'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _settingsService.deleteAllUserData(_user.uid);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('All data deleted'), backgroundColor: Colors.green),
          );
          Navigator.of(context).pushNamedAndRemoveUntil('/user', (route) => false);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }
}

// ============================================
// SYNC DIALOG
// ============================================

class _SyncDialog extends StatefulWidget {
  final List<Map<String, dynamic>> newCategories;

  const _SyncDialog({required this.newCategories});

  @override
  State<_SyncDialog> createState() => _SyncDialogState();
}

class _SyncDialogState extends State<_SyncDialog> {
  late Set<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds = widget.newCategories.map((c) => c['id'] as String).toSet();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1a1a2e),
      title: const Text('Admin Category Updates', style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.newCategories.length} new categories available:', style: TextStyle(color: Colors.grey[400])),
            const SizedBox(height: 16),
            ...widget.newCategories.map((cat) => CheckboxListTile(
              title: Text(cat['name'] ?? 'Unnamed', style: const TextStyle(color: Colors.white)),
              subtitle: Text(cat['description'] ?? '', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
              value: _selectedIds.contains(cat['id']),
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _selectedIds.add(cat['id']);
                  } else {
                    _selectedIds.remove(cat['id']);
                  }
                });
              },
              activeColor: const Color(0xFF7c3aed),
              contentPadding: EdgeInsets.zero,
            )),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _selectedIds.toList()),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7c3aed)),
          child: Text('Add ${_selectedIds.length} Categories'),
        ),
      ],
    );
  }
}
