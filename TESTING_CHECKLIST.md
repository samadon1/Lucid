# Lucid - Testing Checklist

## 📱 Initial Launch Tests

### ✅ App Launch
- [ ] App opens without crashing
- [ ] Shows "Lucid - AI Vision Assistant" screen
- [ ] Shows "Initializing..." message

### ✅ Model Downloads (First Time - Takes 10-15 min)
- [ ] Progress indicator shows
- [ ] Status messages update (e.g., "Downloading vision model...")
- [ ] Progress percentage increases
- [ ] All 4 models download successfully:
  - Vision: LFM2-VL-450M (~450MB)
  - Memory: LFM2-ColBERT-350M (~350MB)
  - Conversation: LFM2-1.2B (~1.2GB)
  - Speech: Whisper-Tiny (~75MB)
- [ ] Navigates to Camera screen when complete

## 📷 Camera Screen Tests

### ✅ Camera Initialization
- [ ] Camera preview shows
- [ ] Camera permission granted (or prompts)
- [ ] Image is not distorted
- [ ] Status text shows "Ready"

### ✅ Microphone Access
- [ ] Microphone permission granted (or prompts)
- [ ] Tapping mic button doesn't crash

## 🎤 Voice Command Tests

### Test 1: Basic Voice Input
**Steps:**
1. Tap microphone button
2. Say something (anything)
3. Release

**Expected:**
- [ ] Status changes to "Listening..."
- [ ] Records audio
- [ ] Status changes to "Processing: [your text]"
- [ ] Transcription appears in status

### Test 2: General Analysis
**Steps:**
1. Point camera at any object (e.g., coffee mug)
2. Tap microphone
3. Say: "What do you see?"

**Expected:**
- [ ] Status shows "Analyzing..."
- [ ] Gets description (e.g., "A white coffee mug on a desk")
- [ ] TTS speaks the description
- [ ] Status shows the description text

### Test 3: Save Memory
**Steps:**
1. Point camera at distinctive object (e.g., water bottle)
2. Tap microphone
3. Say: "Remember this is my water bottle"

**Expected:**
- [ ] Status shows "Saving memory: water bottle"
- [ ] TTS says "Got it! Saved as water bottle"
- [ ] Status shows "Saved: water bottle"
- [ ] No crashes

### Test 4: Recall Memory (Automatic)
**Steps:**
1. Move camera away from saved object
2. Point camera back at same object
3. Wait 2-3 seconds

**Expected:**
- [ ] White card appears at bottom
- [ ] Card shows: "water bottle"
- [ ] Card shows: "Saved: [time ago]"
- [ ] Card shows: "Confidence: [percentage]"

### Test 5: Recall Memory (Voice)
**Steps:**
1. Point camera at saved object
2. Tap microphone
3. Say: "What is this?"

**Expected:**
- [ ] Status shows "Searching memories..."
- [ ] Finds the saved memory
- [ ] TTS says: "This is your water bottle. You saved this [time] ago."
- [ ] Status shows "Found: water bottle"
- [ ] Memory card appears

### Test 6: Ask Questions
**Steps:**
1. Point camera at saved object (e.g., water bottle)
2. Tap microphone
3. Say: "What color is it?"

**Expected:**
- [ ] Status shows "Thinking..."
- [ ] Gets contextual answer
- [ ] TTS speaks answer
- [ ] Status shows response text

### Test 7: No Memory Found
**Steps:**
1. Point camera at new object you haven't saved
2. Tap microphone
3. Say: "What is this?"

**Expected:**
- [ ] Status shows "Searching memories..."
- [ ] TTS says: "I don't recognize this. You can ask me to remember it."
- [ ] Status shows "No memory found"
- [ ] No crash

## 🐛 Edge Cases to Test

### Test 8: Multiple Memories
**Steps:**
1. Save 3-4 different objects:
   - "Remember this is my keys"
   - "Remember this is my phone"
   - "Remember this is my charger"
2. Point at each one and verify recall

**Expected:**
- [ ] Each memory saves successfully
- [ ] Each memory recalls correctly
- [ ] No confusion between similar objects

### Test 9: Similar Objects
**Steps:**
1. Save: "Remember this is my red water bottle"
2. Point at a different water bottle
3. Say: "What is this?"

**Expected:**
- [ ] Either: correctly doesn't match (good threshold)
- [ ] Or: matches with lower confidence (acceptable)
- [ ] No crash

### Test 10: Different Angles
**Steps:**
1. Save object from front view
2. Point at same object from side/back
3. Check if it recalls

**Expected:**
- [ ] Should still recognize (ColBERT is robust)
- [ ] Confidence might be lower but should match
- [ ] If doesn't match: threshold might need adjustment

### Test 11: Different Lighting
**Steps:**
1. Save object in current lighting
2. Move to different lighting (darker/brighter)
3. Check recall

**Expected:**
- [ ] Should still recognize
- [ ] Might need threshold adjustment if fails

### Test 12: Rapid Commands
**Steps:**
1. Tap microphone → Say something → Wait
2. Immediately tap again → Say something else

**Expected:**
- [ ] First command completes
- [ ] Second command processes
- [ ] No crashes or freezes
- [ ] TTS doesn't overlap

## 🎯 Performance Tests

### Response Times
Record actual times:
- [ ] Voice transcription: _____ seconds (expect 1-2s)
- [ ] Image analysis: _____ seconds (expect 1-3s)
- [ ] Memory save: _____ seconds (expect 2-4s)
- [ ] Memory recall: _____ seconds (expect 1-2s)
- [ ] TTS response: _____ (expect instant)

### Memory Usage
- [ ] App doesn't crash after 10+ operations
- [ ] Camera stays responsive
- [ ] No noticeable slowdown over time

## ❌ Error Handling Tests

### Test 13: Silent Input
**Steps:**
1. Tap microphone
2. Say nothing / be very quiet
3. Wait for timeout

**Expected:**
- [ ] TTS says: "I didn't hear anything. Please try again."
- [ ] Returns to ready state
- [ ] No crash

### Test 14: Unclear Speech
**Steps:**
1. Tap microphone
2. Mumble or speak unclearly
3. Wait

**Expected:**
- [ ] Transcribes something (even if wrong)
- [ ] Attempts to process
- [ ] Doesn't crash

### Test 15: App in Background
**Steps:**
1. Open app
2. Press home button
3. Wait 30 seconds
4. Return to app

**Expected:**
- [ ] Camera still works
- [ ] Models still loaded
- [ ] No crash

## 🔧 Threshold Tuning

If memory recall doesn't work well:

**Too Sensitive (false positives):**
```dart
// In memory_service.dart, line ~16
static const double _similarityThreshold = 0.5; // Increase to 0.6-0.7
```

**Not Sensitive Enough (false negatives):**
```dart
// In memory_service.dart, line ~16
static const double _similarityThreshold = 0.5; // Decrease to 0.3-0.4
```

## 📝 Issues Found

Document any issues here:

| Test | Issue | Severity | Notes |
|------|-------|----------|-------|
|  |  |  |  |
|  |  |  |  |
|  |  |  |  |

## ✅ Sign-Off

- [ ] All critical tests passed
- [ ] No major crashes
- [ ] Core workflow (save → recall) works
- [ ] Ready for UI polish
- [ ] Ready for demo preparation

---

**Testing Date:** _________
**Tester:** _________
**Device:** iPhone iOS 26.2
**Build:** Debug
