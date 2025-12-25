// IAMONEAI - LLM Status Content
import 'package:flutter/material.dart';

/// LLM Provider configuration
class LLMProvider {
  final String id;
  final String name;
  final String provider;
  final String description;
  final List<String> models;
  final String secretName;
  final Color brandColor;
  final IconData icon;
  bool isEnabled;
  bool showInRouting; // NEW: Show in routing/config page
  String status; // 'active', 'inactive', 'error', 'checking'
  int? latencyMs;
  String? lastChecked;

  LLMProvider({
    required this.id,
    required this.name,
    required this.provider,
    required this.description,
    required this.models,
    required this.secretName,
    required this.brandColor,
    required this.icon,
    this.isEnabled = false,
    this.showInRouting = true,
    this.status = 'inactive',
    this.latencyMs,
    this.lastChecked,
  });

  LLMProvider copyWith({
    bool? isEnabled,
    bool? showInRouting,
    String? status,
    int? latencyMs,
    String? lastChecked,
  }) {
    return LLMProvider(
      id: id,
      name: name,
      provider: provider,
      description: description,
      models: models,
      secretName: secretName,
      brandColor: brandColor,
      icon: icon,
      isEnabled: isEnabled ?? this.isEnabled,
      showInRouting: showInRouting ?? this.showInRouting,
      status: status ?? this.status,
      latencyMs: latencyMs ?? this.latencyMs,
      lastChecked: lastChecked ?? this.lastChecked,
    );
  }
}

/// Shared LLM state manager
class LLMStateManager {
  static final LLMStateManager _instance = LLMStateManager._internal();
  factory LLMStateManager() => _instance;
  LLMStateManager._internal();

  final List<LLMProvider> _providers = [
    LLMProvider(
      id: 'gemini',
      name: 'Google Gemini',
      provider: 'Google',
      description: 'Multimodal AI with vision, code, and reasoning capabilities',
      models: ['gemini-2.0-flash', 'gemini-1.5-pro', 'gemini-1.5-flash'],
      secretName: 'gemini-api-key',
      brandColor: const Color(0xFF4285F4),
      icon: Icons.auto_awesome,
      isEnabled: true,
      showInRouting: true,
      status: 'active',
      latencyMs: 245,
      lastChecked: '2 min ago',
    ),
    LLMProvider(
      id: 'claude',
      name: 'Anthropic Claude',
      provider: 'Anthropic',
      description: 'Advanced reasoning with safety-focused AI assistant',
      models: ['claude-3-opus', 'claude-3-sonnet', 'claude-3-haiku'],
      secretName: 'anthropic-api-key',
      brandColor: const Color(0xFFD97757),
      icon: Icons.psychology,
      isEnabled: true,
      showInRouting: true,
      status: 'active',
      latencyMs: 312,
      lastChecked: '2 min ago',
    ),
    LLMProvider(
      id: 'openai',
      name: 'OpenAI GPT',
      provider: 'OpenAI',
      description: 'GPT-4 and GPT-3.5 models for diverse AI tasks',
      models: ['gpt-4o', 'gpt-4-turbo', 'gpt-3.5-turbo'],
      secretName: 'openai-api-key',
      brandColor: const Color(0xFF10A37F),
      icon: Icons.smart_toy,
      isEnabled: true,
      showInRouting: true,
      status: 'active',
      latencyMs: 198,
      lastChecked: '2 min ago',
    ),
    LLMProvider(
      id: 'llama3',
      name: 'Meta Llama 3',
      provider: 'RunPod',
      description: 'Open-source LLM for chat and conversation',
      models: ['llama-3-8b-instruct', 'llama-3-70b-instruct'],
      secretName: 'RUNPOD_API_KEY',
      brandColor: const Color(0xFF6C5CE7),
      icon: Icons.memory,
      isEnabled: true,
      showInRouting: true,
      status: 'active',
      latencyMs: 1850,
      lastChecked: '1 min ago',
    ),
    LLMProvider(
      id: 'nemotron',
      name: 'NVIDIA Nemotron',
      provider: 'RunPod',
      description: 'Optimized for classification, routing, and orchestration',
      models: ['nemotron-mini-4b-instruct'],
      secretName: 'RUNPOD_API_KEY',
      brandColor: const Color(0xFF76B900),
      icon: Icons.route,
      isEnabled: true,
      showInRouting: true,
      status: 'active',
      latencyMs: 1420,
      lastChecked: '1 min ago',
    ),
    LLMProvider(
      id: 'mistral',
      name: 'Mistral AI',
      provider: 'Mistral',
      description: 'European AI with efficient open-weight models',
      models: ['mistral-large', 'mistral-medium', 'mistral-small'],
      secretName: 'mistral-api-key',
      brandColor: const Color(0xFFFF6B35),
      icon: Icons.air,
      isEnabled: false,
      showInRouting: false,
      status: 'inactive',
    ),
    LLMProvider(
      id: 'cohere',
      name: 'Cohere',
      provider: 'Cohere',
      description: 'Enterprise NLP with RAG and embeddings focus',
      models: ['command-r-plus', 'command-r', 'embed-v3'],
      secretName: 'cohere-api-key',
      brandColor: const Color(0xFF39594D),
      icon: Icons.hub,
      isEnabled: false,
      showInRouting: false,
      status: 'inactive',
    ),
    LLMProvider(
      id: 'groq',
      name: 'Groq',
      provider: 'Groq',
      description: 'Ultra-fast inference with LPU technology',
      models: ['llama-3-70b', 'mixtral-8x7b', 'gemma-7b'],
      secretName: 'groq-api-key',
      brandColor: const Color(0xFFF55036),
      icon: Icons.speed,
      isEnabled: false,
      showInRouting: false,
      status: 'inactive',
    ),
  ];

  List<LLMProvider> get providers => _providers;

  List<LLMProvider> get routingProviders =>
      _providers.where((p) => p.isEnabled && p.showInRouting).toList();

  void updateProvider(String id, {bool? isEnabled, bool? showInRouting}) {
    final index = _providers.indexWhere((p) => p.id == id);
    if (index != -1) {
      final provider = _providers[index];
      _providers[index] = provider.copyWith(
        isEnabled: isEnabled,
        showInRouting: showInRouting,
        status: (isEnabled ?? provider.isEnabled) ? 'active' : 'inactive',
      );
    }
  }

  final List<VoidCallback> _listeners = [];

  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  void notifyListeners() {
    for (final listener in _listeners) {
      listener();
    }
  }
}

class LLMStatusContent extends StatefulWidget {
  const LLMStatusContent({super.key});

  @override
  State<LLMStatusContent> createState() => _LLMStatusContentState();
}

class _LLMStatusContentState extends State<LLMStatusContent> {
  final _stateManager = LLMStateManager();
  bool _isRefreshing = false;

  List<LLMProvider> get _providers => _stateManager.providers;

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

  Future<void> _refreshAllStatus() async {
    setState(() => _isRefreshing = true);

    // Simulate checking status
    await Future.delayed(const Duration(seconds: 2));

    setState(() {
      for (var provider in _providers) {
        if (provider.isEnabled) {
          provider.lastChecked = 'Just now';
        }
      }
      _isRefreshing = false;
    });
  }

  void _toggleProvider(LLMProvider provider) {
    setState(() {
      provider.isEnabled = !provider.isEnabled;
      provider.status = provider.isEnabled ? 'active' : 'inactive';
      if (!provider.isEnabled) {
        provider.latencyMs = null;
        provider.lastChecked = null;
        provider.showInRouting = false; // Also disable routing when disabled
      }
      _stateManager.notifyListeners();
    });
  }

  void _toggleShowInRouting(LLMProvider provider) {
    if (provider.showInRouting) {
      // Turning OFF - show warning
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Remove from Routing?'),
          content: Text(
            'This will remove ${provider.name} from ALL routing groups.\n\n'
            'The LLM will be completely removed from Orchestrator, Reasoning, Executors, and any custom groups.\n\n'
            'Are you sure?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  provider.showInRouting = false;
                  _stateManager.notifyListeners();
                });
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Remove', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    } else {
      // Turning ON - just enable
      setState(() {
        provider.showInRouting = true;
        _stateManager.notifyListeners();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabledCount = _providers.where((p) => p.isEnabled).length;
    final activeCount = _providers.where((p) => p.status == 'active').length;
    final routingCount = _providers.where((p) => p.showInRouting && p.isEnabled).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Summary bar
        _buildSummaryBar(enabledCount, activeCount, routingCount),
        const SizedBox(height: 16),
        // Provider grid
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 16,
              runSpacing: 16,
              children: _providers.map((p) => _buildProviderCard(p)).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryBar(int enabled, int active, int routing) {
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
          const SizedBox(width: 24),
          _buildStatBadge('In Routing', routing.toString(), Colors.purple),
          const Spacer(),
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

  Widget _buildProviderCard(LLMProvider provider) {
    final isActive = provider.status == 'active';
    final isEnabled = provider.isEnabled;

    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? provider.brandColor.withOpacity(0.3) : const Color(0xFFE0E0E0),
          width: isActive ? 2 : 1,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: provider.brandColor.withOpacity(0.1),
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
              color: isEnabled ? provider.brandColor.withOpacity(0.1) : const Color(0xFFF5F5F5),
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
                    color: isEnabled ? provider.brandColor : Colors.grey,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(provider.icon, color: Colors.white, size: 22),
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
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isEnabled ? const Color(0xFFF0F0F0) : const Color(0xFFF8F8F8),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        model,
                        style: TextStyle(
                          fontSize: 11,
                          color: isEnabled ? const Color(0xFF666666) : const Color(0xFFAAAAAA),
                          fontFamily: 'monospace',
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
                // API Key status
                Row(
                  children: [
                    Icon(
                      Icons.key,
                      size: 14,
                      color: _hasApiKey(provider) ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _hasApiKey(provider) ? 'Configured' : 'Not configured',
                      style: TextStyle(
                        fontSize: 12,
                        color: _hasApiKey(provider) ? Colors.green[700] : Colors.orange[700],
                      ),
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
                        onChanged: isEnabled && _hasApiKey(provider)
                            ? (_) => _toggleShowInRouting(provider)
                            : null,
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
                        onChanged: _hasApiKey(provider)
                            ? (_) => _toggleProvider(provider)
                            : null,
                        activeColor: provider.brandColor,
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

  Widget _buildStatusIndicator(LLMProvider provider) {
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

  bool _hasApiKey(LLMProvider provider) {
    // These are the ones we know are configured
    const configuredSecrets = [
      'gemini-api-key',
      'anthropic-api-key',
      'openai-api-key',
      'RUNPOD_API_KEY',
    ];
    return configuredSecrets.contains(provider.secretName);
  }
}
