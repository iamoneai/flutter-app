import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class DeveloperChatScreen extends StatefulWidget {
  const DeveloperChatScreen({super.key});

  @override
  State<DeveloperChatScreen> createState() => _DeveloperChatScreenState();
}

class _DeveloperChatScreenState extends State<DeveloperChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = false;
  bool _isCheckingIIN = true;
  String? _adminIIN;
  String? _adminUserName;
  String? _linkedUserId;

  String _selectedProvider = 'all';
  String _selectedContext = 'personal';
  int _debugTabIndex = 0;

  // Resizable panel
  double _leftPanelRatio = 0.6;
  static const double _minPanelWidth = 300;

  final List<ChatMessage> _messages = [];
  ChatMessage? _selectedMessage;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final List<Map<String, dynamic>> _providers = [
    {'value': 'all', 'label': 'Smart Router', 'icon': Icons.auto_awesome, 'color': Colors.purple},
    {'value': 'claude', 'label': 'Claude', 'icon': Icons.psychology, 'color': Colors.deepOrange},
    {'value': 'openai', 'label': 'ChatGPT', 'icon': Icons.chat_bubble, 'color': Colors.green},
    {'value': 'gemini', 'label': 'Gemini', 'icon': Icons.diamond, 'color': Colors.blue},
  ];

  final List<Map<String, dynamic>> _contextModes = [
    {'value': 'personal', 'label': 'Personal', 'icon': Icons.person, 'color': Colors.blue},
    {'value': 'work', 'label': 'Work', 'icon': Icons.work, 'color': Colors.orange},
    {'value': 'family', 'label': 'Family', 'icon': Icons.family_restroom, 'color': Colors.purple},
  ];

  @override
  void initState() {
    super.initState();
    _checkAdminIIN();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _checkAdminIIN() async {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() => _isCheckingIIN = false);
      return;
    }

    try {
      final adminDoc = await _firestore.collection('users').doc(user.uid).get();

      if (adminDoc.exists) {
        final data = adminDoc.data()!;
        final iin = data['iin'] as String?;

        if (iin != null && iin.isNotEmpty) {
          final userQuery = await _firestore
              .collection('users')
              .where('iin', isEqualTo: iin)
              .limit(1)
              .get();

          if (userQuery.docs.isNotEmpty) {
            final userData = userQuery.docs.first.data();
            setState(() {
              _adminIIN = iin;
              _linkedUserId = userQuery.docs.first.id;
              _adminUserName = userData['firstName'] as String? ??
                  (userData['displayName'] as String?)?.split(' ')[0] ??
                  'Unknown';
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking admin IIN: $e');
    } finally {
      setState(() => _isCheckingIIN = false);
    }
  }

  Future<void> _sendMessage() async {
    final messageText = _messageController.text.trim();
    if (messageText.isEmpty) return;

    if (_linkedUserId == null || _adminIIN == null) {
      _showSnackBar('Identity Error: No IIN linked.', isError: true);
      return;
    }

    setState(() {
      _messages.add(ChatMessage(text: messageText, isUser: true, timestamp: DateTime.now()));
      _isLoading = true;
    });

    _messageController.clear();
    _scrollToBottom();

    try {
      final startTime = DateTime.now();
      const String apiUrl = 'https://chat-qqkntitb3a-uc.a.run.app';

      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "message": messageText,
          "userId": _linkedUserId,
          "userName": _adminUserName,
          "provider": _selectedProvider,
          "context": _selectedContext,
        }),
      );

      final latency = DateTime.now().difference(startTime).inMilliseconds;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final newMessage = ChatMessage(
          text: data['response'] as String? ?? '<No response>',
          isUser: false,
          timestamp: DateTime.now(),
          debugData: data,
          latencyMs: latency,
        );
        setState(() {
          _messages.add(newMessage);
          _selectedMessage = newMessage;
          _isLoading = false;
        });
      } else {
        throw Exception('API Error: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage(
          text: 'Error: $e',
          isUser: false,
          timestamp: DateTime.now(),
          isError: true,
        ));
        _isLoading = false;
      });
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _clearChat() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Chat?'),
        content: const Text('This will delete all messages in this session.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _messages.clear();
                _selectedMessage = null;
              });
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    _showSnackBar('$label copied!');
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _getProviderLabel(String? provider) {
    if (provider == null) return 'UNKNOWN';
    return provider.toUpperCase();
  }

  Color _getProviderColor(String? provider) {
    switch (provider?.toLowerCase()) {
      case 'gemini':
        return Colors.blue;
      case 'claude':
        return Colors.deepOrange;
      case 'openai':
        return Colors.green;
      default:
        return Colors.purple;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingIIN) {
      return Scaffold(
        appBar: AppBar(title: const Text('Dev Chat')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_adminIIN == null || _linkedUserId == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('Dev Chat'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.person_off, size: 64, color: Colors.orange[700]),
              const SizedBox(height: 24),
              const Text('IIN Required', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text('Link your IIN in your profile to use chat.'),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0f0f1a),
      body: Column(
        children: [
          _buildHeader(),
          _buildContextBar(),
          Expanded(child: _buildMainContent()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a2e),
        border: Border(
          bottom: BorderSide(color: const Color(0xFF2a2a3e).withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Back',
          ),
          const SizedBox(width: 8),
          const Icon(Icons.terminal, color: Color(0xFF7c3aed)),
          const SizedBox(width: 8),
          const Text(
            'Dev Chat',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF7c3aed).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF7c3aed).withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.verified_user, size: 16, color: Color(0xFF7c3aed)),
                const SizedBox(width: 6),
                SelectableText(
                  '$_adminUserName ($_adminIIN)',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF7c3aed),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.delete_outline, color: _messages.isEmpty ? Colors.grey[600] : Colors.red[400]),
            onPressed: _messages.isEmpty ? null : _clearChat,
            tooltip: 'Clear Chat',
          ),
        ],
      ),
    );
  }

  Widget _buildContextBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: const Color(0xFF1a1a2e),
      child: Row(
        children: [
          ..._contextModes.map((mode) {
            final isSelected = _selectedContext == mode['value'];
            final color = mode['color'] as Color;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Material(
                color: isSelected ? color.withValues(alpha: 0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => setState(() => _selectedContext = mode['value'] as String),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? color : const Color(0xFF2a2a3e),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(mode['icon'] as IconData, size: 16, color: isSelected ? color : Colors.grey[500]),
                        const SizedBox(width: 6),
                        Text(
                          mode['label'] as String,
                          style: TextStyle(
                            color: isSelected ? color : Colors.grey[400],
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF0f0f1a),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF2a2a3e)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedProvider,
                dropdownColor: const Color(0xFF1a1a2e),
                items: _providers.map((p) => DropdownMenuItem<String>(
                  value: p['value'] as String,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(p['icon'] as IconData, size: 18, color: p['color'] as Color),
                      const SizedBox(width: 8),
                      Text(p['label'] as String, style: const TextStyle(color: Colors.white)),
                    ],
                  ),
                )).toList(),
                onChanged: (val) => setState(() => _selectedProvider = val!),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final leftWidth = (totalWidth * _leftPanelRatio).clamp(_minPanelWidth, totalWidth - _minPanelWidth);
        final rightWidth = totalWidth - leftWidth - 8; // 8 for divider

        return Row(
          children: [
            SizedBox(width: leftWidth, child: _buildChatPanel()),
            MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                onHorizontalDragUpdate: (details) {
                  setState(() {
                    final newRatio = (leftWidth + details.delta.dx) / totalWidth;
                    _leftPanelRatio = newRatio.clamp(
                      _minPanelWidth / totalWidth,
                      1 - (_minPanelWidth / totalWidth),
                    );
                  });
                },
                child: Container(
                  width: 8,
                  color: const Color(0xFF2a2a3e),
                  child: Center(
                    child: Container(
                      width: 4,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF7c3aed).withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(width: rightWidth, child: _buildDebugPanel()),
          ],
        );
      },
    );
  }

  Widget _buildChatPanel() {
    return Container(
      color: const Color(0xFF0f0f1a),
      child: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[600]),
                        const SizedBox(height: 16),
                        Text(
                          'Start a conversation',
                          style: TextStyle(color: Colors.grey[500], fontSize: 16),
                        ),
                      ],
                    ),
                  )
                : SelectionArea(
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) => _buildMessageBubble(_messages[index]),
                    ),
                  ),
          ),
          if (_isLoading)
            Container(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF7c3aed)),
                  ),
                  const SizedBox(width: 12),
                  Text('Thinking...', style: TextStyle(color: Colors.grey[500])),
                ],
              ),
            ),
          _buildInputArea(),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final hour = timestamp.hour.toString().padLeft(2, '0');
    final minute = timestamp.minute.toString().padLeft(2, '0');
    final second = timestamp.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  Widget _buildMessageBubble(ChatMessage msg) {
    final isSelected = _selectedMessage == msg && !msg.isUser;
    final tokensData = msg.debugData?['tokens'] as Map<String, dynamic>?;
    final totalTokens = tokensData?['total'] ?? msg.debugData?['tokensUsed'];
    final latency = msg.debugData?['latency'] ?? msg.latencyMs;

    return Align(
      alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: msg.isUser ? null : () => setState(() => _selectedMessage = msg),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: msg.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              // Timestamp
              Padding(
                padding: const EdgeInsets.only(bottom: 4, left: 4, right: 4),
                child: Text(
                  _formatTimestamp(msg.timestamp),
                  style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: msg.isUser
                      ? const Color(0xFF7c3aed)
                      : (msg.isError ? Colors.red.withValues(alpha: 0.15) : const Color(0xFF1a1a2e)),
                  borderRadius: BorderRadius.circular(16),
                  border: msg.isUser
                      ? null
                      : Border.all(
                          color: isSelected ? const Color(0xFF7c3aed) : const Color(0xFF2a2a3e),
                          width: isSelected ? 2 : 1,
                        ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      msg.text,
                      style: TextStyle(
                        color: msg.isUser ? Colors.white : (msg.isError ? Colors.red[400] : Colors.white),
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    if (!msg.isUser && !msg.isError && msg.debugData != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildBadge(
                            _getProviderLabel(msg.debugData?['provider'] as String?),
                            _getProviderColor(msg.debugData?['provider'] as String?),
                          ),
                          if (latency != null) ...[
                            const SizedBox(width: 8),
                            _buildBadge('${latency}ms', Colors.grey),
                          ],
                          if (totalTokens != null) ...[
                            const SizedBox(width: 8),
                            _buildBadge('$totalTokens tokens', Colors.purple),
                          ],
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 16),
                            onPressed: () => _copyToClipboard(msg.text, 'Response'),
                            tooltip: 'Copy response',
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(4),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color.withValues(alpha: 0.8),
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a2e),
        border: Border(top: BorderSide(color: const Color(0xFF2a2a3e).withValues(alpha: 0.5))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              enabled: !_isLoading,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Type a message...',
                hintStyle: TextStyle(color: Colors.grey[600]),
                filled: true,
                fillColor: const Color(0xFF0f0f1a),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: const Color(0xFF2a2a3e).withValues(alpha: 0.5)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: Color(0xFF7c3aed)),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 12),
          FloatingActionButton(
            onPressed: _isLoading ? null : _sendMessage,
            backgroundColor: _isLoading ? Colors.grey[700] : const Color(0xFF7c3aed),
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.send, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildDebugPanel() {
    return Container(
      color: const Color(0xFF1a1a2e),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: const Color(0xFF2a2a3e).withValues(alpha: 0.5))),
            ),
            child: Row(
              children: [
                _buildDebugTab('Memory (RAG)', 0),
                const SizedBox(width: 8),
                _buildDebugTab('Raw JSON', 1),
              ],
            ),
          ),
          Expanded(
            child: _selectedMessage == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.info_outline, size: 48, color: Colors.grey[600]),
                        const SizedBox(height: 12),
                        Text(
                          'Select an AI response\nto view debug info',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  )
                : _debugTabIndex == 0
                    ? _buildMemoryTab()
                    : _buildJsonTab(),
          ),
        ],
      ),
    );
  }

  Widget _buildDebugTab(String label, int index) {
    final isSelected = _debugTabIndex == index;
    return Material(
      color: isSelected ? const Color(0xFF7c3aed).withValues(alpha: 0.15) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() => _debugTabIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? const Color(0xFF7c3aed) : Colors.grey[500],
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMemoryTab() {
    final data = _selectedMessage?.debugData;
    final debug = data?['debug'] as Map<String, dynamic>? ?? {};

    // Parse tokens - can be nested or flat
    final tokensData = data?['tokens'] as Map<String, dynamic>?;
    final inputTokens = tokensData?['input'] ?? 0;
    final outputTokens = tokensData?['output'] ?? 0;
    final totalTokens = tokensData?['total'] ?? data?['tokensUsed'] ?? 0;

    final provider = data?['provider'] as String? ?? 'unknown';
    final model = data?['model'] as String? ?? 'unknown';
    final latency = data?['latency'] ?? _selectedMessage?.latencyMs ?? 0;

    // Memory info from debug
    final memoriesUsed = debug['memoriesUsed'] ?? 0;
    final memoryDetails = debug['memoryDetails'] as List<dynamic>? ?? [];
    final routingMethod = debug['routingMethod'] as String? ?? 'unknown';
    final matchedCategory = debug['matchedCategory'] as String? ?? 'None';
    final usedFallback = debug['usedFallback'] ?? false;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SelectionArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tokens card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF7c3aed).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF7c3aed).withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TOKENS USED',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[500],
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$totalTokens total',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF7c3aed),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildTokenBadge('Input', inputTokens, const Color(0xFF6366f1)),
                      const SizedBox(width: 8),
                      _buildTokenBadge('Output', outputTokens, Colors.green),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Model info
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0f0f1a),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2a2a3e)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _buildBadge(provider.toUpperCase(), _getProviderColor(provider)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          model,
                          style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: Colors.grey[400]),
                        ),
                      ),
                      Text(
                        '${latency}ms',
                        style: TextStyle(color: Colors.grey[500], fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.route, size: 16, color: Colors.grey[500]),
                      const SizedBox(width: 6),
                      Text(
                        routingMethod.replaceAll('_', ' ').toUpperCase(),
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                      const SizedBox(width: 12),
                      Icon(Icons.category, size: 16, color: Colors.grey[500]),
                      const SizedBox(width: 6),
                      Text(
                        matchedCategory,
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                      if (usedFallback) ...[
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'FALLBACK',
                            style: TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Retrieved memories
            Row(
              children: [
                const Icon(Icons.memory, size: 20, color: Color(0xFF7c3aed)),
                const SizedBox(width: 8),
                const Text(
                  'RETRIEVED MEMORIES',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2a2a3e),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$memoriesUsed',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (memoryDetails.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF0f0f1a),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2a2a3e)),
                ),
                child: Column(
                  children: [
                    Icon(Icons.memory, size: 32, color: Colors.grey[600]),
                    const SizedBox(height: 8),
                    Text(
                      'No long-term memories triggered',
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                  ],
                ),
              )
            else
              ...memoryDetails.map((memory) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7c3aed).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF7c3aed).withValues(alpha: 0.3)),
                    ),
                    child: SelectableText(
                      memory.toString(),
                      style: const TextStyle(fontSize: 13, color: Colors.white),
                    ),
                  )),
          ],
        ),
      ),
    );
  }

  Widget _buildTokenBadge(String label, dynamic count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildJsonTab() {
    final jsonString = const JsonEncoder.withIndent('  ').convert(_selectedMessage?.debugData ?? {});

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF0f0f1a),
            border: Border(bottom: BorderSide(color: const Color(0xFF2a2a3e).withValues(alpha: 0.5))),
          ),
          child: Row(
            children: [
              Text(
                'Response Data',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[400],
                ),
              ),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.copy, size: 16, color: Color(0xFF7c3aed)),
                label: const Text('Copy', style: TextStyle(color: Color(0xFF7c3aed))),
                onPressed: () => _copyToClipboard(jsonString, 'JSON'),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            color: const Color(0xFF0a0a0f),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                jsonString,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Color(0xFF9CDCFE),
                  height: 1.5,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final bool isError;
  final Map<String, dynamic>? debugData;
  final int? latencyMs;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.isError = false,
    this.debugData,
    this.latencyMs,
  });
}
