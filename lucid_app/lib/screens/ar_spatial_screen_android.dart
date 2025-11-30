import 'dart:ui' as ui;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ar_flutter_plugin_plus/ar_flutter_plugin_plus.dart';
import 'package:ar_flutter_plugin_plus/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin_plus/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_plus/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin_plus/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin_plus/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin_plus/models/ar_node.dart';
import 'package:ar_flutter_plugin_plus/models/ar_hittest_result.dart';
import 'package:ar_flutter_plugin_plus/models/ar_anchor.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import 'package:cactus/cactus.dart';
import '../models/spatial_memory.dart';
import '../services/spatial_memory_service.dart';
import '../services/model_manager.dart';
import '../services/voice_service.dart';
import '../services/face_recognition_service.dart';
import 'settings_screen.dart';

/// AR Spatial Screen for Android using ar_flutter_plugin_plus (ARCore)
/// Mirrors iOS functionality: tap to place markers, voice to find them
/// Uses Cactus embeddings for semantic search & persistence
class ARSpatialScreenAndroid extends StatefulWidget {
  const ARSpatialScreenAndroid({super.key});

  @override
  State<ARSpatialScreenAndroid> createState() => _ARSpatialScreenAndroidState();
}

class _ARSpatialScreenAndroidState extends State<ARSpatialScreenAndroid> {
  ARSessionManager? _arSessionManager;
  ARObjectManager? _arObjectManager;
  ARAnchorManager? _arAnchorManager;
  ARLocationManager? _arLocationManager;
  final Map<String, ARNode> _nodes = {};
  final Map<String, ARAnchor> _anchors = {};

  // Track markers for visualization
  final List<Map<String, dynamic>> _visibleMarkers = [];

  late SpatialMemoryService? _spatialService;
  late VoiceService? _voiceService;
  late FaceRecognitionService? _faceService;
  late ModelManager? _modelManager;
  bool _isListening = false;
  bool _isLoading = true;
  bool _isProcessing = false;

  final TextEditingController _queryController = TextEditingController();
  String _aiResponse = '';
  String _contextSummary = '';
  bool _isLoadingContext = false;
  String _currentSearchTerm = '';
  bool _isDetectingFaces = false;
  bool _isSummarizingPerson = false;
  final Map<String, Map<String, dynamic>> _recognizedFaces = {};

  // Coaching overlay timeout
  bool _showCoachingOverlay = true;

  @override
  void initState() {
    super.initState();
    _initServices();

    // Hide coaching overlay after 8 seconds
    Future.delayed(const Duration(seconds: 8), () {
      if (mounted) {
        setState(() => _showCoachingOverlay = false);
      }
    });
  }

  Future<void> _initServices() async {
    // Start AR immediately - defer AI models to avoid freezing!
    setState(() => _isLoading = false);

    // Initialize AI models in background AFTER AR is running
    Future.delayed(const Duration(seconds: 3), () async {
      if (!mounted) return;

      print('🔄 Starting background AI initialization...');

      final modelManager = ModelManager();
      await modelManager.initialize();
      _modelManager = modelManager;

      final voiceService = VoiceService();
      await voiceService.ensureInitialized();
      _voiceService = voiceService;

      _spatialService = SpatialMemoryService(modelManager, modelManager.rag);
      _faceService = FaceRecognitionService(modelManager, modelManager.rag);

      // Load existing memories after models are ready
      await _loadExistingMemories();

      print('✅ Background AI initialization complete');
    });
  }

  List<SpatialMemory> _pendingMemories = [];

  Future<void> _loadExistingMemories() async {
    if (_spatialService == null) return;
    final memories = await _spatialService!.getAllMemories();
    _pendingMemories = memories;
    print(
      '📍 Found ${memories.length} spatial memories (will display when AR is ready)',
    );
  }

  void _onARViewCreated(
    ARSessionManager arSessionManager,
    ARObjectManager arObjectManager,
    ARAnchorManager arAnchorManager,
    ARLocationManager arLocationManager,
  ) {
    _arSessionManager = arSessionManager;
    _arObjectManager = arObjectManager;
    _arAnchorManager = arAnchorManager;
    _arLocationManager = arLocationManager;

    try {
      // Initialize AR session with OPTIMIZED settings for performance
      // Feature points and excessive plane rendering cause lag!
      _arSessionManager!.onInitialize(
        showFeaturePoints: false, // ❌ Disable - very expensive
        showPlanes: false, // ❌ Disable visual planes - causes freezing
        showWorldOrigin: false,
        handleTaps: true,
        handlePans: false,
        handleRotation: false,
      );
      _arObjectManager!.onInitialize();

      // Handle taps - user taps to place markers
      _arSessionManager!.onPlaneOrPointTap = (List<ARHitTestResult> hits) {
        if (hits.isNotEmpty && !_isListening) {
          _handleTap(hits.first);
        }
      };

      // Load pending memories after a delay
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (!mounted) return;
        for (final memory in _pendingMemories) {
          _createARMarker(memory.label, memory.position);
        }
        if (_pendingMemories.isNotEmpty) {
          print('✅ Displayed ${_pendingMemories.length} AR markers on Android');
        }
      });
    } catch (e) {
      print('❌ Error initializing AR session: $e');
    }
  }

  void _handleTap(ARHitTestResult hit) {
    // Get 3D position from tap
    final pos = hit.worldTransform.getTranslation();
    // Show dialog to name it
    _showNameDialog(pos);
  }

  void _showNameDialog(vm.Vector3 position) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.3),
      builder: (context) => BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Dialog(
          backgroundColor: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withOpacity(0.25),
                      Colors.white.withOpacity(0.15),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.4),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 40,
                      spreadRadius: -5,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Icon
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF0A84FF), Color(0xFF0066CC)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0A84FF).withOpacity(0.3),
                            blurRadius: 15,
                            spreadRadius: 0,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Title
                    const Text(
                      'Name this spot',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Input field
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.2),
                          width: 1,
                        ),
                      ),
                      child: TextField(
                        controller: controller,
                        autofocus: true,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          hintText: 'e.g., keys, laptop',
                          hintStyle: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 17,
                            fontWeight: FontWeight.w400,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Buttons
                    Row(
                      children: [
                        // Cancel button
                        Expanded(
                          child: GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.2),
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                'Cancel',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.9),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Save button
                        Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              if (controller.text.isNotEmpty) {
                                await _saveMarker(controller.text, position);
                              }
                              Navigator.pop(context);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF0A84FF),
                                    Color(0xFF0066CC),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(
                                      0xFF0A84FF,
                                    ).withOpacity(0.3),
                                    blurRadius: 15,
                                    spreadRadius: 0,
                                  ),
                                ],
                              ),
                              child: const Text(
                                'Save',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveMarker(String label, vm.Vector3 position) async {
    // Create AR marker
    await _createARMarker(label, position);

    // Save to Cactus with embeddings (if service is ready)
    if (_spatialService != null) {
      final memory = SpatialMemory(
        label: label.toLowerCase(),
        anchorId: 'marker_${DateTime.now().millisecondsSinceEpoch}',
        position: position,
        timestamp: DateTime.now(),
      );

      await _spatialService!.saveMemory(memory);
    }

    // Premium styled snackbar
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.check_circle,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Saved: $label',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF0A84FF).withOpacity(0.9),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    setState(() {});
  }

  Future<void> _createARMarker(String label, vm.Vector3 position) async {
    final anchorId = 'marker_${DateTime.now().millisecondsSinceEpoch}';

    try {
      // Create an anchor at the tap position
      final anchor = ARPlaneAnchor(
        transformation: vm.Matrix4.identity()..setTranslation(position),
      );

      final didAddAnchor = await _arAnchorManager?.addAnchor(anchor);

      if (didAddAnchor == true) {
        _anchors[anchorId] = anchor;

        // Create text label as AR object with green background
        // Note: ar_flutter_plugin_plus has limited 3D object support
        // We'll use the plugin's basic capabilities
        print('✅ Created AR anchor for: $label at $position');
        print('   Anchor ID: $anchorId');

        // Store for future retrieval
        setState(() {
          _visibleMarkers.add({
            'label': label,
            'anchorId': anchorId,
            'position': position,
          });
        });
      }
    } catch (e) {
      print('❌ Error creating AR marker: $e');
    }
  }

  // Create HTML widget for 3D text label
  String _createTextWidget(String label) {
    return '''
      <div style="
        background: linear-gradient(135deg, rgba(34, 197, 94, 0.9), rgba(22, 163, 74, 0.9));
        color: white;
        padding: 12px 20px;
        border-radius: 16px;
        font-family: -apple-system, sans-serif;
        font-size: 24px;
        font-weight: 700;
        text-align: center;
        box-shadow: 0 8px 24px rgba(0, 0, 0, 0.4);
        border: 3px solid rgba(255, 255, 255, 0.5);
        min-width: 100px;
      ">
        📍 $label
      </div>
    ''';
  }

  // Build a single AR marker widget
  Widget _buildMarkerWidget(String label) {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.green.withOpacity(0.5),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Green sphere marker
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [Colors.green.shade300, Colors.green.shade600],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.green.withOpacity(0.6),
                  blurRadius: 15,
                  spreadRadius: 3,
                ),
              ],
            ),
            child: const Icon(Icons.location_on, color: Colors.white, size: 32),
          ),
          const SizedBox(height: 8),
          // Label
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.green.withOpacity(0.5),
                width: 1.5,
              ),
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Glassmorphism widget builder
  Widget _buildGlassMorphism({
    required Widget child,
    double blur = 20,
    double opacity = 0.15,
    Color? tint,
    EdgeInsets? padding,
    BorderRadius? borderRadius,
  }) {
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding ?? const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: (tint ?? Colors.white).withOpacity(opacity),
            borderRadius: borderRadius ?? BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 30,
                spreadRadius: -5,
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Future<void> _handleTextQuery() async {
    if (_queryController.text.isEmpty || _spatialService == null) return;

    final query = _queryController.text.toLowerCase();
    _queryController.clear();

    setState(() => _isProcessing = true);

    try {
      final result = await _spatialService!.findMemory(query);

      if (result != null) {
        setState(() {
          _aiResponse = 'Found: ${result.label}';
          _isProcessing = false;
        });
      } else {
        setState(() {
          _aiResponse = 'No matches found';
          _isProcessing = false;
        });
      }
    } catch (e) {
      print('Error searching: $e');
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleVoiceCommand() async {
    if (_voiceService == null) {
      print('Voice service not ready yet');
      return;
    }

    if (_isListening) {
      // Already listening - ignore
      return;
    }

    // Start listening
    setState(() => _isListening = true);

    try {
      final result = await _voiceService!.listen();

      setState(() => _isListening = false);

      if (result != null && result.isNotEmpty) {
        _queryController.text = result;
        await _handleTextQuery();
      }
    } catch (e) {
      print('Error with voice: $e');
      setState(() => _isListening = false);
    }
  }

  @override
  void dispose() {
    _arSessionManager?.dispose();
    _voiceService?.dispose();
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Color(0xFF0A84FF)),
              const SizedBox(height: 20),
              Text(
                'Starting AR...',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: buildGlassAppBar(),
      body: Stack(
        children: [
          // AR View - ARCore for Android
          ARView(
            onARViewCreated: _onARViewCreated,
            planeDetectionConfig: PlaneDetectionConfig.horizontalAndVertical,
          ),

          // Gradient overlay
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.1),
                      Colors.transparent,
                      Colors.black.withOpacity(0.2),
                    ],
                    stops: const [0.0, 0.3, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // Instructions Banner - Top Center
          Positioned(
            top: MediaQuery.of(context).padding.top + 70,
            left: 24,
            right: 24,
            child: _buildGlassMorphism(
              blur: 20,
              opacity: 0.12,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              borderRadius: BorderRadius.circular(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.touch_app_outlined,
                    color: Colors.white.withOpacity(0.9),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Tap to tag',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.3,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Container(
                      width: 1,
                      height: 16,
                      color: Colors.white.withOpacity(0.3),
                    ),
                  ),
                  Icon(
                    Icons.mic_outlined,
                    color: Colors.white.withOpacity(0.9),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Voice to find',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Processing Indicator
          if (_isProcessing)
            Positioned(
              top: MediaQuery.of(context).size.height / 2 - 40,
              left: MediaQuery.of(context).size.width / 2 - 40,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF0A84FF).withOpacity(0.4),
                      const Color(0xFF0A84FF).withOpacity(0.1),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Center(
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF0A84FF).withOpacity(0.3),
                    ),
                    child: const Center(
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // AI Response Display
          if (_aiResponse.isNotEmpty)
            Positioned(
              top: MediaQuery.of(context).padding.top + 140,
              left: 24,
              right: 24,
              child: _buildGlassMorphism(
                blur: 30,
                opacity: 0.08,
                padding: const EdgeInsets.all(24),
                borderRadius: BorderRadius.circular(28),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _aiResponse = '';
                              _contextSummary = '';
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Icon(
                      Icons.location_on,
                      color: Colors.white.withOpacity(0.9),
                      size: 28,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _aiResponse,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),

          // Bottom Input Bar
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 24,
            left: 20,
            right: 20,
            child: _buildGlassMorphism(
              blur: 30,
              opacity: 0.15,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              borderRadius: BorderRadius.circular(28),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 52,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: TextField(
                        controller: _queryController,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Where is...',
                          hintStyle: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onSubmitted: (_) => _handleTextQuery(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Mic Button
                  GestureDetector(
                    onTap: _handleVoiceCommand,
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: _isListening
                              ? [
                                  const Color(0xFFFF375F),
                                  const Color(0xFFFF1744),
                                ]
                              : [
                                  const Color(0xFF0A84FF),
                                  const Color(0xFF0066CC),
                                ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                (_isListening
                                        ? const Color(0xFFFF375F)
                                        : const Color(0xFF0A84FF))
                                    .withOpacity(0.4),
                            blurRadius: 20,
                            spreadRadius: 0,
                          ),
                        ],
                      ),
                      child: Icon(
                        _isListening ? Icons.mic : Icons.mic_none_outlined,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),

          // Coaching Overlay Blocker - Hides ARCore hand animation after timeout
          if (_showCoachingOverlay)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.7),
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }

  AppBar buildGlassAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      toolbarHeight: 70,
      flexibleSpace: ClipRRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(0.15),
                  Colors.white.withOpacity(0.05),
                ],
              ),
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withOpacity(0.1),
                  width: 1,
                ),
              ),
            ),
          ),
        ),
      ),
      titleSpacing: 20,
      title: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF0A84FF).withOpacity(0.8),
                  const Color(0xFF0066CC).withOpacity(0.8),
                ],
              ),
            ),
            child: const Icon(Icons.view_in_ar, size: 20, color: Colors.white),
          ),
          const SizedBox(width: 12),
          const Text(
            'Spatial Memory',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
      actions: [
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            );
          },
          child: Container(
            margin: const EdgeInsets.only(right: 16),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.15),
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: const Icon(
              Icons.settings_outlined,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      ],
    );
  }
}
