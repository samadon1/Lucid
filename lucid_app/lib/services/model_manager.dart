import 'package:cactus/cactus.dart';

/// Manages all Cactus AI models and their initialization
class ModelManager {
  static final ModelManager _instance = ModelManager._internal();
  factory ModelManager() => _instance;
  ModelManager._internal();

  // Model instances
  CactusLM? _visionLM;  // Vision Language Model
  CactusLM? _memoryLM;
  CactusLM? _conversationLM;
  CactusSTT? _stt;
  CactusRAG? _rag;

  // Getters
  CactusLM get visionLM => _visionLM!;
  CactusLM get memoryLM => _memoryLM!;
  CactusLM get conversationLM => _conversationLM!;
  CactusSTT get stt => _stt!;
  CactusRAG get rag => _rag!;

  bool get isInitialized =>
      _visionLM != null &&
      _memoryLM != null &&
      _conversationLM != null &&
      _stt != null &&
      _rag != null;

  /// Initialize all models (download + load)
  Future<void> initialize({
    Function(String step, double? progress)? onProgress,
  }) async {
    try {
      // Initialize vision model - try to find a vision-capable model
      onProgress?.call('Fetching available models...', null);
      _visionLM = CactusLM();

      // Get available models and find one with vision support
      final models = await _visionLM!.getModels();

      // DEBUG: Print all available models to see if audio models exist
      print('=== ALL AVAILABLE MODELS ===');
      for (final model in models) {
        print('Model: ${model.slug} (${model.sizeMb}MB) - Vision: ${model.supportsVision}');
      }
      print('===========================');

      // DEBUG: Try to load OuteTTS manually
      print('DEBUG: Attempting to load OuteTTS model...');
      try {
        final ttsModel = CactusLM();
        await ttsModel.downloadModel(
          model: 'outetts-0.2-500m',
          downloadProcessCallback: (progress, status, isError) {
            print('OuteTTS download: $status ${progress != null ? "(${(progress * 100).toInt()}%)" : ""}');
          },
        );
        print('DEBUG: OuteTTS downloaded successfully!');
      } catch (e) {
        print('DEBUG: OuteTTS not available in Cactus: $e');
      }

      final visionModels = models.where((m) => m.supportsVision).toList();

      if (visionModels.isEmpty) {
        throw Exception('No vision-capable models available');
      }

      // Use the first available vision model (or prioritize LFM2-VL if available)
      final visionModel = visionModels.firstWhere(
        (m) => m.slug.contains('lfm2-vl'),
        orElse: () => visionModels.first,
      );

      print('Selected vision model: ${visionModel.slug} (${visionModel.sizeMb}MB)');
      onProgress?.call('Downloading ${visionModel.slug}...', null);

      await _visionLM!.downloadModel(
        model: visionModel.slug,
        downloadProcessCallback: (progress, status, isError) {
          if (!isError) {
            onProgress?.call(status, progress);
          }
        },
      );

      onProgress?.call('Initializing vision model...', null);
      await _visionLM!.initializeModel(
        params: CactusInitParams(model: visionModel.slug),
      );
      print('Vision model initialized: ${visionModel.slug}');
      onProgress?.call('Vision AI ready', 1.0);

      // Use same model for memory and conversation
      _memoryLM = _visionLM;
      _conversationLM = _visionLM;
      onProgress?.call('Models configured', 1.0);

      // Speech-to-text
      onProgress?.call('Downloading speech model...', null);
      _stt = CactusSTT();
      await _stt!.download(
        model: 'whisper-tiny',
        downloadProcessCallback: (progress, status, isError) {
          if (!isError) {
            onProgress?.call(status, progress);
          }
        },
      );
      await _stt!.init(model: 'whisper-tiny');
      onProgress?.call('Speech model ready', 1.0);

      // RAG system
      onProgress?.call('Initializing memory database...', null);
      _rag = CactusRAG();
      await _rag!.initialize();

      // Set up embedding generator for RAG (uses ColBERT)
      _rag!.setEmbeddingGenerator((text) async {
        final result = await _memoryLM!.generateEmbedding(text: text);
        return result.embeddings;
      });

      // Configure chunking
      _rag!.setChunking(chunkSize: 512, chunkOverlap: 64);
      onProgress?.call('Memory database ready', 1.0);

      onProgress?.call('All models initialized!', 1.0);
    } catch (e) {
      print('Error initializing models: $e');
      rethrow;
    }
  }

  /// Dispose of all models
  void dispose() {
    _visionLM?.unload();
    _memoryLM?.unload();
    _conversationLM?.unload();
    _stt?.dispose();
    _rag?.close();
  }
}
