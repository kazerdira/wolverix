import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;

/// Dramatic Role Reveal Animation
/// Shows when the game starts and players receive their roles
class RoleRevealScreen extends StatefulWidget {
  final String roleName;
  final String roleDescription;
  final String team; // 'werewolves' or 'villagers'
  final List<String>? teammates; // For werewolves
  final VoidCallback onComplete;

  const RoleRevealScreen({
    super.key,
    required this.roleName,
    required this.roleDescription,
    required this.team,
    this.teammates,
    required this.onComplete,
  });

  @override
  State<RoleRevealScreen> createState() => _RoleRevealScreenState();
}

class _RoleRevealScreenState extends State<RoleRevealScreen>
    with TickerProviderStateMixin {
  
  late AnimationController _cardController;
  late AnimationController _glowController;
  late AnimationController _particleController;
  late AnimationController _textController;
  
  late Animation<double> _cardFlipAnimation;
  late Animation<double> _cardScaleAnimation;
  late Animation<double> _glowAnimation;
  late Animation<double> _fadeInAnimation;
  
  bool _isRevealed = false;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _startRevealSequence();
  }

  void _initAnimations() {
    // Card flip and scale
    _cardController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    
    _cardFlipAnimation = Tween<double>(begin: 0, end: math.pi).animate(
      CurvedAnimation(
        parent: _cardController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeInOutBack),
      ),
    );
    
    _cardScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.8), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 0.8, end: 1.1), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.1, end: 1.0), weight: 30),
    ]).animate(CurvedAnimation(parent: _cardController, curve: Curves.easeInOut));

    // Glow effect
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    
    _glowAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    // Particles
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();

    // Text fade in
    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    
    _fadeInAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeOut),
    );
  }

  Future<void> _startRevealSequence() async {
    // Wait a moment for dramatic effect
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Haptic feedback
    HapticFeedback.heavyImpact();
    
    // Start card flip
    await _cardController.forward();
    
    setState(() => _isRevealed = true);
    
    // Start text animation
    _textController.forward();
    
    // Another haptic for the reveal
    HapticFeedback.mediumImpact();
  }

  @override
  void dispose() {
    _cardController.dispose();
    _glowController.dispose();
    _particleController.dispose();
    _textController.dispose();
    super.dispose();
  }

  Color get _roleColor {
    switch (widget.roleName.toLowerCase()) {
      case 'werewolf':
        return const Color(0xFFDC143C);
      case 'seer':
        return const Color(0xFF9C27B0);
      case 'witch':
        return const Color(0xFF00BCD4);
      case 'hunter':
        return const Color(0xFFFF9800);
      case 'cupid':
        return const Color(0xFFE91E63);
      case 'bodyguard':
        return const Color(0xFF3F51B5);
      default:
        return const Color(0xFF4CAF50);
    }
  }

  IconData get _roleIcon {
    switch (widget.roleName.toLowerCase()) {
      case 'werewolf':
        return Icons.pets;
      case 'seer':
        return Icons.visibility;
      case 'witch':
        return Icons.science;
      case 'hunter':
        return Icons.gps_fixed;
      case 'cupid':
        return Icons.favorite;
      case 'bodyguard':
        return Icons.shield;
      default:
        return Icons.person;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      body: Stack(
        children: [
          // Animated background
          _AnimatedRoleBackground(
            controller: _particleController,
            roleColor: _roleColor,
            isRevealed: _isRevealed,
          ),
          
          // Main content
          SafeArea(
            child: Column(
              children: [
                const Spacer(),
                
                // Card
                Center(
                  child: AnimatedBuilder(
                    animation: _cardController,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _cardScaleAnimation.value,
                        child: Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.001)
                            ..rotateY(_cardFlipAnimation.value),
                          child: _cardFlipAnimation.value < math.pi / 2
                              ? _buildCardBack()
                              : Transform(
                                  alignment: Alignment.center,
                                  transform: Matrix4.identity()..rotateY(math.pi),
                                  child: _buildCardFront(),
                                ),
                        ),
                      );
                    },
                  ),
                ),
                
                const SizedBox(height: 40),
                
                // Role info (after reveal)
                if (_isRevealed) ...[
                  FadeTransition(
                    opacity: _fadeInAnimation,
                    child: _buildRoleInfo(),
                  ),
                  
                  // Teammates (for werewolves)
                  if (widget.teammates != null && widget.teammates!.isNotEmpty)
                    FadeTransition(
                      opacity: _fadeInAnimation,
                      child: _buildTeammatesSection(),
                    ),
                ],
                
                const Spacer(),
                
                // Continue button
                if (_isRevealed)
                  FadeTransition(
                    opacity: _fadeInAnimation,
                    child: _buildContinueButton(),
                  ),
                
                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardBack() {
    return Container(
      width: 280,
      height: 400,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1B263B),
            Color(0xFF243B53),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 30,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Pattern
          ...List.generate(6, (i) {
            return Positioned(
              top: 50 + (i * 50),
              child: Container(
                width: 200,
                height: 30,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            );
          }),
          
          // Mystery icon
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF7C4DFF).withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.help_outline,
              size: 80,
              color: Color(0xFF7C4DFF),
            ),
          ),
          
          // "Tap to reveal" text
          Positioned(
            bottom: 40,
            child: Text(
              '?',
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.bold,
                color: Colors.white.withOpacity(0.3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardFront() {
    return AnimatedBuilder(
      animation: _glowController,
      builder: (context, child) {
        return Container(
          width: 280,
          height: 400,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _roleColor.withOpacity(0.3),
                const Color(0xFF1B263B),
                _roleColor.withOpacity(0.2),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: _roleColor.withOpacity(0.5 + (0.3 * _glowAnimation.value)),
              width: 3,
            ),
            boxShadow: [
              BoxShadow(
                color: _roleColor.withOpacity(0.3 * _glowAnimation.value),
                blurRadius: 30 + (20 * _glowAnimation.value),
                spreadRadius: 5,
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Team indicator at top
              Positioned(
                top: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(
                    color: widget.team == 'werewolves'
                        ? Colors.red.withOpacity(0.2)
                        : Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: widget.team == 'werewolves'
                          ? Colors.red.withOpacity(0.5)
                          : Colors.green.withOpacity(0.5),
                    ),
                  ),
                  child: Text(
                    widget.team == 'werewolves' ? '🐺 WEREWOLF TEAM' : '🏠 VILLAGE TEAM',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: widget.team == 'werewolves' ? Colors.red : Colors.green,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
              
              // Role icon with glow
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: _roleColor.withOpacity(0.2),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _roleColor.withOpacity(0.4 * _glowAnimation.value),
                      blurRadius: 40,
                      spreadRadius: 10,
                    ),
                  ],
                ),
                child: Icon(
                  _roleIcon,
                  size: 80,
                  color: _roleColor,
                ),
              ),
              
              // Role name at bottom
              Positioned(
                bottom: 60,
                child: Column(
                  children: [
                    Text(
                      widget.roleName.toUpperCase(),
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: _roleColor,
                        letterSpacing: 4,
                        shadows: [
                          Shadow(
                            color: _roleColor.withOpacity(0.5),
                            blurRadius: 20,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 60,
                      height: 3,
                      decoration: BoxDecoration(
                        color: _roleColor,
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: [
                          BoxShadow(
                            color: _roleColor.withOpacity(0.5),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRoleInfo() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        children: [
          Text(
            'YOUR ROLE',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white.withOpacity(0.5),
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.roleDescription,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.white.withOpacity(0.8),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTeammatesSection() {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        children: [
          Text(
            'YOUR PACK',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.red.withOpacity(0.7),
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: widget.teammates!.map((name) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.pets, size: 16, color: Colors.red),
                    const SizedBox(width: 8),
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildContinueButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () {
            HapticFeedback.lightImpact();
            widget.onComplete();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: _roleColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 8,
            shadowColor: _roleColor.withOpacity(0.5),
          ),
          child: const Text(
            'ENTER THE NIGHT',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// ANIMATED BACKGROUND WITH PARTICLES
// ============================================================================
class _AnimatedRoleBackground extends StatelessWidget {
  final AnimationController controller;
  final Color roleColor;
  final bool isRevealed;

  const _AnimatedRoleBackground({
    required this.controller,
    required this.roleColor,
    required this.isRevealed,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 1.5,
              colors: [
                isRevealed
                    ? roleColor.withOpacity(0.15)
                    : const Color(0xFF1B263B),
                const Color(0xFF0D1B2A),
              ],
            ),
          ),
          child: Stack(
            children: [
              // Floating particles
              if (isRevealed)
                ...List.generate(20, (index) {
                  final random = math.Random(index);
                  final startX = random.nextDouble();
                  final startY = random.nextDouble();
                  final speed = 0.3 + random.nextDouble() * 0.7;
                  final size = 2.0 + random.nextDouble() * 4;
                  
                  return Positioned(
                    left: MediaQuery.of(context).size.width * 
                        ((startX + controller.value * speed) % 1),
                    top: MediaQuery.of(context).size.height * 
                        ((startY + controller.value * speed * 0.5) % 1),
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: roleColor.withOpacity(0.3 + random.nextDouble() * 0.4),
                        boxShadow: [
                          BoxShadow(
                            color: roleColor.withOpacity(0.3),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              
              // Ambient glow orbs
              Positioned(
                top: 100 + 50 * math.sin(controller.value * 2 * math.pi),
                right: 50,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        roleColor.withOpacity(isRevealed ? 0.1 : 0.05),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 150 + 30 * math.cos(controller.value * 2 * math.pi),
                left: 30,
                child: Container(
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF7C4DFF).withOpacity(isRevealed ? 0.08 : 0.04),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ============================================================================
// USAGE EXAMPLE
// ============================================================================
/*
Navigator.push(
  context,
  PageRouteBuilder(
    pageBuilder: (context, animation, secondaryAnimation) => RoleRevealScreen(
      roleName: 'Werewolf',
      roleDescription: 'Hunt villagers at night. Know your fellow wolves. Eliminate all villagers to win.',
      team: 'werewolves',
      teammates: ['WolfMaster', 'NightStalker'],
      onComplete: () {
        Navigator.pop(context);
        // Navigate to game screen
      },
    ),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(opacity: animation, child: child);
    },
    transitionDuration: const Duration(milliseconds: 500),
  ),
);
*/
