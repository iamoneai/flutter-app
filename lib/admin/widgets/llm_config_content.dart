// IAMONEAI - LLM Config Content (Groups & Routing)
import 'package:flutter/material.dart';
import 'llm_status_content.dart';

/// LLM Group for routing
class LLMGroup {
  final String id;
  String name;
  String description;
  final bool isDefault; // Default groups cannot be deleted
  List<String> llmIds; // LLM IDs in priority order
  bool isExpanded;
  int order;

  LLMGroup({
    required this.id,
    required this.name,
    required this.description,
    this.isDefault = false,
    List<String>? llmIds,
    this.isExpanded = true,
    this.order = 0,
  }) : llmIds = llmIds ?? [];
}

class LLMConfigContent extends StatefulWidget {
  const LLMConfigContent({super.key});

  @override
  State<LLMConfigContent> createState() => _LLMConfigContentState();
}

class _LLMConfigContentState extends State<LLMConfigContent> {
  final _stateManager = LLMStateManager();

  // Default groups + custom groups
  final List<LLMGroup> _groups = [
    LLMGroup(
      id: 'orchestrator',
      name: 'Orchestrator',
      description: 'Deciders - Classification, routing, intent detection',
      isDefault: true,
      llmIds: ['claude', 'nemotron', 'gemini'],
      order: 0,
    ),
    LLMGroup(
      id: 'reasoning',
      name: 'Reasoning',
      description: 'Speakers - Chat responses, explanations, analysis',
      isDefault: true,
      llmIds: ['claude', 'openai', 'gemini', 'llama3'],
      order: 1,
    ),
    LLMGroup(
      id: 'executors',
      name: 'Executors',
      description: 'Utility - Code execution, API calls, data processing',
      isDefault: true,
      llmIds: ['gemini', 'openai', 'llama3'],
      order: 2,
    ),
  ];

  String? _draggedLlmId;

  @override
  void initState() {
    super.initState();
    _stateManager.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    _stateManager.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  // Show ALL LLMs with API keys configured (enabled or not)
  List<LLMProvider> get _allConfiguredLlms {
    const configuredSecrets = [
      'gemini-api-key',
      'anthropic-api-key',
      'openai-api-key',
      'RUNPOD_API_KEY',
    ];
    return _stateManager.providers
        .where((p) => configuredSecrets.contains(p.secretName))
        .toList();
  }

  bool _isLlmActive(String llmId) {
    final provider = _getLlmProvider(llmId);
    return provider != null && provider.isEnabled && provider.showInRouting;
  }

  void _addLlmToGroup(String llmId, LLMGroup group) {
    // Only allow adding if LLM is active
    if (!_isLlmActive(llmId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot add disabled LLM. Enable it in Status page first.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() {
      if (!group.llmIds.contains(llmId)) {
        group.llmIds.add(llmId);
      }
    });
  }

  void _removeLlmFromGroup(String llmId, LLMGroup group) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove LLM'),
        content: Text('Remove ${_getLlmName(llmId)} from ${group.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                group.llmIds.remove(llmId);
              });
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _moveLlmInGroup(LLMGroup group, int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final llmId = group.llmIds.removeAt(oldIndex);
      group.llmIds.insert(newIndex, llmId);
    });
  }

  void _reorderGroups(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final group = _groups.removeAt(oldIndex);
      _groups.insert(newIndex, group);
      // Update order values
      for (int i = 0; i < _groups.length; i++) {
        _groups[i].order = i;
      }
    });
  }

  void _toggleGroupExpanded(LLMGroup group) {
    setState(() {
      group.isExpanded = !group.isExpanded;
    });
  }

  void _showCreateGroupDialog() {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New Group'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Group Name',
                hintText: 'e.g., Science, Creative, Code',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'What is this group for?',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.trim().isNotEmpty) {
                setState(() {
                  _groups.add(LLMGroup(
                    id: nameController.text.toLowerCase().replaceAll(' ', '_'),
                    name: nameController.text.trim(),
                    description: descController.text.trim(),
                    isDefault: false,
                    order: _groups.length,
                  ));
                });
                Navigator.pop(context);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _deleteGroup(LLMGroup group) {
    if (group.isDefault) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Group'),
        content: Text('Delete "${group.name}" group? LLMs will be removed from this group.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _groups.remove(group);
              });
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  String _getLlmName(String llmId) {
    final provider = _stateManager.providers.firstWhere(
      (p) => p.id == llmId,
      orElse: () => LLMProvider(
        id: llmId,
        name: llmId,
        provider: '',
        description: '',
        models: [],
        secretName: '',
        brandColor: Colors.grey,
        icon: Icons.memory,
      ),
    );
    return provider.name;
  }

  LLMProvider? _getLlmProvider(String llmId) {
    try {
      return _stateManager.providers.firstWhere((p) => p.id == llmId);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header with create button
        _buildHeader(),
        // Main content
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Available LLMs column
              _buildAvailableLlmsColumn(),
              // Vertical divider
              Container(
                width: 1,
                color: const Color(0xFFE0E0E0),
              ),
              // Groups area
              Expanded(
                child: _buildGroupsArea(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFFF8F9FA),
        border: Border(
          bottom: BorderSide(color: Color(0xFFE0E0E0)),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_tree, color: Color(0xFF666666), size: 18),
          const SizedBox(width: 10),
          const Text(
            'LLM Routing Groups',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '(${_groups.length} groups)',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF999999),
            ),
          ),
          const Spacer(),
          SizedBox(
            height: 32,
            child: ElevatedButton.icon(
              onPressed: _showCreateGroupDialog,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('New Group', style: TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A1A1A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvailableLlmsColumn() {
    return Container(
      width: 200,
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFFE0E0E0)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Available LLMs',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Drag to add to groups',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          // LLM list - show ALL configured LLMs
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _allConfiguredLlms.length,
              itemBuilder: (context, index) {
                final provider = _allConfiguredLlms[index];
                final isActive = provider.isEnabled && provider.showInRouting;
                return _buildDraggableLlmChip(provider, isActive);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDraggableLlmChip(LLMProvider provider, bool isActive) {
    if (!isActive) {
      // Show grayed out, non-draggable
      return Opacity(
        opacity: 0.5,
        child: _buildLlmChip(provider, isActive),
      );
    }

    return Draggable<String>(
      data: provider.id,
      onDragStarted: () {
        setState(() => _draggedLlmId = provider.id);
      },
      onDragEnd: (_) {
        setState(() => _draggedLlmId = null);
      },
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: provider.brandColor,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(provider.icon, color: Colors.white, size: 14),
              const SizedBox(width: 6),
              Text(
                provider.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.5,
        child: _buildLlmChip(provider, isActive),
      ),
      child: _buildLlmChip(provider, isActive),
    );
  }

  Widget _buildLlmChip(LLMProvider provider, bool isActive) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isActive
            ? provider.brandColor.withOpacity(0.1)
            : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isActive
              ? provider.brandColor.withOpacity(0.3)
              : const Color(0xFFE0E0E0),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: isActive ? provider.brandColor : Colors.grey,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(provider.icon, color: Colors.white, size: 14),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              provider.name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isActive ? const Color(0xFF1A1A1A) : const Color(0xFF999999),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!isActive)
            const Icon(Icons.block, size: 12, color: Color(0xFFCCCCCC))
          else
            const Icon(Icons.drag_indicator, size: 14, color: Color(0xFFCCCCCC)),
        ],
      ),
    );
  }

  Widget _buildGroupsArea() {
    return ReorderableListView.builder(
      padding: const EdgeInsets.all(12),
      buildDefaultDragHandles: false,
      itemCount: _groups.length,
      onReorder: _reorderGroups,
      itemBuilder: (context, index) {
        return ReorderableDragStartListener(
          key: ValueKey(_groups[index].id),
          index: index,
          child: _buildGroupCard(_groups[index], index),
        );
      },
    );
  }

  Widget _buildGroupCard(LLMGroup group, int index) {
    final isEmpty = group.llmIds.isEmpty;
    final isExpanded = group.isExpanded;

    return DragTarget<String>(
      onWillAccept: (data) => data != null && !group.llmIds.contains(data) && _isLlmActive(data),
      onAccept: (llmId) => _addLlmToGroup(llmId, group),
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isHovering ? Colors.blue : const Color(0xFFE0E0E0),
              width: isHovering ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Group header - compact
              InkWell(
                onTap: () => _toggleGroupExpanded(group),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(7),
                  topRight: const Radius.circular(7),
                  bottomLeft: Radius.circular(isExpanded ? 0 : 7),
                  bottomRight: Radius.circular(isExpanded ? 0 : 7),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isHovering
                        ? Colors.blue.withOpacity(0.05)
                        : const Color(0xFFF8F9FA),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(7),
                      topRight: const Radius.circular(7),
                      bottomLeft: Radius.circular(isExpanded ? 0 : 7),
                      bottomRight: Radius.circular(isExpanded ? 0 : 7),
                    ),
                  ),
                  child: Row(
                    children: [
                      // Drag handle
                      const Icon(Icons.drag_indicator, size: 16, color: Color(0xFFCCCCCC)),
                      const SizedBox(width: 8),
                      // Group info
                      Expanded(
                        child: Row(
                          children: [
                            Text(
                              group.name,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1A1A1A),
                              ),
                            ),
                            if (group.isDefault) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: const Text(
                                  'Default',
                                  style: TextStyle(fontSize: 9, color: Colors.blue, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                            const SizedBox(width: 6),
                            Text(
                              '(${group.llmIds.length})',
                              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ),
                      // Delete button (only for custom)
                      if (!group.isDefault)
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                          onPressed: () => _deleteGroup(group),
                          tooltip: 'Delete group',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        ),
                      // Expand/collapse
                      Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                        size: 18,
                        color: const Color(0xFF666666),
                      ),
                    ],
                  ),
                ),
              ),
              // Group content - compact
              if (isExpanded)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: Color(0xFFE0E0E0))),
                  ),
                  child: isEmpty
                      ? Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8F9FA),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFE0E0E0)),
                          ),
                          child: Center(
                            child: Text(
                              'Drag LLMs here',
                              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                            ),
                          ),
                        )
                      : ReorderableListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          buildDefaultDragHandles: false,
                          itemCount: group.llmIds.length,
                          onReorder: (oldIndex, newIndex) =>
                              _moveLlmInGroup(group, oldIndex, newIndex),
                          itemBuilder: (context, llmIndex) {
                            final llmId = group.llmIds[llmIndex];
                            final provider = _getLlmProvider(llmId);
                            if (provider == null) return const SizedBox.shrink();

                            final isActive = provider.isEnabled && provider.showInRouting;
                            return ReorderableDragStartListener(
                              key: ValueKey('${group.id}_$llmId'),
                              index: llmIndex,
                              enabled: isActive, // Only allow reordering active LLMs
                              child: _buildGroupLlmItem(provider, group, llmIndex + 1, isActive),
                            );
                          },
                        ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGroupLlmItem(LLMProvider provider, LLMGroup group, int priority, bool isActive) {
    return Opacity(
      opacity: isActive ? 1.0 : 0.4,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isActive
                ? provider.brandColor.withOpacity(0.3)
                : const Color(0xFFE0E0E0),
          ),
        ),
        child: Row(
          children: [
            // Priority number
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: isActive
                    ? provider.brandColor.withOpacity(0.1)
                    : const Color(0xFFE0E0E0),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  '$priority',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isActive ? provider.brandColor : Colors.grey,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // LLM icon
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: isActive ? provider.brandColor : Colors.grey,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(provider.icon, color: Colors.white, size: 12),
            ),
            const SizedBox(width: 8),
            // LLM name
            Expanded(
              child: Row(
                children: [
                  Text(
                    provider.name,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isActive ? const Color(0xFF1A1A1A) : const Color(0xFF999999),
                    ),
                  ),
                  if (!isActive) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: const Text(
                        'Disabled',
                        style: TextStyle(fontSize: 9, color: Colors.orange, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Drag handle
            if (isActive)
              const Icon(Icons.drag_indicator, size: 14, color: Color(0xFFCCCCCC)),
            const SizedBox(width: 4),
            // Remove button
            InkWell(
              onTap: () => _removeLlmFromGroup(provider.id, group),
              borderRadius: BorderRadius.circular(4),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, size: 14, color: Color(0xFFAAAAAA)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
