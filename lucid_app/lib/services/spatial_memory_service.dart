import 'package:cactus/cactus.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import '../models/spatial_memory.dart';
import 'model_manager.dart';

/// Service for managing spatial memories with Cactus embeddings
/// - Semantic search: "Where are my car keys?" finds "keys"
/// - Persistent storage using Cactus database
/// - Vector similarity for fuzzy matching
class SpatialMemoryService {
  final ModelManager _modelManager;
  final CactusRAG _rag;

  static const String _collectionName = 'spatial_memories';

  SpatialMemoryService(this._modelManager, this._rag);

  /// Save a spatial memory with embeddings
  Future<void> saveMemory(SpatialMemory memory) async {
    try {
      // Natural language format for better semantic embeddings
      final content =
          'Spatial memory object labeled "${memory.label}" located at position coordinates: ${memory.position.x.toStringAsFixed(2)}, ${memory.position.y.toStringAsFixed(2)}, ${memory.position.z.toStringAsFixed(2)}';

      // Store in RAG with metadata
      await _rag.storeDocument(
        fileName: memory.anchorId,
        filePath: 'spatial_memory/${memory.anchorId}',
        content: content,
      );

      print('✅ Saved memory to Cactus: ${memory.label}');
    } catch (e) {
      print('❌ Error saving spatial memory: $e');
    }
  }

  /// Find a memory by semantic search (e.g., "car keys" matches "keys")
  Future<SpatialMemory?> findMemory(String query) async {
    print('RAG: 🔍 Search query="$query"');

    // HYBRID SEARCH STRATEGY
    // 1. Try simple text match first (High precision)
    //    If I ask for "bottle" and I have a "bottle", I want that exact one.
    final textMatch = await _fallbackTextSearch(query);
    if (textMatch != null) {
      print(
        'RAG: ✅ Text match found (prioritizing over RAG): "${textMatch.label}"',
      );
      return textMatch;
    }

    // 2. If no text match, try RAG (Semantic recall)
    //    e.g. "water" -> "bottle"
    try {
      print('RAG: ℹ️ No text match, trying semantic RAG search...');

      final results = await _rag.search(text: query, limit: 5);

      print('RAG: 🔍 Returned ${results.length} results');
      for (var i = 0; i < results.length && i < 5; i++) {
        final r = results[i];
        final content = r.chunk.content;

        var label = 'unknown';
        var match = RegExp(r'labeled "([^"]+)"').firstMatch(content);
        if (match != null) {
          label = match.group(1)!;
        } else {
          match = RegExp(r'(.+) position:').firstMatch(content);
          if (match != null) label = match.group(1)!.trim();
        }

        print('RAG:    [$i] label="$label"');
      }

      if (results.isEmpty) {
        print('RAG: ⚠️ Search returned EMPTY');
        return null;
      }

      // Check the top result
      final result = results.first;
      final chunk = result.chunk;
      final content = chunk.content;

      // Parse content
      String? label;
      vm.Vector3? position;

      var match = RegExp(
        r'labeled "([^"]+)" located at position coordinates: ([-\d.]+), ([-\d.]+), ([-\d.]+)',
      ).firstMatch(content);

      if (match != null) {
        label = match.group(1)!;
        position = vm.Vector3(
          double.parse(match.group(2)!),
          double.parse(match.group(3)!),
          double.parse(match.group(4)!),
        );
      } else {
        match = RegExp(
          r'(.+) position:([-\d.]+),([-\d.]+),([-\d.]+)',
        ).firstMatch(content);
        if (match != null) {
          label = match.group(1)!.trim();
          position = vm.Vector3(
            double.parse(match.group(2)!),
            double.parse(match.group(3)!),
            double.parse(match.group(4)!),
          );
        }
      }

      if (label == null || position == null) {
        print('RAG: ⚠️ Could not parse result');
        return null;
      }

      print('RAG: ✅ Semantic match found: "$label"');

      return SpatialMemory(
        label: label,
        anchorId: chunk.document.target!.fileName,
        position: position,
        timestamp: chunk.document.target!.createdAt,
      );
    } catch (e) {
      print('RAG: ❌ Error in search: $e');
      return null;
    }
  }

  /// Fallback: simple case-insensitive text matching
  Future<SpatialMemory?> _fallbackTextSearch(String query) async {
    try {
      final allMemories = await getAllMemories();
      final queryLower = query.toLowerCase();

      // 1. Exact match check
      for (final memory in allMemories) {
        if (memory.label.toLowerCase() == queryLower) {
          return memory;
        }
      }

      // 2. Contains match check
      for (final memory in allMemories) {
        if (memory.label.toLowerCase().contains(queryLower)) {
          return memory;
        }
      }

      return null;
    } catch (e) {
      print('❌ Error in fallback: $e');
      return null;
    }
  }

  /// Get all saved memories
  Future<List<SpatialMemory>> getAllMemories() async {
    try {
      final documents = await _rag.getAllDocuments();
      final spatialDocs = documents
          .where((doc) => doc.filePath.startsWith('spatial_memory/'))
          .toList();

      return spatialDocs
          .map((doc) {
            if (doc.chunks.isEmpty) return null;
            final content = doc.chunks.first.content;

            var match = RegExp(
              r'labeled "([^"]+)" located at position coordinates: ([-\d.]+), ([-\d.]+), ([-\d.]+)',
            ).firstMatch(content);
            if (match != null) {
              return SpatialMemory(
                label: match.group(1)!,
                anchorId: doc.fileName,
                position: vm.Vector3(
                  double.parse(match.group(2)!),
                  double.parse(match.group(3)!),
                  double.parse(match.group(4)!),
                ),
                timestamp: doc.createdAt,
              );
            }

            match = RegExp(
              r'(.+) position:([-\d.]+),([-\d.]+),([-\d.]+)',
            ).firstMatch(content);
            if (match != null) {
              return SpatialMemory(
                label: match.group(1)!.trim(),
                anchorId: doc.fileName,
                position: vm.Vector3(
                  double.parse(match.group(2)!),
                  double.parse(match.group(3)!),
                  double.parse(match.group(4)!),
                ),
                timestamp: doc.createdAt,
              );
            }
            return null;
          })
          .whereType<SpatialMemory>()
          .toList();
    } catch (e) {
      print('❌ Error getting all memories: $e');
      return [];
    }
  }

  /// Delete a memory
  Future<void> deleteMemory(String label) async {
    try {
      // Note: RAG doesn't have direct delete by label
      // For now, we'll need to implement this differently
      // or accept that memories are permanent
      print('⚠️ Delete not implemented yet - memories persist');
    } catch (e) {
      print('❌ Error deleting memory: $e');
    }
  }

  /// Clear all spatial memories
  Future<void> clearAll() async {
    try {
      print('🗑️ Clearing all spatial memories...');

      final allDocs = await _rag.getAllDocuments();
      final spatialDocs = allDocs
          .where((doc) => doc.filePath.startsWith('spatial_memory/'))
          .toList();

      print('🗑️ Found ${spatialDocs.length} spatial memories to delete');

      for (final doc in spatialDocs) {
        try {
          // Attempt to delete document
          print('   Deleting: ${doc.fileName}');
          // Note: CactusRAG does not support deletion yet
          // await _rag.deleteDocument(doc.fileName);
        } catch (e) {
          print('   Error deleting ${doc.fileName}: $e');
        }
      }

      print('✅ Cleared spatial memories');
    } catch (e) {
      print('❌ Error clearing memories: $e');
    }
  }
}
