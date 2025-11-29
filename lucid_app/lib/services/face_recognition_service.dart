import 'dart:io';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cactus/cactus.dart';
import 'model_manager.dart';

/// Face recognition using VLM (Vision Language Model) comparison
/// Much more robust than ML Kit landmarks!
class FaceRecognitionService {
  final ModelManager _modelManager;
  final CactusRAG _rag;

  FaceRecognitionService(this._modelManager, this._rag);

  /// Pick image from gallery or camera
  Future<File?> pickImage({bool fromCamera = false}) async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
    );

    if (image != null) {
      return File(image.path);
    }
    return null;
  }

  /// Store face with photo in app storage
  Future<void> storeFace(String name, String notes, File photoFile) async {
    // Copy photo to app documents directory
    final appDir = await getApplicationDocumentsDirectory();
    final facesDir = Directory('${appDir.path}/faces');
    if (!await facesDir.exists()) {
      await facesDir.create(recursive: true);
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final savedPhotoPath = '${facesDir.path}/${name}_$timestamp.jpg';
    await photoFile.copy(savedPhotoPath);

    // Store metadata in RAG
    final content = '''
Face: $name
Notes: $notes
PhotoPath: $savedPhotoPath
Timestamp: ${DateTime.now().toIso8601String()}
    ''';

    await _rag.storeDocument(
      fileName: '${name}_$timestamp',
      filePath: 'faces/$name',
      content: content,
    );

    print('✅ Stored face for $name with photo at $savedPhotoPath');
  }

  /// Get all saved faces (for showing in list)
  Future<List<Map<String, dynamic>>> getAllSavedFaces() async {
    try {
      final results = await _rag.search(text: "Face:", limit: 50);
      
      List<Map<String, dynamic>> faces = [];
      
      for (final result in results) {
        // Only include face records (filter by filePath and content)
        final filePath = result.chunk.document.target?.filePath ?? '';
        final content = result.chunk.content;
        
        // Must be from faces/ directory or start with "Face:"
        if (!filePath.startsWith('faces/') && !content.startsWith('Face:')) {
          continue;
        }
        final lines = content.split('\n');

        String? name;
        String? notes;
        String? photoPath;
        DateTime? timestamp;

        for (final line in lines) {
          if (line.startsWith('Face: ')) {
            name = line.substring(6).trim();
          } else if (line.startsWith('Notes: ')) {
            notes = line.substring(7).trim();
          } else if (line.startsWith('PhotoPath: ')) {
            photoPath = line.substring(11).trim();
          } else if (line.startsWith('Timestamp: ')) {
            timestamp = DateTime.tryParse(line.substring(11).trim());
          }
        }

        if (name != null && photoPath != null) {
          faces.add({
            'name': name,
            'notes': notes ?? '',
            'photoPath': photoPath,
            'timestamp': timestamp ?? DateTime.now(),
          });
        }
      }

      // Sort by most recent
      faces.sort((a, b) => (b['timestamp'] as DateTime).compareTo(a['timestamp'] as DateTime));
      
      return faces;
    } catch (e) {
      print('❌ Error getting saved faces: $e');
      return [];
    }
  }

  /// Find matching faces using VLM comparison
  Future<List<Map<String, dynamic>>> findMatchingFaces(File queryPhoto) async {
    try {
      final savedFaces = await getAllSavedFaces();
      
      if (savedFaces.isEmpty) {
        print('⚠️ No saved faces to compare against');
        return [];
      }

      // Limit to recent 10 for performance
      final recentFaces = savedFaces.take(10).toList();
      
      print('🔍 Comparing against ${recentFaces.length} saved faces using VLM...');
      
      List<Map<String, dynamic>> matches = [];
      
      // Get description of query photo
      print('📸 Analyzing query photo...');
      final queryDesc = await _describeFace(queryPhoto.path);
      if (queryDesc.isEmpty) {
        print('❌ Failed to analyze query photo');
        return [];
      }
      print('Query face: $queryDesc');
      
      // Compare with each saved face
      for (final savedFace in recentFaces) {
        final savedPhotoFile = File(savedFace['photoPath']);
        if (!await savedPhotoFile.exists()) {
          print('⚠️ Saved photo not found: ${savedFace['photoPath']}');
          continue;
        }
        
        // Get description of saved photo
        final savedDesc = await _describeFace(savedPhotoFile.path);
        if (savedDesc.isEmpty) continue;
        
        // Ask VLM to compare descriptions
        final prompt = '''Compare these two face descriptions:

Person A: $queryDesc
Person B (${savedFace['name']}): $savedDesc

Are they the same person? Answer ONLY YES or NO.''';
        
        final result = await _modelManager.conversationLM.generateCompletion(
          messages: [ChatMessage(content: prompt, role: 'user')],
          params: CactusCompletionParams(maxTokens: 10),
        );
        
        print('🔍 Comparison for ${savedFace['name']}: "${result.response}"');
        
        if (!result.success) {
          print('❌ Comparison failed for ${savedFace['name']}');
          continue;
        }
        
        // Check for match
        final response = result.response.toUpperCase();
        if (response.contains('YES')) {
          matches.add({
            'name': savedFace['name'],
            'notes': savedFace['notes'],
            'photoPath': savedFace['photoPath'],
            'similarity': 0.85,
          });
          print('✅ Match found: ${savedFace['name']}');
        }
      }
      
      return matches;
    } catch (e) {
      print('❌ Error in VLM face matching: $e');
      return [];
    }
  }

  /// Describe a face using VLM
  Future<String> _describeFace(String imagePath) async {
    try {
      final result = await _modelManager.visionLM.generateCompletion(
        messages: [
          ChatMessage(
            content: 'Describe this person\'s face in detail: gender, age range, hair color/style, facial features, glasses, facial hair, etc. Be specific and concise.',
            role: 'user',
            images: [imagePath],
          ),
        ],
        params: CactusCompletionParams(maxTokens: 100),
      );
      
      if (result.success) {
        return result.response.trim();
      }
      return '';
    } catch (e) {
      print('❌ Error describing face: $e');
      return '';
    }
  }

  /// Delete a face record
  Future<void> deleteFace(String name) async {
    // Note: CactusRAG doesn't have direct delete by query
    // We'd need to track document IDs separately
    print('⚠️ Delete not implemented yet');
  }

  void dispose() {
    // VLM is managed by ModelManager
    print('🧹 FaceRecognitionService disposed');
  }
}
