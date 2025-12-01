import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import 'package:ar_flutter_plugin_plus/ar_flutter_plugin_plus.dart';
import 'package:ar_flutter_plugin_plus/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin_plus/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_plus/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin_plus/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin_plus/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin_plus/datatypes/node_types.dart';
import 'package:ar_flutter_plugin_plus/models/ar_node.dart';
import 'package:ar_flutter_plugin_plus/models/ar_hittest_result.dart';
import 'package:ar_flutter_plugin_plus/models/ar_anchor.dart';
import '../services/spatial_memory_service.dart';
import '../services/voice_service.dart';
import '../services/face_recognition_service.dart';
import '../services/model_manager.dart';
import '../models/spatial_memory.dart';
import 'settings_screen.dart';

/// Android AR spatial memory screen using ar_flutter_plugin_plus
/// Loads 3D GLTF sphere + 2D text overlays for markers
class ARSpatialScreenAndroid extends StatefulWidget {
  const ARSpatialScreenAndroid({super.key});

  @override
  State<ARSpatialScreenAndroid> createState() => _ARSpatialScreenAndroidState();
}

class _ARSpatialScreenAndroidState extends State<ARSpatialScreenAndroid> {
  ARSessionManager? _arSessionManager;
  ARObjectManager? _arObjectManager;
  ARAnchorManager? _arAnchorManager;

  // Services (deferred)
  late SpatialMemoryService? _spatialService;
  late VoiceService? _voiceService;
  late FaceRecognitionService? _faceService;
  late ModelManager? _modelManager;

  // State
  bool _isLoading = true;
  bool _isListening = false;
  bool _isProcessing = false;
  String _aiResponse = '';
  final TextEditingController _queryController = TextEditingController();

  // Marker tracking for 2D text overlays
  final Map<String, Map<String, dynamic>> _markers = {};

  // Screen projection helper
  void _startTextPositionUpdates() {
    // Update text positions 30 times per second
    Stream.periodic(const Duration(milliseconds: 33)).listen((_) {
      if (mounted && _markers.isNotEmpty) {
        setState(() {
          // Trigger rebuild to update text positions
        });
      }
    });
  }

  Offset? _projectPositionToScreen(vm.Vector3 position) {
    if (!mounted) return null;

    // Simplified approach: stack labels vertically
    // More reliable than trying to project 3D without proper camera matrix
    final index = _markers.values.toList().indexWhere(
      (m) => (m['position'] as vm.Vector3) == position,
    );

    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    // Stack vertically with spacing
    final baseY = screenHeight * 0.25;
    final yOffset = baseY + (index * 70.0);

    return Offset(screenWidth / 2, yOffset);
  }

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
    // Start AR immediately
    setState(() => _isLoading = false);

    // Initialize AI models in background
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

      // Load existing memories and DEBUG LOG them
      final memories = await _spatialService!.getAllMemories();
      print('📍 ===== STORED MEMORIES IN CACTUS ===== ');
      print('📍 Total count: ${memories.length}');
      for (var i = 0; i < memories.length; i++) {
        final m = memories[i];
        print(
          '📍 [$i] ${m.label} at (${m.position.x.toStringAsFixed(2)}, ${m.position.y.toStringAsFixed(2)}, ${m.position.z.toStringAsFixed(2)})',
        );
      }
      print('📍 ===================================== ');

      print('✅ Background AI initialization complete');
    });
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

    try {
      // Initialize AR session with plane visualization
      _arSessionManager!.onInitialize(
        showFeaturePoints: false,
        showPlanes: true, // Enable to see detected planes (blue overlay)
        showWorldOrigin: false,
        handleTaps: true,
        handlePans: false,
        handleRotation: false,
      );
      _arObjectManager!.onInitialize();

      // Handle taps
      _arSessionManager!.onPlaneOrPointTap = (List<ARHitTestResult> hits) {
        if (hits.isNotEmpty && !_isListening) {
          _handleTap(hits.first);
        }
      };

      // Update text positions every frame
      _startTextPositionUpdates();

      print('✅ AR session initialized');
    } catch (e) {
      print('❌ Error initializing AR: $e');
    }
  }

  void _handleTap(ARHitTestResult hit) {
    final position = hit.worldTransform.getTranslation();
    _showNameDialog(position);
  }

  void _showNameDialog(vm.Vector3 position) {
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Name this location',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: nameController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'e.g., Keys, Phone, Bag...',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF00C853)),
            ),
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              Navigator.pop(context);
              _saveMarker(value.trim(), position);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.white.withOpacity(0.7)),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.trim().isNotEmpty) {
                Navigator.pop(context);
                _saveMarker(nameController.text.trim(), position);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00C853),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _saveMarker(String label, vm.Vector3 position) async {
    print('🔵 Saving marker: $label at $position');

    // Save to Cactus
    if (_spatialService != null) {
      final memory = SpatialMemory(
        label: label,
        anchorId: 'anchor_${DateTime.now().millisecondsSinceEpoch}',
        position: position,
        timestamp: DateTime.now(),
      );

      await _spatialService!.saveMemory(memory);
      print('💾 Saved to Cactus: $label');
      print(
        '   Position: (${position.x.toStringAsFixed(2)}, ${position.y.toStringAsFixed(2)}, ${position.z.toStringAsFixed(2)})',
      );
    } else {
      print('⚠️ Spatial service not ready - memory NOT saved!');
    }

    // Create 3D AR marker
    await _createARMarker(label, position);

    // Show confirmation
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Color(0xFF00C853)),
              const SizedBox(width: 12),
              Text('Saved: $label'),
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
  }

  Future<void> _createARMarker(String label, vm.Vector3 position) async {
    final anchorId = 'marker_${DateTime.now().millisecondsSinceEpoch}';

    try {
      // Create anchor
      final anchor = ARPlaneAnchor(
        transformation: vm.Matrix4.identity()..setTranslation(position),
      );

      final didAddAnchor = await _arAnchorManager?.addAnchor(anchor);

      if (didAddAnchor == true) {
        // Create 3D sphere node from GLB (binary GLTF)
        final node = ARNode(
          type: NodeType.localGLB,
          uri: 'assets/models/sphere-gltf-example.glb',
          scale: vm.Vector3(0.0008, 0.0008, 0.0008), // Extremely tiny
          position: position,
        );

        final didAddNode = await _arObjectManager?.addNode(
          node,
          planeAnchor: anchor,
        );

        if (didAddNode == true) {
          // Track marker for 2D text overlay
          setState(() {
            _markers[anchorId] = {
              'label': label,
              'position': position,
              'anchor': anchor,
              'node': node,
            };
          });

          print('✅ Created 3D AR marker: $label');
        }
      }
    } catch (e) {
      print('❌ Error creating AR marker: $e');
    }
  }

  Future<void> _handleVoiceCommand() async {
    if (_voiceService == null) return;
    if (_isListening) return;

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

  Future<void> _handleTextQuery() async {
    if (_queryController.text.isEmpty || _spatialService == null) {
      print('⚠️ Query empty or service not ready');
      return;
    }

    final query = _queryController.text.toLowerCase();
    print('🔍 Searching for: "$query"');
    _queryController.clear();

    setState(() => _isProcessing = true);

    try {
      final result = await _spatialService!.findMemory(query);
      print('📍 Search result: ${result?.label ?? "NULL"}');

      if (result != null) {
        setState(() {
          _aiResponse =
              'Found: ${result.label}\nAt position: ${result.position.x.toStringAsFixed(1)}, ${result.position.y.toStringAsFixed(1)}, ${result.position.z.toStringAsFixed(1)}';
          _isProcessing = false;
        });
      } else {
        setState(() {
          _aiResponse = 'No matches found for "$query"';
          _isProcessing = false;
        });
      }
    } catch (e) {
      print('❌ Error searching: $e');
      setState(() {
        _aiResponse = 'Error: $e';
        _isProcessing = false;
      });
    }
  }

  Widget _buildGlassMorphism({
    required Widget child,
    double blur = 20,
    double opacity = 0.15,
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
            color: Colors.white.withOpacity(opacity),
            borderRadius: borderRadius ?? BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 1.5,
            ),
          ),
          child: child,
        ),
      ),
    );
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
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          // AR View
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

          // 2D Text Labels for markers (projected from 3D positions)
          ..._markers.entries.map((entry) {
            final label = entry.value['label'] as String;
            final position = entry.value['position'] as vm.Vector3;

            // Project 3D position to 2D screen coordinates
            final screenPos = _projectPositionToScreen(position);

            if (screenPos == null) return const SizedBox.shrink();

            return Positioned(
              left: screenPos.dx - 80, // Center the label (approximate width/2)
              top: screenPos.dy,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF00C853).withOpacity(0.9),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.3),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00C853).withOpacity(0.5),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            );
          }).toList(),

          // Instructions Banner
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
                child: const Center(
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
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
                          onTap: () => setState(() => _aiResponse = ''),
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
                          ),
                          border: InputBorder.none,
                        ),
                        onSubmitted: (_) => _handleTextQuery(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
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

          // Coaching Overlay Blocker
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

  AppBar _buildAppBar() {
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
                bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
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
                colors: [
                  const Color(0xFF0A84FF).withOpacity(0.8),
                  const Color(0xFF0066CC).withOpacity(0.8),
                ],
              ),
            ),
            child: const Icon(Icons.view_in_ar, size: 20),
          ),
          const SizedBox(width: 12),
          const Text(
            'Spatial Memory',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      actions: [
        // Debug button to clear old data
        GestureDetector(
          onLongPress: () async {
            // Long press settings = clear database
            final confirm = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: const Color(0xFF1E1E1E),
                title: const Text(
                  'Clear All Memories?',
                  style: TextStyle(color: Colors.white),
                ),
                content: const Text(
                  'This will delete all saved spatial memories from Cactus.',
                  style: TextStyle(color: Colors.white70),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text(
                      'Clear All',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            );

            if (confirm == true && _spatialService != null) {
              await _spatialService!.clearAll();
              setState(() => _markers.clear());
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('All memories cleared')),
                );
              }
            }
          },
          child: GestureDetector(
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
                border: Border.all(color: Colors.white.withOpacity(0.3)),
              ),
              child: const Icon(Icons.settings_outlined, size: 20),
            ),
          ),
        ),
      ],
    );
  }
}
