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
      // Simple storage - just label and position
      final content = '${memory.label} position:${memory.position.x.toStringAsFixed(2)},${memory.position.y.toStringAsFixed(2)},${memory.position.z.toStringAsFixed(2)}';

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
    try {
      // Use RAG's semantic search
      final results = await _rag.search(
        text: query,
        limit: 1,
      );

      if (results.isEmpty) {
        return null;
      }

      // Get the best match
      final result = results.first;
      final chunk = result.chunk;

      // Parse content to extract label and position
      // Format: "label position:x,y,z"
      final content = chunk.content;
      final match = RegExp(r'(.+) position:([-\d.]+),([-\d.]+),([-\d.]+)').firstMatch(content);

      if (match == null) return null;

      return SpatialMemory(
        label: match.group(1)!.trim(),
        anchorId: chunk.document.target!.fileName,
        position: vm.Vector3(
          double.parse(match.group(2)!),
          double.parse(match.group(3)!),
          double.parse(match.group(4)!),
        ),
        timestamp: chunk.document.target!.createdAt,
      );
    } catch (e) {
      print('❌ Error finding spatial memory: $e');
      return null;
    }
  }

  /// Get all saved memories
  Future<List<SpatialMemory>> getAllMemories() async {
    try {
      // Get all documents
      final documents = await _rag.getAllDocuments();

      // Filter only spatial memory documents
      final spatialDocs = documents.where((doc) => doc.filePath.startsWith('spatial_memory/')).toList();

      return spatialDocs.map((doc) {
        // Parse first chunk content
        if (doc.chunks.isEmpty) return null;

        final content = doc.chunks.first.content;
        final match = RegExp(r'(.+) position:([-\d.]+),([-\d.]+),([-\d.]+)').firstMatch(content);

        if (match == null) return null;

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
      }).whereType<SpatialMemory>().toList();
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
      // Note: Would need to clear the RAG collection
      print('⚠️ Clear all not implemented yet');
    } catch (e) {
      print('❌ Error clearing memories: $e');
    }
  }
}
