import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ApiKeysScreen extends StatefulWidget {
  const ApiKeysScreen({super.key});

  @override
  State<ApiKeysScreen> createState() => _ApiKeysScreenState();
}

class _ApiKeysScreenState extends State<ApiKeysScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  bool _isLoading = true;
  Map<String, dynamic> _keys = {};

  final List<Map<String, String>> _providers = [
    {'id': 'anthropic', 'name': 'Anthropic (Claude)', 'icon': '🟣'},
    {'id': 'openai', 'name': 'OpenAI (GPT)', 'icon': '🟢'},
    {'id': 'google', 'name': 'Google (Gemini)', 'icon': '🔵'},
  ];

  @override
  void initState() {
    super.initState();
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    try {
      final doc = await _db.collection('admin').doc('api_keys').get();
      setState(() {
        _keys = doc.data() ?? {};
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading keys: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveKey(String provider, String key, String? model) async {
    try {
      await _db.collection('admin').doc('api_keys').set({
        provider: {
          'key': key,
          'model': model,
          'updatedAt': FieldValue.serverTimestamp(),
          'isActive': true,
        }
      }, SetOptions(merge: true));
      
      await _loadKeys();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$provider key saved'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving key: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteKey(String provider) async {
    try {
      await _db.collection('admin').doc('api_keys').update({
        provider: FieldValue.delete(),
      });
      await _loadKeys();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Key deleted'), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      debugPrint('Error deleting key: $e');
    }
  }

  void _showKeyDialog(String providerId, String providerName) {
    final existingData = _keys[providerId] as Map<String, dynamic>?;
    final keyController = TextEditingController(text: existingData?['key'] ?? '');
    final modelController = TextEditingController(text: existingData?['model'] ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Configure $providerName'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: keyController,
                decoration: const InputDecoration(
                  labelText: 'API Key',
                  hintText: 'sk-... or AIza...',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: modelController,
                decoration: InputDecoration(
                  labelText: 'Default Model (optional)',
                  hintText: _getModelHint(providerId),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          if (existingData != null)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _deleteKey(providerId);
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ElevatedButton(
            onPressed: () {
              if (keyController.text.isNotEmpty) {
                Navigator.pop(context);
                _saveKey(providerId, keyController.text, 
                    modelController.text.isNotEmpty ? modelController.text : null);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  String _getModelHint(String provider) {
    switch (provider) {
      case 'anthropic': return 'claude-sonnet-4-20250514';
      case 'openai': return 'gpt-4o';
      case 'google': return 'gemini-1.5-flash';
      default: return '';
    }
  }

  String _maskKey(String key) {
    if (key.length <= 8) return '••••••••';
    return '${key.substring(0, 4)}••••${key.substring(key.length - 4)}';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF7c3aed)));
    }

    return Container(
      color: const Color(0xFF0f0f1a),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Configure your LLM API keys. Keys are stored securely in Firestore.',
            style: TextStyle(color: Colors.grey[500]),
          ),
          const SizedBox(height: 24),

          // Provider cards
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: _providers.map((provider) {
              final data = _keys[provider['id']] as Map<String, dynamic>?;
              final isConfigured = data != null && data['key'] != null;

              return SizedBox(
                width: 300,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1a1a2e),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF2a2a3e).withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(provider['icon']!, style: const TextStyle(fontSize: 24)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              provider['name']!,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          Icon(
                            isConfigured ? Icons.check_circle : Icons.circle_outlined,
                            color: isConfigured ? Colors.green : Colors.grey[600],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (isConfigured) ...[
                        Text(
                          'Key: ${_maskKey(data['key'])}',
                          style: TextStyle(color: Colors.grey[500], fontSize: 13),
                        ),
                        if (data['model'] != null)
                          Text(
                            'Model: ${data['model']}',
                            style: TextStyle(color: Colors.grey[500], fontSize: 13),
                          ),
                        const SizedBox(height: 12),
                      ],
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => _showKeyDialog(
                            provider['id']!,
                            provider['name']!,
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF7c3aed),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(isConfigured ? 'Edit Key' : 'Add Key'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 32),
          Divider(color: const Color(0xFF2a2a3e).withValues(alpha: 0.5)),
          const SizedBox(height: 16),

          // Info section
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF6366f1).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF6366f1).withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info, color: Color(0xFF6366f1)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'API keys are used by the Smart Router to send requests to different LLMs based on task type. '
                    'Configure routing rules in the Config section.',
                    style: TextStyle(color: Colors.grey[400]),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
