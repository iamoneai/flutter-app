import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = true;
  List<Map<String, dynamic>> _categories = [];

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    setState(() => _isLoading = true);
    try {
      final snapshot = await _firestore
          .collection('admin')
          .doc('config')
          .collection('categories')
          .orderBy('priority')
          .get();
      _categories = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _saveCategory(Map<String, dynamic> category, {String? existingId}) async {
    try {
      final docRef = existingId != null
          ? _firestore.collection('admin').doc('config').collection('categories').doc(existingId)
          : _firestore.collection('admin').doc('config').collection('categories').doc();
      await docRef.set({...category, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(existingId != null ? 'Updated!' : 'Created!'), backgroundColor: Colors.green),
        );
      }
      _loadCategories();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteCategory(String id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Category'),
        content: Text('Delete "$name"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm == true) {
      await _firestore.collection('admin').doc('config').collection('categories').doc(id).delete();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted!'), backgroundColor: Colors.orange));
      _loadCategories();
    }
  }

  void _showCategoryDialog({Map<String, dynamic>? existing}) {
    final isEditing = existing != null;
    final nameCtrl = TextEditingController(text: existing?['name'] ?? '');
    final displayCtrl = TextEditingController(text: existing?['displayName'] ?? '');
    final descCtrl = TextEditingController(text: existing?['description'] ?? '');
    final keywordsCtrl = TextEditingController(text: (existing?['keywords'] as List<dynamic>?)?.join(', ') ?? '');
    final priorityCtrl = TextEditingController(text: (existing?['priority'] ?? _categories.length + 1).toString());
    String primaryLLM = existing?['primaryLLM'] ?? 'claude-sonnet';
    String fallbackLLM = existing?['fallbackLLM'] ?? 'gpt-4o';
    String costTier = existing?['costTier'] ?? 'medium';
    bool isActive = existing?['isActive'] ?? true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(isEditing ? 'Edit Category' : 'Add Category'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nameCtrl, enabled: !isEditing, decoration: const InputDecoration(labelText: 'Category ID *', hintText: 'e.g., code', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(controller: displayCtrl, decoration: const InputDecoration(labelText: 'Display Name *', hintText: 'e.g., Code & Programming', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()), maxLines: 2),
                  const SizedBox(height: 12),
                  TextField(controller: keywordsCtrl, decoration: const InputDecoration(labelText: 'Keywords *', hintText: 'python, javascript, debug', helperText: 'Comma-separated', border: OutlineInputBorder()), maxLines: 2),
                  const SizedBox(height: 12),
                  TextField(controller: priorityCtrl, decoration: const InputDecoration(labelText: 'Priority', helperText: 'Lower = checked first', border: OutlineInputBorder()), keyboardType: TextInputType.number),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(initialValue: primaryLLM, decoration: const InputDecoration(labelText: 'Primary LLM', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'claude-sonnet', child: Text('🟣 Claude Sonnet')),
                      DropdownMenuItem(value: 'claude-haiku', child: Text('🟣 Claude Haiku')),
                      DropdownMenuItem(value: 'gpt-4o', child: Text('🟢 GPT-4o')),
                      DropdownMenuItem(value: 'gpt-4o-mini', child: Text('🟢 GPT-4o Mini')),
                      DropdownMenuItem(value: 'gemini-pro', child: Text('🔵 Gemini Pro')),
                      DropdownMenuItem(value: 'gemini-flash', child: Text('🔵 Gemini Flash')),
                    ], onChanged: (v) => setDialogState(() => primaryLLM = v!)),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(initialValue: fallbackLLM, decoration: const InputDecoration(labelText: 'Fallback LLM', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'claude-sonnet', child: Text('🟣 Claude Sonnet')),
                      DropdownMenuItem(value: 'claude-haiku', child: Text('🟣 Claude Haiku')),
                      DropdownMenuItem(value: 'gpt-4o', child: Text('🟢 GPT-4o')),
                      DropdownMenuItem(value: 'gpt-4o-mini', child: Text('🟢 GPT-4o Mini')),
                      DropdownMenuItem(value: 'gemini-pro', child: Text('🔵 Gemini Pro')),
                      DropdownMenuItem(value: 'gemini-flash', child: Text('🔵 Gemini Flash')),
                    ], onChanged: (v) => setDialogState(() => fallbackLLM = v!)),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(initialValue: costTier, decoration: const InputDecoration(labelText: 'Cost Tier', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'low', child: Text('💚 Low')),
                      DropdownMenuItem(value: 'medium', child: Text('💛 Medium')),
                      DropdownMenuItem(value: 'high', child: Text('🔴 High')),
                    ], onChanged: (v) => setDialogState(() => costTier = v!)),
                  const SizedBox(height: 12),
                  SwitchListTile(title: const Text('Active'), value: isActive, onChanged: (v) => setDialogState(() => isActive = v), contentPadding: EdgeInsets.zero),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final name = nameCtrl.text.trim().toLowerCase().replaceAll(' ', '_');
                final displayName = displayCtrl.text.trim();
                final keywords = keywordsCtrl.text.split(',').map((k) => k.trim().toLowerCase()).where((k) => k.isNotEmpty).toList();
                if (name.isEmpty || displayName.isEmpty || keywords.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Fill required fields'), backgroundColor: Colors.red));
                  return;
                }
                Navigator.pop(ctx);
                _saveCategory({'name': name, 'displayName': displayName, 'description': descCtrl.text.trim(), 'keywords': keywords, 'priority': int.tryParse(priorityCtrl.text) ?? 99, 'primaryLLM': primaryLLM, 'fallbackLLM': fallbackLLM, 'costTier': costTier, 'isActive': isActive}, existingId: isEditing ? existing['id'] : name);
              },
              child: Text(isEditing ? 'Update' : 'Create'),
            ),
          ],
        ),
      ),
    );
  }

  void _seedDefaults() async {
    final defaults = [
      {'name': 'code', 'displayName': 'Code & Programming', 'description': 'Programming, debugging', 'keywords': ['python', 'javascript', 'code', 'debug', 'function', 'error', 'bug'], 'priority': 1, 'primaryLLM': 'claude-sonnet', 'fallbackLLM': 'gpt-4o', 'costTier': 'high', 'isActive': true},
      {'name': 'math', 'displayName': 'Math & Calculations', 'description': 'Math problems', 'keywords': ['calculate', 'math', 'equation', 'solve', 'formula', 'number'], 'priority': 2, 'primaryLLM': 'claude-sonnet', 'fallbackLLM': 'gemini-pro', 'costTier': 'high', 'isActive': true},
      {'name': 'creative', 'displayName': 'Creative Writing', 'description': 'Stories, poems', 'keywords': ['write', 'story', 'poem', 'creative', 'imagine'], 'priority': 3, 'primaryLLM': 'claude-sonnet', 'fallbackLLM': 'gpt-4o', 'costTier': 'high', 'isActive': true},
      {'name': 'images', 'displayName': 'Image Analysis', 'description': 'Analyzing images', 'keywords': ['image', 'photo', 'picture', 'analyze', 'describe'], 'priority': 4, 'primaryLLM': 'gemini-pro', 'fallbackLLM': 'gpt-4o', 'costTier': 'medium', 'isActive': true},
      {'name': 'translation', 'displayName': 'Translation', 'description': 'Language translation', 'keywords': ['translate', 'spanish', 'french', 'portuguese'], 'priority': 5, 'primaryLLM': 'gemini-pro', 'fallbackLLM': 'gpt-4o', 'costTier': 'medium', 'isActive': true},
      {'name': 'memory', 'displayName': 'Memory Operations', 'description': 'Store and recall', 'keywords': ['remember', 'recall', 'forget', 'my name', 'save'], 'priority': 6, 'primaryLLM': 'gemini-flash', 'fallbackLLM': 'claude-haiku', 'costTier': 'low', 'isActive': true},
      {'name': 'simple_chat', 'displayName': 'Simple Chat', 'description': 'Greetings, casual', 'keywords': ['hi', 'hello', 'thanks', 'bye', 'how are you'], 'priority': 100, 'primaryLLM': 'gemini-flash', 'fallbackLLM': 'claude-haiku', 'costTier': 'low', 'isActive': true},
    ];
    for (final cat in defaults) {
      await _firestore.collection('admin').doc('config').collection('categories').doc(cat['name'] as String).set({...cat, 'updatedAt': FieldValue.serverTimestamp()});
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Defaults loaded!'), backgroundColor: Colors.green));
    _loadCategories();
  }

  Color _costColor(String? t) => t == 'low' ? Colors.green : t == 'high' ? Colors.red : Colors.orange;
  String _llmEmoji(String? l) => l == null ? '🤖' : l.contains('claude') ? '🟣' : l.contains('gpt') ? '🟢' : '🔵';

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0f0f1a),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Categories', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                Text('Define task types and keywords for Smart Router', style: TextStyle(color: Colors.grey[500])),
              ]),
              Row(children: [
                if (_categories.isEmpty) OutlinedButton.icon(onPressed: _seedDefaults, icon: const Icon(Icons.auto_fix_high), label: const Text('Load Defaults'), style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF7c3aed), side: const BorderSide(color: Color(0xFF7c3aed)))),
                const SizedBox(width: 12),
                ElevatedButton.icon(onPressed: () => _showCategoryDialog(), icon: const Icon(Icons.add), label: const Text('Add Category'), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7c3aed), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
              ]),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: _isLoading ? const Center(child: CircularProgressIndicator(color: Color(0xFF7c3aed)))
              : _categories.isEmpty ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.category_outlined, size: 64, color: Colors.grey[600]),
                  const SizedBox(height: 16),
                  Text('No categories yet', style: TextStyle(color: Colors.grey[500])),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(onPressed: _seedDefaults, icon: const Icon(Icons.auto_fix_high), label: const Text('Load Defaults'), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7c3aed), foregroundColor: Colors.white)),
                ]))
              : ListView.builder(
                  itemCount: _categories.length,
                  itemBuilder: (ctx, i) {
                    final cat = _categories[i];
                    final keywords = (cat['keywords'] as List?) ?? [];
                    final active = cat['isActive'] ?? true;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1a1a2e),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF2a2a3e).withValues(alpha: 0.5)),
                      ),
                      child: Opacity(
                        opacity: active ? 1 : 0.5,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: const Color(0xFF2a2a3e), borderRadius: BorderRadius.circular(4)), child: Text('#${cat['priority']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white))),
                              const SizedBox(width: 12),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Text(cat['displayName'] ?? cat['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                                  const SizedBox(width: 8),
                                  Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: const Color(0xFF0f0f1a), borderRadius: BorderRadius.circular(4)), child: Text(cat['name'], style: TextStyle(fontSize: 11, color: Colors.grey[500], fontFamily: 'monospace'))),
                                  if (!active) Container(margin: const EdgeInsets.only(left: 8), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)), child: Text('INACTIVE', style: TextStyle(fontSize: 10, color: Colors.red[400], fontWeight: FontWeight.bold))),
                                ]),
                                if (cat['description']?.isNotEmpty == true) Padding(padding: const EdgeInsets.only(top: 4), child: Text(cat['description'], style: TextStyle(color: Colors.grey[500], fontSize: 13))),
                              ])),
                              Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFF0f0f1a), borderRadius: BorderRadius.circular(8)), child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Text(_llmEmoji(cat['primaryLLM'])), const SizedBox(width: 4), Text(cat['primaryLLM'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.white)),
                                Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.arrow_forward, size: 12, color: Colors.grey[600])),
                                Text(_llmEmoji(cat['fallbackLLM'])), const SizedBox(width: 4), Text(cat['fallbackLLM'] ?? '', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                              ])),
                              const SizedBox(width: 12),
                              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: _costColor(cat['costTier']).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)), child: Text((cat['costTier'] ?? 'medium').toString().toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _costColor(cat['costTier'])))),
                              IconButton(icon: const Icon(Icons.edit_outlined, color: Color(0xFF7c3aed)), onPressed: () => _showCategoryDialog(existing: cat)),
                              IconButton(icon: Icon(Icons.delete_outline, color: Colors.red[400]), onPressed: () => _deleteCategory(cat['id'], cat['displayName'] ?? cat['name'])),
                            ]),
                            const SizedBox(height: 12),
                            Wrap(spacing: 6, runSpacing: 6, children: keywords.map<Widget>((k) => Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: const Color(0xFF6366f1).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF6366f1).withValues(alpha: 0.3))), child: Text(k.toString(), style: const TextStyle(fontSize: 12, color: Color(0xFF6366f1))))).toList()),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
          ),
          Container(margin: const EdgeInsets.only(top: 16), padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFF6366f1).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF6366f1).withValues(alpha: 0.3))),
            child: Row(children: [const Icon(Icons.info_outline, color: Color(0xFF6366f1)), const SizedBox(width: 12), Expanded(child: Text('Categories matched by keywords in priority order. Lower number = checked first.', style: TextStyle(color: Colors.grey[400])))])),
        ],
      ),
    );
  }
}
