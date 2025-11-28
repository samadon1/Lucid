import '../models/command.dart';

/// Parses voice transcriptions into commands
class CommandParser {
  /// Parse voice text into a command
  VoiceCommand parse(String transcription) {
    final text = transcription.toLowerCase().trim();

    // Pattern 1: "remember this as X" or "remember this is X"
    if (text.contains('remember')) {
      final match = RegExp(r'remember.*(?:this as|this is) (.+)', caseSensitive: false)
          .firstMatch(text);
      if (match != null) {
        final label = match.group(1)!.trim();
        return VoiceCommand.save(transcription, label);
      }
    }

    // Pattern 2: "where is X" or "where are my X"
    if (text.contains('where is') || text.contains('where are')) {
      final match = RegExp(r'where (?:is|are)(?: my)? (.+)', caseSensitive: false)
          .firstMatch(text);
      if (match != null) {
        final label = match.group(1)!.trim();
        return VoiceCommand.find(transcription, label);
      }
    }

    // Pattern 3: "what is this" / "what's this"
    if (text.contains('what is') ||
        text.contains('what\'s this') ||
        text.contains('whats this')) {
      return VoiceCommand.recall(transcription);
    }

    // Pattern 4: Question (ends with ?)
    if (text.endsWith('?')) {
      return VoiceCommand.question(transcription);
    }

    // Default: general analysis
    return VoiceCommand.analyze(transcription);
  }

  /// Check if text is a memory save command
  bool isSaveCommand(String text) {
    return text.toLowerCase().contains('remember');
  }

  /// Check if text is a recall command
  bool isRecallCommand(String text) {
    final lower = text.toLowerCase();
    return lower.contains('what is') ||
        lower.contains('what\'s this') ||
        lower.contains('whats this');
  }

  /// Check if text is a question
  bool isQuestion(String text) {
    return text.trim().endsWith('?');
  }
}
