# Lucid — Technical Brief

## Overview

Lucid is a mobile AI assistant that sees the world through your camera, describes it out loud, answers follow-up questions, and remembers what you tell it to.

**Tagline:** A camera that sees, speaks, listens, and remembers.

**Target:** Mobile AI Hackathon (Cactus x Nothing x Hugging Face) — Memory Master Track

---

## Core Features

### 1. Live Vision + Conversation
- Camera feed → on-device vision model → spoken description
- User can ask follow-up questions via voice
- Continuous conversation about what the camera sees
- Real-time, low-latency, works offline

### 2. Memory
- User says "Remember this is [X]"
- App saves: image embedding + text label
- When camera sees similar object later, recalls the saved context
- All stored locally (privacy-first)

---

## User Flow

```
[LIVE MODE]
User points camera → "You're looking at a white pill bottle on a wooden table"
User asks: "What does the label say?" → "It says Ibuprofen 200mg, take 2 tablets"
User says: "Remember this is my headache medication"
App: "Got it. I'll remember this is your headache medication."

[LATER]
User points camera at same bottle → "This is your headache medication. Ibuprofen 200mg."
```

---

## Target Users

- Blind and visually impaired users
- People with memory challenges
- Elderly with cognitive decline
- Anyone who wants a memory assist for the real world

---

## Technical Architecture

```
┌─────────────────────────────────────────────────────────┐
│                      INPUT                              │
│  Camera Frame + Voice (STT)                             │
└─────────────────┬───────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────────────────────────┐
│                   PROCESSING                            │
│                                                         │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐ │
│  │ Cactus VLM  │    │  Embedding  │    │   Vector    │ │
│  │ (Smol/LFM)  │    │   Model     │    │    Store    │ │
│  │             │    │  (Qwen3)    │    │  (SQLite)   │ │
│  └─────────────┘    └─────────────┘    └─────────────┘ │
│        ↓                  ↓                  ↓          │
│   Description      Image Embedding      Memory Match   │
└─────────────────┬───────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────────────────────────┐
│                      OUTPUT                             │
│  Text-to-Speech (Native TTS)                            │
└─────────────────────────────────────────────────────────┘
```

---

## Tech Stack

| Component | Technology |
|-----------|------------|
| Framework | Flutter |
| On-device AI | Cactus SDK |
| Vision Model | Smol-VL or LFM2-VL-450M |
| Embeddings | Qwen3-Embedding-0.6B |
| Local Storage | SQLite + vector embeddings |
| Speech-to-Text | Native (platform STT) |
| Text-to-Speech | Native (platform TTS) |

---

## Cactus SDK Models Reference

From Cactus documentation:

| Model | Completion | Tool Call | Vision | Embed |
|-------|------------|-----------|--------|-------|
| LiquidAI/LFM2-VL-450M | ✓ | ✗ | ✓ | ✓ |
| HuggingFaceTB/SmolLM2-360m-Instruct | ✓ | ✗ | ✗ | ✗ |
| Qwen/Qwen3-0.6B | ✓ | ✓ | ✗ | ✓ |
| Qwen/Qwen3-Embedding-0.6B | ✗ | ✗ | ✗ | ✓ |

**Recommendation:** Use LFM2-VL-450M for vision + description. Use Qwen3-Embedding for image embeddings.

---

## Data Models

```dart
// Saved memory item
class Memory {
  String id;
  String label;           // "my headache medication"
  List<double> embedding; // image embedding vector
  String? notes;          // optional extra context
  DateTime createdAt;
}

// Conversation message
class Message {
  String role;            // "user" or "assistant"
  String content;         // text content
  String? imageBase64;    // optional image attachment
  DateTime timestamp;
}
```

---

## Key Voice Commands

| Voice Command | Action |
|---------------|--------|
| "What do you see?" | Describe current camera view |
| "What does it say?" | Read any text (OCR) |
| "Remember this is [X]" | Save image embedding + label |
| "What is this?" | Check memory, describe if no match |
| Any follow-up question | Continue conversation about current view |

---

## File Structure

```
lucid/
├── lib/
│   ├── main.dart
│   ├── screens/
│   │   └── camera_screen.dart
│   ├── services/
│   │   ├── vision_service.dart    # Cactus VLM wrapper
│   │   ├── memory_service.dart    # Embedding + storage
│   │   ├── speech_service.dart    # STT + TTS
│   │   └── cactus_service.dart    # Cactus SDK init
│   ├── models/
│   │   ├── memory.dart
│   │   └── message.dart
│   └── widgets/
│       └── camera_preview.dart
├── assets/
│   └── models/                    # .gguf model files if needed
└── pubspec.yaml
```

---

## MVP Scope (24-hour hackathon)

### Must Ship
- [ ] Camera preview with live capture
- [ ] VLM describes what it sees
- [ ] TTS speaks the description
- [ ] Voice input for follow-up questions
- [ ] "Remember this" saves embedding + label
- [ ] Basic memory recall when seeing saved object

### Stretch Goals
- [ ] Continuous camera scanning (not just on-demand)
- [ ] Multiple memories with search
- [ ] Confidence score on memory matches

### Out of Scope
- Face detection/recognition
- Calendar/email integration
- Cloud sync
- Smart glasses hardware integration (demo only)

---

## Implementation Notes

### 1. Cactus SDK Setup
Read the quickstart guide first: https://github.com/cactus-compute/cactus

Basic usage:
```cpp
cactus_model_t model = cactus_init("path/to/weight/folder", 2048);

const char* messages = R"([
  {"role": "user", "content": "What do you see in this image?"}
])";

char response[1024];
cactus_complete(model, messages, response, sizeof(response), options, nullptr, nullptr, nullptr);
```

### 2. Model Selection
- Start with Smol-VL (smaller, faster)
- Upgrade to LFM2-VL-450M if quality is lacking
- Both support vision input

### 3. Embedding Similarity
- Use cosine similarity to match new images against saved memories
- Threshold ~0.85 for positive match
- Store embeddings as Float32 arrays in SQLite

```dart
double cosineSimilarity(List<double> a, List<double> b) {
  double dot = 0, normA = 0, normB = 0;
  for (int i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  return dot / (sqrt(normA) * sqrt(normB));
}
```

### 4. Latency Target
- Response should feel conversational
- Target: <2 seconds from capture to speech start
- Use streaming TTS if possible

### 5. Conversation Context
- Keep last 3-5 messages in context for follow-up questions
- Always include current camera frame in vision requests

---

## Future Roadmap

### Interface Modes

| Mode | Description | How It Works |
|------|-------------|--------------|
| **Voice Mode** | Hands-free, always listening | Wake word → continuous conversation |
| **AirPods Mode** | Phone in pocket, audio only | Bluetooth audio in/out, tap to activate |
| **Smart Glasses Mode** | Camera on your face | Glasses stream video → phone processes → audio back |

### Architecture for Future Modes

The core engine stays the same. Future modes just swap the I/O layer:

```
┌─────────────────────────────────────────────────────────┐
│                   INPUT SOURCES                         │
│   Phone Camera │ Webcam │ Smart Glasses │ Screen Share  │
└────────────────────────┬────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────┐
│                    LUCID CORE                           │
│         Vision + Memory + Conversation                  │
└────────────────────────┬────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────┐
│                   OUTPUT TARGETS                        │
│   Phone Speaker │ AirPods │ Glasses Speaker │ Earbuds   │
└─────────────────────────────────────────────────────────┘
```

### Future Integrations
- Calendar (context about your day)
- Email (recall conversations)
- Notes (connect what you see to what you've written)
- Location (remember places)

---

## Demo Strategy

For the hackathon demo:

1. **Phone demo** — Show the core loop working
2. **Webcam option** — Easier to show on stage, big screen
3. **Pre-recorded POV** — Backup if live demo is risky

### Demo Script (60 seconds)

1. Point at object → Lucid describes it
2. Ask follow-up question → Lucid answers
3. Say "Remember this is my [X]" → Lucid confirms
4. Point at same object later → Lucid recalls

### Pitch Angle

"We built the brain. It works on any eyes."

- Today: Phone
- Tomorrow: Smart glasses, AirPods, wearables
- The AI engine is hardware-agnostic

---

## Resources

- Cactus SDK: https://github.com/cactus-compute/cactus
- Cactus Quickstart: Check Discord channel after registration
- Flutter Camera: https://pub.dev/packages/camera
- Flutter TTS: https://pub.dev/packages/flutter_tts
- Flutter STT: https://pub.dev/packages/speech_to_text
- SQLite for Flutter: https://pub.dev/packages/sqflite

---

## Contact / Team

[Add your team info here]

---

**Built for Mobile AI Hackathon: Cactus x Nothing x Hugging Face**

**Track: Memory Master**