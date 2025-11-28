import 'dart:convert';
import 'package:cactus/cactus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:geolocator/geolocator.dart';
import '../models/memory.dart';
import 'model_manager.dart';
import 'vision_service.dart';

/// Service for storing and recalling visual memories
class MemoryService {
  final ModelManager _modelManager = ModelManager();
  final VisionService _visionService = VisionService();
  final _uuid = const Uuid();

  static const String _memoriesKey = 'saved_memories';
  static const double _similarityThreshold = 0.5; // Distance < 0.5 = match

  /// Get current location (simplified for demo)
  Future<Map<String, dynamic>> _getCurrentLocation() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return {'locationName': 'Location services disabled'};
      }

      // Check permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return {'locationName': 'Location permission denied'};
        }
      }

      // Get position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );

      // For demo, create a simple location name based on coordinates
      // In production, you'd use reverse geocoding
      final locationName = _generateLocationName(position);

      return {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'locationName': locationName,
      };
    } catch (e) {
      print('Error getting location: $e');
      return {'locationName': 'Unknown location'};
    }
  }

  /// Generate a simple location name (for demo purposes)
  String _generateLocationName(Position position) {
    // Simple location naming - in production use geocoding service
    final lat = position.latitude.toStringAsFixed(4);
    final lon = position.longitude.toStringAsFixed(4);
    return 'Location ($lat, $lon)';
  }

  /// Save a new memory
  Future<Memory> saveMemory({
    required String imagePath,
    required String userLabel,
  }) async {
    try {
      // Get vision description
      final visionDescription =
          await _visionService.analyzeImage(imagePath);

      // Get current location
      final locationData = await _getCurrentLocation();

      // Store in RAG with combined content
      final combinedContent = '$userLabel: $visionDescription';
      final document = await _modelManager.rag.storeDocument(
        fileName: 'memory_${DateTime.now().millisecondsSinceEpoch}.jpg',
        filePath: imagePath,
        content: combinedContent,
      );

      // Create memory object with location
      final memory = Memory(
        id: _uuid.v4(),
        imagePath: imagePath,
        userLabel: userLabel,
        visionDescription: visionDescription,
        timestamp: DateTime.now(),
        ragDocumentId: document.id,
        latitude: locationData['latitude'],
        longitude: locationData['longitude'],
        locationName: locationData['locationName'],
      );

      // Save to SharedPreferences
      await _saveMemoryMetadata(memory);

      return memory;
    } catch (e) {
      print('Error saving memory: $e');
      rethrow;
    }
  }

  /// Recall memories similar to current image
  Future<List<Memory>> recallMemory(String imagePath) async {
    try {
      // Analyze current image
      final currentDescription =
          await _visionService.analyzeImage(imagePath);

      // Search RAG for similar memories
      final searchResults = await _modelManager.rag.search(
        text: currentDescription,
        limit: 3,
      );

      // Filter by threshold and convert to Memory objects
      final memories = <Memory>[];
      final savedMemories = await getAllMemories();

      for (final result in searchResults) {
        if (result.distance < _similarityThreshold) {
          // Find matching memory by ragDocumentId
          final memory = savedMemories.firstWhere(
            (m) => m.ragDocumentId == result.chunk.document.target?.id,
            orElse: () => savedMemories.first,
          );

          memories.add(Memory(
            id: memory.id,
            imagePath: memory.imagePath,
            userLabel: memory.userLabel,
            visionDescription: memory.visionDescription,
            timestamp: memory.timestamp,
            ragDocumentId: memory.ragDocumentId,
            lastMatchScore: result.distance,
          ));
        }
      }

      return memories;
    } catch (e) {
      print('Error recalling memory: $e');
      return [];
    }
  }

  /// Get all saved memories
  Future<List<Memory>> getAllMemories() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final memoriesJson = prefs.getStringList(_memoriesKey) ?? [];

      return memoriesJson
          .map((json) => Memory.fromJson(jsonDecode(json)))
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    } catch (e) {
      print('Error getting memories: $e');
      return [];
    }
  }

  /// Delete a memory
  Future<void> deleteMemory(String memoryId) async {
    try {
      final memories = await getAllMemories();
      final memory = memories.firstWhere((m) => m.id == memoryId);

      // Delete from RAG
      await _modelManager.rag.deleteDocument(memory.ragDocumentId);

      // Remove from SharedPreferences
      memories.removeWhere((m) => m.id == memoryId);
      await _saveAllMemories(memories);
    } catch (e) {
      print('Error deleting memory: $e');
      rethrow;
    }
  }

  /// Clear all memories
  Future<void> clearAllMemories() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_memoriesKey);

      // Note: RAG documents remain, but metadata is cleared
      // Could add: await _modelManager.rag.clearAll() if needed
    } catch (e) {
      print('Error clearing memories: $e');
      rethrow;
    }
  }

  // Private helpers
  Future<void> _saveMemoryMetadata(Memory memory) async {
    final memories = await getAllMemories();
    memories.add(memory);
    await _saveAllMemories(memories);
  }

  Future<void> _saveAllMemories(List<Memory> memories) async {
    final prefs = await SharedPreferences.getInstance();
    final memoriesJson =
        memories.map((m) => jsonEncode(m.toJson())).toList();
    await prefs.setStringList(_memoriesKey, memoriesJson);
  }
}
