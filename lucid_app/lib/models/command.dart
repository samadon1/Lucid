/// Types of voice commands
enum CommandType {
  save, // "remember this as..."
  find, // "where is..."
  recall, // "what is this"
  question, // any question about current view
  analyze, // general analysis
}

/// Parsed voice command
class VoiceCommand {
  final CommandType type;
  final String rawText;
  final String? extractedLabel; // for save commands

  VoiceCommand({
    required this.type,
    required this.rawText,
    this.extractedLabel,
  });

  factory VoiceCommand.save(String rawText, String label) => VoiceCommand(
        type: CommandType.save,
        rawText: rawText,
        extractedLabel: label,
      );

  factory VoiceCommand.find(String rawText, String label) => VoiceCommand(
        type: CommandType.find,
        rawText: rawText,
        extractedLabel: label,
      );

  factory VoiceCommand.recall(String rawText) => VoiceCommand(
        type: CommandType.recall,
        rawText: rawText,
      );

  factory VoiceCommand.question(String rawText) => VoiceCommand(
        type: CommandType.question,
        rawText: rawText,
      );

  factory VoiceCommand.analyze(String rawText) => VoiceCommand(
        type: CommandType.analyze,
        rawText: rawText,
      );
}
