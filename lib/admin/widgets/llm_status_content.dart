// IAMONEAI - LLM Status Content
// Displays and manages LLM provider configurations from Firebase
import 'package:flutter/material.dart';
import '../services/llm_config_service.dart';

/// Filter options for LLM list
enum LLMFilter { all, activeOnly }

class LLMStatusContent extends StatefulWidget {
  const LLMStatusContent({super.key});

  @override
  State<LLMStatusContent> createState() => _LLMStatusContentState();
}

class _LLMStatusContentState extends State<LLMStatusContent> {
  final LLMConfigService _configService = LLMConfigService();
  List<LLMProviderConfig> _providers = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  LLMFilter _filter = LLMFilter.all;

  @override
  void initState() {
    super.initState();
    _loadProviders();
  }

  Future<void> _loadProviders() async {
    setState(() => _isLoading = true);
    try {
      final providers = await _configService.getProviders();
      setState(() {
        _providers = providers;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading providers: $e')),
        );
      }
    }
  }

  List<LLMProviderConfig> get _filteredProviders {
    if (_filter == LLMFilter.activeOnly) {
      return _providers.where((p) => p.isEnabled).toList();
    }
    return _providers;
  }

  Future<void> _refreshAllStatus() async {
    setState(() => _isRefreshing = true);
    // Simulate checking status
    await Future.delayed(const Duration(seconds: 2));
    setState(() {
      for (var provider in _providers) {
        if (provider.isEnabled) {
          provider.lastChecked = 'Just now';
          provider.status = 'active';
        }
      }
      _isRefreshing = false;
    });
  }

  Future<void> _toggleProvider(LLMProviderConfig provider) async {
    final newEnabled = !provider.isEnabled;
    final success = await _configService.toggleEnabled(provider.id, newEnabled);
    if (success) {
      setState(() {
        final index = _providers.indexWhere((p) => p.id == provider.id);
        if (index != -1) {
          _providers[index] = provider.copyWith(
            isEnabled: newEnabled,
            status: newEnabled ? 'active' : 'inactive',
          );
        }
      });
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to ${newEnabled ? 'enable' : 'disable'} ${provider.name}')),
        );
      }
    }
  }

  Future<void> _toggleShowInRouting(LLMProviderConfig provider) async {
    final newValue = !provider.showInRouting;
    final success = await _configService.toggleShowInRouting(provider.id, newValue);
    if (success) {
      setState(() {
        final index = _providers.indexWhere((p) => p.id == provider.id);
        if (index != -1) {
          _providers[index] = provider.copyWith(showInRouting: newValue);
        }
      });
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update routing for ${provider.name}')),
        );
      }
    }
  }

  Future<void> _deleteProvider(LLMProviderConfig provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete LLM Provider?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to delete "${provider.name}"?'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning, color: Colors.red, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This action cannot be undone. The provider will be permanently removed.',
                      style: TextStyle(fontSize: 13, color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await _configService.deleteProvider(provider.id);
      if (success) {
        setState(() {
          _providers.removeWhere((p) => p.id == provider.id);
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${provider.name} deleted successfully')),
          );
        }
      }
    }
  }

  void _editProvider(LLMProviderConfig provider) {
    showDialog(
      context: context,
      builder: (context) => _EditProviderDialog(
        provider: provider,
        onSave: (updated) async {
          final success = await _configService.updateProvider(updated);
          if (success) {
            setState(() {
              final index = _providers.indexWhere((p) => p.id == updated.id);
              if (index != -1) {
                _providers[index] = updated;
              }
            });
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${updated.name} saved successfully')),
              );
            }
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Failed to save ${updated.name}')),
              );
            }
          }
        },
      ),
    );
  }

  void _addProvider() {
    showDialog(
      context: context,
      builder: (context) => _EditProviderDialog(
        provider: null,
        onSave: (newProvider) async {
          final success = await _configService.createProvider(newProvider);
          if (success) {
            setState(() {
              _providers.add(newProvider);
              _providers.sort((a, b) => a.order.compareTo(b.order));
            });
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${newProvider.name} created successfully')),
              );
            }
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Failed to create ${newProvider.name}')),
              );
            }
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final enabledCount = _providers.where((p) => p.isEnabled).length;
    final activeCount = _providers.where((p) => p.status == 'active').length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Summary bar with filter
        _buildSummaryBar(enabledCount, activeCount),
        const SizedBox(height: 16),
        // Provider grid
        Expanded(
          child: _filteredProviders.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.smart_toy_outlined, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        _filter == LLMFilter.activeOnly
                            ? 'No active providers'
                            : 'No providers configured',
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: _filteredProviders.map((p) => _buildProviderCard(p)).toList(),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildSummaryBar(int enabled, int active) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        color: Color(0xFFF8F9FA),
        border: Border(
          bottom: BorderSide(color: Color(0xFFE0E0E0)),
        ),
      ),
      child: Row(
        children: [
          // Stats
          _buildStatBadge('Total', _providers.length.toString(), Colors.grey),
          const SizedBox(width: 24),
          _buildStatBadge('Enabled', enabled.toString(), Colors.blue),
          const SizedBox(width: 24),
          _buildStatBadge('Active', active.toString(), Colors.green),
          const SizedBox(width: 32),
          // Filter checkboxes
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE0E0E0)),
            ),
            child: Row(
              children: [
                const Text('Show: ', style: TextStyle(fontSize: 13, color: Color(0xFF666666))),
                _buildFilterChip('All', LLMFilter.all),
                const SizedBox(width: 8),
                _buildFilterChip('Active Only', LLMFilter.activeOnly),
              ],
            ),
          ),
          const Spacer(),
          // Add button
          ElevatedButton.icon(
            onPressed: _addProvider,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Provider'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
          const SizedBox(width: 12),
          // Refresh button
          ElevatedButton.icon(
            onPressed: _isRefreshing ? null : _refreshAllStatus,
            icon: _isRefreshing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, size: 18),
            label: Text(_isRefreshing ? 'Checking...' : 'Check All Status'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A1A1A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, LLMFilter filter) {
    final isSelected = _filter == filter;
    return GestureDetector(
      onTap: () => setState(() => _filter = filter),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1A1A1A) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? Colors.white : const Color(0xFF666666),
          ),
        ),
      ),
    );
  }

  Widget _buildStatBadge(String label, String value, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF666666),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A1A1A),
          ),
        ),
      ],
    );
  }

  Widget _buildProviderCard(LLMProviderConfig provider) {
    final isActive = provider.status == 'active';
    final isEnabled = provider.isEnabled;
    final brandColor = provider.getBrandColor();

    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? brandColor.withOpacity(0.3) : const Color(0xFFE0E0E0),
          width: isActive ? 2 : 1,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: brandColor.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with brand color
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isEnabled ? brandColor.withOpacity(0.1) : const Color(0xFFF5F5F5),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(11),
                topRight: Radius.circular(11),
              ),
            ),
            child: Row(
              children: [
                // Icon
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isEnabled ? brandColor : Colors.grey,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(provider.getIcon(), color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                // Name and provider
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        provider.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isEnabled ? const Color(0xFF1A1A1A) : const Color(0xFF999999),
                        ),
                      ),
                      Text(
                        provider.provider,
                        style: TextStyle(
                          fontSize: 12,
                          color: isEnabled ? const Color(0xFF666666) : const Color(0xFFAAAAAA),
                        ),
                      ),
                    ],
                  ),
                ),
                // Status indicator
                _buildStatusIndicator(provider),
                // More menu
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 20),
                  onSelected: (value) {
                    if (value == 'edit') {
                      _editProvider(provider);
                    } else if (value == 'delete') {
                      _deleteProvider(provider);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit, size: 18),
                          SizedBox(width: 8),
                          Text('Edit'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, size: 18, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Delete', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Body
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Description
                Text(
                  provider.description,
                  style: TextStyle(
                    fontSize: 14,
                    color: isEnabled ? const Color(0xFF666666) : const Color(0xFFAAAAAA),
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                // Models
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: provider.models.take(3).map((model) {
                    final isDefault = model == provider.defaultModel;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDefault
                            ? brandColor.withOpacity(0.1)
                            : isEnabled
                                ? const Color(0xFFF0F0F0)
                                : const Color(0xFFF8F8F8),
                        borderRadius: BorderRadius.circular(4),
                        border: isDefault ? Border.all(color: brandColor.withOpacity(0.3)) : null,
                      ),
                      child: Text(
                        isDefault ? '$model (default)' : model,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDefault
                              ? brandColor
                              : isEnabled
                                  ? const Color(0xFF666666)
                                  : const Color(0xFFAAAAAA),
                          fontFamily: 'monospace',
                          fontWeight: isDefault ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                // Metrics row
                if (isEnabled && provider.latencyMs != null) ...[
                  Row(
                    children: [
                      _buildMetric('Latency', '${provider.latencyMs}ms', Icons.timer_outlined),
                      const SizedBox(width: 16),
                      _buildMetric('Checked', provider.lastChecked ?? '-', Icons.schedule),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                // Cost info
                Row(
                  children: [
                    Icon(Icons.attach_money, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      'Input: \$${provider.costPer1kInput.toStringAsFixed(5)}/1k',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Output: \$${provider.costPer1kOutput.toStringAsFixed(5)}/1k',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Divider
                const Divider(height: 1),
                const SizedBox(height: 12),
                // Show in Routing toggle
                Row(
                  children: [
                    Icon(
                      Icons.route,
                      size: 16,
                      color: provider.showInRouting && isEnabled
                          ? Colors.purple
                          : const Color(0xFFCCCCCC),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Show in Routing',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF666666),
                      ),
                    ),
                    const Spacer(),
                    Transform.scale(
                      scale: 0.8,
                      child: Switch(
                        value: provider.showInRouting,
                        onChanged: isEnabled ? (_) => _toggleShowInRouting(provider) : null,
                        activeColor: Colors.purple,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Enable/Disable toggle
                Row(
                  children: [
                    Icon(
                      Icons.power_settings_new,
                      size: 16,
                      color: isEnabled ? Colors.green : const Color(0xFFCCCCCC),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Enabled',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF666666),
                      ),
                    ),
                    const Spacer(),
                    Transform.scale(
                      scale: 0.8,
                      child: Switch(
                        value: provider.isEnabled,
                        onChanged: (_) => _toggleProvider(provider),
                        activeColor: brandColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator(LLMProviderConfig provider) {
    Color color;
    String label;

    switch (provider.status) {
      case 'active':
        color = Colors.green;
        label = 'Active';
        break;
      case 'error':
        color = Colors.red;
        label = 'Error';
        break;
      case 'checking':
        color = Colors.orange;
        label = 'Checking';
        break;
      default:
        color = Colors.grey;
        label = 'Inactive';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetric(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFF999999)),
        const SizedBox(width: 4),
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF999999),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF666666),
          ),
        ),
      ],
    );
  }
}

/// Dialog for editing/adding an LLM provider
class _EditProviderDialog extends StatefulWidget {
  final LLMProviderConfig? provider;
  final Future<void> Function(LLMProviderConfig) onSave;

  const _EditProviderDialog({
    required this.provider,
    required this.onSave,
  });

  @override
  State<_EditProviderDialog> createState() => _EditProviderDialogState();
}

class _EditProviderDialogState extends State<_EditProviderDialog> {
  late TextEditingController _idController;
  late TextEditingController _nameController;
  late TextEditingController _providerController;
  late TextEditingController _descriptionController;
  late TextEditingController _modelsController;
  late TextEditingController _defaultModelController;
  late TextEditingController _secretNameController;
  late TextEditingController _costInputController;
  late TextEditingController _costOutputController;
  late TextEditingController _contextWindowController;
  late TextEditingController _orderController;
  late String _selectedIcon;
  late String _selectedColor;
  bool _isSaving = false;

  bool get isNew => widget.provider == null;

  final List<Map<String, dynamic>> _iconOptions = [
    {'name': 'auto_awesome', 'icon': Icons.auto_awesome},
    {'name': 'psychology', 'icon': Icons.psychology},
    {'name': 'smart_toy', 'icon': Icons.smart_toy},
    {'name': 'memory', 'icon': Icons.memory},
    {'name': 'route', 'icon': Icons.route},
    {'name': 'air', 'icon': Icons.air},
    {'name': 'hub', 'icon': Icons.hub},
    {'name': 'speed', 'icon': Icons.speed},
  ];

  final List<String> _colorOptions = [
    '#4285F4', '#D97757', '#10A37F', '#6C5CE7',
    '#76B900', '#FF6B35', '#39594D', '#F55036',
  ];

  @override
  void initState() {
    super.initState();
    final p = widget.provider;
    _idController = TextEditingController(text: p?.id ?? '');
    _nameController = TextEditingController(text: p?.name ?? '');
    _providerController = TextEditingController(text: p?.provider ?? '');
    _descriptionController = TextEditingController(text: p?.description ?? '');
    _modelsController = TextEditingController(text: p?.models.join(', ') ?? '');
    _defaultModelController = TextEditingController(text: p?.defaultModel ?? '');
    _secretNameController = TextEditingController(text: p?.secretName ?? '');
    _costInputController = TextEditingController(text: p?.costPer1kInput.toString() ?? '0.0');
    _costOutputController = TextEditingController(text: p?.costPer1kOutput.toString() ?? '0.0');
    _contextWindowController = TextEditingController(text: p?.contextWindow.toString() ?? '128000');
    _orderController = TextEditingController(text: p?.order.toString() ?? '0');
    _selectedIcon = p?.icon ?? 'smart_toy';
    _selectedColor = p?.brandColor ?? '#4285F4';
  }

  @override
  void dispose() {
    _idController.dispose();
    _nameController.dispose();
    _providerController.dispose();
    _descriptionController.dispose();
    _modelsController.dispose();
    _defaultModelController.dispose();
    _secretNameController.dispose();
    _costInputController.dispose();
    _costOutputController.dispose();
    _contextWindowController.dispose();
    _orderController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;

    setState(() => _isSaving = true);

    final models = _modelsController.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    final config = LLMProviderConfig(
      id: _idController.text.trim(),
      name: _nameController.text.trim(),
      provider: _providerController.text.trim(),
      description: _descriptionController.text.trim(),
      models: models,
      defaultModel: _defaultModelController.text.trim(),
      secretName: _secretNameController.text.trim(),
      brandColor: _selectedColor,
      icon: _selectedIcon,
      isEnabled: widget.provider?.isEnabled ?? false,
      showInRouting: widget.provider?.showInRouting ?? false,
      order: int.tryParse(_orderController.text) ?? 0,
      costPer1kInput: double.tryParse(_costInputController.text) ?? 0.0,
      costPer1kOutput: double.tryParse(_costOutputController.text) ?? 0.0,
      contextWindow: int.tryParse(_contextWindowController.text) ?? 128000,
    );

    await widget.onSave(config);
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(isNew ? 'Add LLM Provider' : 'Edit LLM Provider'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isNew) ...[
                TextField(
                  controller: _idController,
                  decoration: const InputDecoration(
                    labelText: 'ID *',
                    hintText: 'e.g., groq, openai, custom-llm',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Display Name *',
                  hintText: 'e.g., Groq, OpenAI GPT',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _providerController,
                decoration: const InputDecoration(
                  labelText: 'Provider Company *',
                  hintText: 'e.g., Groq, OpenAI, Anthropic',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _descriptionController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _modelsController,
                decoration: const InputDecoration(
                  labelText: 'Models (comma-separated) *',
                  hintText: 'e.g., gpt-4o, gpt-4-turbo, gpt-3.5-turbo',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _defaultModelController,
                decoration: const InputDecoration(
                  labelText: 'Default Model *',
                  hintText: 'e.g., gpt-4o',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _secretNameController,
                decoration: const InputDecoration(
                  labelText: 'Secret Name (in Secret Manager) *',
                  hintText: 'e.g., openai-api-key',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _costInputController,
                      decoration: const InputDecoration(
                        labelText: 'Cost per 1k Input',
                        prefixText: '\$',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _costOutputController,
                      decoration: const InputDecoration(
                        labelText: 'Cost per 1k Output',
                        prefixText: '\$',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _contextWindowController,
                      decoration: const InputDecoration(
                        labelText: 'Context Window',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _orderController,
                      decoration: const InputDecoration(
                        labelText: 'Order',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Icon', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _iconOptions.map((opt) {
                  final isSelected = opt['name'] == _selectedIcon;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedIcon = opt['name']),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.blue.withOpacity(0.1) : Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected ? Colors.blue : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Icon(opt['icon'], size: 24),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              const Text('Brand Color', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _colorOptions.map((hex) {
                  final isSelected = hex == _selectedColor;
                  final color = Color(int.parse('FF${hex.substring(1)}', radix: 16));
                  return GestureDetector(
                    onTap: () => setState(() => _selectedColor = hex),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected ? Colors.black : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: isSelected
                          ? const Icon(Icons.check, color: Colors.white, size: 18)
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isNew ? 'Create' : 'Save'),
        ),
      ],
    );
  }
}
