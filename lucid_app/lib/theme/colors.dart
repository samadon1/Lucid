import 'package:flutter/material.dart';

/// Premium color palette for Lucid
/// Inspired by Linear, Superhuman, and modern SaaS aesthetics
class AppColors {
  AppColors._();

  // Neutral Base (Light Mode Primary)
  static const Color background = Color(0xFFFFFFFF); // Pure white
  static const Color surface = Color(0xFFF3F4F6); // Light gray surface
  static const Color surfaceVariant = Color(0xFFE5E7EB); // Borders, inputs
  static const Color surfaceDim = Color(0xFFF9FAFB); // Very light gray

  // Accent Colors
  static const Color primaryIndigo = Color(0xFF222222); // Black/Dark Gray
  static const Color primaryPurple = Color(0xFF444444); // Gray
  static const Color secondary = Color(0xFF10B981); // Success green
  static const Color error = Color(0xFFEF4444); // Error red
  static const Color warning = Color(0xFFF59E0B); // Warning amber

  // Text Colors
  static const Color textPrimary = Color(0xFF111827); // Rich black text
  static const Color textSecondary = Color(0xFF4B5563); // Gray text
  static const Color textTertiary = Color(0xFF9CA3AF); // Light gray text
  static const Color textDisabled = Color(0xFFD1D5DB); // Disabled text

  // Glass Effects (Ultra Premium Clean Glass)
  static const Color glassFill = Color(0xCCFFFFFF); // 80% white (Frosted)
  static const Color glassStroke = Color(0x1A000000); // 10% black stroke
  static const Color glassDark = Color(0x0D000000); // 5% black tint
  static const double glassBlur = 30.0; // Higher blur for premium feel

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF222222), Color(0xFF444444)], // Minimalist black/gray
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient successGradient = LinearGradient(
    colors: [Color(0xFF10B981), Color(0xFF059669)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient dangerGradient = LinearGradient(
    colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Semantic Colors
  static const Color memoryCardBg = Color(0x14FFFFFF); // Slightly more visible
  static const Color divider = Color(0x1AFFFFFF); // 10% white
  static const Color overlay = Color(0xB3000000); // 70% black

  // Status Colors
  static const Color statusSuccess = secondary;
  static const Color statusWarning = warning;
  static const Color statusError = error;
  static const Color statusInfo = primaryIndigo;

  // Shadows
  static List<BoxShadow> get softShadow => [
        BoxShadow(
          color: Colors.black.withOpacity(0.1),
          blurRadius: 24,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> get mediumShadow => [
        BoxShadow(
          color: Colors.black.withOpacity(0.2),
          blurRadius: 32,
          offset: const Offset(0, 8),
        ),
      ];

  static List<BoxShadow> get largeShadow => [
        BoxShadow(
          color: Colors.black.withOpacity(0.3),
          blurRadius: 48,
          offset: const Offset(0, 12),
        ),
      ];

  // Glow effects for active states
  static List<BoxShadow> get primaryGlow => [
        BoxShadow(
          color: primaryIndigo.withOpacity(0.4),
          blurRadius: 24,
          spreadRadius: 0,
        ),
      ];

  static List<BoxShadow> get successGlow => [
        BoxShadow(
          color: secondary.withOpacity(0.4),
          blurRadius: 24,
          spreadRadius: 0,
        ),
      ];
}
