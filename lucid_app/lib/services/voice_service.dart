import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Service for speech-to-text and text-to-speech
class VoiceService {
  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _isSpeaking = false;
  bool _isInitialized = false;
  bool _speechInitialized = false;
  bool _isAlwaysListening = false; // Flag for always-listening mode
  Future<void>? _initFuture;

  // Callbacks for always-listening mode
  Function(String)? _alwaysListeningOnResult;
  Function()? _alwaysListeningOnStart;
  Function()? _alwaysListeningOnStop;

  VoiceService() {
    _initFuture = _initializeTTS();
  }

  Future<void> _initializeTTS() async {
    if (_isInitialized) return;

    print('DEBUG TTS: Initializing TTS...');
    try {
      await _tts.setLanguage('en-US');

      // Try to use a better-sounding iOS voice
      // Options: "Samantha" (warm female), "Alex" (clear male), "Zoe" (expressive)
      try {
        await _tts.setVoice({"name": "Samantha", "locale": "en-US"});
      } catch (e) {
        print('Could not set custom voice, using default');
      }

      await _tts.setSpeechRate(0.55); // Natural conversational speed
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.05); // Slightly higher for friendliness

      // Set iOS-specific settings
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
        ],
        IosTextToSpeechAudioMode.voicePrompt,
      );

      _tts.setCompletionHandler(() {
        print('DEBUG TTS: Completion handler called');
        _isSpeaking = false;
      });

      _tts.setStartHandler(() {
        print('DEBUG TTS: Start handler called');
      });

      _tts.setErrorHandler((msg) {
        print('DEBUG TTS: Error handler called: $msg');
        _isSpeaking = false;
      });

      _isInitialized = true;
      print('DEBUG TTS: TTS initialized successfully');
    } catch (e) {
      print('DEBUG TTS: Error initializing TTS: $e');
    }
  }

  /// Ensure TTS is initialized before use
  Future<void> ensureInitialized() async {
    if (_initFuture != null) {
      await _initFuture;
    }
  }

  /// Initialize speech recognition
  Future<bool> _initializeSpeech() async {
    if (_speechInitialized) return true;

    try {
      _speechInitialized = await _speech.initialize(
        onError: (error) => print('Speech error: $error'),
        onStatus: (status) => print('Speech status: $status'),
      );
      return _speechInitialized;
    } catch (e) {
      print('Error initializing speech: $e');
      return false;
    }
  }

  /// Listen for voice command (non-blocking with Apple Speech Recognition)
  Future<String?> listen() async {
    try {
      // Initialize speech if needed
      if (!_speechInitialized) {
        final initialized = await _initializeSpeech();
        if (!initialized) {
          print('Speech recognition not available');
          return null;
        }
      }

      // Stop TTS if speaking
      if (_isSpeaking) {
        await _tts.stop();
        _isSpeaking = false;
        // Small delay to ensure TTS is fully stopped
        await Future.delayed(const Duration(milliseconds: 300));
      }

      String? recognizedText;
      final completer = Future<String?>(() async {
        await _speech.listen(
          onResult: (result) {
            if (result.finalResult) {
              recognizedText = result.recognizedWords;
            }
          },
          listenFor: const Duration(seconds: 5),
          pauseFor: const Duration(seconds: 3),
          partialResults: false,
          cancelOnError: true,
          listenMode: stt.ListenMode.confirmation,
        );

        // Wait for speech to complete
        await Future.delayed(const Duration(seconds: 6));
        await _speech.stop();

        return recognizedText;
      });

      return await completer;
    } catch (e) {
      print('Error listening: $e');
      return null;
    }
  }

  /// Start continuous listening with VAD (Voice Activity Detection)
  /// This creates an "always listening" mode that automatically restarts after each command
  Future<void> listenContinuously({
    required Function(String) onResult,
    required Function() onListeningStart,
    required Function() onListeningStop,
  }) async {
    try {
      // Initialize speech if needed
      if (!_speechInitialized) {
        final initialized = await _initializeSpeech();
        if (!initialized) {
          print('Speech recognition not available');
          return;
        }
      }

      // Store callbacks for always-listening mode
      _isAlwaysListening = true;
      _alwaysListeningOnResult = onResult;
      _alwaysListeningOnStart = onListeningStart;
      _alwaysListeningOnStop = onListeningStop;

      // Start the listening loop
      await _startListeningCycle();
    } catch (e) {
      print('Error in continuous listening: $e');
    }
  }

  /// Internal method to start a single listening cycle
  Future<void> _startListeningCycle() async {
    if (!_isAlwaysListening) return;

    try {
      // Stop TTS if speaking
      if (_isSpeaking) {
        await _tts.stop();
        _isSpeaking = false;
        await Future.delayed(const Duration(milliseconds: 300));
      }

      print('🎙️ Starting listening cycle...');

      // Start listening
      await _speech.listen(
        onResult: (result) async {
          if (result.finalResult && result.recognizedWords.isNotEmpty) {
            print('🎤 Got final result: ${result.recognizedWords}');

            // Call the stop callback
            _alwaysListeningOnStop?.call();

            // Call the result callback
            _alwaysListeningOnResult?.call(result.recognizedWords);

            // Wait a bit for processing to complete, then restart if still in always-listening mode
            await Future.delayed(const Duration(milliseconds: 500));

            // Automatically restart listening after processing (if still in always-listening mode)
            if (_isAlwaysListening) {
              print('🔄 Restarting listening cycle...');
              await _startListeningCycle();
            }
          }
        },
        onSoundLevelChange: (level) {
          // When sound is detected, notify UI
          if (level > -10) {
            _alwaysListeningOnStart?.call();
          }
        },
        listenFor: const Duration(seconds: 30), // Max listening time
        pauseFor: const Duration(seconds: 2), // 2 seconds of silence = done
        partialResults: true, // Get partial results as user speaks
        cancelOnError: false, // Don't cancel on errors, keep listening
        listenMode: stt.ListenMode.confirmation, // Wait for pause
      );
    } catch (e) {
      print('Error in listening cycle: $e');

      // Retry after a short delay if still in always-listening mode
      if (_isAlwaysListening) {
        await Future.delayed(const Duration(seconds: 1));
        await _startListeningCycle();
      }
    }
  }

  /// Stop continuous listening
  Future<void> stopListening() async {
    try {
      // Disable always-listening mode
      _isAlwaysListening = false;
      _alwaysListeningOnResult = null;
      _alwaysListeningOnStart = null;
      _alwaysListeningOnStop = null;

      // Stop the speech recognition
      if (_speech.isListening) {
        await _speech.stop();
      }

      print('🛑 Always-listening mode stopped');
    } catch (e) {
      print('Error stopping listening: $e');
    }
  }

  /// Check if currently listening
  bool get isListening => _speech.isListening;

  /// Speak text
  Future<void> speak(String text) async {
    try {
      print('DEBUG TTS: speak() called with text: "$text"');

      // Ensure TTS is initialized first
      await ensureInitialized();
      print('DEBUG TTS: TTS initialization check complete, isInitialized: $_isInitialized');

      if (_isSpeaking) {
        print('DEBUG TTS: Already speaking, stopping previous...');
        await _tts.stop();
      }

      _isSpeaking = true;
      print('DEBUG TTS: Calling _tts.speak()...');
      final result = await _tts.speak(text);
      print('DEBUG TTS: _tts.speak() returned: $result');
    } catch (e) {
      print('DEBUG TTS: Error speaking: $e');
      print('DEBUG TTS: Stack trace: ${StackTrace.current}');
      _isSpeaking = false;
    }
  }

  /// Stop speaking
  Future<void> stopSpeaking() async {
    if (_isSpeaking) {
      await _tts.stop();
      _isSpeaking = false;
    }
  }

  /// Check if currently speaking
  bool get isSpeaking => _isSpeaking;

  /// Check if voice service is ready
  bool get isReady => _isInitialized && _speechInitialized;

  /// Stop recording
  void stopRecording() {
    _speech.stop();
  }

  void dispose() {
    _tts.stop();
    _speech.stop();
  }
}
