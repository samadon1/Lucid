import 'package:cactus/cactus.dart';
import '../models/memory.dart';
import 'model_manager.dart';

/// Service for conversational interactions
class ConversationService {
  final ModelManager _modelManager = ModelManager();
  final List<ChatMessage> _history = [];
  static const int _maxHistory = 5;

  /// Respond to a user query with optional memory context
  Future<String> respond(
    String query, {
    Memory? memoryContext,
    String? currentVisionDescription,
  }) async {
    try {
      // Add memory context if available
      if (memoryContext != null) {
        _history.add(ChatMessage(
          content: 'Context: ${memoryContext.userLabel}. '
              'Visual: ${memoryContext.visionDescription}',
          role: 'system',
        ));
      }

      // Add current vision context if available
      if (currentVisionDescription != null && currentVisionDescription.isNotEmpty) {
        _history.add(ChatMessage(
          content: 'Current view: $currentVisionDescription',
          role: 'system',
        ));
      }

      // Add user query
      _history.add(ChatMessage(content: query, role: 'user'));

      // Generate response
      final result = await _modelManager.conversationLM.generateCompletion(
        messages: _history,
        params: CactusCompletionParams(maxTokens: 150),
      );

      if (result.success) {
        // Add assistant response to history
        _history.add(ChatMessage(content: result.response, role: 'assistant'));

        // Keep only last N messages
        while (_history.length > _maxHistory) {
          _history.removeAt(0);
        }

        return result.response;
      } else {
        throw Exception('Conversation failed');
      }
    } catch (e) {
      print('Error in conversation: $e');
      rethrow;
    }
  }

  /// Reset conversation history
  void reset() {
    _history.clear();
  }

  /// Get conversation history
  List<ChatMessage> get history => List.unmodifiable(_history);
}
