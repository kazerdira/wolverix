import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DeathOverlay extends StatefulWidget {
  final String playerName;
  final String deathReason;
  final VoidCallback onDismiss;

  const DeathOverlay({
    super.key,
    required this.playerName,
    required this.deathReason,
    required this.onDismiss,
  });

  @override
  State<DeathOverlay> createState() => _DeathOverlayState();
}

class _DeathOverlayState extends State<DeathOverlay>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _scaleController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    // Haptic feedback
    HapticFeedback.heavyImpact();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeIn),
    );

    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.elasticOut),
    );

    _fadeController.forward();
    _scaleController.forward();

    // Auto-dismiss after 4 seconds
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        _dismiss();
      }
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  void _dismiss() async {
    await _fadeController.reverse();
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Material(
        color: Colors.black.withOpacity(0.9),
        child: InkWell(
          onTap: _dismiss,
          child: Center(
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Skull icon
                  const Icon(
                    Icons.emoji_emotions_outlined,
                    size: 120,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 30),

                  // RIP Text
                  const Text(
                    'R.I.P.',
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 8,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Player name
                  Text(
                    widget.playerName,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w500,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Death reason
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 30,
                      vertical: 15,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.red.withOpacity(0.5)),
                    ),
                    child: Text(
                      _formatDeathReason(widget.deathReason),
                      style: const TextStyle(
                        fontSize: 18,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Dismiss hint
                  const Text(
                    'Tap to dismiss',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white38,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatDeathReason(String reason) {
    switch (reason) {
      case 'werewolf_kill':
        return '🐺 Killed by Werewolves';
      case 'lynch':
        return '⚖️ Lynched by the Village';
      case 'poison':
        return '🧪 Poisoned by the Witch';
      case 'hunter':
        return '🎯 Shot by the Hunter';
      case 'lover_death':
        return '💔 Died of a Broken Heart';
      default:
        return '☠️ Eliminated';
    }
  }
}
