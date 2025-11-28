import 'dart:io';
import 'dart:ui' as ui;
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/vision_service.dart';
import '../services/memory_service.dart';
import '../services/voice_service.dart';
import '../services/conversation_service.dart';
import '../services/command_parser.dart';
import '../models/command.dart';
import '../models/memory.dart';
import '../theme/colors.dart';
import '../theme/typography.dart';
import 'settings_screen.dart';
import 'notes_screen.dart';
import 'ar_spatial_screen.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;

  // Services
  final _visionService = VisionService();
  final _memoryService = MemoryService();
  final _voiceService = VoiceService();
  final _conversationService = ConversationService();
  final _commandParser = CommandParser();

  // State
  String _statusText = 'Ready';
  bool _isProcessing = false;
  bool _isListening = false;
  Memory? _matchedMemory;
  String? _currentImagePath;
  final _memoryLabelController = TextEditingController();
  late AnimationController _meshController;

  // PageView controller for swipeable modes
  late PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _initializeCamera();
    _initDemo();
    _meshController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();

    // Start VAD since we're starting on Page 0 (HUD mode)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_currentPage == 0) {
        print('🎯 App started in HUD Mode - Starting always-listening VAD');
        _startContinuousVAD();
      }
    });
  }

  Future<void> _initDemo() async {
    await Future.delayed(const Duration(seconds: 1));
    // Silent initialization - no voice prompt
  }

  @override
  void dispose() {
    _pageController.dispose();
    _memoryLabelController.dispose();
    _cameraController?.dispose();
    _voiceService.dispose();
    _meshController.dispose();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        _cameraController = CameraController(
          _cameras!.first,
          ResolutionPreset.medium,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.jpeg,
        );
        await _cameraController!.initialize();
        if (mounted) setState(() {});
      }
    } catch (e) {
      print('Error initializing camera: $e');
    }
  }

  // Seamless frame capture (SILENT - no shutter sound!)
  Future<String> _captureImage() async {
    try {
      // Use takePicture() which is fast and grabs current frame
      // Note: On iOS, this may make a shutter sound due to privacy laws
      // The sound is required in some regions (Japan, Korea) and cannot be disabled
      final XFile image = await _cameraController!.takePicture();

      final directory = await getTemporaryDirectory();
      final imagePath = '${directory.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(image.path).copy(imagePath);

      // Clean up the original temp file
      try {
        await File(image.path).delete();
      } catch (e) {
        // Ignore cleanup errors
      }

      return imagePath;
    } catch (e) {
      print('Error capturing frame: $e');
      rethrow;
    }
  }

  Future<void> _handleVoiceTap() async {
    if (_isListening || _isProcessing) return;

    setState(() {
      _isListening = true;
      _statusText = 'Listening...';
    });

    try {
      final recognizedText = await _voiceService.listen();

      if (recognizedText == null || recognizedText.isEmpty) {
        setState(() {
          _isListening = false;
          _statusText = 'No speech detected';
        });
        return;
      }

      setState(() {
        _isListening = false;
        _isProcessing = true;
        _statusText = 'Processing...';
      });

      final command = _commandParser.parse(recognizedText);
      await _executeVoiceCommand(command, recognizedText);

    } catch (e) {
      print('Voice error: $e');
      setState(() {
        _isListening = false;
        _statusText = 'Try again';
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  // Start continuous VAD for HUD mode (always-listening)
  Future<void> _startContinuousVAD() async {
    print('🎙️ Starting always-listening VAD in HUD mode');

    await _voiceService.listenContinuously(
      onListeningStart: () {
        if (mounted) {
          setState(() {
            _isListening = true;
            _statusText = 'Listening...';
          });
        }
      },
      onListeningStop: () {
        if (mounted) {
          setState(() {
            _isListening = false;
          });
        }
      },
      onResult: (recognizedText) async {
        // Process voice command with buffered frame
        if (mounted && recognizedText.isNotEmpty) {
          setState(() {
            _isProcessing = true;
            _statusText = 'Processing...';
          });

          final command = _commandParser.parse(recognizedText);
          await _executeVoiceCommand(command, recognizedText);

          // Reset processing state (VoiceService will auto-restart listening)
          if (mounted) {
            setState(() {
              _isProcessing = false;
              _statusText = 'Ready';
            });
          }
        }
      },
    );
  }

  // Stop continuous VAD
  Future<void> _stopContinuousVAD() async {
    print('🛑 Stopping continuous VAD');
    await _voiceService.stopListening();

    if (mounted) {
      setState(() {
        _isListening = false;
        _statusText = 'Ready';
      });
    }
  }

  Future<void> _executeVoiceCommand(VoiceCommand command, String originalText) async {
    // Capture frame when user speaks (on-demand)
    print('📸 Capturing frame for voice command...');
    final imagePath = await _captureImage();

    switch (command.type) {
      case CommandType.save:
        if (command.extractedLabel != null && command.extractedLabel!.isNotEmpty) {
          await _handleSaveMemory(imagePath, command.extractedLabel!);
        } else {
          await _voiceService.speak('What should I call this?');
        }
        break;

      case CommandType.find:
        // Handle "where is..." queries
        if (command.extractedLabel != null && command.extractedLabel!.isNotEmpty) {
          await _handleFindMemory(command.extractedLabel!);
        } else {
          await _voiceService.speak('What are you looking for?');
        }
        break;

      case CommandType.recall:
        await _handleRecallMemory(imagePath);
        break;

      case CommandType.analyze:
        final description = await _visionService.analyzeImage(imagePath);
        setState(() => _statusText = description);
        await _voiceService.speak("I see $description");
        break;

      case CommandType.question:
        final visionDescription = await _visionService.analyzeImage(imagePath);
        final response = await _conversationService.respond(
          originalText,
          memoryContext: _matchedMemory,
          currentVisionDescription: visionDescription,
        );
        await _voiceService.speak(response);
        setState(() => _statusText = response);
        break;
    }
  }

  Future<void> _handleSaveMemory(String imagePath, String label) async {
    await _memoryService.saveMemory(imagePath: imagePath, userLabel: label);
    await _voiceService.speak('Saved as $label');
    setState(() => _statusText = 'Saved: $label');
  }

  Future<void> _handleFindMemory(String searchTerm) async {
    final response = "Searching for $searchTerm... This feature is coming soon!";
    await _voiceService.speak(response);
    setState(() => _statusText = response);
  }

  Future<void> _handleRecallMemory(String imagePath) async{
    final memories = await _memoryService.recallMemory(imagePath);

    if (memories.isNotEmpty) {
      final memory = memories.first;
      setState(() {
        _matchedMemory = memory;
        _statusText = 'Found: ${memory.userLabel}';
      });

      await _voiceService.speak(
        'This is your ${memory.userLabel}. You saved this ${_getTimeAgo(memory.timestamp)}.',
      );
    } else {
      await _voiceService.speak('I don\'t recognize this.');
      setState(() => _statusText = 'No memory found');
    }
  }

  String _getTimeAgo(DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'just now';
  }

  // ===== LIQUID GLASS HELPER =====
  Widget _buildLiquidGlassCard({
    required Widget child,
    EdgeInsets? padding,
    double? width,
    double? height,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12), // Reduced blur for more transparency
        child: Container(
          width: width,
          height: height,
          padding: padding ?? const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.15), // Almost fully transparent dark tint
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withOpacity(0.15), // Subtle border
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05), // Minimal shadow
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  // Build suggestion pill (tappable quick action)
  Widget _buildSuggestionPill(String text, IconData icon) {
    return GestureDetector(
      onTap: () async {
        // Simulate the user saying the suggestion
        print('💡 Suggestion pill tapped: "$text"');

        setState(() {
          _isProcessing = true;
          _statusText = 'Processing...';
        });

        try {
          final command = _commandParser.parse(text);
          print('💡 Parsed command type: ${command.type}');
          await _executeVoiceCommand(command, text);
          print('💡 Command execution completed');
        } catch (e) {
          print('❌ Error executing suggestion pill: $e');
        }

        if (mounted) {
          setState(() {
            _isProcessing = false;
            _statusText = 'Ready';
          });
        }
      },
      child: _buildLiquidGlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: Colors.white.withOpacity(0.8),
              size: 14,
            ),
            const SizedBox(width: 6),
            Text(
              text,
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProcessingMeshOverlay() {
    return IgnorePointer(
      child: SizedBox.expand(
        child: AnimatedBuilder(
          animation: _meshController,
          builder: (context, _) {
            return CustomPaint(
              painter: _SpatialMeshPainter(progress: _meshController.value),
            );
          },
        ),
      ),
    );
  }

  // ===== PAGE 1: HUD MODE =====
  Widget _buildHUDPage() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Camera preview
        CameraPreview(_cameraController!),

        if (_isProcessing)
          Positioned.fill(
            child: _buildProcessingMeshOverlay(),
          ),

        // TOP-LEFT: Camera off/cancel button
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          left: 16,
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: _buildLiquidGlassCard(
              padding: const EdgeInsets.all(10),
              width: 44,
              height: 44,
              child: Icon(
                Icons.videocam_off,
                color: Colors.white.withOpacity(0.9),
                size: 22,
              ),
            ),
          ),
        ),

        // TOP-RIGHT: VAD Status Indicator (Always visible in HUD mode)
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          right: 16,
          child: _buildLiquidGlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Animated pulsing dot
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: _isListening ? 8 : 6,
                  height: _isListening ? 8 : 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isListening
                        ? Colors.greenAccent
                        : _isProcessing
                            ? Colors.orangeAccent
                            : Colors.white.withOpacity(0.4), // Subtle when idle
                    boxShadow: _isListening
                        ? [
                            BoxShadow(
                              color: Colors.greenAccent.withOpacity(0.6),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ]
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _isListening
                      ? 'Listening'
                      : _isProcessing
                          ? 'Processing'
                          : 'VAD Ready', // Show "VAD Ready" when idle in always-listening mode
                  style: TextStyle(
                    color: Colors.white.withOpacity(_isListening ? 0.95 : 0.7),
                    fontSize: 11,
                    fontWeight: _isListening ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),

        // BOTTOM-LEFT: Memory match
        if (_matchedMemory != null)
          Positioned(
            bottom: 90,
            left: 16,
            child: _buildLiquidGlassCard(
              padding: const EdgeInsets.all(16),
              width: 200,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.greenAccent.withOpacity(0.2),
                    ),
                    child: const Icon(Icons.check, color: Colors.greenAccent, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _matchedMemory!.userLabel,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _getTimeAgo(_matchedMemory!.timestamp),
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.white.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

        // BOTTOM BAR: Pills + Mic on same line (only show when not listening/processing)
        if (!_isListening && !_isProcessing)
          Positioned(
            bottom: 90,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Left side: Suggestion Pills
                Row(
                  children: [
                    _buildSuggestionPill('What do you see?', Icons.visibility_outlined),
                    const SizedBox(width: 8),
                    _buildSuggestionPill('Remember this', Icons.bookmark_add_outlined),
                  ],
                ),
                // Right side: Mic button
                GestureDetector(
                  onTap: _handleVoiceTap,
                  child: _buildLiquidGlassCard(
                    padding: EdgeInsets.zero,
                    width: 56,
                    height: 56,
                    child: Center(
                      child: Icon(
                        Icons.mic_none_outlined,
                        color: Colors.white.withOpacity(0.9),
                        size: 26,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ===== PAGE 2: VOICE-ONLY MODE =====
  Widget _buildVoiceOnlyPage() {
    return Container(
      color: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            // Top bar with title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 40),
                  Text(
                    'Integrations',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Colors.black.withOpacity(0.85),
                      letterSpacing: -0.4,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const SettingsScreen()),
                      );
                    },
                    child: Icon(
                      Icons.settings_outlined,
                      size: 24,
                      color: Colors.black.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),

            const Spacer(),

            // Gmail icon
            Container(
              width: 280,
              height: 280,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Image.asset(
                  'assets/images/gmail.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),

            const SizedBox(height: 40),

            // Status text
            if (_isListening)
              Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF34c759),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Listening',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: Colors.black.withOpacity(0.6),
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Waveform when listening
                  Image.asset(
                    'assets/images/waveform.gif',
                    width: 200,
                    height: 60,
                    color: Colors.black.withOpacity(0.3),
                    colorBlendMode: BlendMode.modulate,
                  ),
                ],
              )
            else if (_isProcessing)
              Text(
                'Processing...',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  color: Colors.black.withOpacity(0.6),
                  letterSpacing: -0.2,
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  'Connect your apps and services to enhance your spatial memories',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    color: Colors.black.withOpacity(0.6),
                    letterSpacing: -0.2,
                  ),
                ),
              ),

            const Spacer(),

            // Memory match indicator (if exists, show above button)
            if (_matchedMemory != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFf5f5f7),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle, color: Color(0xFF34c759), size: 20),
                      const SizedBox(width: 10),
                      Text(
                        _matchedMemory!.userLabel,
                        style: TextStyle(
                          color: Colors.black.withOpacity(0.85),
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Notes button (circular, AR mic style)
            Padding(
              padding: const EdgeInsets.only(bottom: 60),
              child: GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const NotesScreen()),
                  );
                },
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(
                      color: Colors.black.withOpacity(0.1),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      Icons.sticky_note_2_outlined,
                      size: 32,
                      color: Colors.black.withOpacity(0.8),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== PAGE 3: SMART GLASSES MODE =====
  Widget _buildSmartGlassesPage() {
    return Container(
      color: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            // Top bar with title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 40),
                  Text(
                    'Smart Glasses',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Colors.black.withOpacity(0.85),
                      letterSpacing: -0.4,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const SettingsScreen()),
                      );
                    },
                    child: Icon(
                      Icons.settings_outlined,
                      size: 24,
                      color: Colors.black.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),

            const Spacer(),

            // Smart glasses icon
            Image.asset(
              'assets/images/smart_glasses_icon.png',
              width: 280,
              height: 280,
              fit: BoxFit.contain,
            ),

            const SizedBox(height: 40),

            // Status text
            if (_isListening)
              Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF34c759),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Listening',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: Colors.black.withOpacity(0.6),
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Waveform when listening
                  Image.asset(
                    'assets/images/waveform.gif',
                    width: 200,
                    height: 60,
                    color: Colors.black.withOpacity(0.3),
                    colorBlendMode: BlendMode.modulate,
                  ),
                ],
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  'Pair your smart glasses for hands-free AR experiences',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    color: Colors.black.withOpacity(0.6),
                    letterSpacing: -0.2,
                  ),
                ),
              ),

            const Spacer(),

            // Memory match indicator (ABOVE button)
            if (_matchedMemory != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFf5f5f7),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle, color: Color(0xFF34c759), size: 20),
                      const SizedBox(width: 10),
                      Text(
                        _matchedMemory!.userLabel,
                        style: TextStyle(
                          color: Colors.black.withOpacity(0.85),
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Coming Soon button (circular bluetooth style)
            Padding(
              padding: const EdgeInsets.only(bottom: 60),
              child: GestureDetector(
                onTap: _showComingSoonModal,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(
                      color: Colors.black.withOpacity(0.1),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      Icons.bluetooth,
                      size: 32,
                      color: Colors.black.withOpacity(0.8),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Conversation mode handler (no picture taking)
  Future<void> _handleConversationTap() async {
    if (_isListening || _isProcessing) return;

    setState(() {
      _isListening = true;
      _statusText = 'Listening...';
    });

    try {
      final recognizedText = await _voiceService.listen();

      if (recognizedText == null || recognizedText.isEmpty) {
        setState(() {
          _isListening = false;
          _statusText = 'No speech detected';
        });
        return;
      }

      setState(() {
        _isListening = false;
        _isProcessing = true;
        _statusText = 'Processing...';
      });

      // Just have a conversation - no vision, no pictures
      final response = await _conversationService.respond(recognizedText);
      await _voiceService.speak(response);

    } catch (e) {
      print('Conversation error: $e');
      setState(() {
        _isListening = false;
        _statusText = 'Try again';
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  // ===== PAGE 4: CONVERSATION MODE =====
  Widget _buildConversationPage() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFFF8F9FA),
            const Color(0xFFE9ECEF),
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Top bar with glassmorphic design
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const SizedBox(width: 24),
                        Text(
                          'Conversation',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: Colors.black.withOpacity(0.85),
                            letterSpacing: -0.4,
                          ),
                        ),
                        Icon(
                          Icons.settings_outlined,
                          size: 22,
                          color: Colors.black.withOpacity(0.6),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            const Spacer(),

            // AI Conversation Animation with glassmorphic container
            ClipRRect(
              borderRadius: BorderRadius.circular(200),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  width: 340,
                  height: 340,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.5),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.4),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Center(
                    child: _isListening
                      ? // Show animated AI conversation GIF when listening
                      ClipOval(
                        child: Container(
                          color: const Color(0xFFF8F9FA), // Match background to GIF
                          child: Image.asset(
                            'assets/images/ai_conversation.gif',
                            width: 300,
                            height: 300,
                            fit: BoxFit.cover,
                          ),
                        ),
                      )
                      : // Show gradient icon when idle
                      Container(
                        width: 280,
                        height: 280,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              const Color(0xFF667eea).withOpacity(0.15),
                              const Color(0xFF764ba2).withOpacity(0.15),
                            ],
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 100,
                            color: const Color(0xFF667eea).withOpacity(0.6),
                          ),
                        ),
                      ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 50),

            // Status text with glassmorphism
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: _isListening
                    ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF34c759),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Listening...',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: Colors.black.withOpacity(0.75),
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    )
                  : _isProcessing
                    ? Text(
                      'Processing...',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Colors.black.withOpacity(0.75),
                        letterSpacing: -0.2,
                      ),
                    )
                    : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Your AI Assistant',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: Colors.black.withOpacity(0.85),
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Ask me anything',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: Colors.black.withOpacity(0.5),
                            letterSpacing: -0.1,
                          ),
                        ),
                      ],
                    ),
                ),
              ),
            ),

            const Spacer(),

            // Glassmorphic conversation button
            Padding(
              padding: const EdgeInsets.only(bottom: 60),
              child: GestureDetector(
                onTap: _handleConversationTap,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 18),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            const Color(0xFF667eea).withOpacity(0.9),
                            const Color(0xFF764ba2).withOpacity(0.9),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.2),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF667eea).withOpacity(0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isListening ? Icons.stop_rounded : Icons.mic_rounded,
                            size: 24,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 14),
                          Text(
                            _isListening ? 'Stop' : 'Start Conversation',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Show Coming Soon modal
  void _showComingSoonModal() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.science_outlined,
                    size: 64,
                    color: Colors.black.withOpacity(0.7),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Coming Soon',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: Colors.black.withOpacity(0.9),
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Smart glasses integration is currently in development. Stay tuned!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      color: Colors.black.withOpacity(0.6),
                      height: 1.4,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 28),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.black.withOpacity(0.1),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        'Got it',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black.withOpacity(0.85),
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  // Get mode name based on current page
  String get _modeName {
    switch (_currentPage) {
      case 0:
        return 'HUD Mode';
      case 1:
        return 'Voice Mode';
      case 2:
        return 'Smart Glasses';
      case 3:
        return 'Conversation';
      default:
        return 'HUD Mode';
    }
  }

  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _currentPage == 0 ? Colors.black : Colors.white,
      body: Stack(
        children: [
          // PageView for swipeable modes
          PageView(
            controller: _pageController,
            onPageChanged: (index) async {
              final wasInHUDMode = _currentPage == 0;
              final isNowInHUDMode = index == 0;

              setState(() => _currentPage = index);

              // Start VAD when entering HUD mode
              if (isNowInHUDMode && !wasInHUDMode) {
                print('🎯 Entering HUD Mode - Starting always-listening VAD');
                await _startContinuousVAD();
              }

              // Stop VAD when leaving HUD mode
              if (!isNowInHUDMode && wasInHUDMode) {
                print('🛑 Leaving HUD Mode - Stopping VAD');
                await _stopContinuousVAD();
              }
            },
            children: [
              // Page 0: AR Spatial Screen
              const ARSpatialScreen(),
              // Page 1: Integrations (Notes)
              _buildVoiceOnlyPage(),
              // Page 2: Smart Glasses Mode
              _buildSmartGlassesPage(),
            ],
          ),

          // Page indicators (animated dots)
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (index) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _currentPage == index ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: _currentPage == 0
                        ? Colors.white.withOpacity(_currentPage == index ? 0.9 : 0.3)
                        : Colors.black.withOpacity(_currentPage == index ? 0.8 : 0.2),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpatialMeshPainter extends CustomPainter {
  const _SpatialMeshPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final spacing = 70.0;
    final travel = progress * spacing * 2;

    final primaryLine = Paint()
      ..color = Colors.white.withOpacity(0.18)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    for (double i = -size.height; i < size.width; i += spacing) {
      final start = Offset(i + travel, 0);
      final end = Offset(i + size.height + travel, size.height);
      canvas.drawLine(start, end, primaryLine);
    }

    final secondaryLine = Paint()
      ..color = Colors.white.withOpacity(0.12)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    for (double i = -size.height; i < size.width; i += spacing) {
      final start = Offset(size.width - (i + travel), 0);
      final end = Offset(size.width - (i + size.height + travel), size.height);
      canvas.drawLine(start, end, secondaryLine);
    }

    final nodePaint = Paint();
    for (double x = -spacing; x <= size.width + spacing; x += spacing) {
      for (double y = -spacing; y <= size.height + spacing; y += spacing) {
        final wave = math.sin((x + y) / spacing + progress * math.pi * 2);
        final radius = 1.2 + (wave + 1) * 0.6;
        final opacity = 0.06 + (wave + 1) * 0.08;
        final pos = Offset(x + travel, y - travel);
        nodePaint.color = Colors.white.withOpacity(opacity.clamp(0.05, 0.2));
        canvas.drawCircle(pos, radius, nodePaint);
      }
    }

    final waveCenter = Offset(
      size.width * 0.5 + math.sin(progress * math.pi * 2) * size.width * 0.2,
      size.height * 0.5 + math.cos(progress * math.pi * 2) * size.height * 0.15,
    );

    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withOpacity(0.16),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(center: waveCenter, radius: size.shortestSide * 0.8),
      );
    canvas.drawRect(Offset.zero & size, glowPaint);

    final sweepPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withOpacity(0.12),
          Colors.transparent,
        ],
      ).createShader(Offset.zero & size);

    canvas.drawRect(Offset.zero & size, sweepPaint);
  }

  @override
  bool shouldRepaint(covariant _SpatialMeshPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
