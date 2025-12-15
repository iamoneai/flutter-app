import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class GlobalSettingsScreen extends StatefulWidget {
  const GlobalSettingsScreen({super.key});

  @override
  State<GlobalSettingsScreen> createState() => _GlobalSettingsScreenState();
}

class _GlobalSettingsScreenState extends State<GlobalSettingsScreen> {
  final _firestore = FirebaseFirestore.instance;
  bool _loading = true;
  bool _saving = false;

  // Locale settings
  bool _autoDetectByIP = true;
  String _defaultDateFormat = 'MM/DD/YYYY';
  String _defaultTimeFormat = '12h';
  String _defaultTimezone = 'UTC';

  // Guardrails
  List<String> _blockedDomains = [];
  List<String> _restrictedDomains = [];
  String _restrictedDisclaimer = "I'm not a professional. Please consult a qualified {domain} expert.";
  int _maxResponseLength = 2000;
  String _contentFilterLevel = 'moderate';

  // Response defaults
  String _defaultStyle = 'friendly';
  bool _aiForSimpleRecall = false;
  bool _aiForFormatting = true;
  String _defaultEmojiUsage = 'moderate';
  String _defaultResponseLength = 'balanced';

  // Metadata
  DateTime? _updatedAt;
  String? _updatedBy;

  // Options
  final List<String> _dateFormats = ['MM/DD/YYYY', 'DD/MM/YYYY', 'YYYY-MM-DD'];
  final List<String> _timeFormats = ['12h', '24h'];
  final List<String> _timezones = ['UTC', 'America/New_York', 'America/Los_Angeles', 'America/Sao_Paulo', 'Europe/London', 'Europe/Paris', 'Asia/Tokyo', 'Asia/Shanghai', 'Australia/Sydney'];
  final List<String> _contentFilters = ['strict', 'moderate', 'relaxed'];
  final List<String> _styles = ['direct', 'friendly', 'conversational'];
  final List<String> _emojiOptions = ['none', 'minimal', 'moderate', 'frequent'];
  final List<String> _lengthOptions = ['brief', 'balanced', 'detailed'];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _loading = true);
    try {
      final doc = await _firestore.collection('admin').doc('config').collection('settings').doc('global').get();
      
      if (doc.exists) {
        final data = doc.data()!;
        final locale = data['locale'] as Map<String, dynamic>? ?? {};
        _autoDetectByIP = locale['auto_detect_by_ip'] ?? true;
        _defaultDateFormat = locale['default_date_format'] ?? 'MM/DD/YYYY';
        _defaultTimeFormat = locale['default_time_format'] ?? '12h';
        _defaultTimezone = locale['default_timezone'] ?? 'UTC';

        final guardrails = data['guardrails'] as Map<String, dynamic>? ?? {};
        _blockedDomains = List<String>.from(guardrails['blocked_domains'] ?? []);
        _restrictedDomains = List<String>.from(guardrails['restricted_domains'] ?? []);
        _restrictedDisclaimer = guardrails['restricted_domain_disclaimer'] ?? _restrictedDisclaimer;
        _maxResponseLength = guardrails['max_response_length'] ?? 2000;
        _contentFilterLevel = guardrails['content_filter_level'] ?? 'moderate';

        final response = data['response'] as Map<String, dynamic>? ?? {};
        _defaultStyle = response['default_style'] ?? 'friendly';
        _aiForSimpleRecall = response['ai_for_simple_recall'] ?? false;
        _aiForFormatting = response['ai_for_formatting'] ?? true;
        _defaultEmojiUsage = response['default_emoji_usage'] ?? 'moderate';
        _defaultResponseLength = response['default_response_length'] ?? 'balanced';

        _updatedAt = (data['updatedAt'] as Timestamp?)?.toDate();
        _updatedBy = data['updatedBy'];
      } else {
        _blockedDomains = ['illegal_activity', 'violence', 'self_harm', 'explicit_content'];
        _restrictedDomains = ['medical', 'legal', 'financial'];
      }
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
    setState(() => _saving = true);
    try {
      await _firestore.collection('admin').doc('config').collection('settings').doc('global').set({
        'locale': {
          'auto_detect_by_ip': _autoDetectByIP,
          'default_date_format': _defaultDateFormat,
          'default_time_format': _defaultTimeFormat,
          'default_timezone': _defaultTimezone,
        },
        'guardrails': {
          'blocked_domains': _blockedDomains,
          'restricted_domains': _restrictedDomains,
          'restricted_domain_disclaimer': _restrictedDisclaimer,
          'max_response_length': _maxResponseLength,
          'content_filter_level': _contentFilterLevel,
        },
        'response': {
          'default_style': _defaultStyle,
          'ai_for_simple_recall': _aiForSimpleRecall,
          'ai_for_formatting': _aiForFormatting,
          'default_emoji_usage': _defaultEmojiUsage,
          'default_response_length': _defaultResponseLength,
        },
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': 'admin',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings saved'), backgroundColor: Colors.green),
        );
        _loadSettings();
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

  void _addDomain(List<String> list, String title) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add $title'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Domain name', hintText: 'e.g., gambling'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final value = controller.text.trim().toLowerCase().replaceAll(' ', '_');
              if (value.isNotEmpty && !list.contains(value)) {
                setState(() => list.add(value));
              }
              Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
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
            Row(
              children: [
                const Icon(Icons.settings, size: 32, color: Color(0xFF7c3aed)),
                const SizedBox(width: 12),
                const Text('Global Settings', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: _saving ? null : _saveSettings,
                  icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save),
                  label: Text(_saving ? 'Saving...' : 'Save Settings'),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7c3aed), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('These settings apply to all users by default', style: TextStyle(color: Colors.grey[500], fontSize: 14)),
            const SizedBox(height: 24),

          _buildSection(Icons.language, 'Locale', 'Location detection and date/time formats', [
            SwitchListTile(title: const Text('Auto-detect location by IP'), subtitle: const Text('Automatically set date/time format based on user location'), value: _autoDetectByIP, onChanged: (v) => setState(() => _autoDetectByIP = v)),
            const Divider(),
            Row(children: [
              Expanded(child: _buildDropdown('Default Date Format', _defaultDateFormat, _dateFormats, (v) => setState(() => _defaultDateFormat = v!), displayBuilder: _getDateExample)),
              const SizedBox(width: 16),
              Expanded(child: _buildDropdown('Default Time Format', _defaultTimeFormat, _timeFormats, (v) => setState(() => _defaultTimeFormat = v!), displayBuilder: (v) => v == '12h' ? '12 hour (3:30 PM)' : '24 hour (15:30)')),
            ]),
            const SizedBox(height: 16),
            _buildDropdown('Default Timezone', _defaultTimezone, _timezones, (v) => setState(() => _defaultTimezone = v!)),
          ]),
          const SizedBox(height: 24),

          _buildSection(Icons.shield, 'Guardrails', 'Safety controls and content restrictions', [
            const Text('Blocked Domains', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('AI will refuse to help with these topics', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ..._blockedDomains.map((d) => Chip(label: Text(d), backgroundColor: Colors.red[100], deleteIcon: const Icon(Icons.close, size: 18), onDeleted: () => setState(() => _blockedDomains.remove(d)))),
              ActionChip(label: const Text('+ Add'), onPressed: () => _addDomain(_blockedDomains, 'Blocked Domain')),
            ]),
            const SizedBox(height: 24),
            const Text('Restricted Domains', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('AI will add disclaimer for these topics', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ..._restrictedDomains.map((d) => Chip(label: Text(d), backgroundColor: Colors.orange[100], deleteIcon: const Icon(Icons.close, size: 18), onDeleted: () => setState(() => _restrictedDomains.remove(d)))),
              ActionChip(label: const Text('+ Add'), onPressed: () => _addDomain(_restrictedDomains, 'Restricted Domain')),
            ]),
            const SizedBox(height: 16),
            TextField(decoration: const InputDecoration(labelText: 'Restricted Domain Disclaimer', helperText: 'Use {domain} as placeholder', border: OutlineInputBorder()), controller: TextEditingController(text: _restrictedDisclaimer), onChanged: (v) => _restrictedDisclaimer = v, maxLines: 2),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: _buildDropdown('Content Filter Level', _contentFilterLevel, _contentFilters, (v) => setState(() => _contentFilterLevel = v!), displayBuilder: _capitalize)),
              const SizedBox(width: 16),
              Expanded(child: TextField(decoration: const InputDecoration(labelText: 'Max Response Length', suffixText: 'chars', border: OutlineInputBorder()), keyboardType: TextInputType.number, controller: TextEditingController(text: _maxResponseLength.toString()), onChanged: (v) => _maxResponseLength = int.tryParse(v) ?? 2000)),
            ]),
          ]),
          const SizedBox(height: 24),

          _buildSection(Icons.chat_bubble_outline, 'Response Defaults', 'How AI responds by default', [
            const Text('Default Response Style', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            RadioGroup<String>(
              groupValue: _defaultStyle,
              onChanged: (v) => setState(() => _defaultStyle = v!),
              child: Row(children: _styles.map((s) => Expanded(child: RadioListTile<String>(title: Text(_capitalize(s)), subtitle: Text(_styleDesc(s), style: const TextStyle(fontSize: 11)), value: s, contentPadding: EdgeInsets.zero))).toList()),
            ),
            const Divider(),
            SwitchListTile(title: const Text('Use AI for simple memory recall'), subtitle: const Text('e.g., "What\'s my wife\'s name?" - If OFF, returns data directly'), value: _aiForSimpleRecall, onChanged: (v) => setState(() => _aiForSimpleRecall = v)),
            SwitchListTile(title: const Text('Use AI for response formatting'), subtitle: const Text('Makes responses more natural (costs more)'), value: _aiForFormatting, onChanged: (v) => setState(() => _aiForFormatting = v)),
            const Divider(),
            Row(children: [
              Expanded(child: _buildDropdown('Default Emoji Usage', _defaultEmojiUsage, _emojiOptions, (v) => setState(() => _defaultEmojiUsage = v!), displayBuilder: _capitalize)),
              const SizedBox(width: 16),
              Expanded(child: _buildDropdown('Default Response Length', _defaultResponseLength, _lengthOptions, (v) => setState(() => _defaultResponseLength = v!), displayBuilder: _capitalize)),
            ]),
          ]),
          const SizedBox(height: 24),

            if (_updatedAt != null) Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFF1a1a2e), borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                Icon(Icons.history, size: 16, color: Colors.grey[500]),
                const SizedBox(width: 8),
                Text('Last updated: ${_updatedAt!.month}/${_updatedAt!.day}/${_updatedAt!.year} by ${_updatedBy ?? 'unknown'}', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(IconData icon, String title, String subtitle, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a2e),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2a2a3e).withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: const Color(0xFF7c3aed)),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            Text(subtitle, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
          ]),
        ]),
        Divider(height: 24, color: const Color(0xFF2a2a3e).withValues(alpha: 0.5)),
        ...children,
      ]),
    );
  }

  Widget _buildDropdown(String label, String value, List<String> items, ValueChanged<String?> onChanged, {String Function(String)? displayBuilder}) {
    return DropdownButtonFormField<String>(initialValue: value, decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()), items: items.map((i) => DropdownMenuItem(value: i, child: Text(displayBuilder?.call(i) ?? i))).toList(), onChanged: onChanged);
  }

  String _getDateExample(String f) => f == 'MM/DD/YYYY' ? 'MM/DD/YYYY (12/25/2025)' : f == 'DD/MM/YYYY' ? 'DD/MM/YYYY (25/12/2025)' : 'YYYY-MM-DD (2025-12-25)';
  String _styleDesc(String s) => s == 'direct' ? 'Just facts, minimal' : s == 'friendly' ? 'Brief, friendly touch' : 'Full AI personality';
  String _capitalize(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}
