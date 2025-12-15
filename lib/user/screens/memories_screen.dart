import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MemoriesScreen extends StatefulWidget {
  const MemoriesScreen({super.key});

  @override
  State<MemoriesScreen> createState() => _MemoriesScreenState();
}

class _MemoriesScreenState extends State<MemoriesScreen> {
  String _selectedCategory = 'all';

  final List<Map<String, dynamic>> _categories = [
    {'value': 'all', 'label': 'All', 'icon': Icons.grid_view, 'color': Colors.grey},
    {'value': 'personal', 'label': 'Personal', 'icon': Icons.person, 'color': Colors.blue},
    {'value': 'work', 'label': 'Work', 'icon': Icons.work, 'color': Colors.orange},
    {'value': 'family', 'label': 'Family', 'icon': Icons.family_restroom, 'color': Colors.purple},
    {'value': 'preferences', 'label': 'Preferences', 'icon': Icons.favorite, 'color': Colors.pink},
  ];

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Column(
      children: [
        // Category filter
        Container(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _categories.map((cat) {
                final isSelected = _selectedCategory == cat['value'];
                final color = cat['color'] as Color;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          cat['icon'] as IconData,
                          size: 16,
                          color: isSelected ? Colors.white : color,
                        ),
                        const SizedBox(width: 6),
                        Text(cat['label'] as String),
                      ],
                    ),
                    selected: isSelected,
                    onSelected: (_) => setState(() => _selectedCategory = cat['value'] as String),
                    backgroundColor: const Color(0xFF1a1a2e),
                    selectedColor: color,
                    checkmarkColor: Colors.white,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.grey[400],
                    ),
                    side: BorderSide(
                      color: isSelected ? color : const Color(0xFF2a2a3e),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),

        // Memories list
        Expanded(
          child: user == null
              ? const Center(
                  child: Text('Please sign in', style: TextStyle(color: Colors.grey)),
                )
              : StreamBuilder<QuerySnapshot>(
                  stream: _getMemoriesStream(user.uid),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: Color(0xFF00d9ff)),
                      );
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline, size: 48, color: Colors.red[400]),
                            const SizedBox(height: 16),
                            Text(
                              'Error loading memories',
                              style: TextStyle(color: Colors.red[400]),
                            ),
                          ],
                        ),
                      );
                    }

                    final memories = snapshot.data?.docs ?? [];

                    if (memories.isEmpty) {
                      return _buildEmptyState();
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: memories.length,
                      itemBuilder: (context, index) {
                        final doc = memories[index];
                        final data = doc.data() as Map<String, dynamic>;
                        return _buildMemoryCard(doc.id, data);
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Stream<QuerySnapshot> _getMemoriesStream(String userId) {
    var query = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('memories')
        .orderBy('createdAt', descending: true);

    if (_selectedCategory != 'all') {
      query = query.where('category', isEqualTo: _selectedCategory);
    }

    return query.limit(50).snapshots();
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1a1a2e),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.memory,
                size: 48,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No memories yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Start chatting and I\'ll remember\nimportant things about you',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemoryCard(String id, Map<String, dynamic> data) {
    final content = data['content'] as String? ?? data['text'] as String? ?? 'No content';
    final category = data['category'] as String? ?? 'personal';
    final createdAt = data['createdAt'] as Timestamp?;
    final importance = data['importance'] as int? ?? 5;

    final categoryData = _categories.firstWhere(
      (c) => c['value'] == category,
      orElse: () => _categories.first,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a2e),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2a2a3e)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (categoryData['color'] as Color).withValues(alpha: 0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  categoryData['icon'] as IconData,
                  size: 16,
                  color: categoryData['color'] as Color,
                ),
                const SizedBox(width: 8),
                Text(
                  categoryData['label'] as String,
                  style: TextStyle(
                    color: categoryData['color'] as Color,
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                if (createdAt != null)
                  Text(
                    _formatDate(createdAt.toDate()),
                    style: TextStyle(color: Colors.grey[600], fontSize: 11),
                  ),
                const SizedBox(width: 12),
                // Importance indicator
                Row(
                  children: List.generate(5, (i) {
                    return Icon(
                      Icons.circle,
                      size: 6,
                      color: i < importance
                          ? const Color(0xFF00d9ff)
                          : Colors.grey[800],
                    );
                  }),
                ),
              ],
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              content,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ),
          // Actions
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: const Color(0xFF2a2a3e).withValues(alpha: 0.5)),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: Icon(Icons.edit_outlined, size: 18, color: Colors.grey[600]),
                  onPressed: () => _editMemory(id, data),
                  tooltip: 'Edit',
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(8),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 18, color: Colors.red[400]),
                  onPressed: () => _deleteMemory(id),
                  tooltip: 'Delete',
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(8),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return 'Today';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  void _editMemory(String id, Map<String, dynamic> data) {
    final controller = TextEditingController(text: data['content'] ?? data['text']);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        title: const Text('Edit Memory', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          maxLines: 4,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF0a0a0f),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF2a2a3e)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF2a2a3e)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final user = FirebaseAuth.instance.currentUser;
              if (user == null) return;

              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .collection('memories')
                  .doc(id)
                  .update({
                'content': controller.text,
                'updatedAt': FieldValue.serverTimestamp(),
              });

              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00d9ff),
              foregroundColor: Colors.black,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _deleteMemory(String id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        title: const Text('Delete Memory?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This cannot be undone.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final user = FirebaseAuth.instance.currentUser;
              if (user == null) return;

              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .collection('memories')
                  .doc(id)
                  .delete();

              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
