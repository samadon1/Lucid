# Lucid Live Mode - Implementation Plan

## 🎯 Your Vision (Better UX!)

Instead of tapping microphone button manually:

### Current Flow (Clunky):
```
User opens app → Camera shows → User taps mic → Says command → AI responds
```

### NEW Live Mode Flow (Natural!):
```
User opens app
  ↓
Camera shows + Auto-capture
  ↓
AI: "I see a desk with a laptop and coffee mug. How can I help you?"
  ↓
Automatically listens...
  ↓
User: "Remember this is my favorite mug"
  ↓
AI: "Got it! Saved as favorite mug"
  ↓
Automatically analyzes again...
  ↓
AI: "Still see the mug. Anything else?"
  ↓
Continuous loop...
```

## 🔧 Implementation

### Phase 1: Auto-Describe on Launch
```dart
class LiveCameraScreen extends StatefulWidget {
  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _startLiveMode();  // NEW!
  }

  Future<void> _startLiveMode() async {
    // Wait for camera to be ready
    await Future.delayed(Duration(seconds: 1));

    // Auto-describe what we see
    await _describeAndGreet();

    // Start continuous listening loop
    _startContinuousListening();
  }

  Future<void> _describeAndGreet() async {
    // Capture image
    final imagePath = await _captureImage();

    // Get description
    setState(() => _statusText = 'Looking...');
    final description = await _visionService.analyzeImage(imagePath);

    // Speak it
    await _voiceService.speak(
      "I see $description. How can I help you?"
    );
  }

  Future<void> _startContinuousListening() async {
    while (mounted) {
      // Listen for command
      final command = await _voiceService.listen();

      if (command != null && command.isNotEmpty) {
        // Process command
        await _handleCommand(command);

        // Brief pause
        await Future.delayed(Duration(milliseconds: 500));

        // Auto-describe again
        await _describeAndGreet();
      }

      // Small delay before next listen cycle
      await Future.delayed(Duration(milliseconds: 100));
    }
  }
}
```

### Phase 2: Smart Context Awareness
```dart
// Only describe when scene changes significantly
bool _hasSceneChanged(String newDescription) {
  if (_lastDescription == null) return true;

  // Compare similarity
  return !_areSimilar(_lastDescription!, newDescription);
}

// If scene hasn't changed, just say "I'm still here, what do you need?"
```

### Phase 3: Memory Integration
```dart
Future<void> _describeWithMemory() async {
  final imagePath = await _captureImage();

  // Check for recognized memories first
  final memories = await _memoryService.recallMemory(imagePath);

  if (memories.isNotEmpty) {
    final memory = memories.first;
    await _voiceService.speak(
      "I recognize this! It's your ${memory.userLabel}. "
      "You saved it ${_getTimeAgo(memory.timestamp)}. "
      "What would you like to know?"
    );
  } else {
    // New scene - describe it
    final description = await _visionService.analyzeImage(imagePath);
    await _voiceService.speak(
      "I see $description. How can I help?"
    );
  }
}
```

## 🎨 UI Changes

### Status Indicator States:
- 🟢 "Listening..." (actively recording)
- 🔵 "Looking..." (analyzing image)
- 🟣 "Thinking..." (processing command)
- ⚪ "Ready" (waiting for voice)

### Visual Feedback:
- Pulsing animation on screen edge when listening
- No button needed - always "on"
- Subtle wave animation during speech
- Quick flash when memory recognized

## 🔧 Technical Considerations

### 1. Battery Management
- Only analyze when needed (scene change detection)
- Pause listening when app in background
- Allow user to "sleep" the assistant (tap screen)

### 2. Continuous Listening Fix
The current issue: `transcription = null`

**Problem**: STT recording but getting empty audio
**Solution**:
- Add explicit microphone permission request
- Use `permission_handler` package
- Show permission prompt on first launch

```dart
// Add to initState
Future<void> _requestMicPermission() async {
  final status = await Permission.microphone.request();
  if (!status.isGranted) {
    // Show error
    await _voiceService.speak(
      "I need microphone permission to listen. "
      "Please grant it in Settings."
    );
  }
}
```

### 3. Wake Word (Future)
Instead of continuous listening (battery drain):
- Listen for "Hey Lucid" wake word
- Then activate full listening
- Or: Tap screen to wake

## 🎯 Implementation Priority

### Must Have (Next 30 min):
1. ✅ Fix microphone permission issue
2. ✅ Implement auto-describe on launch
3. ✅ Add "How can I help?" greeting
4. ✅ Test basic flow

### Nice to Have (If time):
5. Scene change detection
6. Continuous listening loop
7. Smart memory recognition greeting
8. Visual feedback improvements

## 🚀 Testing Script

```
1. Open app
   Expected: "I see [room description]. How can I help you?"

2. Say: "Remember this is my desk"
   Expected: "Got it! Saved as desk"
   Expected: Auto-describes again

3. Move camera to different object
   Expected: "I see [new object]. How can I help?"

4. Say: "What is this?"
   Expected: Recognizes if previously saved, or describes

5. Point back at desk
   Expected: "I recognize this! It's your desk. You saved it just now."
```

## 💡 Why This Is Better

**Old way**: Tap → Speak → Wait → Tap → Speak...
**New way**: Open app → Natural conversation!

**Benefits**:
- ✅ More intuitive (like talking to a person)
- ✅ Hands-free (especially important for accessibility!)
- ✅ Faster workflow (no tapping)
- ✅ Better for demo (more impressive!)
- ✅ Aligns with "AI assistant" metaphor

---

**Status**: Ready to implement!
**ETA**: 30-45 minutes
**Priority**: HIGH - This is the killer feature!
