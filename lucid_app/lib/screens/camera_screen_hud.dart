// Smart Glasses HUD Layout
// Peripheral corners, minimal overlays, glanceable info
// Based on Meta Ray-Ban Display principles

Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: Colors.black,
    body: Stack(
      fit: StackFit.expand,
      children: [
        // Camera preview - Full screen unobstructed
        CameraPreview(_cameraController!),

        // TOP-RIGHT: Status indicator (HUD style - peripheral)
        if (_isListening || _isProcessing)
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            right: 16,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.25),
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isListening ? Colors.greenAccent : Colors.white.withOpacity(0.6),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isListening ? 'Listening' : 'Processing',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // BOTTOM-LEFT: Memory match (HUD style - corner overlay)
        if (_matchedMemory != null)
          Positioned(
            bottom: 20,
            left: 16,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 200),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.25),
                      width: 0.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            color: Colors.white.withOpacity(0.7),
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              _matchedMemory!.userLabel,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withOpacity(0.95),
                                letterSpacing: 0.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _getTimeAgo(_matchedMemory!.timestamp),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withOpacity(0.6),
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // BOTTOM-RIGHT: Voice mic (HUD style - corner button)
        Positioned(
          bottom: 20,
          right: 16,
          child: GestureDetector(
            onTap: _handleVoiceTap,
            child: ClipOval(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: _isListening ? 60 : 54,
                  height: _isListening ? 60 : 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(_isListening ? 0.2 : 0.12),
                    border: Border.all(
                      color: Colors.white.withOpacity(_isListening ? 0.4 : 0.25),
                      width: 0.5,
                    ),
                  ),
                  child: Icon(
                    Icons.mic_none_outlined,
                    color: Colors.white.withOpacity(0.9),
                    size: _isListening ? 28 : 24,
                  ),
                ),
              ),
            ),
          ),
        ),

        // BOTTOM-CENTER: Quick actions (HUD style - minimal pill)
        Positioned(
          bottom: 24,
          left: 0,
          right: 0,
          child: Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.25),
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildHUDIconButton(Icons.search, _handleRecallMemoryButton),
                      const SizedBox(width: 4),
                      _buildHUDIconButton(Icons.visibility_outlined, _handleDescribeScene),
                      const SizedBox(width: 4),
                      _buildHUDIconButton(Icons.bookmark_outline, _handleSaveMemoryButton),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _buildHUDIconButton(IconData icon, VoidCallback onPressed) {
  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: _isProcessing ? null : onPressed,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(10),
        child: Icon(
          icon,
          color: Colors.white.withOpacity(_isProcessing ? 0.3 : 0.8),
          size: 20,
        ),
      ),
    ),
  );
}
