import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class TechDocsScreen extends StatefulWidget {
  const TechDocsScreen({super.key});

  @override
  State<TechDocsScreen> createState() => _TechDocsScreenState();
}

class _TechDocsScreenState extends State<TechDocsScreen> {
  String? _selectedModuleId;
  String? _selectedModuleName;
  String? _selectedFeatureId;
  Map<String, dynamic>? _selectedFeatureData;

  final _firestore = FirebaseFirestore.instance;

  final Map<String, IconData> _iconMap = {
    'cloud': Icons.cloud,
    'api': Icons.api,
    'storage': Icons.storage,
    'lock': Icons.lock,
    'settings': Icons.settings,
    'phone_android': Icons.phone_android,
    'memory': Icons.memory,
    'psychology': Icons.psychology,
    'smart_toy': Icons.smart_toy,
    'security': Icons.security,
    'person': Icons.person,
    'chat': Icons.chat,
    'code': Icons.code,
    'data_object': Icons.data_object,
    'hub': Icons.hub,
    'folder': Icons.folder,
    'description': Icons.description,
    'route': Icons.route,
    'category': Icons.category,
  };

  static const String _documentationTemplate = '''
# [Feature Name]

**Module:** [Module Name]
**Version:** 1.0
**Status:** [Planning/In Progress/Completed]
**Last Updated:** YYYY-MM-DD

---

## 1. Overview

> [2-3 sentence description of what this feature does]

---

## 2. Purpose

**Problem Solved:**
- [What problem does this solve?]

**User Benefit:**
- [How does the user benefit?]

---

## 3. Technical Details

### 3.1 Endpoints

| Method | URL | Description |
|--------|-----|-------------|
| POST | /api/example | Description |

### 3.2 Files

| File | Purpose |
|------|---------|
| file.ts | Main logic |

---

## 4. Configuration

```json
{
  "setting1": "value1"
}
```

---

## 5. Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | YYYY-MM-DD | Initial implementation |

---

*Template Version: 1.0*
*Based on: IAMONEAI Foundation Blueprint*
''';

  IconData _getIcon(String? iconName) {
    if (iconName == null) return Icons.folder;
    return _iconMap[iconName] ?? Icons.folder;
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'completed':
        return Colors.green;
      case 'in_progress':
        return Colors.orange;
      case 'planned':
        return Colors.blue;
      case 'deprecated':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _getStatusLabel(String? status) {
    switch (status) {
      case 'completed':
        return 'Completed';
      case 'in_progress':
        return 'In Progress';
      case 'planned':
        return 'Planned';
      case 'deprecated':
        return 'Deprecated';
      default:
        return status ?? 'Unknown';
    }
  }

  void _copyTemplate() {
    Clipboard.setData(const ClipboardData(text: _documentationTemplate));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Template copied to clipboard!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0f0f1a),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.description, color: Color(0xFF7c3aed), size: 32),
                const SizedBox(width: 12),
                const Text(
                  'Tech Documentation',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                // Copy Template Button
                OutlinedButton.icon(
                  onPressed: _copyTemplate,
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy Template'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF7c3aed),
                    side: const BorderSide(color: Color(0xFF7c3aed)),
                  ),
                ),
                const SizedBox(width: 12),
                // Add Module Button
                ElevatedButton.icon(
                  onPressed: _showAddModuleDialog,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Module'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7c3aed),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Module and feature documentation with version tracking',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
            const SizedBox(height: 24),
            // Main content - 3 panels
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Modules Panel
                  Expanded(flex: 3, child: _buildModulesPanel()),
                  const SizedBox(width: 16),
                  // Features Panel
                  Expanded(flex: 4, child: _buildFeaturesPanel()),
                  const SizedBox(width: 16),
                  // Detail Panel
                  Expanded(flex: 5, child: _buildDetailPanel()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== MODULES PANEL ====================
  Widget _buildModulesPanel() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a2e),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2a2a3e).withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.folder, color: Color(0xFF7c3aed)),
                const SizedBox(width: 8),
                const Text(
                  'Modules',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: const Color(0xFF2a2a3e).withValues(alpha: 0.5)),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('admin')
                  .doc('tech_docs')
                  .collection('modules')
                  .orderBy('order')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final modules = snapshot.data!.docs;
                if (modules.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.folder_open, size: 48, color: Colors.grey[600]),
                        const SizedBox(height: 8),
                        Text('No modules yet', style: TextStyle(color: Colors.grey[500])),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _showAddModuleDialog,
                          child: const Text('+ Add Module', style: TextStyle(color: Color(0xFF7c3aed))),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: modules.length,
                  itemBuilder: (context, index) {
                    final doc = modules[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final isSelected = _selectedModuleId == doc.id;
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF7c3aed).withValues(alpha: 0.15) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        leading: Icon(
                          _getIcon(data['icon']),
                          color: isSelected ? const Color(0xFF7c3aed) : Colors.grey[500],
                        ),
                        title: Text(
                          data['name'] ?? 'Unnamed',
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: Colors.white,
                          ),
                        ),
                        subtitle: Text(
                          data['description'] ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                        ),
                        trailing: PopupMenuButton<String>(
                          icon: Icon(Icons.more_vert, size: 18, color: Colors.grey[500]),
                          color: const Color(0xFF1a1a2e),
                          onSelected: (value) {
                            if (value == 'edit') {
                              _showEditModuleDialog(doc.id, data);
                            } else if (value == 'delete') {
                              _deleteModule(doc.id, data['name']);
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(value: 'edit', child: Text('Edit', style: TextStyle(color: Colors.white))),
                            PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red[400]))),
                          ],
                        ),
                        onTap: () {
                          setState(() {
                            _selectedModuleId = doc.id;
                            _selectedModuleName = data['name'];
                            _selectedFeatureId = null;
                            _selectedFeatureData = null;
                          });
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ==================== FEATURES PANEL ====================
  Widget _buildFeaturesPanel() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a2e),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2a2a3e).withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.list_alt, color: Color(0xFF7c3aed)),
                const SizedBox(width: 8),
                Text(
                  _selectedModuleName != null ? 'Features: $_selectedModuleName' : 'Features',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const Spacer(),
                if (_selectedModuleId != null)
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: Color(0xFF7c3aed)),
                    tooltip: 'Add Feature',
                    onPressed: _showAddFeatureDialog,
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: const Color(0xFF2a2a3e).withValues(alpha: 0.5)),
          Expanded(
            child: _selectedModuleId == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.arrow_back, size: 48, color: Colors.grey[600]),
                        const SizedBox(height: 8),
                        Text('Select a module', style: TextStyle(color: Colors.grey[500])),
                      ],
                    ),
                  )
                : StreamBuilder<QuerySnapshot>(
                    stream: _firestore
                        .collection('admin')
                        .doc('tech_docs')
                        .collection('modules')
                        .doc(_selectedModuleId)
                        .collection('features')
                        .orderBy('name')
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(child: Text('Error: ${snapshot.error}'));
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final features = snapshot.data!.docs;
                      if (features.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.note_add, size: 48, color: Colors.grey[600]),
                              const SizedBox(height: 8),
                              Text('No features yet', style: TextStyle(color: Colors.grey[500])),
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: _showAddFeatureDialog,
                                child: const Text('+ Add Feature', style: TextStyle(color: Color(0xFF7c3aed))),
                              ),
                            ],
                          ),
                        );
                      }
                      return ListView.builder(
                        itemCount: features.length,
                        itemBuilder: (context, index) {
                          final doc = features[index];
                          final data = doc.data() as Map<String, dynamic>;
                          final isSelected = _selectedFeatureId == doc.id;
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFF7c3aed).withValues(alpha: 0.15) : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: ListTile(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              leading: Container(
                                width: 8,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: _getStatusColor(data['status']),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              title: Text(
                                data['name'] ?? 'Unnamed',
                                style: TextStyle(
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  color: Colors.white,
                                ),
                              ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _getStatusLabel(data['status']),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _getStatusColor(data['status']),
                                  ),
                                ),
                                if (data['currentVersion'] != null)
                                  Text(
                                    'v${data['currentVersion']}',
                                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                                  ),
                              ],
                            ),
                              trailing: PopupMenuButton<String>(
                                icon: Icon(Icons.more_vert, size: 18, color: Colors.grey[500]),
                                color: const Color(0xFF1a1a2e),
                                onSelected: (value) {
                                  if (value == 'edit') {
                                    _showEditFeatureDialog(doc.id, data);
                                  } else if (value == 'delete') {
                                    _deleteFeature(doc.id, data['name']);
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(value: 'edit', child: Text('Edit', style: TextStyle(color: Colors.white))),
                                  PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red[400]))),
                                ],
                              ),
                              onTap: () {
                                setState(() {
                                  _selectedFeatureId = doc.id;
                                  _selectedFeatureData = data;
                                });
                              },
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ==================== DETAIL PANEL ====================
  Widget _buildDetailPanel() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a2e),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2a2a3e).withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.article, color: Color(0xFF7c3aed)),
                const SizedBox(width: 8),
                const Text(
                  'Documentation',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const Spacer(),
                if (_selectedFeatureData != null) ...[
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20, color: Color(0xFF7c3aed)),
                    tooltip: 'Edit Documentation',
                    onPressed: () => _showEditDocumentationDialog(),
                  ),
                  IconButton(
                    icon: Icon(Icons.copy, size: 20, color: Colors.grey[500]),
                    tooltip: 'Copy Documentation',
                    onPressed: () {
                      final doc = _selectedFeatureData?['documentation'] ?? '';
                      Clipboard.setData(ClipboardData(text: doc));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Documentation copied!'), backgroundColor: Color(0xFF7c3aed)),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
          Divider(height: 1, color: const Color(0xFF2a2a3e).withValues(alpha: 0.5)),
          Expanded(
            child: _selectedFeatureData == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.description, size: 48, color: Colors.grey[600]),
                        const SizedBox(height: 8),
                        Text('Select a feature to view documentation',
                            style: TextStyle(color: Colors.grey[500])),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Feature header
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF7c3aed).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: _getStatusColor(_selectedFeatureData?['status']),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  _getStatusLabel(_selectedFeatureData?['status']),
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                ),
                              ),
                              const SizedBox(width: 12),
                              if (_selectedFeatureData?['currentVersion'] != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2a2a3e),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Text(
                                    'v${_selectedFeatureData?['currentVersion']}',
                                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Markdown documentation
                        MarkdownBody(
                          data: _selectedFeatureData?['documentation'] ?? '_No documentation yet_',
                          selectable: true,
                          styleSheet: MarkdownStyleSheet(
                            h1: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                            h2: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                            h3: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                            p: TextStyle(color: Colors.grey[300]),
                            code: TextStyle(
                              backgroundColor: const Color(0xFF0f0f1a),
                              fontFamily: 'monospace',
                              color: const Color(0xFF9CDCFE),
                            ),
                            codeblockDecoration: BoxDecoration(
                              color: const Color(0xFF0f0f1a),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            tableHead: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                            tableBorder: TableBorder.all(color: const Color(0xFF2a2a3e)),
                            tableCellsPadding: const EdgeInsets.all(8),
                            listBullet: TextStyle(color: Colors.grey[300]),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ==================== DIALOGS ====================

  // Add Module Dialog
  Future<void> _showAddModuleDialog() async {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    String selectedIcon = 'folder';

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Module'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Module Name',
                  hintText: 'e.g., Infrastructure',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'Brief description',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: selectedIcon,
                decoration: const InputDecoration(
                  labelText: 'Icon',
                  border: OutlineInputBorder(),
                ),
                items: _iconMap.keys.map((key) => DropdownMenuItem(
                  value: key,
                  child: Row(
                    children: [
                      Icon(_iconMap[key], size: 20),
                      const SizedBox(width: 8),
                      Text(key),
                    ],
                  ),
                )).toList(),
                onChanged: (value) => selectedIcon = value ?? 'folder',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isEmpty) return;

              final modulesSnapshot = await _firestore
                  .collection('admin')
                  .doc('tech_docs')
                  .collection('modules')
                  .get();

              await _firestore
                  .collection('admin')
                  .doc('tech_docs')
                  .collection('modules')
                  .add({
                'name': nameController.text,
                'description': descController.text,
                'icon': selectedIcon,
                'order': modulesSnapshot.docs.length,
                'createdAt': FieldValue.serverTimestamp(),
              });

              if (!context.mounted) return;
              Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  // Edit Module Dialog
  Future<void> _showEditModuleDialog(String docId, Map<String, dynamic> data) async {
    final nameController = TextEditingController(text: data['name']);
    final descController = TextEditingController(text: data['description']);
    String selectedIcon = data['icon'] ?? 'folder';

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Module'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Module Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: selectedIcon,
                decoration: const InputDecoration(
                  labelText: 'Icon',
                  border: OutlineInputBorder(),
                ),
                items: _iconMap.keys.map((key) => DropdownMenuItem(
                  value: key,
                  child: Row(
                    children: [
                      Icon(_iconMap[key], size: 20),
                      const SizedBox(width: 8),
                      Text(key),
                    ],
                  ),
                )).toList(),
                onChanged: (value) => selectedIcon = value ?? 'folder',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await _firestore
                  .collection('admin')
                  .doc('tech_docs')
                  .collection('modules')
                  .doc(docId)
                  .update({
                'name': nameController.text,
                'description': descController.text,
                'icon': selectedIcon,
                'updatedAt': FieldValue.serverTimestamp(),
              });

              if (_selectedModuleId == docId) {
                setState(() => _selectedModuleName = nameController.text);
              }
              if (!context.mounted) return;
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // Delete Module
  Future<void> _deleteModule(String docId, String? name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Module?'),
        content: Text('Are you sure you want to delete "${name ?? 'this module'}"?\n\nThis will also delete all features in this module.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // Delete all features first
      final features = await _firestore
          .collection('admin')
          .doc('tech_docs')
          .collection('modules')
          .doc(docId)
          .collection('features')
          .get();

      for (var doc in features.docs) {
        await doc.reference.delete();
      }

      // Delete the module
      await _firestore
          .collection('admin')
          .doc('tech_docs')
          .collection('modules')
          .doc(docId)
          .delete();

      if (_selectedModuleId == docId) {
        setState(() {
          _selectedModuleId = null;
          _selectedModuleName = null;
          _selectedFeatureId = null;
          _selectedFeatureData = null;
        });
      }
    }
  }

  // Add Feature Dialog
  Future<void> _showAddFeatureDialog() async {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final versionController = TextEditingController(text: '1.0');
    String selectedStatus = 'planned';

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add Feature to $_selectedModuleName'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Feature Name',
                  hintText: 'e.g., User Authentication',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: selectedStatus,
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'planned', child: Text('Planned')),
                        DropdownMenuItem(value: 'in_progress', child: Text('In Progress')),
                        DropdownMenuItem(value: 'completed', child: Text('Completed')),
                        DropdownMenuItem(value: 'deprecated', child: Text('Deprecated')),
                      ],
                      onChanged: (value) => selectedStatus = value ?? 'planned',
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: versionController,
                      decoration: const InputDecoration(
                        labelText: 'Version',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isEmpty) return;

              await _firestore
                  .collection('admin')
                  .doc('tech_docs')
                  .collection('modules')
                  .doc(_selectedModuleId)
                  .collection('features')
                  .add({
                'name': nameController.text,
                'description': descController.text,
                'status': selectedStatus,
                'currentVersion': versionController.text,
                'documentation': _documentationTemplate
                    .replaceAll('[Feature Name]', nameController.text)
                    .replaceAll('[Module Name]', _selectedModuleName ?? 'Module'),
                'createdAt': FieldValue.serverTimestamp(),
              });

              if (!context.mounted) return;
              Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  // Edit Feature Dialog
  Future<void> _showEditFeatureDialog(String docId, Map<String, dynamic> data) async {
    final nameController = TextEditingController(text: data['name']);
    final descController = TextEditingController(text: data['description']);
    final versionController = TextEditingController(text: data['currentVersion']);
    String selectedStatus = data['status'] ?? 'planned';

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Feature'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Feature Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: selectedStatus,
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'planned', child: Text('Planned')),
                        DropdownMenuItem(value: 'in_progress', child: Text('In Progress')),
                        DropdownMenuItem(value: 'completed', child: Text('Completed')),
                        DropdownMenuItem(value: 'deprecated', child: Text('Deprecated')),
                      ],
                      onChanged: (value) => selectedStatus = value ?? 'planned',
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: versionController,
                      decoration: const InputDecoration(
                        labelText: 'Version',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await _firestore
                  .collection('admin')
                  .doc('tech_docs')
                  .collection('modules')
                  .doc(_selectedModuleId)
                  .collection('features')
                  .doc(docId)
                  .update({
                'name': nameController.text,
                'description': descController.text,
                'status': selectedStatus,
                'currentVersion': versionController.text,
                'updatedAt': FieldValue.serverTimestamp(),
              });

              if (_selectedFeatureId == docId) {
                setState(() {
                  _selectedFeatureData = {
                    ..._selectedFeatureData!,
                    'name': nameController.text,
                    'description': descController.text,
                    'status': selectedStatus,
                    'currentVersion': versionController.text,
                  };
                });
              }
              if (!context.mounted) return;
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // Delete Feature
  Future<void> _deleteFeature(String docId, String? name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Feature?'),
        content: Text('Are you sure you want to delete "${name ?? 'this feature'}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _firestore
          .collection('admin')
          .doc('tech_docs')
          .collection('modules')
          .doc(_selectedModuleId)
          .collection('features')
          .doc(docId)
          .delete();

      if (_selectedFeatureId == docId) {
        setState(() {
          _selectedFeatureId = null;
          _selectedFeatureData = null;
        });
      }
    }
  }

  // Edit Documentation Dialog
  Future<void> _showEditDocumentationDialog() async {
    final docController = TextEditingController(
      text: _selectedFeatureData?['documentation'] ?? '',
    );

    await showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.8,
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Edit Documentation',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      docController.text = _documentationTemplate
                          .replaceAll('[Feature Name]', _selectedFeatureData?['name'] ?? 'Feature')
                          .replaceAll('[Module Name]', _selectedModuleName ?? 'Module');
                    },
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Reset to Template'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Use Markdown formatting. Preview updates in real-time.',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Row(
                  children: [
                    // Editor
                    Expanded(
                      child: TextField(
                        controller: docController,
                        maxLines: null,
                        expands: true,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'Write your documentation in Markdown...',
                        ),
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Preview
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: ListenableBuilder(
                            listenable: docController,
                            builder: (context, child) => MarkdownBody(
                              data: docController.text.isEmpty
                                  ? '_Start typing to see preview..._'
                                  : docController.text,
                              selectable: true,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () async {
                      await _firestore
                          .collection('admin')
                          .doc('tech_docs')
                          .collection('modules')
                          .doc(_selectedModuleId)
                          .collection('features')
                          .doc(_selectedFeatureId)
                          .update({
                        'documentation': docController.text,
                        'updatedAt': FieldValue.serverTimestamp(),
                      });

                      setState(() {
                        _selectedFeatureData = {
                          ..._selectedFeatureData!,
                          'documentation': docController.text,
                        };
                      });
                      if (!context.mounted) return;
                      Navigator.pop(context);
                    },
                    child: const Text('Save Documentation'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
