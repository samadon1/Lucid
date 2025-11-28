import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:arkit_plugin/arkit_plugin.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import 'package:cactus/cactus.dart';
import '../models/spatial_memory.dart';
import '../services/spatial_memory_service.dart';
import '../services/model_manager.dart';
import '../services/voice_service.dart';
import 'settings_screen.dart';

/// Simple standalone AR page for spatial memory
/// Tap to place markers, voice to find them
/// Uses Cactus embeddings for semantic search & persistence
class ARSpatialScreen extends StatefulWidget {
  const ARSpatialScreen({super.key});

  @override
  State<ARSpatialScreen> createState() => _ARSpatialScreenState();
}

class _ARSpatialScreenState extends State<ARSpatialScreen> {
  ARKitController? _arController;
  final Map<String, ARKitNode> _nodes = {};

  late SpatialMemoryService _spatialService;
  late VoiceService _voiceService;
  bool _isListening = false;
  bool _isLoading = true;
  bool _isProcessing = false;

  final TextEditingController _queryController = TextEditingController();
  String _aiResponse = '';
  List<String> _relatedNotes = [];
  bool _showMoreContext = false;
  String _currentSearchTerm = '';

  @override
  void initState() {
    super.initState();
    _initServices();
  }

  Future<void> _initServices() async {
    final modelManager = ModelManager();
    await modelManager.initialize();

    _voiceService = VoiceService();
    await _voiceService.ensureInitialized();

    _spatialService = SpatialMemoryService(
      modelManager,
      modelManager.rag,
    );

    // Load existing memories
    await _loadExistingMemories();

    setState(() => _isLoading = false);
  }

  List<SpatialMemory> _pendingMemories = [];

  Future<void> _loadExistingMemories() async {
    final memories = await _spatialService.getAllMemories();
    // Store memories to load after ARKit is ready
    _pendingMemories = memories;
    print('📍 Found ${memories.length} spatial memories (will display when AR is ready)');
  }

  @override
  void dispose() {
    _arController?.dispose();
    _voiceService.dispose();
    _queryController.dispose();
    super.dispose();
  }

  void _onARKitViewCreated(ARKitController controller) {
    _arController = controller;

    // Handle taps
    controller.onARTap = (List<ARKitTestResult> hits) {
      if (hits.isNotEmpty && !_isListening) {
        _handleTap(hits.first);
      }
    };

    // Load pending memories now that ARKit is ready
    Future.delayed(const Duration(milliseconds: 500), () {
      for (final memory in _pendingMemories) {
        _createARNode(memory.label, memory.position);
      }
      if (_pendingMemories.isNotEmpty) {
        print('✅ Displayed ${_pendingMemories.length} AR markers');
      }
    });
  }

  void _handleTap(ARKitTestResult hit) {
    // Get 3D position from tap
    final position = hit.worldTransform.getColumn(3);
    final pos = vm.Vector3(position.x, position.y, position.z);

    // Show dialog to name it
    _showNameDialog(pos);
  }

  void _showNameDialog(vm.Vector3 position) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.3),
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Dialog(
          backgroundColor: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
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
                          colors: [
                            Color(0xFF0A84FF),
                            Color(0xFF0066CC),
                          ],
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
                                    color: const Color(0xFF0A84FF).withOpacity(0.3),
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
    // Create AR node
    _createARNode(label, position);

    // Save to Cactus with embeddings
    final memory = SpatialMemory(
      label: label.toLowerCase(),
      anchorId: 'marker_${DateTime.now().millisecondsSinceEpoch}',
      position: position,
      timestamp: DateTime.now(),
    );

    await _spatialService.saveMemory(memory);

    // Premium styled snackbar
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

    setState(() {}); // Refresh UI
  }

  void _createARNode(String label, vm.Vector3 position) {
    final nodeId = 'node_${label}_${DateTime.now().millisecondsSinceEpoch}';

    // Simple default styling
    final text = ARKitText(
      text: label,
      extrusionDepth: 1,
      materials: [
        ARKitMaterial(
          diffuse: ARKitMaterialProperty.color(Colors.white),
        ),
      ],
    );

    final textNode = ARKitNode(
      geometry: text,
      position: position,
      scale: vm.Vector3(0.02, 0.02, 0.02),
    );

    _arController?.add(textNode);
    _nodes[nodeId] = textNode;
  }

  // Voice commands
  Future<void> _handleVoiceCommand() async {
    if (_isListening) return;

    setState(() => _isListening = true);

    final text = await _voiceService.listen();

    if (text != null && text.isNotEmpty) {
      print('🎤 Voice: $text');
      await _handleQuery(text);
    }

    setState(() => _isListening = false);
  }

  Future<void> _handleTextQuery() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) return;

    _queryController.clear();
    await _handleQuery(query);
  }

  // Process query directly with RAG (no LLM parsing)
  Future<void> _handleQuery(String query) async {
    setState(() => _isProcessing = true);

    try {
      // Clean up query to extract just the item name
      final searchTerm = query.toLowerCase()
        .replaceAll('where is', '')
        .replaceAll('where are', '')
        .replaceAll('find', '')
        .replaceAll('my', '')
        .replaceAll('the', '')
        .replaceAll('?', '')
        .trim();

      print('🔍 Searching for: $searchTerm');

      // Search directly with RAG
      await _findLocation(searchTerm);
    } catch (e) {
      print('❌ Error processing query: $e');
      setState(() {
        _aiResponse = "Sorry, I couldn't find that.";
        _isProcessing = false;
      });
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _aiResponse = '');
      });
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _findLocation(String searchTerm) async {
    // Store for "More Context"
    _currentSearchTerm = searchTerm;

    // Search using RAG
    final memory = await _spatialService.findMemory(searchTerm);

    if (memory == null) {
      final response = "I don't remember saving $searchTerm";
      setState(() {
        _aiResponse = response;
      });
      await _voiceService.speak(response);
    } else {
      // Get camera position for distance/direction
      final cameraPos = await _arController?.cameraPosition();
      if (cameraPos == null) {
        setState(() {
          _aiResponse = "Unable to get your current position";
        });
        return;
      }

      final currentPos = vm.Vector3(cameraPos.x, cameraPos.y, cameraPos.z);
      final distance = memory.distanceFrom(currentPos);
      final direction = memory.getRelativeDirection(
        currentPos,
        vm.Vector3(0, 0, -1),
      );

      // Calculate time since saved
      final now = DateTime.now();
      final difference = now.difference(memory.timestamp);
      final timeAgo = _formatTimeAgo(difference);

      // Simple direct response with distance, direction, and timestamp
      final response = "Your ${memory.label} is ${distance.toStringAsFixed(1)} meters $direction. Last saved $timeAgo.";

      setState(() {
        _aiResponse = response;
      });
      await _voiceService.speak(response);
    }

    // Response stays visible until user manually dismisses it
  }

  Future<void> _fetchRelatedContext() async {
    if (_currentSearchTerm.isEmpty) return;

    try {
      // Use the RAG to search for notes related to the search term
      final modelManager = ModelManager();
      await modelManager.initialize();

      final results = await modelManager.rag.search(
        text: _currentSearchTerm,
        limit: 5, // Get top 5 related notes
      );

      // Extract note content from results
      final notes = results.map((result) {
        return result.chunk.content;
      }).toList();

      setState(() {
        _relatedNotes = notes;
        _showMoreContext = true;
      });

      print('Found ${notes.length} related notes for: $_currentSearchTerm');
    } catch (e) {
      print('Error fetching context: $e');
      setState(() {
        _relatedNotes = ['Unable to load context'];
        _showMoreContext = true;
      });
    }
  }

  String _formatTimeAgo(Duration difference) {
    if (difference.inSeconds < 60) {
      return '${difference.inSeconds} seconds ago';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} minutes ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} hours ago';
    } else {
      return '${difference.inDays} days ago';
    }
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
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: _buildGlassMorphism(
            child: const SizedBox(
              width: 100,
              height: 100,
              child: Center(
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: _buildGlassMorphism(
            padding: const EdgeInsets.all(8),
            borderRadius: BorderRadius.circular(12),
            blur: 15,
            opacity: 0.1,
            child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          ),
        ),
        title: _buildGlassMorphism(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          borderRadius: BorderRadius.circular(20),
          blur: 15,
          opacity: 0.1,
          child: const Text(
            'Spatial Memory',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const SettingsScreen(),
                  ),
                );
              },
              child: _buildGlassMorphism(
                padding: const EdgeInsets.all(8),
                borderRadius: BorderRadius.circular(12),
                blur: 15,
                opacity: 0.1,
                child: const Icon(Icons.settings_outlined, color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // ARKit view
          ARKitSceneView(
            onARKitViewCreated: _onARKitViewCreated,
            enableTapRecognizer: true,
          ),

          // Subtle gradient overlay for depth
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

          // Instructions - Top Center (minimalist)
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

          // Processing Visual Effect - Spatial gradient overlay
          if (_isProcessing)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _isProcessing ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.center,
                        radius: 1.5,
                        colors: [
                          const Color(0xFF0A84FF).withOpacity(0.15),
                          const Color(0xFF0A84FF).withOpacity(0.08),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                      child: Container(
                        color: Colors.transparent,
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Processing Indicator - Center pulse
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

          // AI Response Display - Premium centered card
          if (_aiResponse.isNotEmpty)
            Positioned(
              top: MediaQuery.of(context).padding.top + 140,
              left: 24,
              right: 24,
              child: _buildGlassMorphism(
                blur: 25,
                opacity: 0.2,
                tint: const Color(0xFF0A84FF),
                padding: const EdgeInsets.all(24),
                borderRadius: BorderRadius.circular(28),
                child: Column(
                  children: [
                    // Close button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        GestureDetector(
                          onTap: () {
                            setState(() => _aiResponse = '');
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
                    if (_aiResponse.isNotEmpty && _currentSearchTerm.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: GestureDetector(
                          onTap: _fetchRelatedContext,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF0A84FF), Color(0xFF0066CC)],
                              ),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF0A84FF).withOpacity(0.3),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                                SizedBox(width: 8),
                                Text(
                                  'More Context',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
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
            ),

          // Context Panel - Related notes
          _buildContextPanel(),

          // Bottom Input Bar - Ultra premium
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
                  // Text input field
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
                  // Mic button - Glowing orb
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
                            color: (_isListening
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
        ],
      ),
    );
  }

  Widget _buildContextPanel() {
    if (!_showMoreContext || _relatedNotes.isEmpty) return const SizedBox.shrink();

    return Positioned(
      bottom: 120,
      left: 20,
      right: 20,
      child: GestureDetector(
        onTap: () {}, // Prevent taps from passing through
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 400),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withOpacity(0.3),
                    Colors.white.withOpacity(0.2),
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withOpacity(0.4),
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Related Context',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          setState(() => _showMoreContext = false);
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
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Notes list
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _relatedNotes.map((note) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.3),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              note,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                          );
                        }).toList(),
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
}
