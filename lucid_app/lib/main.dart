import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'services/model_manager.dart';
import 'screens/camera_screen.dart';
import 'theme/colors.dart';
import 'theme/typography.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait mode
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  
  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.background,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(const LucidApp());
}

class LucidApp extends StatelessWidget {
  const LucidApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lucid',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: const ColorScheme.light(
          primary: AppColors.primaryIndigo,
          secondary: AppColors.secondary,
          surface: AppColors.surface,
          error: AppColors.error,
        ),
        useMaterial3: true,
      ),
      home: const InitializationScreen(),
    );
  }
}

class InitializationScreen extends StatefulWidget {
  const InitializationScreen({super.key});

  @override
  State<InitializationScreen> createState() => _InitializationScreenState();
}

class _InitializationScreenState extends State<InitializationScreen> {
  final _modelManager = ModelManager();
  String _status = 'Initializing...';
  double? _progress;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initializeModels();
  }

  Future<void> _initializeModels() async {
    try {
      await _modelManager.initialize(
        onProgress: (step, progress) {
          if (mounted) {
            setState(() {
              _status = step;
              _progress = progress;
            });
          }
        },
      );

      // Navigate to camera screen with PageView carousel once initialized
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => const CameraScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 800),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _status = 'Error: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white,
              Color(0xFFF3F4F6), // Light gray
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(),

              // Logo / Title
              Column(
                children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primaryIndigo.withOpacity(0.1),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primaryIndigo.withOpacity(0.2),
                            blurRadius: 40,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.visibility_outlined, 
                        size: 64, 
                        color: AppColors.primaryIndigo
                      ),
                    ).animate().scale(duration: 800.ms, curve: Curves.easeOutBack),
                    
                    const SizedBox(height: 32),
                    
                    Text(
                      'Lucid',
                      style: AppTypography.displayLarge.copyWith(
                        fontSize: 48,
                        letterSpacing: 4,
                      ),
                    ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.2, end: 0),
                    
                    const SizedBox(height: 12),
                    
                    Text(
                      'AI VISION ASSISTANT',
                      style: AppTypography.labelMedium.copyWith(
                        letterSpacing: 3,
                        color: AppColors.textSecondary,
                      ),
                    ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.2, end: 0),
                  ],
                ),
                
                const Spacer(),

                // Progress Card
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: AppColors.glassFill,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: AppColors.glassStroke,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          if (!_hasError) ...[
                            SizedBox(
                              width: 64,
                              height: 64,
                              child: CircularProgressIndicator(
                                value: _progress,
                                color: AppColors.primaryIndigo,
                                strokeWidth: 4,
                                backgroundColor: AppColors.textTertiary.withOpacity(0.2),
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],

                          Text(
                            _status,
                            style: AppTypography.bodyMedium.copyWith(
                              color: _hasError ? AppColors.error : AppColors.textPrimary,
                            ),
                            textAlign: TextAlign.center,
                          ),

                          if (_hasError) ...[
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  _hasError = false;
                                  _status = 'Initializing...';
                                  _progress = null;
                                });
                                _initializeModels();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryIndigo,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 32,
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: const Text('Retry'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ).animate().fadeIn(delay: 600.ms).slideY(begin: 0.2, end: 0),
                ),

                const SizedBox(height: 32),

                // Info text
                if (!_hasError)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      'First launch may take a few minutes\nto download AI models (~2GB)',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textTertiary,
                      ),
                      textAlign: TextAlign.center,
                    ).animate().fadeIn(delay: 800.ms),
                  ),

                const SizedBox(height: 20),
              ],
            ),
        ),
      ),
    );
  }
}
