import 'package:cactus/cactus.dart';
import 'model_manager.dart';

/// Service for analyzing images with vision model
class VisionService {
  final ModelManager _modelManager = ModelManager();

  /// Clean model response by removing think tags and extracting clean answer
  String _cleanResponse(String response) {
    // Remove <think> blocks entirely
    String cleaned = response.replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '').trim();

    // If response starts with "I see" or similar, extract just that part
    if (cleaned.isEmpty) {
      // Fallback: try to extract text after </think> if present
      final thinkEnd = response.lastIndexOf('</think>');
      if (thinkEnd != -1) {
        cleaned = response.substring(thinkEnd + 8).trim();
      }
    }

    // Remove any remaining XML-like tags
    cleaned = cleaned.replaceAll(RegExp(r'<[^>]+>'), '').trim();

    // Take only the first 2-3 sentences for TTS
    final sentences = cleaned.split(RegExp(r'[.!?]\s+'));
    if (sentences.length > 3) {
      cleaned = sentences.take(3).join('. ') + '.';
    }

    print('DEBUG VISION: Cleaned response: "$cleaned"');
    return cleaned.isEmpty ? 'I see an image.' : cleaned;
  }

  /// Analyze an image and return description
  Future<String> analyzeImage(
    String imagePath, {
    String prompt = 'Describe what you see in this image in detail.',
  }) async {
    try {
      final result = await _modelManager.visionLM.generateCompletion(
        params: CactusCompletionParams(maxTokens: 200),
        messages: [
          ChatMessage(
            content: 'You are a vision assistant that analyzes images. Describe what you see concisely and accurately.',
            role: 'system',
          ),
          ChatMessage(
            content: prompt,
            role: 'user',
            images: [imagePath],
          ),
        ],
      );

      if (result.success) {
        print('DEBUG VISION: Raw response: "${result.response}"');
        return _cleanResponse(result.response);
      } else {
        throw Exception('Vision analysis failed');
      }
    } catch (e) {
      print('Error analyzing image: $e');
      rethrow;
    }
  }

  /// Analyze image with streaming response
  Stream<String> analyzeImageStream(
    String imagePath, {
    String prompt = 'Describe what you see in this image in detail.',
  }) async* {
    try {
      final streamedResult =
          await _modelManager.visionLM.generateCompletionStream(
        messages: [
          ChatMessage(
            content: 'You are a vision assistant that analyzes images. Describe what you see concisely and accurately.',
            role: 'system',
          ),
          ChatMessage(
            content: prompt,
            role: 'user',
            images: [imagePath],
          ),
        ],
        params: CactusCompletionParams(maxTokens: 200),
      );

      await for (final chunk in streamedResult.stream) {
        yield chunk;
      }
    } catch (e) {
      print('Error in streaming analysis: $e');
      rethrow;
    }
  }

  /// Extract specific information from image (e.g., read label)
  Future<String> extractInfo(
    String imagePath,
    String question,
  ) async {
    try {
      final result = await _modelManager.visionLM.generateCompletion(
        params: CactusCompletionParams(maxTokens: 150),
        messages: [
          ChatMessage(
            content: 'You are a vision assistant that analyzes images. Answer questions about what you see concisely and accurately.',
            role: 'system',
          ),
          ChatMessage(
            content: question,
            role: 'user',
            images: [imagePath],
          ),
        ],
      );

      if (result.success) {
        return _cleanResponse(result.response);
      } else {
        throw Exception('Information extraction failed');
      }
    } catch (e) {
      print('Error extracting info: $e');
      rethrow;
    }
  }
}
