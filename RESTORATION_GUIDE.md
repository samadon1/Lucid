# Camera Screen Restoration Guide

## Current State (After git checkout)
- Has OLD code with AirPods icon, "Voice Mode", "Activate" button
- Missing: Gmail icon, Notes button, Coming Soon modal, Settings navigation
- Missing: `dart:ui as ui` import

## Required Changes:

### 1. Import Section (lines 1-20)
- Change `import 'dart:ui';` to `import 'dart:ui' as ui;`
- Add imports for: SettingsScreen, NotesScreen, ARSpatialScreen, AppColors, AppTypography

### 2. PageView (line ~398)
- Replace `_buildHUDPage()` with `const ARSpatialScreen()`

### 3. Integrations Page (_buildVoiceOnlyPage)
- Change title from "Voice Mode" to "Integrations"
- Replace AirPods icon with Gmail icon in white circle
- Replace yellow voice button with circular Notes button (AR mic style)
- Make settings icon functional (navigate to SettingsScreen)

### 4. Smart Glasses Page (_buildSmartGlassesPage)
- Replace yellow "Activate" button with circular Coming Soon button (AR mic style, bluetooth icon)
- Make settings icon functional (navigate to SettingsScreen)
- Move memory match indicator ABOVE button (remove extra Spacer after button)
- Add `_showComingSoonModal()` method

### 5. All ImageFilter references
- Change `ImageFilter.blur` to `ui.ImageFilter.blur`

## Key Issue from User:
The bluetooth icon appears too high because there's an extra Spacer() after the button pushing it up.
The "Got it" button in modal has invisible text (needs white color).
