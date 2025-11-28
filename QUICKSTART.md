# Lucid - Quick Start Guide

## 🚀 Running the App

### 1. Navigate to Project
```bash
cd /Users/mac/Downloads/Lucid/lucid_app
```

### 2. Check Connected Devices
```bash
flutter devices
```

### 3. Run on Your Device
```bash
# For iOS
flutter run

# For macOS (for development testing)
flutter run -d macos

# For specific device
flutter run -d <device-id>
```

### 4. First Launch
- App will show "Lucid - AI Vision Assistant" screen
- Models will download automatically (~2GB, takes 10-15 minutes)
- Progress bar shows download status
- Once complete, camera screen will appear

## 📱 Testing the Core Features

### Test 1: Visual Analysis
1. Point camera at any object
2. Tap the white microphone button
3. Say: "What do you see?"
4. Listen to the description

### Test 2: Save Memory
1. Point camera at a distinctive object (e.g., water bottle)
2. Tap microphone button
3. Say: "Remember this is my water bottle"
4. App will say: "Got it! Saved as water bottle"

### Test 3: Recall Memory
1. Move camera away from the object
2. Point camera back at the same object
3. App should automatically show a white card saying "water bottle"
4. Or tap microphone and say: "What is this?"
5. App should say: "This is your water bottle. You saved this..."

### Test 4: Ask Questions
1. Point camera at the saved object
2. Tap microphone button
3. Ask: "What color is it?"
4. App will analyze and respond

## 🐛 Troubleshooting

### Camera Not Working
```bash
# Check permissions in Settings app
# iOS: Settings > Lucid > Camera
# macOS: System Settings > Privacy & Security > Camera
```

### Microphone Not Working
```bash
# Check permissions in Settings app
# iOS: Settings > Lucid > Microphone
# macOS: System Settings > Privacy & Security > Microphone
```

### Models Not Downloading
- Check internet connection
- Check storage space (need ~3GB free)
- Restart app and try again

### App Crashes on Launch
```bash
# Clean and rebuild
flutter clean
flutter pub get
flutter run
```

## 📝 Voice Commands Reference

| Command | Action |
|---------|--------|
| "Remember this is [label]" | Save current view as memory |
| "What is this?" | Recall saved memory |
| "What do you see?" | Describe current view |
| "What color is it?" | Ask question about current view |
| "Read the label" | Extract text from image |
| Any question ending with ? | Conversational Q&A |

## 🎯 Demo Workflow

### Preparation (Do Before Demo)
```bash
# 1. Run app and let models download
flutter run

# 2. Save 3-4 demo objects:
# - Medication bottle: "Remember this is my headache medication"
# - Keys: "Remember this is my car keys"
# - Water bottle: "Remember this is my water bottle"
# - Phone charger: "Remember this is my phone charger"

# 3. Test recall by pointing at each object
```

### Live Demo Script
1. **Introduction** (30 seconds)
   - "Lucid is an AI vision assistant that remembers what you show it"
   - "It runs 100% on-device for privacy"

2. **Save Demo** (1 minute)
   - Point at medication bottle
   - Say: "Remember this is my headache medication"
   - Show confirmation

3. **Recall Demo** (1 minute)
   - Point at bottle from different angle
   - Show automatic recognition
   - Say: "What is this?"
   - Show response with timestamp

4. **Question Demo** (1 minute)
   - Ask: "What's the recommended dosage?"
   - Show contextual response

5. **Technical Highlight** (30 seconds)
   - "Powered by Liquid AI's LFM2 models"
   - "ColBERT for specialized similarity matching"
   - "No cloud, no internet, complete privacy"

## 🔧 Development Commands

### Code Analysis
```bash
flutter analyze
```

### Run Tests
```bash
flutter test
```

### Build Release
```bash
# iOS
flutter build ios --release

# macOS
flutter build macos --release

# Android
flutter build apk --release
```

### Clean Build
```bash
flutter clean
flutter pub get
flutter run
```

## 📊 Performance Expectations

| Operation | Expected Time |
|-----------|---------------|
| Model initialization (first time) | 10-15 minutes |
| Model initialization (subsequent) | 5-10 seconds |
| Image analysis | 1-3 seconds |
| Voice transcription | 1-2 seconds |
| Memory save | 2-4 seconds |
| Memory recall | 1-2 seconds |
| TTS response | Instant |

## 🎨 Next Steps for UI Polish

Once functionality is verified, enhance UI:

```dart
// 1. Add glassmorphic effects to camera_screen.dart
import 'package:lucid_app/theme/colors.dart';
import 'package:lucid_app/theme/typography.dart';
import 'dart:ui'; // For BackdropFilter

// 2. Replace plain containers with glass containers:
Container(
  decoration: BoxDecoration(
    color: AppColors.glassFill,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(
      color: AppColors.glassStroke,
      width: 1,
    ),
  ),
  child: BackdropFilter(
    filter: ImageFilter.blur(
      sigmaX: AppColors.glassBlur,
      sigmaY: AppColors.glassBlur,
    ),
    child: YourWidget(),
  ),
)

// 3. Add animations with flutter_animate:
import 'package:flutter_animate/flutter_animate.dart';

Widget().animate()
  .fadeIn(duration: 300.ms)
  .slideY(begin: 0.2, end: 0);
```

## 🏆 Success Checklist

Before submitting/demoing:
- [ ] All models downloaded
- [ ] Camera works
- [ ] Microphone works
- [ ] Can save memory
- [ ] Can recall memory
- [ ] Voice commands work
- [ ] TTS speaks responses
- [ ] 3+ demo memories saved
- [ ] Tested in demo lighting
- [ ] Backup video recorded
- [ ] Pitch practiced

## 🆘 Quick Fixes

### "Models not found" error
```bash
# Models might be in wrong location
# Restart app to re-download
```

### "Camera permission denied"
- Go to device Settings
- Find Lucid app
- Enable Camera permission
- Restart app

### "Microphone permission denied"
- Go to device Settings
- Find Lucid app
- Enable Microphone permission
- Restart app

### Memory recall not working
```dart
// Adjust threshold in memory_service.dart
static const double _similarityThreshold = 0.5; // Try 0.3-0.7
```

---

**You're ready to test!** 🎉

Start with: `flutter run` and follow the testing workflow above.
