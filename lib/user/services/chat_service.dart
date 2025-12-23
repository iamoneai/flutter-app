// IAMONEAI - Chat Service
// Handles chat interactions with the AI backend
import 'package:flutter/foundation.dart';
import '../../core/services/api_service.dart';

/// Represents a chat message
class ChatMessage {
  final String id;
  final String content;
  final bool isUser;
  final DateTime timestamp;
  final String? model;
  final bool isError;
  final Map<String, dynamic>? requestJson;
  final Map<String, dynamic>? responseJson;

  ChatMessage({
    required this.id,
    required this.content,
    required this.isUser,
    required this.timestamp,
    this.model,
    this.isError = false,
    this.requestJson,
    this.responseJson,
  });
}

/// Chat service for communicating with the AI backend
class ChatService {
  final ApiService _apiService = ApiService();
  final List<ChatMessage> _messages = [];
  String? _userIin;

  /// Get all messages
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  /// Set the user IIN for API calls
  void setUserIin(String iin) {
    _userIin = iin;
  }

  /// Clear all messages
  void clearMessages() {
    _messages.clear();
  }

  /// Send a message and get a response
  Future<ChatMessage> sendMessage(
    String message, {
    String model = 'llama3',
    bool useHistory = true,
  }) async {
    final requestBody = {
      'message': message,
      'model': model,
      'max_tokens': 1024,
      'temperature': 0.7,
      'use_history': useHistory,
    };

    // Add user message with request JSON
    final userMessage = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: message,
      isUser: true,
      timestamp: DateTime.now(),
      requestJson: requestBody,
    );
    _messages.add(userMessage);

    try {
      final response = await _apiService.post(
        '/api/chat',
        requestBody,
        userId: _userIin,
      );

      final assistantMessage = ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        content: response['response'] as String? ?? 'No response received',
        isUser: false,
        timestamp: DateTime.now(),
        model: response['model'] as String?,
        responseJson: response,
      );
      _messages.add(assistantMessage);

      return assistantMessage;
    } catch (e) {
      debugPrint('Chat error: $e');

      final errorMessage = ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        content: 'Sorry, I encountered an error. Please try again.',
        isUser: false,
        timestamp: DateTime.now(),
        isError: true,
        responseJson: {'error': e.toString()},
      );
      _messages.add(errorMessage);

      return errorMessage;
    }
  }

  /// Get chat history from the server
  Future<List<Map<String, dynamic>>> getChatHistory({int limit = 20}) async {
    if (_userIin == null) return [];

    try {
      final response = await _apiService.get(
        '/api/chat/history',
        userId: _userIin,
        queryParams: {'limit': limit.toString()},
      );

      return List<Map<String, dynamic>>.from(response['history'] ?? []);
    } catch (e) {
      debugPrint('Error getting chat history: $e');
      return [];
    }
  }

  /// Clear chat history on the server
  Future<bool> clearChatHistory() async {
    if (_userIin == null) return false;

    try {
      await _apiService.get('/api/chat/history', userId: _userIin);
      _messages.clear();
      return true;
    } catch (e) {
      debugPrint('Error clearing chat history: $e');
      return false;
    }
  }
}
