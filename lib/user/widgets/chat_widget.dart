// IAMONEAI - Chat Widget
// Beautiful chat interface for AI interactions
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/chat_service.dart';

class ChatWidget extends StatefulWidget {
  final String userIin;
  final String userName;

  const ChatWidget({
    super.key,
    required this.userIin,
    required this.userName,
  });

  @override
  State<ChatWidget> createState() => _ChatWidgetState();
}

class _ChatWidgetState extends State<ChatWidget> {
  final ChatService _chatService = ChatService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ScrollController _debugScrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  bool _isLoading = false;
  String _selectedModel = 'llama3';
  bool _showDebugPanel = true;
  double _debugPanelWidth = 350;
  ChatMessage? _selectedMessage;

  @override
  void initState() {
    super.initState();
    _chatService.setUserIin(widget.userIin);
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _debugScrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool _isDesktop(BuildContext context) {
    return MediaQuery.of(context).size.width >= 900;
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

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty || _isLoading) return;

    _messageController.clear();
    setState(() {
      _isLoading = true;
    });
    _scrollToBottom();

    await _chatService.sendMessage(message, model: _selectedModel);

    setState(() {
      _isLoading = false;
    });
    _scrollToBottom();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = _isDesktop(context);

    return Row(
      children: [
        // Chat area
        Expanded(
          child: Column(
            children: [
              // Chat messages
              Expanded(
                child: _chatService.messages.isEmpty
                    ? _buildEmptyState()
                    : _buildMessageList(),
              ),
              // Input area
              _buildInputArea(),
            ],
          ),
        ),

        // Debug panel (desktop only)
        if (isDesktop && _showDebugPanel) ...[
          // Resizable divider
          MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              onHorizontalDragUpdate: (details) {
                setState(() {
                  _debugPanelWidth -= details.delta.dx;
                  _debugPanelWidth = _debugPanelWidth.clamp(200.0, 600.0);
                });
              },
              child: Container(
                width: 8,
                color: const Color(0xFFE0E0E0),
                child: Center(
                  child: Container(
                    width: 4,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF999999),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Debug panel
          SizedBox(
            width: _debugPanelWidth,
            child: _buildDebugPanel(),
          ),
        ],
      ],
    );
  }

  Widget _buildDebugPanel() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        border: Border(
          left: BorderSide(color: Color(0xFF333333)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF252525),
              border: Border(
                bottom: BorderSide(color: Color(0xFF333333)),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.bug_report, color: Color(0xFF4EC9B0), size: 18),
                const SizedBox(width: 8),
                const Text(
                  'Debug Panel',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF999999), size: 18),
                  onPressed: () {
                    setState(() {
                      _showDebugPanel = false;
                    });
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: _selectedMessage != null
                ? _buildJsonViewer(_selectedMessage!)
                : _buildDebugInstructions(),
          ),
        ],
      ),
    );
  }

  Widget _buildDebugInstructions() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.touch_app, color: Color(0xFF666666), size: 48),
            SizedBox(height: 16),
            Text(
              'Click on a message\nto view JSON',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF666666),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJsonViewer(ChatMessage message) {
    final jsonData = message.isUser
        ? {'type': 'request', 'data': message.requestJson}
        : {'type': 'response', 'data': message.responseJson};

    final jsonString = const JsonEncoder.withIndent('  ').convert(jsonData);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Copy button
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: const BoxDecoration(
            color: Color(0xFF2D2D2D),
            border: Border(
              bottom: BorderSide(color: Color(0xFF333333)),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: message.isUser ? const Color(0xFF264F78) : const Color(0xFF3C3C3C),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  message.isUser ? 'REQUEST' : 'RESPONSE',
                  style: TextStyle(
                    color: message.isUser ? const Color(0xFF9CDCFE) : const Color(0xFF4EC9B0),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: jsonString));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Copied to clipboard'),
                        duration: Duration(seconds: 2),
                        backgroundColor: Color(0xFF333333),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFF444444)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.copy, color: Color(0xFF999999), size: 14),
                        SizedBox(width: 4),
                        Text(
                          'Copy',
                          style: TextStyle(
                            color: Color(0xFF999999),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // JSON content
        Expanded(
          child: SingleChildScrollView(
            controller: _debugScrollController,
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              jsonString,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Color(0xFFD4D4D4),
                height: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFFE0E0E0),
                width: 2,
              ),
            ),
            child: const Center(
              child: Text(
                'I',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Hello, ${widget.userName}!',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'How can I help you today?',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF666666),
            ),
          ),
          const SizedBox(height: 32),
          // Suggestion chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _buildSuggestionChip('Tell me a joke'),
              _buildSuggestionChip('What can you do?'),
              _buildSuggestionChip('Help me brainstorm'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionChip(String text) {
    return ActionChip(
      label: Text(text),
      onPressed: () {
        _messageController.text = text;
        _sendMessage();
      },
      backgroundColor: Colors.white,
      side: const BorderSide(color: Color(0xFFE0E0E0)),
      labelStyle: const TextStyle(
        color: Color(0xFF1A1A1A),
        fontSize: 13,
      ),
    );
  }

  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      itemCount: _chatService.messages.length + (_isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _chatService.messages.length && _isLoading) {
          return _buildTypingIndicator();
        }
        return _buildMessageBubble(_chatService.messages[index]);
      },
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final isUser = message.isUser;
    final isSelected = _selectedMessage?.id == message.id;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedMessage = message;
            _showDebugPanel = true;
          });
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: isSelected
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF4EC9B0), width: 2),
                )
              : null,
          padding: isSelected ? const EdgeInsets.all(4) : null,
          child: Row(
            mainAxisAlignment:
                isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isUser) ...[
                // AI Avatar
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: message.isError
                        ? const Color(0xFFFFEBEE)
                        : const Color(0xFF1A1A1A),
                  ),
                  child: Center(
                    child: Text(
                      message.isError ? '!' : 'I',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: message.isError ? Colors.red : Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isUser
                        ? const Color(0xFF1A1A1A)
                        : message.isError
                            ? const Color(0xFFFFEBEE)
                            : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isUser ? 16 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 16),
                    ),
                    border: isUser
                        ? null
                        : Border.all(
                            color: message.isError
                                ? Colors.red.shade200
                                : const Color(0xFFE0E0E0),
                          ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        message.content,
                        style: TextStyle(
                          fontSize: 14,
                          color: isUser
                              ? Colors.white
                              : message.isError
                                  ? Colors.red.shade700
                                  : const Color(0xFF1A1A1A),
                          height: 1.5,
                        ),
                      ),
                      if (!isUser && message.responseJson != null) ...[
                        const SizedBox(height: 10),
                        _buildMetadataBadges(message),
                      ],
                    ],
                  ),
                ),
              ),
              if (isUser) ...[
                const SizedBox(width: 12),
                // User Avatar
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF666666),
                  ),
                  child: Center(
                    child: Text(
                      widget.userName.isNotEmpty
                          ? widget.userName[0].toUpperCase()
                          : 'U',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetadataBadges(ChatMessage message) {
    final response = message.responseJson ?? {};
    final provider = response['provider'] as String? ?? 'unknown';
    final model = response['model'] as String? ?? 'unknown';
    final latencyMs = response['latency_ms'] as int?;
    final usage = response['usage'] as Map<String, dynamic>?;
    final promptTokens = usage?['prompt_tokens'] as int?;
    final completionTokens = usage?['completion_tokens'] as int?;
    final totalTokens = usage?['total_tokens'] as int?;

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        // Provider badge
        _buildBadge(
          icon: Icons.cloud_outlined,
          label: provider.toUpperCase(),
          color: const Color(0xFF6366F1),
        ),
        // Model badge
        _buildBadge(
          icon: Icons.smart_toy_outlined,
          label: model.toUpperCase(),
          color: const Color(0xFF10B981),
        ),
        // Latency badge
        if (latencyMs != null)
          _buildBadge(
            icon: Icons.timer_outlined,
            label: latencyMs >= 1000
                ? '${(latencyMs / 1000).toStringAsFixed(1)}s'
                : '${latencyMs}ms',
            color: latencyMs < 2000
                ? const Color(0xFF10B981)
                : latencyMs < 5000
                    ? const Color(0xFFF59E0B)
                    : const Color(0xFFEF4444),
          ),
        // Tokens badge
        if (totalTokens != null || promptTokens != null)
          _buildBadge(
            icon: Icons.token_outlined,
            label: totalTokens != null
                ? '$totalTokens tok'
                : '${promptTokens ?? 0}+${completionTokens ?? 0} tok',
            color: const Color(0xFF8B5CF6),
          ),
      ],
    );
  }

  Widget _buildBadge({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Color.fromRGBO(color.red, color.green, color.blue, 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Color.fromRGBO(color.red, color.green, color.blue, 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF1A1A1A),
            ),
            child: const Center(
              child: Text(
                'I',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE0E0E0)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDot(0),
                const SizedBox(width: 4),
                _buildDot(1),
                const SizedBox(width: 4),
                _buildDot(2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDot(int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 600 + (index * 200)),
      builder: (context, value, child) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Color.lerp(
              const Color(0xFFE0E0E0),
              const Color(0xFF666666),
              (1 + (index * 0.3) + value) % 1,
            ),
          ),
        );
      },
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Color(0xFFE0E0E0)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Model selector
            PopupMenuButton<String>(
              initialValue: _selectedModel,
              onSelected: (value) {
                setState(() {
                  _selectedModel = value;
                });
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'llama3',
                  child: Text('Llama 3'),
                ),
                const PopupMenuItem(
                  value: 'mistral',
                  child: Text('Mistral'),
                ),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _selectedModel == 'llama3' ? 'Llama 3' : 'Mistral',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF666666),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.arrow_drop_down,
                      size: 16,
                      color: Color(0xFF666666),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Message input
            Expanded(
              child: TextField(
                controller: _messageController,
                focusNode: _focusNode,
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  hintStyle: const TextStyle(color: Color(0xFF999999)),
                  filled: true,
                  fillColor: const Color(0xFFF5F5F5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 12),

            // Send button
            Material(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(24),
              child: InkWell(
                onTap: _isLoading ? null : _sendMessage,
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Icon(
                    _isLoading ? Icons.hourglass_empty : Icons.send,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
