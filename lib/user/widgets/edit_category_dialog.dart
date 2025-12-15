import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EditCategoryDialog extends StatefulWidget {
  final Map<String, dynamic> category;

  const EditCategoryDialog({super.key, required this.category});

  @override
  State<EditCategoryDialog> createState() => _EditCategoryDialogState();
}

class _EditCategoryDialogState extends State<EditCategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  final _keywordController = TextEditingController();

  late List<String> _keywords;
  late String _primaryLlm;
  late String _fallbackLlm;
  late String _priority;
  late String _contextFilter;

  bool _showOriginal = false;
  Map<String, dynamic>? _originalAdminData;

  final List<Map<String, String>> _llmOptions = [
    {'id': 'claude-haiku', 'name': 'Claude Haiku', 'provider': 'claude'},
    {'id': 'claude-sonnet', 'name': 'Claude Sonnet', 'provider': 'claude'},
    {'id': 'gpt-4o-mini', 'name': 'GPT-4o Mini', 'provider': 'openai'},
    {'id': 'gpt-4o', 'name': 'GPT-4o', 'provider': 'openai'},
    {'id': 'gemini-flash', 'name': 'Gemini Flash', 'provider': 'gemini'},
    {'id': 'gemini-pro', 'name': 'Gemini Pro', 'provider': 'gemini'},
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.category['name'] ?? '');
    _descriptionController = TextEditingController(text: widget.category['description'] ?? '');
    _keywords = List<String>.from(widget.category['keywords'] ?? []);
    _primaryLlm = widget.category['primaryLlm'] ?? 'gemini-flash';
    _fallbackLlm = widget.category['fallbackLlm'] ?? 'gpt-4o-mini';
    _priority = widget.category['priority'] ?? 'MEDIUM';
    _contextFilter = widget.category['contextFilter'] ?? 'all';

    // Load original admin data if this is inherited or modified
    if (widget.category['sourceAdminId'] != null) {
      _loadOriginalData();
    }
  }

  Future<void> _loadOriginalData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .doc('admin/config/categories/${widget.category['sourceAdminId']}')
          .get();
      if (doc.exists && mounted) {
        setState(() {
          _originalAdminData = doc.data();
        });
      }
    } catch (e) {
      // Ignore errors
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _keywordController.dispose();
    super.dispose();
  }

  void _addKeyword() {
    final keyword = _keywordController.text.trim().toLowerCase();
    if (keyword.isNotEmpty && !_keywords.contains(keyword)) {
      setState(() {
        _keywords.add(keyword);
        _keywordController.clear();
      });
    }
  }

  void _removeKeyword(String keyword) {
    setState(() => _keywords.remove(keyword));
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    Navigator.pop(context, {
      'name': _nameController.text.trim(),
      'description': _descriptionController.text.trim(),
      'keywords': _keywords,
      'primaryLlm': _primaryLlm,
      'fallbackLlm': _fallbackLlm,
      'priority': _priority,
      'contextFilter': _contextFilter,
    });
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.category['type'] as String? ?? 'inherited';
    final isInherited = type == 'inherited';

    return Dialog(
      backgroundColor: const Color(0xFF1a1a2e),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 500,
        constraints: const BoxConstraints(maxHeight: 700),
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.edit, color: Colors.orange, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Edit Category',
                            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          if (type != 'custom')
                            Text(
                              type == 'inherited' ? 'DEFAULT' : 'MODIFIED',
                              style: TextStyle(
                                color: type == 'inherited' ? Colors.grey : Colors.orange,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Info banner for inherited categories
                if (isInherited)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.orange[400], size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Editing will mark this category as customized. You can reset to defaults later.',
                            style: TextStyle(color: Colors.orange[400], fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (isInherited) const SizedBox(height: 16),

                // Name field
                TextFormField(
                  controller: _nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration('Category Name *', Icons.label_outline),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Name is required' : null,
                ),
                const SizedBox(height: 16),

                // Description field
                TextFormField(
                  controller: _descriptionController,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration('Description (optional)', Icons.description_outlined),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),

                // Keywords input
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _keywordController,
                        style: const TextStyle(color: Colors.white),
                        decoration: _inputDecoration('Add keyword', Icons.tag),
                        onFieldSubmitted: (_) => _addKeyword(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _addKeyword,
                      icon: const Icon(Icons.add_circle, color: Color(0xFF7c3aed)),
                      tooltip: 'Add keyword',
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Keywords chips
                if (_keywords.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _keywords.map((k) => Chip(
                      label: Text(k, style: const TextStyle(color: Color(0xFF6366f1), fontSize: 12)),
                      backgroundColor: const Color(0xFF6366f1).withValues(alpha: 0.15),
                      deleteIcon: const Icon(Icons.close, size: 16, color: Color(0xFF6366f1)),
                      onDeleted: () => _removeKeyword(k),
                      side: BorderSide(color: const Color(0xFF6366f1).withValues(alpha: 0.3)),
                    )).toList(),
                  ),
                const SizedBox(height: 16),

                // LLM selection
                Row(
                  children: [
                    Expanded(child: _buildLlmDropdown('Primary LLM', _primaryLlm, (v) => setState(() => _primaryLlm = v!))),
                    const SizedBox(width: 12),
                    Expanded(child: _buildLlmDropdown('Fallback LLM', _fallbackLlm, (v) => setState(() => _fallbackLlm = v!))),
                  ],
                ),
                const SizedBox(height: 16),

                // Priority and Context
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _priority,
                        decoration: _inputDecoration('Priority', Icons.flag_outlined),
                        dropdownColor: const Color(0xFF1a1a2e),
                        style: const TextStyle(color: Colors.white),
                        items: ['HIGH', 'MEDIUM', 'LOW'].map((p) => DropdownMenuItem(
                          value: p,
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: p == 'HIGH' ? Colors.green : p == 'MEDIUM' ? Colors.yellow[700] : Colors.grey,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(p),
                            ],
                          ),
                        )).toList(),
                        onChanged: (v) => setState(() => _priority = v!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _contextFilter,
                        decoration: _inputDecoration('Context Filter', Icons.filter_list),
                        dropdownColor: const Color(0xFF1a1a2e),
                        style: const TextStyle(color: Colors.white),
                        items: ['all', 'personal', 'work', 'family'].map((c) => DropdownMenuItem(
                          value: c,
                          child: Text(_capitalize(c)),
                        )).toList(),
                        onChanged: (v) => setState(() => _contextFilter = v!),
                      ),
                    ),
                  ],
                ),

                // Original admin settings (collapsible)
                if (_originalAdminData != null) ...[
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () => setState(() => _showOriginal = !_showOriginal),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0f0f1a),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF2a2a3e).withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _showOriginal ? Icons.expand_less : Icons.expand_more,
                            color: Colors.grey[500],
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Original Admin Settings',
                            style: TextStyle(color: Colors.grey[500], fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_showOriginal) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0f0f1a),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF2a2a3e).withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildOriginalField('Name', _originalAdminData!['name']),
                          _buildOriginalField('Description', _originalAdminData!['description']),
                          _buildOriginalField('Keywords', (_originalAdminData!['keywords'] as List?)?.join(', ')),
                          _buildOriginalField('Primary LLM', _originalAdminData!['primaryLlm']),
                          _buildOriginalField('Fallback LLM', _originalAdminData!['fallbackLlm']),
                          _buildOriginalField('Priority', _originalAdminData!['priority']),
                        ],
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 24),

                // Actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7c3aed),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Save Changes'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOriginalField(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          ),
          Expanded(
            child: Text(
              value?.toString() ?? '-',
              style: TextStyle(color: Colors.grey[400], fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLlmDropdown(String label, String value, ValueChanged<String?> onChanged) {
    // Ensure value is in the list
    final validValue = _llmOptions.any((l) => l['id'] == value) ? value : _llmOptions.first['id']!;

    return DropdownButtonFormField<String>(
      initialValue: validValue,
      decoration: _inputDecoration(label, Icons.psychology),
      dropdownColor: const Color(0xFF1a1a2e),
      style: const TextStyle(color: Colors.white),
      isExpanded: true,
      items: _llmOptions.map((llm) => DropdownMenuItem(
        value: llm['id'],
        child: Row(
          children: [
            _buildLlmDot(llm['provider']!),
            const SizedBox(width: 8),
            Flexible(child: Text(llm['name']!, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
          ],
        ),
      )).toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildLlmDot(String provider) {
    Color color;
    switch (provider) {
      case 'claude':
        color = Colors.purple;
        break;
      case 'openai':
        color = Colors.green;
        break;
      default:
        color = Colors.blue;
    }
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.grey[500]),
      prefixIcon: Icon(icon, color: Colors.grey[600], size: 20),
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
    );
  }

  String _capitalize(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}
