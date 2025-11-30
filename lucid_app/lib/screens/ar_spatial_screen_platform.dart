import 'dart:io';
import 'package:flutter/material.dart';
import 'ar_spatial_screen_ios.dart';
import 'ar_spatial_screen_android.dart';

/// Platform-aware AR Spatial Screen
/// Routes to iOS (ARKit) or Android (ARCore) implementation
class ARSpatialScreen extends StatelessWidget {
  const ARSpatialScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (Platform.isIOS) {
      return const ARSpatialScreenIOS();
    } else if (Platform.isAndroid) {
      return const ARSpatialScreenAndroid();
    } else {
      // Fallback for unsupported platforms
      return Scaffold(
        appBar: AppBar(title: const Text('AR Not Supported')),
        body: const Center(
          child: Text('AR is only supported on iOS and Android'),
        ),
      );
    }
  }
}
