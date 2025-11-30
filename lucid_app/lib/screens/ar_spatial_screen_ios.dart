import 'dart:ui' as ui;
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:arkit_plugin/arkit_plugin.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import 'package:cactus/cactus.dart';
import 'package:path_provider/path_provider.dart';
import '../models/spatial_memory.dart';
import '../services/spatial_memory_service.dart';
import '../services/model_manager.dart';
import '../services/voice_service.dart';
import '../services/face_recognition_service.dart';
import 'settings_screen.dart';

/// Simple standalone AR page for spatial memory (iOS - ARKit)
/// Tap to place markers, voice to find them
/// Uses Cactus embeddings for semantic search & persistence
class ARSpatialScreenIOS extends StatefulWidget {
  const ARSpatialScreenIOS({super.key});

  @override
  State<ARSpatialScreenIOS> createState() => _ARSpatialScreenIOSState();
}

class _ARSpatialScreenIOSState extends State<ARSpatialScreenIOS> {
  ARKitController? _arController;
  final Map<String, ARKitNode> _nodes = {};

  late SpatialMemoryService _spatialService;
  late VoiceService _voiceService;
  late FaceRecognitionService _faceService;
  late ModelManager
  _modelManager; // Cache ModelManager to avoid re-initialization
  bool _isListening = false;
  bool _isLoading = true;
  bool _isProcessing = false;

  final TextEditingController _queryController = TextEditingController();
  String _aiResponse = '';
  String _contextSummary = ''; // Related notes from RAG (raw, no LLM)
  bool _isLoadingContext = false;
  String _currentSearchTerm = '';
  bool _isDetectingFaces = false;
  bool _isSummarizingPerson = false; // Loading state for person summarization
  // Cache of the most recent face recognition results keyed by face id/name.
  final Map<String, Map<String, dynamic>> _recognizedFaces = {};

  @override
  void initState() {
    super.initState();
    _initServices();
  }

  Future<void> _initServices() async {
    _modelManager = ModelManager();
    await _modelManager.initialize();

    _voiceService = VoiceService();
    await _voiceService.ensureInitialized();

    _spatialService = SpatialMemoryService(_modelManager, _modelManager.rag);

    _faceService = FaceRecognitionService(_modelManager, _modelManager.rag);

    // Load existing memories
    await _loadExistingMemories();

    setState(() => _isLoading = false);
  }

  List<SpatialMemory> _pendingMemories = [];

  Future<void> _loadExistingMemories() async {
    final memories = await _spatialService.getAllMemories();
    // Store memories to load after ARKit is ready
    _pendingMemories = memories;
    print(
      '📍 Found ${memories.length} spatial memories (will display when AR is ready)',
    );
  }

  // Show recent people (no face detection needed!)
  Future<void> _showRecentPeople() async {
    if (_isDetectingFaces) return;

    setState(() {
      _isDetectingFaces = true;
    });

    try {
      // Get all saved faces (sorted by most recent)
      final savedFaces = await _faceService.getAllSavedFaces();

      if (!mounted) return;

      if (savedFaces.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No people saved yet. Add them in Notes first.'),
          ),
        );
        return;
      }

      // Show recent people in bottom sheet
      await _showPeopleList(savedFaces.take(10).toList());
    } catch (e) {
      print('Error loading people: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load people: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isDetectingFaces = false);
      }
    }
  }

  /// Show people list and let user select
  Future<void> _showPeopleList(List<Map<String, dynamic>> people) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _buildPeopleListSheet(people),
    );
  }

  Widget _buildPeopleListSheet(List<Map<String, dynamic>> people) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(0.25),
                  Colors.white.withOpacity(0.15),
                ],
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              border: Border.all(
                color: Colors.white.withOpacity(0.4),
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                // Title
                Text(
                  'Recent People',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 20),
                // People list
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: people.length,
                    itemBuilder: (context, index) {
                      final person = people[index];
                      return _buildPersonCard(person);
                    },
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPersonCard(Map<String, dynamic> person) {
    return GestureDetector(
      onTap: () async {
        Navigator.pop(context); // Close bottom sheet
        await _showPersonContext(person);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
        ),
        child: Row(
          children: [
            // Photo thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: File(person['photoPath']).existsSync()
                  ? Image.file(
                      File(person['photoPath']),
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      width: 60,
                      height: 60,
                      color: Colors.white.withOpacity(0.2),
                      child: const Icon(
                        Icons.person,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
            ),
            const SizedBox(width: 16),
            // Info - just name
            Expanded(
              child: Text(
                person['name'],
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            // Arrow
            Icon(
              Icons.arrow_forward_ios,
              color: Colors.white.withOpacity(0.5),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inDays == 0) {
      if (diff.inHours == 0) {
        return '${diff.inMinutes}m ago';
      }
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    }
  }

  /// Show full context about selected person
  Future<void> _showPersonContext(Map<String, dynamic> person) async {
    // Show overlay immediately with loading state
    setState(() {
      _isSummarizingPerson = true;
      _recognizedFaces
        ..clear()
        ..['selected'] = {
          'name': person['name'],
          'notes': '', // Will be filled after summarization
          'similarity': 1.0, // User selected, so 100% confidence
        };
    });

    // Generate LLM summary using lfm2-350m
    final summary = await _summarizeFaceNotes(person['name'], person['notes']);

    setState(() {
      _isSummarizingPerson = false;
      _recognizedFaces['selected'] = {
        'name': person['name'],
        'notes': summary,
        'similarity': 1.0,
      };
    });
  }

  @override
  void dispose() {
    // Remove camera and timer disposal since we're not using them
    _faceService.dispose();
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );

    setState(() {}); // Refresh UI
  }

  void _createARNode(String label, vm.Vector3 position) {
    final nodeId = 'node_${label}_${DateTime.now().millisecondsSinceEpoch}';

    // Create a minimal, consistent marker
    // Green sphere (0.05m diameter) + white text above it

    // 1. Green sphere marker
    final sphere = ARKitSphere(
      radius: 0.025, // 5cm diameter sphere
      materials: [
        ARKitMaterial(
          diffuse: ARKitMaterialProperty.color(
            const Color(0xFF00C853),
          ), // Bright green
          emission: ARKitMaterialProperty.color(
            const Color(0xFF00C853).withOpacity(0.3),
          ), // Slight glow
        ),
      ],
    );

    final sphereNode = ARKitNode(geometry: sphere, position: position);

    // 2. Text label (positioned 8cm above the sphere)
    final text = ARKitText(
      text: label.toUpperCase(), // Uppercase for consistency
      extrusionDepth: 0.5, // Subtle depth
      materials: [
        ARKitMaterial(
          diffuse: ARKitMaterialProperty.color(Colors.white),
          emission: ARKitMaterialProperty.color(
            Colors.white.withOpacity(0.2),
          ), // Slight glow
        ),
      ],
    );

    final textNode = ARKitNode(
      geometry: text,
      position: vm.Vector3(
        position.x,
        position.y + 0.08,
        position.z,
      ), // 8cm above sphere
      scale: vm.Vector3(0.015, 0.015, 0.015), // Smaller, cleaner text
    );

    // Add both nodes
    _arController?.add(sphereNode);
    _arController?.add(textNode);

    // Store both for cleanup
    _nodes['${nodeId}_sphere'] = sphereNode;
    _nodes['${nodeId}_text'] = textNode;
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
      final searchTerm = query
          .toLowerCase()
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
    // Store for "More Context" and clear old context immediately
    _currentSearchTerm = searchTerm;
    setState(() {
      _contextSummary = ''; // Clear old context immediately
      _isLoadingContext = false; // Reset loading state
    });

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
      final response =
          "Your ${memory.label} is ${distance.toStringAsFixed(1)} meters $direction. Last saved $timeAgo.";

      setState(() {
        _aiResponse = response;
        _contextSummary = ''; // Clear old context
      });
      await _voiceService.speak(response);

      // Fetch and stream contextual summary
      _fetchAndStreamContext(searchTerm);
    }
  }

  /// Summarize face notes into natural language (fast, no thinking)
  Future<String> _summarizeFaceNotes(String name, String rawNotes) async {
    if (rawNotes.isEmpty) return '';

    try {
      // If notes are short and clear, show them directly without LLM
      // Split notes by lines to check individual note length
      final noteLines = rawNotes
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .toList();
      final totalLength = noteLines.fold<int>(
        0,
        (sum, note) => sum + note.trim().length,
      );
      final avgNoteLength = noteLines.isEmpty
          ? 0
          : totalLength / noteLines.length;

      // If notes are short (avg < 30 chars) and we have 2 or fewer, just format them directly
      if (noteLines.length <= 2 && avgNoteLength < 30) {
        final formattedNotes = noteLines.map((note) => note.trim()).join('. ');
        print('✅ Showing raw notes directly for $name (short and clear)');
        return formattedNotes;
      }

      // Debug: Print what notes we're sending
      print('📝 Notes being sent to LLM for $name: $rawNotes');

      // For longer notes, use LLM with explicit prompt to prevent general knowledge
      final messages = [
        ChatMessage(
          content:
              '/no_think These are notes about $name. Summarize them in 1-2 short sentences. DO NOT explain who $name is or add general information. ONLY use the information below:\n\n$rawNotes',
          role: 'user',
        ),
      ];

      final result = await _modelManager.conversationLM.generateCompletion(
        messages: messages,
        params: CactusCompletionParams(
          maxTokens: 40, // Even shorter to force 1-2 sentences
          temperature:
              0.3, // Lower temperature for more factual, less creative output
        ),
      );

      if (result.success) {
        // Strip thinking tags
        var cleaned = _stripThinkingTags(result.response.trim());

        // Check if LLM generated general knowledge instead of using notes
        // Common general knowledge words that shouldn't appear if we're just listing facts
        final generalKnowledgeWords = [
          'person',
          'individual',
          'human',
          'someone',
          'they are',
          'he is',
          'she is',
        ];
        final responseLower = cleaned.toLowerCase();
        final notesLower = rawNotes.toLowerCase();

        // If response contains general knowledge words but notes don't, it's likely hallucination
        bool isGeneralKnowledge = generalKnowledgeWords.any(
          (word) => responseLower.contains(word) && !notesLower.contains(word),
        );

        // Also check if response doesn't contain any of the actual note content
        bool lacksNoteContent = !noteLines.any(
          (note) => responseLower.contains(
            note.toLowerCase().substring(
              0,
              note.length > 10 ? 10 : note.length,
            ),
          ),
        );

        if (isGeneralKnowledge || lacksNoteContent) {
          print(
            '⚠️ LLM generated general knowledge for $name, falling back to raw notes',
          );
          // Fallback to formatted raw notes
          return noteLines.map((note) => note.trim()).join('. ');
        }

        // Enforce length limit: if too long, truncate at sentence boundary
        if (cleaned.length > 200) {
          final sentences = cleaned.split(RegExp(r'[.!?]+\s*'));
          var truncated = '';
          for (final sentence in sentences) {
            if ((truncated + sentence).length > 200) break;
            truncated += sentence + (truncated.isEmpty ? '' : '. ');
          }
          cleaned = truncated.isNotEmpty
              ? truncated.trim()
              : cleaned.substring(0, 200).trim();
        }

        return cleaned.isNotEmpty ? cleaned : rawNotes;
      }
      return rawNotes;
    } catch (e) {
      print('❌ Error summarizing face notes: $e');
      return rawNotes; // Fallback to raw notes
    }
  }

  /// Clean note content by removing metadata prefixes
  String _cleanNoteContent(String content) {
    // Split into lines
    final lines = content.split('\n');

    // Process each line
    final cleanedLines = lines
        .map((line) {
          final trimmed = line.trim();
          final lowerTrimmed = trimmed.toLowerCase();

          // Remove entire line if it's just "Title: X"
          if (lowerTrimmed.startsWith('title:')) {
            return null; // Filter out this line
          }

          // If line starts with "content:", remove just the prefix and keep the rest
          if (lowerTrimmed.startsWith('content:')) {
            // Remove "content:" prefix (case insensitive) and any following whitespace
            final withoutPrefix = trimmed.replaceFirst(
              RegExp(r'^content:\s*', caseSensitive: false),
              '',
            );
            return withoutPrefix.isEmpty
                ? null
                : withoutPrefix; // Return rest of line, or null if empty
          }

          // Keep all other lines as-is
          return line;
        })
        .where((line) => line != null && line.isNotEmpty)
        .cast<String>()
        .toList();

    // Join back and clean up
    return cleanedLines.join('\n').trim();
  }

  /// Strip thinking tags from LLM output
  String _stripThinkingTags(String content) {
    // Remove Cactus thinking tags: <think>...</think>
    content = content.replaceAll(
      RegExp(r'<think>.*?</think>', dotAll: true),
      '',
    );
    // Remove generic thinking tags: <think>...</think>
    content = content.replaceAll(
      RegExp(r'<think>.*?</think>', dotAll: true),
      '',
    );
    return content.trim();
  }

  /// Fetch related notes and summarize with lfm2-350m
  Future<void> _fetchAndStreamContext(String searchTerm) async {
    if (searchTerm.isEmpty) return;

    // Store the search term we're processing (capture it at start)
    final originalSearchTerm = searchTerm;

    // Update current search term and clear context immediately
    _currentSearchTerm = searchTerm;

    setState(() {
      _isLoadingContext = true;
      _contextSummary = ''; // Clear previous immediately
    });

    try {
      // Search RAG for related notes (using cached ModelManager)
      // Check if search term changed (new search started)
      if (_currentSearchTerm != originalSearchTerm) {
        print(
          '⚠️ Search term changed from "$originalSearchTerm" to "$_currentSearchTerm", aborting',
        );
        return;
      }

      // Boost title matches by including "title" in search query
      // This helps match notes where the search term is in the title
      // e.g., "curtains" -> "title curtains" to match "Title: curtains"
      final boostedQuery = 'title $searchTerm $searchTerm';

      final results = await _modelManager.rag.search(
        text: boostedQuery,
        limit: 10, // Get more candidates for filtering
      );

      // Filter out spatial memories and faces - only show actual notes
      final noteResults = results.where((r) {
        final filePath = r.chunk.document.target?.filePath ?? '';
        final content = r.chunk.content;
        // Exclude spatial memories (position data) and face records
        return !filePath.startsWith('spatial_memory/') &&
            !filePath.startsWith('faces/') &&
            !content.startsWith('Face:');
      }).toList();

      // Check if search term changed (new search started)
      if (_currentSearchTerm != originalSearchTerm) {
        print(
          '⚠️ Search term changed from "$originalSearchTerm" to "$_currentSearchTerm", aborting',
        );
        return;
      }

      if (noteResults.isEmpty) {
        print(
          '⚠️ No notes found for: $originalSearchTerm (found ${results.length} total results, but none were notes)',
        );
        if (mounted && _currentSearchTerm == originalSearchTerm) {
          setState(() {
            _isLoadingContext = false;
          });
        }
        return; // No context to show
      }

      // Re-rank results: boost title matches but keep semantic similarity as primary
      final searchTermLower = originalSearchTerm.toLowerCase();

      // Create a list with adjusted distances (boost title matches)
      final rankedResults = noteResults.map((r) {
        final content = r.chunk.content;
        final titleMatch = RegExp(
          r'Title:\s*(.+)',
          caseSensitive: false,
        ).firstMatch(content);
        final title = titleMatch?.group(1)?.trim().toLowerCase() ?? '';

        // Check if title contains search term - boost by reducing distance
        final hasTitleMatch = title.contains(searchTermLower);
        // Boost title matches by 30% (reduce distance = better ranking)
        final adjustedDistance = hasTitleMatch ? r.distance * 0.7 : r.distance;

        return {
          'result': r,
          'distance': adjustedDistance,
          'originalDistance': r.distance,
          'hasTitleMatch': hasTitleMatch,
        };
      }).toList();

      // Sort by adjusted distance (lower = better), but keep original distance for filtering
      rankedResults.sort(
        (a, b) => (a['distance'] as double).compareTo(b['distance'] as double),
      );

      // Filter by original distance threshold (lower distance = more similar)
      const distanceThreshold = 1.0; // More lenient - show more matches
      final strongMatches = rankedResults
          .where((r) => (r['originalDistance'] as double) < distanceThreshold)
          .take(3)
          .map((r) => r['result'])
          .toList();

      // If no matches pass threshold, still show top note result
      final matchesToShow = strongMatches.isNotEmpty
          ? strongMatches
          : (rankedResults.isNotEmpty ? [rankedResults.first['result']] : []);

      // Check if search term changed (new search started)
      if (_currentSearchTerm != originalSearchTerm) {
        print(
          '⚠️ Search term changed from "$originalSearchTerm" to "$_currentSearchTerm", aborting',
        );
        return;
      }

      if (matchesToShow.isEmpty) {
        print('⚠️ No RAG results found for: $originalSearchTerm');
        if (mounted && _currentSearchTerm == originalSearchTerm) {
          setState(() {
            _isLoadingContext = false;
          });
        }
        return; // No context to show
      }

      print(
        '🔍 Found ${results.length} total results, ${noteResults.length} notes, showing ${matchesToShow.length} (distances: ${matchesToShow.map((r) => r.distance.toStringAsFixed(2)).join(", ")})',
      );

      // Check if search term changed (new search started)
      if (_currentSearchTerm != originalSearchTerm) {
        print(
          '⚠️ Search term changed from "$originalSearchTerm" to "$_currentSearchTerm", aborting',
        );
        return;
      }

      // Extract note content and clean it (remove metadata)
      final notes = matchesToShow
          .map((r) => _cleanNoteContent(r.chunk.content))
          .toList();

      // Limit notes to prevent too much input (max 2-3 notes for concise summary)
      final limitedNotes = notes.take(2).toList();
      final notesText = limitedNotes.join('\n');

      // Debug: Print what notes we're sending
      print('📝 Notes being sent to LLM: $notesText');

      // If notes are already short and clear (like "fix laptop", "block time"),
      // just format them nicely without LLM to avoid hallucination
      final totalLength = limitedNotes.fold<int>(
        0,
        (sum, note) => sum + note.length,
      );
      final avgNoteLength = limitedNotes.isEmpty
          ? 0
          : totalLength / limitedNotes.length;

      // If notes are short (avg < 30 chars) and we have 2 or fewer, just show them directly
      if (limitedNotes.length <= 2 && avgNoteLength < 30) {
        final formattedNotes = limitedNotes.map((note) => '• $note').join('\n');
        if (mounted && _currentSearchTerm == originalSearchTerm) {
          setState(() {
            _contextSummary = formattedNotes;
            _isLoadingContext = false;
          });
          print('✅ Showing raw notes directly (short and clear)');
        }
        return;
      }

      // For longer notes, use LLM with explicit task/reminder format
      final messages = [
        ChatMessage(
          content:
              '/no_think These are your tasks and reminders about "$originalSearchTerm". List them in 1-2 short sentences. DO NOT explain what "$originalSearchTerm" is. ONLY use the information below:\n\n$notesText',
          role: 'user',
        ),
      ];

      // Check if search term changed before calling LLM
      if (_currentSearchTerm != originalSearchTerm) {
        print(
          '⚠️ Search term changed from "$originalSearchTerm" to "$_currentSearchTerm", aborting',
        );
        return;
      }

      final result = await _modelManager.conversationLM.generateCompletion(
        messages: messages,
        params: CactusCompletionParams(
          maxTokens: 40, // Even shorter to force 1-2 sentences
          temperature:
              0.3, // Lower temperature for more factual, less creative output
        ),
      );

      // Check if search term changed after LLM call
      if (_currentSearchTerm != originalSearchTerm) {
        print(
          '⚠️ Search term changed from "$originalSearchTerm" to "$_currentSearchTerm", ignoring context update',
        );
        return;
      }

      if (result.success) {
        // Strip thinking tags
        var cleaned = _stripThinkingTags(result.response.trim());

        // Check if LLM generated general knowledge instead of using notes
        // Common general knowledge words that shouldn't appear if we're just listing tasks
        final generalKnowledgeWords = [
          'device',
          'portable',
          'computer',
          'tool',
          'machine',
          'electronic',
          'technology',
        ];
        final responseLower = cleaned.toLowerCase();
        final notesLower = notesText.toLowerCase();

        // If response contains general knowledge words but notes don't, it's likely hallucination
        bool isGeneralKnowledge = generalKnowledgeWords.any(
          (word) => responseLower.contains(word) && !notesLower.contains(word),
        );

        // Also check if response doesn't contain any of the actual note content
        bool lacksNoteContent = !limitedNotes.any(
          (note) => responseLower.contains(
            note.toLowerCase().substring(
              0,
              note.length > 10 ? 10 : note.length,
            ),
          ),
        );

        if (isGeneralKnowledge || lacksNoteContent) {
          print(
            '⚠️ LLM generated general knowledge, falling back to raw notes',
          );
          // Fallback to formatted raw notes
          final formattedNotes = limitedNotes
              .map((note) => '• $note')
              .join('\n');
          if (mounted && _currentSearchTerm == originalSearchTerm) {
            setState(() {
              _contextSummary = formattedNotes;
              _isLoadingContext = false;
            });
            print('✅ Showing raw notes instead (${limitedNotes.length} items)');
          }
        } else {
          // Enforce length limit: if too long, truncate at sentence boundary
          if (cleaned.length > 200) {
            // Find the last sentence before 200 chars
            final sentences = cleaned.split(RegExp(r'[.!?]+\s*'));
            var truncated = '';
            for (final sentence in sentences) {
              if ((truncated + sentence).length > 200) break;
              truncated += sentence + (truncated.isEmpty ? '' : '. ');
            }
            cleaned = truncated.isNotEmpty
                ? truncated.trim()
                : cleaned.substring(0, 200).trim();
          }

          // Only update if search term is still current
          if (mounted && _currentSearchTerm == originalSearchTerm) {
            setState(() {
              _contextSummary = cleaned;
              _isLoadingContext = false;
            });
            print(
              '✅ Context summarized with lfm2-350m (${matchesToShow.length} notes, ${cleaned.length} chars)',
            );
          }
        }
      } else {
        // Fallback to raw notes if LLM fails
        final formattedNotes = limitedNotes.map((note) => '• $note').join('\n');
        if (mounted && _currentSearchTerm == originalSearchTerm) {
          setState(() {
            _contextSummary = formattedNotes;
            _isLoadingContext = false;
          });
          print('⚠️ LLM failed, showing raw notes');
        }
      }
    } catch (e) {
      print('❌ Error fetching context: $e');
      if (mounted && _currentSearchTerm == searchTerm) {
        setState(() => _isLoadingContext = false);
      }
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
          // Face Recognition Button
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: GestureDetector(
              onTap: _isDetectingFaces ? null : _showRecentPeople,
              child: _buildGlassMorphism(
                padding: const EdgeInsets.all(8),
                borderRadius: BorderRadius.circular(12),
                blur: 15,
                opacity: 0.1,
                child: _isDetectingFaces
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.face, color: Colors.white, size: 20),
              ),
            ),
          ),
          // Settings Button
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
                child: const Icon(
                  Icons.settings_outlined,
                  color: Colors.white,
                  size: 20,
                ),
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

          // Face recognition overlays
          if (_recognizedFaces.isNotEmpty)
            ...(_recognizedFaces.entries.map((entry) {
              final faceInfo = entry.value;
              return Positioned(
                top: MediaQuery.of(context).padding.top + 140,
                left: 20,
                right: 20,
                child: _buildGlassMorphism(
                  blur: 30,
                  opacity: 0.08,
                  padding: const EdgeInsets.all(20),
                  borderRadius: BorderRadius.circular(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.person,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  faceInfo['name'],
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Close button
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _recognizedFaces.clear();
                                _isSummarizingPerson = false;
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
                      const SizedBox(height: 12),
                      if (_isSummarizingPerson) ...[
                        // Loading indicator
                        Row(
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                color: Colors.white.withOpacity(0.6),
                                strokeWidth: 2,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Summarizing...',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 14,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ] else if (faceInfo['notes'] != null &&
                          faceInfo['notes'].toString().isNotEmpty) ...[
                        // Summary text
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            faceInfo['notes'],
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }).toList()),

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
                      filter: ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                      child: Container(color: Colors.transparent),
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
                blur: 30,
                opacity: 0.08,
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

                    // Contextual summary (streamed below primary answer)
                    if (_contextSummary.isNotEmpty || _isLoadingContext) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.2),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.auto_awesome,
                                  color: Colors.white.withOpacity(0.8),
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'From your integrations',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.7),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (_isLoadingContext)
                              Row(
                                children: [
                                  SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      color: Colors.white.withOpacity(0.6),
                                      strokeWidth: 1.5,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Thinking...',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.6),
                                      fontSize: 14,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              )
                            else
                              Text(
                                _contextSummary,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.9),
                                  fontSize: 15,
                                  height: 1.5,
                                  letterSpacing: 0.2,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

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
        ],
      ),
    );
  }
}
