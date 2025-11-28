import 'package:cactus/cactus.dart';
import 'package:uuid/uuid.dart';
import '../models/note.dart';
import 'model_manager.dart';

/// Service for managing text notes with RAG embedding
class NotesService {
  final ModelManager _modelManager;
  final CactusRAG _rag;
  final _uuid = const Uuid();

  NotesService(this._modelManager, this._rag);

  /// Save a new note and add to RAG
  Future<Note> saveNote(String title, String content) async {
    final now = DateTime.now();
    final note = Note(
      id: _uuid.v4(),
      title: title,
      content: content,
      createdAt: now,
      updatedAt: now,
    );

    // Combine title and content for storage
    final text = 'Title: $title\nContent: $content';

    // Store in RAG
    await _rag.storeDocument(
      fileName: note.id,
      filePath: 'notes/${note.id}',
      content: text,
    );

    print('📝 Saved note: $title');
    return note;
  }

  /// Search for notes using semantic search
  Future<List<Note>> searchNotes(String query, {int limit = 5}) async {
    final results = await _rag.search(
      text: query,
      limit: limit,
    );

    final notes = <Note>[];
    for (final result in results) {
      final chunk = result.chunk;
      final doc = chunk.document.target;

      if (doc == null || !doc.filePath.startsWith('notes/')) continue;

      // Parse content back to Note
      final content = chunk.content;
      final titleMatch = RegExp(r'Title: (.+)').firstMatch(content);
      final contentMatch = RegExp(r'Content: (.+)', dotAll: true).firstMatch(content);

      if (titleMatch != null && contentMatch != null) {
        notes.add(Note(
          id: doc.fileName,
          title: titleMatch.group(1)!.trim(),
          content: contentMatch.group(1)!.trim(),
          createdAt: doc.createdAt,
          updatedAt: doc.updatedAt,
        ));
      }
    }

    return notes;
  }

  /// Get all notes (sorted by updated date, newest first)
  Future<List<Note>> getAllNotes() async {
    final documents = await _rag.getAllDocuments();

    // Filter only note documents
    final noteDocs = documents.where((doc) => doc.filePath.startsWith('notes/')).toList();

    final notes = noteDocs.map((doc) {
      if (doc.chunks.isEmpty) return null;

      final content = doc.chunks.first.content;
      final titleMatch = RegExp(r'Title: (.+)').firstMatch(content);
      final contentMatch = RegExp(r'Content: (.+)', dotAll: true).firstMatch(content);

      if (titleMatch == null || contentMatch == null) return null;

      return Note(
        id: doc.fileName,
        title: titleMatch.group(1)!.trim(),
        content: contentMatch.group(1)!.trim(),
        createdAt: doc.createdAt,
        updatedAt: doc.updatedAt,
      );
    }).whereType<Note>().toList();

    // Sort by updatedAt descending
    notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return notes;
  }

  /// Delete a note
  Future<void> deleteNote(String id) async {
    // Note: Cactus RAG doesn't have direct delete by ID yet
    // For now, notes persist until database is cleared
    print('⚠️ Delete note not fully implemented - note will persist in RAG');
  }
}
