# Lucid - AI Vision Assistant Implementation Plan

## Project Overview

**Lucid** is a camera app that sees, speaks, listens, and remembers objects using on-device AI models. It's designed for the Memory Master hackathon track, targeting visually impaired users, elderly care, and memory assistance use cases.

**Tagline**: "A camera that sees, speaks, listens, and remembers"

**Timeline**: 24 hours

**Framework**: Flutter + Cactus SDK

---

## Core Features

### Must-Have (MVP)
1. **Visual Analysis**: Point camera at object → AI describes it
2. **Voice Commands**: Press button → speak commands
3. **Memory Save**: "Remember this is my headache medication" → saves visual memory
4. **Memory Recall**: Point at previously saved object → automatically recognizes it
5. **Conversation**: Ask follow-up questions about what you're looking at
6. **Audio Output**: Speaks all responses via TTS

### Stretch Goals
- Memory list/management UI
- Similarity threshold tuning
- Label text extraction (LFM2-1.2B-Extract)
- Upgrade to LFM2-Audio-1.5B for unified STT+TTS

---

## Model Architecture

### Final Model Selection

| Task | Model | Size | Rationale |
|------|-------|------|-----------|
| **Vision Analysis** | `LFM2-VL-450M-GGUF` | ~450MB | Mobile-optimized multimodal vision |
| **Memory Embeddings** | `LFM2-ColBERT-350M` | ~350MB | **Specialized sentence similarity model** - key differentiator |
| **Conversation** | `LFM2-1.2B-GGUF` | ~1.2GB | General chat, follow-up questions |
| **Speech-to-Text** | `whisper-tiny` | ~75MB | Proven Cactus SDK integration, fast |
| **Text-to-Speech** | Flutter TTS | ~0MB | Platform native, simple |

**Total Download Size: ~2GB**

### Why Liquid AI over Qwen?

✅ **Smaller, faster models** optimized for edge devices
✅ **Task-specific variants** (ColBERT for similarity!)
✅ **Better mobile performance**
✅ **GGUF format** for all models (quantized, efficient)
✅ **Cohesive ecosystem** - impressive demo story

### Why Whisper over LFM2-Audio?

✅ **Proven Cactus SDK integration** (documented examples)
✅ **Much smaller** (75MB vs 1.5GB)
✅ **Lower risk** for 24-hour hackathon
⚠️ Can upgrade to LFM2-Audio-1.5B as stretch goal if time permits

### Key Advantage: LFM2-ColBERT-350M

This specialized **sentence similarity model** is the secret weapon for memory matching:

- Purpose-built for semantic similarity (not general embeddings)
- Better at matching "white bottle" vs "white container with blue cap"
- More robust to different angles, lighting, and phrasings
- Higher accuracy in memory recall → better demo

**Example:**
```
General embeddings (Qwen):
  "white bottle with blue cap" vs "white container with lid"
  → Similarity: ~0.72 (might miss)

ColBERT (LFM2):
  "white bottle with blue cap" vs "white container with lid"
  → Similarity: ~0.89 (strong match!)

Why? ColBERT understands:
  "bottle" ≈ "container"
  "cap" ≈ "lid"
  Context preserved
```

---

## System Architecture

```
┌─────────────────────────────────────────────┐
│           Flutter UI Layer                   │
│  • Camera Preview (full screen)              │
│  • Voice Button (bottom center)              │
│  • Status Indicator (top)                    │
│  • Memory List Screen                        │
└───────────────┬─────────────────────────────┘
                │
┌───────────────▼─────────────────────────────┐
│        Core Services (Singleton)             │
│                                              │
│  ┌──────────────┐  ┌──────────────┐        │
│  │ VisionService│  │MemoryService │        │
│  │              │  │              │        │
│  │ LFM2-VL     │  │ CactusRAG +  │        │
│  │ 450M        │  │ ColBERT      │        │
│  └──────────────┘  └──────────────┘        │
│                                              │
│  ┌──────────────┐  ┌──────────────┐        │
│  │ VoiceService │  │ ConversationS│        │
│  │              │  │              │        │
│  │ Whisper-Tiny│  │ LFM2-1.2B    │        │
│  │ + FlutterTTS │  │              │        │
│  └──────────────┘  └──────────────┘        │
│                                              │
│  ┌──────────────────────────────┐          │
│  │  CommandParser               │          │
│  │  (Voice command detection)   │          │
│  └──────────────────────────────┘          │
└─────────────────────────────────────────────┘
```

---

## User Flows

### Flow 1: Save Memory

```
1. User points camera at object (e.g., medication bottle)
2. User presses voice button
3. User says: "Remember this is my headache medication"
4. System:
   a. Captures image from camera
   b. Analyzes image with VisionService (LFM2-VL-450M)
      → Returns: "white pill bottle with blue cap and red label"
   c. Parses voice command → extracts label "headache medication"
   d. Stores in MemoryService:
      - Document content: "headache medication: white pill bottle with blue cap"
      - Generates embedding with ColBERT
      - Saves to CactusRAG (ObjectBox)
      - Saves image path + metadata to SharedPreferences
5. Speaks: "Got it! Saved as headache medication"
```

### Flow 2: Recall Memory

```
1. User points camera at same object (different angle/lighting)
2. System automatically (or on tap):
   a. Captures image
   b. Analyzes with VisionService
      → Returns: "white bottle with blue lid"
   c. Generates embedding with ColBERT
   d. Searches CactusRAG for similar memories
   e. Finds match (distance < 0.5 threshold)
      → Matched document: "headache medication: white pill bottle..."
3. Speaks: "This is your headache medication. You saved this yesterday."
4. Shows matched memory card in UI with confidence %
```

### Flow 3: Ask Questions

```
1. User looking at remembered object (medication bottle)
2. User presses voice button
3. User asks: "What's the recommended dosage?"
4. System:
   a. Transcribes with VoiceService (Whisper-Tiny)
   b. Gets current camera analysis + memory context
   c. Sends to ConversationService with context:
      - System: "Context: headache medication, white pill bottle with blue cap..."
      - User: "What's the recommended dosage?"
   d. LFM2-1.2B analyzes image (focusing on label text)
      → Returns: "The label indicates 500mg tablets, take one every 6 hours"
5. Speaks: "The label says take one tablet every 6 hours"
```

---

## Project Structure

```
lucid/
├── lib/
│   ├── main.dart                    # App entry, route setup
│   │
│   ├── models/
│   │   ├── memory.dart              # Memory data class
│   │   ├── command.dart             # Voice command types
│   │   └── app_state.dart           # Global app state
│   │
│   ├── services/
│   │   ├── model_manager.dart       # Initialize all Cactus models
│   │   ├── camera_service.dart      # Camera capture
│   │   ├── vision_service.dart      # Image analysis (LFM2-VL)
│   │   ├── memory_service.dart      # RAG + embeddings (ColBERT)
│   │   ├── voice_service.dart       # STT (Whisper) + TTS
│   │   ├── conversation_service.dart # Chat (LFM2-1.2B)
│   │   └── command_parser.dart      # Parse "Remember this is..."
│   │
│   ├── screens/
│   │   ├── camera_screen.dart       # Main camera view
│   │   ├── memory_list_screen.dart  # View saved memories
│   │   └── settings_screen.dart     # Threshold tuning, etc.
│   │
│   └── widgets/
│       ├── voice_button.dart        # Recording button UI
│       ├── status_indicator.dart    # Loading/processing states
│       └── memory_card.dart         # Memory display card
│
├── android/
│   └── app/src/main/AndroidManifest.xml  # Permissions
│
├── ios/
│   └── Runner/Info.plist            # Permissions
│
├── macos/
│   └── Runner/*.entitlements        # Permissions
│
└── pubspec.yaml                     # Dependencies
```

---

## Dependencies

### pubspec.yaml

```yaml
dependencies:
  flutter:
    sdk: flutter
  cactus: ^latest              # Main AI SDK
  camera: ^latest              # Camera access
  flutter_tts: ^latest         # Text-to-speech
  shared_preferences: ^latest  # Local metadata storage
  path_provider: ^latest       # File paths
  permission_handler: ^latest  # Runtime permissions
```

---

## Platform Setup

### Android (android/app/src/main/AndroidManifest.xml)

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.CAMERA" />
```

### iOS (ios/Runner/Info.plist)

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Lucid needs microphone access for voice commands</string>
<key>NSCameraUsageDescription</key>
<string>Lucid needs camera access to analyze objects</string>
```

### macOS (macos/Runner/*.entitlements)

```xml
<!-- Network access for model downloads -->
<key>com.apple.security.network.client</key>
<true/>
<!-- Microphone access for speech-to-text -->
<key>com.apple.security.device.microphone</key>
<true/>
<!-- Camera access -->
<key>com.apple.security.device.camera</key>
<true/>
```

---

## Key Implementation Details

### Memory Storage Strategy

```dart
// models/memory.dart
class Memory {
  final String id;
  final String imagePath;           // Local file path to saved image
  final String userLabel;            // "headache medication"
  final String visionDescription;    // "white bottle with blue cap"
  final DateTime timestamp;
  final int ragDocumentId;           // CactusRAG document ID
  final double? lastMatchScore;      // For showing confidence in UI
}

// In CactusRAG, store combined content:
// document.content = "$userLabel: $visionDescription"
// This combines user intent + visual features for better matching
```

### Voice Command Parsing

```dart
// services/command_parser.dart
class CommandParser {
  MemoryCommand? parse(String transcription) {
    final text = transcription.toLowerCase().trim();

    // Pattern 1: "remember this is X"
    if (text.contains('remember')) {
      final match = RegExp(r'remember.*this is (.+)').firstMatch(text);
      if (match != null) {
        return MemoryCommand.save(label: match.group(1)!.trim());
      }
    }

    // Pattern 2: "what is this" → recall mode
    if (text.contains('what is') || text.contains('what\'s this')) {
      return MemoryCommand.recall();
    }

    // Pattern 3: Question → conversation mode
    if (text.endsWith('?')) {
      return MemoryCommand.question(query: text);
    }

    // Default: general vision analysis
    return MemoryCommand.analyze(prompt: text);
  }
}
```

### Model Initialization

```dart
// services/model_manager.dart
class ModelManager {
  late CactusLM visionLM;
  late CactusLM memoryLM;      // Specialized ColBERT for similarity!
  late CactusLM conversationLM;
  late CactusSTT stt;
  late CactusRAG rag;

  Future<void> initialize() async {
    // Download models in parallel
    await Future.wait([
      _initVision(),
      _initMemory(),
      _initConversation(),
      _initSTT(),
    ]);

    // Initialize RAG with ColBERT embeddings
    await _initRAG();
  }

  Future<void> _initVision() async {
    visionLM = CactusLM();
    await visionLM.downloadModel(model: "lfm2-vl-450m-gguf");
    await visionLM.initializeModel();
  }

  Future<void> _initMemory() async {
    memoryLM = CactusLM();
    await memoryLM.downloadModel(model: "lfm2-colbert-350m");
    await memoryLM.initializeModel();
  }

  Future<void> _initConversation() async {
    conversationLM = CactusLM();
    await conversationLM.downloadModel(model: "lfm2-1.2b-gguf");
    await conversationLM.initializeModel();
  }

  Future<void> _initSTT() async {
    stt = CactusSTT();
    await stt.download(model: "whisper-tiny");
    await stt.init(model: "whisper-tiny");
  }

  Future<void> _initRAG() async {
    rag = CactusRAG();
    await rag.initialize();

    // Use ColBERT for embedding generation
    rag.setEmbeddingGenerator((text) async {
      final result = await memoryLM.generateEmbedding(text: text);
      return result.embeddings;
    });

    // Configure chunking (optional, defaults are fine)
    rag.setChunking(chunkSize: 512, chunkOverlap: 64);
  }

  void dispose() {
    visionLM.unload();
    memoryLM.unload();
    conversationLM.unload();
    stt.dispose();
    rag.close();
  }
}
```

### Similarity Threshold Strategy

```dart
// Start with conservative threshold
double similarityThreshold = 0.5; // Distance < 0.5 = match

// CactusRAG returns squared Euclidean distance
// Lower distance = more similar
// Typical ranges:
// - 0.0 - 0.3: Very similar (same object, different angle)
// - 0.3 - 0.7: Somewhat similar (same category)
// - 0.7+: Different objects

// Allow user to tune in settings
// Show confidence percentage in UI: (1 - distance) * 100
```

### Conversation Context Management

```dart
// services/conversation_service.dart
class ConversationService {
  final CactusLM _lm;
  final List<ChatMessage> _history = [];
  final int maxHistory = 5;

  Future<String> respond(String query, {Memory? memoryContext}) async {
    // Add memory context as system message
    if (memoryContext != null) {
      _history.add(ChatMessage(
        content: "Context: ${memoryContext.userLabel}. "
                 "Visual: ${memoryContext.visionDescription}",
        role: "system"
      ));
    }

    // Add user query
    _history.add(ChatMessage(content: query, role: "user"));

    // Generate response
    final result = await _lm.generateCompletion(
      messages: _history,
      params: CactusCompletionParams(maxTokens: 150)
    );

    // Add assistant response
    _history.add(ChatMessage(content: result.response, role: "assistant"));

    // Keep last N messages
    while (_history.length > maxHistory) {
      _history.removeAt(0);
    }

    return result.response;
  }

  void reset() {
    _history.clear(); // Call on new camera capture
  }
}
```

---

## 24-Hour Implementation Timeline

### Phase 1: Setup & Models (Hours 1-2)
- [ ] Create Flutter project: `flutter create lucid`
- [ ] Add dependencies to pubspec.yaml
- [ ] Configure platform permissions (Android/iOS/macOS)
- [ ] Create basic project structure (folders for models/, services/, screens/, widgets/)
- [ ] Download all models in parallel (visionLM, memoryLM, conversationLM, STT)
- [ ] Initialize ModelManager singleton
- [ ] Verify models load successfully with test print statements

### Phase 2: Vision Pipeline (Hours 3-6)
- [ ] Implement CameraService: Live preview + capture frames
- [ ] Implement VisionService: Analyze images with LFM2-VL-450M
- [ ] Test basic flow: Capture → Analyze → Get description
- [ ] Integrate Flutter TTS: Speak vision results
- [ ] Create basic CameraScreen UI: Camera preview + status indicator
- [ ] Test end-to-end: Point at object → Hear description

### Phase 3: Memory System (Hours 7-10)
- [ ] Implement MemoryService with CactusRAG + ColBERT
- [ ] Implement storeMemory():
  - Generate vision description from captured image
  - Store in RAG with user label
  - Save image path + metadata to SharedPreferences
- [ ] Implement recallMemory():
  - Generate embedding for current camera view
  - Search RAG with similarity threshold
  - Return top matches
- [ ] Implement CommandParser: Detect "Remember this is X" pattern
- [ ] Test memory workflow: Save → Recall (same object, different angle)

### Phase 4: Voice Interaction (Hours 11-14)
- [ ] Implement VoiceService: Whisper-Tiny integration
- [ ] Implement listenForCommand() with recording UI feedback
- [ ] Implement ConversationService: LFM2-1.2B chat
- [ ] Add conversation context management (last 5 messages)
- [ ] Add memory context injection for follow-up questions
- [ ] Test voice flow: Voice → Transcribe → Respond → Speak

### Phase 5: UI Integration (Hours 15-18)
- [ ] Build main CameraScreen:
  - Full-screen camera preview
  - Voice button (bottom center) with recording animation
  - Status overlay (listening/analyzing/speaking states)
  - Memory match notification card
- [ ] Build MemoryListScreen:
  - Grid view of saved memories
  - Show thumbnail + label + timestamp
  - Delete functionality
- [ ] Build SettingsScreen:
  - Similarity threshold slider
  - Model status indicators
  - Clear all memories button
- [ ] Polish UI: Loading states, error messages, smooth animations

### Phase 6: Testing & Polish (Hours 19-22)
- [ ] Integration testing:
  - Full save → recall flow with multiple objects
  - Test different lighting conditions and angles
  - Test voice command variations
  - Test follow-up questions
- [ ] Error handling:
  - Camera permission denied
  - Microphone permission denied
  - Model loading failures
  - Network errors during download
- [ ] Performance optimization:
  - Image compression before analysis
  - Cancel in-flight requests on new input
  - Memory cleanup (unload unused models)
- [ ] UI polish: Smooth transitions, helpful error messages

### Phase 7: Demo Preparation (Hours 23-24)
- [ ] Prepare demo objects:
  - Pre-save 3-4 memories (medication bottle, keys, water bottle, charger)
  - Test in demo environment lighting conditions
  - Verify recall accuracy
- [ ] Create demo script:
  - Scenario 1: "Save memory" (medication bottle)
  - Scenario 2: "Recall memory" (point at bottle from different angle)
  - Scenario 3: "Ask question" ("What's the dosage?")
- [ ] Record backup video (in case live demo fails)
- [ ] Practice pitch:
  - Problem statement (memory assistance, accessibility)
  - Technical approach (all Liquid AI models, on-device)
  - Memory Master track alignment
  - Future vision (smart glasses, AirPods mode)

---

## UI/UX Design

### Camera Screen Layout

```
┌─────────────────────────────────┐
│  [Status: Listening... 🎤]      │ ← Top overlay (status indicator)
│                                 │
│                                 │
│     Camera Preview              │
│     (Full Screen)               │
│                                 │
│  ┌─────────────────────────┐   │
│  │ 💊 Headache Medication   │   │ ← Memory match card (if found)
│  │ Saved: Yesterday 3:42 PM │   │
│  │ Confidence: 89%          │   │
│  │ [View] [Forget]          │   │
│  └─────────────────────────┘   │
│                                 │
│          [ 🎤 ]                 │ ← Voice button (bottom center)
│    [Memories]  [Settings]       │ ← Bottom navigation
└─────────────────────────────────┘
```

### Voice Button States

- **Idle**: White circle with microphone icon
- **Listening**: Pulsing red circle with waveform animation
- **Processing**: Spinning loader with "Analyzing..." text
- **Speaking**: Blue circle with speaker icon + sound waves

### Memory Match Card

Shows when object is recognized:
```
┌─────────────────────────────────┐
│  💊 Headache Medication          │
│  Saved: Yesterday at 3:42 PM    │
│  Confidence: 89%                │
│  "White pill bottle with..."    │
│  [View Full] [Forget This]      │
└─────────────────────────────────┘
```

---

## Risk Mitigation

### Top Risks & Solutions

| Risk | Likelihood | Impact | Mitigation Strategy |
|------|-----------|--------|---------------------|
| **Models too slow on device** | Medium | High | Test on target device in Hour 3; fallback to smaller models if needed; use streaming for progressive output |
| **Poor memory matching accuracy** | Medium | High | Use ColBERT (specialized!); allow threshold tuning in settings; combine visual + text embeddings |
| **Voice command ambiguity** | Medium | Medium | Simple keyword matching ("remember"); confirmation prompts; show parsed intent in UI |
| **Model download failures** | Low | High | Retry logic with exponential backoff; show clear progress; allow partial initialization |
| **Camera permission denied** | Low | Medium | Clear permission request screens; fallback to file upload mode |
| **Out of memory crashes** | Medium | High | Unload unused models; compress images before processing; limit conversation history size |
| **Live demo fails** | Medium | Critical | Pre-recorded video backup; planted demo objects; practice run in similar environment |
| **LFM2-Audio integration issues** | High | Low | Already mitigated by using Whisper (proven) instead |

---

## Success Criteria

### MVP Complete Checklist

✅ **Core Features Working:**
- [ ] Camera captures and analyzes images with LFM2-VL-450M
- [ ] Voice button records and transcribes commands with Whisper-Tiny
- [ ] "Remember this is X" saves memory to CactusRAG
- [ ] Memory recall finds similar objects via ColBERT similarity
- [ ] Follow-up questions use conversation context with LFM2-1.2B
- [ ] Text-to-speech speaks all responses clearly

✅ **Demo Ready:**
- [ ] 3+ saved memories working reliably
- [ ] Live demo script tested and practiced
- [ ] Backup video recorded
- [ ] Pitch deck/talking points prepared

✅ **Technical Quality:**
- [ ] All 3 Liquid AI models integrated (VL, ColBERT, 1.2B)
- [ ] No crashes on happy path
- [ ] Responsive UI (< 2s per operation)
- [ ] Works offline (no internet required after initial download)
- [ ] Clean error handling and user feedback

---

## Memory Master Track Alignment

### How Lucid Addresses the Track

✅ **Novel Memory Mechanism**
- Visual embeddings + RAG for object recall
- Automatic recognition without manual tagging
- Semantic similarity matching (ColBERT)

✅ **Practical Use Cases**
- Visually impaired assistance
- Elderly care and memory support
- General memory augmentation

✅ **Technical Innovation**
- ColBERT specialized similarity vs general embeddings
- All on-device processing (privacy-first)
- Multi-modal: vision + speech + memory

✅ **Scalability**
- Easy to add unlimited memories
- No backend infrastructure needed
- Efficient vector search with ObjectBox

### Pitch Angle

> "Traditional memory apps rely on manual text entry or tagging. Lucid uses AI vision to automatically understand what you're looking at and creates visual memories. Just point your camera and say 'remember this is my medication' - Lucid will recognize it next time, even from different angles or lighting. All powered by Liquid AI's cutting-edge foundation models, running entirely on your device for privacy and offline capability."

**Key Differentiators:**
1. **Visual-first** memory (vs text-based apps)
2. **Automatic recognition** (vs manual tagging)
3. **Specialized AI** (ColBERT for similarity)
4. **On-device privacy** (vs cloud processing)
5. **Conversational interface** (accessible to all)

---

## Future Enhancements (Post-Hackathon)

If MVP succeeds and there's interest in continuing development:

### Near-term (1-2 months)
1. **Memory Categories**: Auto-group similar items ("all medications", "keys", etc.)
2. **Temporal Context**: "Where did I last see my keys?" (location + timestamp)
3. **Export/Import**: Backup memories to cloud storage
4. **Multi-language**: Leverage Whisper's 99-language support

### Medium-term (3-6 months)
5. **Smart Glasses Integration**: Hands-free with Meta Ray-Ban, Brilliant Labs
6. **AirPods Mode**: Audio-only interface for true accessibility
7. **Multi-object Scenes**: Remember entire rooms/desk layouts
8. **Family Sharing**: Share memories with caregivers

### Long-term (6+ months)
9. **Specialized Models**:
   - LFM2-1.2B-RAG for better Q&A
   - LFM2-1.2B-Extract for reading labels/text
   - LFM2-Audio-1.5B for unified audio I/O
10. **AR Overlay**: Real-time object recognition with AR labels
11. **Proactive Reminders**: "You haven't seen your keys in 2 days"
12. **Health Integration**: Medication schedules, dosage tracking

---

## Technical Advantages

### Why This Stack Wins

1. **All Liquid AI LFM2 Models**
   → Cohesive story, cutting-edge technology, impressive branding

2. **ColBERT for Memory Matching**
   → Purpose-built similarity beats general embeddings by ~20%

3. **On-Device Everything**
   → Privacy-preserving, offline-capable, low latency

4. **GGUF Quantization**
   → Efficient models fit on mobile devices

5. **CactusRAG Integration**
   → Auto chunking, embeddings, ObjectBox storage - batteries included

6. **Sub-100ms Latency Potential**
   → Real-time feel for all operations (if using LFM2-Audio later)

7. **Flutter Cross-Platform**
   → iOS + Android + macOS from single codebase

### Competitive Advantages vs Other Solutions

| Feature | Lucid | Text-based Memory Apps | Cloud AI Apps |
|---------|-------|----------------------|---------------|
| **Visual Memory** | ✅ Automatic | ❌ Manual tagging | ⚠️ Some support |
| **Privacy** | ✅ On-device | ✅ Local | ❌ Cloud processing |
| **Offline** | ✅ Fully | ✅ Fully | ❌ Requires internet |
| **Accessibility** | ✅ Voice + Vision | ❌ Text only | ⚠️ Varies |
| **Similarity Matching** | ✅ ColBERT (specialized) | ❌ Keyword only | ⚠️ General embeddings |
| **Speed** | ✅ < 2s | ✅ Instant | ⚠️ 3-10s (network) |

---

## Pre-Implementation Checklist

### Development Environment
- [ ] Flutter SDK installed and up-to-date (`flutter --version`)
- [ ] Android Studio / Xcode set up for target platforms
- [ ] Device/emulator ready for testing (iPhone 12+ or Android flagship recommended)
- [ ] Git initialized in project directory
- [ ] Code editor configured (VS Code with Flutter/Dart extensions)

### Resources
- [ ] Stable internet connection for model downloads (~2GB)
- [ ] At least 10GB free storage on development machine
- [ ] At least 5GB free storage on test device
- [ ] Cactus SDK documentation bookmarked
- [ ] Liquid AI Hugging Face page bookmarked

### Physical Prep
- [ ] 24 hours blocked on calendar
- [ ] Demo objects gathered (pill bottle, keys, etc.)
- [ ] Well-lit demo environment identified
- [ ] Coffee/snacks/meals planned
- [ ] Backup laptop/charger ready

### Hackathon Logistics
- [ ] Submission deadline confirmed
- [ ] Demo format understood (live vs video)
- [ ] Pitch time limit confirmed (usually 3-5 min)
- [ ] Judging criteria reviewed
- [ ] Team roles assigned (if team project)

---

## Additional Resources

### Cactus SDK Documentation
- Main docs: https://docs.cactus.ai
- Flutter plugin: https://github.com/cactus-compute/cactus-flutter
- HuggingFace models: https://huggingface.co/cactus

### Liquid AI Resources
- Company site: https://www.liquid.ai
- HuggingFace org: https://huggingface.co/LiquidAI
- LFM2 models: https://huggingface.co/LiquidAI/models
- LFM2-Audio blog: https://www.liquid.ai/blog/lfm2-audio-an-end-to-end-audio-foundation-model

### Flutter Resources
- Camera plugin: https://pub.dev/packages/camera
- Flutter TTS: https://pub.dev/packages/flutter_tts
- SharedPreferences: https://pub.dev/packages/shared_preferences

---

## Contact & Support

**Project**: Lucid - AI Vision Assistant
**Timeline**: 24 hours
**Track**: Memory Master
**Tech Stack**: Flutter + Cactus SDK + Liquid AI LFM2 Models

---

*Last Updated: 2025-11-26*
*Status: Planning Phase - Ready for Implementation*
