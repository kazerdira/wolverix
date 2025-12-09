import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'dart:math' as math;

// Import your existing files (adjust paths as needed)
// import '../../providers/room_provider.dart';
// import '../../providers/voice_provider.dart';
// import '../../models/models.dart';
// import '../../services/storage_service.dart';

/// Enhanced Room Lobby with premium UI/UX
class EnhancedRoomLobbyScreen extends StatefulWidget {
  const EnhancedRoomLobbyScreen({super.key});

  @override
  State<EnhancedRoomLobbyScreen> createState() => _EnhancedRoomLobbyScreenState();
}

class _EnhancedRoomLobbyScreenState extends State<EnhancedRoomLobbyScreen>
    with TickerProviderStateMixin {
  
  late AnimationController _backgroundController;
  late AnimationController _pulseController;
  
  // Mock data for demonstration
  final bool isHost = true;
  final String roomCode = 'ABC123';
  final String roomName = 'Night Hunters';
  final int currentPlayers = 6;
  final int maxPlayers = 12;
  
  final List<MockPlayer> players = [
    MockPlayer(name: 'WolfMaster', isHost: true, isReady: true, avatar: '🐺'),
    MockPlayer(name: 'VillagerPro', isHost: false, isReady: true, avatar: '🧑‍🌾'),
    MockPlayer(name: 'MysticSeer', isHost: false, isReady: false, avatar: '🔮'),
    MockPlayer(name: 'NightHunter', isHost: false, isReady: true, avatar: '🏹'),
    MockPlayer(name: 'WitchBrew', isHost: false, isReady: false, avatar: '🧙‍♀️'),
    MockPlayer(name: 'Guardian42', isHost: false, isReady: true, avatar: '🛡️'),
  ];

  @override
  void initState() {
    super.initState();
    _backgroundController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _backgroundController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Animated background
          _AnimatedBackground(controller: _backgroundController),
          
          // Main content
          SafeArea(
            child: Column(
              children: [
                // Custom App Bar
                _buildAppBar(),
                
                // Room Info Card
                _buildRoomInfoCard(),
                
                // Voice Controls
                _buildVoiceControls(),
                
                // Players Grid
                Expanded(
                  child: _buildPlayersGrid(),
                ),
                
                // Bottom Action Bar
                _buildBottomActions(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Back button with confirmation
          _GlassButton(
            icon: Icons.arrow_back,
            onTap: () => _showLeaveConfirmation(),
          ),
          
          const SizedBox(width: 16),
          
          // Room name
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  roomName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF00E676),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Waiting for players',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Room code with copy
          _buildRoomCodeChip(),
        ],
      ),
    );
  }

  Widget _buildRoomCodeChip() {
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: roomCode));
        HapticFeedback.mediumImpact();
        _showCopiedFeedback();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withOpacity(0.2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              roomCode,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.copy_rounded,
              size: 18,
              color: Colors.white.withOpacity(0.7),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomInfoCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF243B53).withOpacity(0.8),
            const Color(0xFF1B263B).withOpacity(0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _InfoItem(
            icon: Icons.people_alt_rounded,
            label: 'Players',
            value: '$currentPlayers/$maxPlayers',
            color: const Color(0xFF7C4DFF),
          ),
          _VerticalDivider(),
          _InfoItem(
            icon: Icons.timer_outlined,
            label: 'Day Phase',
            value: '120s',
            color: const Color(0xFFFFAB00),
          ),
          _VerticalDivider(),
          _InfoItem(
            icon: Icons.nightlight_round,
            label: 'Night Phase',
            value: '60s',
            color: const Color(0xFF40C4FF),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceControls() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1B263B).withOpacity(0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
        ),
      ),
      child: Row(
        children: [
          // Connection status
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF00E676).withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.mic_rounded,
              color: Color(0xFF00E676),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Voice Connected',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  '5 participants',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
          
          // Voice controls
          Row(
            children: [
              _VoiceControlButton(
                icon: Icons.mic_rounded,
                isActive: true,
                activeColor: const Color(0xFF7C4DFF),
                onTap: () {},
              ),
              const SizedBox(width: 8),
              _VoiceControlButton(
                icon: Icons.volume_up_rounded,
                isActive: true,
                activeColor: const Color(0xFF7C4DFF),
                onTap: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlayersGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.1,
      ),
      itemCount: maxPlayers,
      itemBuilder: (context, index) {
        if (index < players.length) {
          return _PlayerCard(
            player: players[index],
            isCurrentUser: index == 0, // First player is current user
            onKick: isHost && index != 0 ? () => _kickPlayer(index) : null,
            pulseController: _pulseController,
          );
        } else {
          return _EmptyPlayerSlot(index: index + 1);
        }
      },
    );
  }

  Widget _buildBottomActions() {
    final readyCount = players.where((p) => p.isReady).length;
    final allReady = players.where((p) => !p.isHost).every((p) => p.isReady);
    final canStart = allReady && currentPlayers >= 5;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            const Color(0xFF0D1B2A).withOpacity(0.9),
            const Color(0xFF0D1B2A),
          ],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Ready status bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    allReady ? Icons.check_circle : Icons.hourglass_empty,
                    size: 18,
                    color: allReady 
                        ? const Color(0xFF00E676) 
                        : const Color(0xFFFFAB00),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    allReady 
                        ? 'All players ready!' 
                        : '$readyCount/${players.length - 1} players ready',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 12),
            
            // Action buttons
            Row(
              children: [
                if (!isHost)
                  Expanded(
                    child: _AnimatedReadyButton(
                      isReady: players[0].isReady,
                      onPressed: () {
                        setState(() {
                          players[0].isReady = !players[0].isReady;
                        });
                        HapticFeedback.mediumImpact();
                      },
                    ),
                  ),
                  
                if (isHost)
                  Expanded(
                    child: _StartGameButton(
                      canStart: canStart,
                      currentPlayers: currentPlayers,
                      minPlayers: 5,
                      onPressed: canStart ? () => _startGame() : null,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showLeaveConfirmation() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Color(0xFF1B263B),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFF5252).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.exit_to_app_rounded,
                color: Color(0xFFFF5252),
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Leave Room?',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isHost 
                  ? 'As host, leaving will close the room for everyone.'
                  : 'Are you sure you want to leave this room?',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      // Leave room logic
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF5252),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('Leave'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showCopiedFeedback() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: const [
            Icon(Icons.check_circle, color: Color(0xFF00E676), size: 20),
            SizedBox(width: 12),
            Text('Room code copied!'),
          ],
        ),
        backgroundColor: const Color(0xFF243B53),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _kickPlayer(int index) {
    // Implement kick logic
  }

  void _startGame() {
    // Implement start game logic
  }
}

// ============================================================================
// ANIMATED BACKGROUND
// ============================================================================
class _AnimatedBackground extends StatelessWidget {
  final AnimationController controller;

  const _AnimatedBackground({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF0D1B2A),
                Color(0xFF1B263B),
                Color(0xFF0D1B2A),
              ],
            ),
          ),
          child: Stack(
            children: [
              // Subtle animated orbs
              Positioned(
                top: -100 + (50 * math.sin(controller.value * 2 * math.pi)),
                right: -50,
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF7C4DFF).withOpacity(0.15),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: -150 + (30 * math.cos(controller.value * 2 * math.pi)),
                left: -100,
                child: Container(
                  width: 400,
                  height: 400,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFFE94560).withOpacity(0.1),
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
// GLASS BUTTON
// ============================================================================
class _GlassButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _GlassButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withOpacity(0.1),
          ),
        ),
        child: Icon(icon, size: 22),
      ),
    );
  }
}

// ============================================================================
// INFO ITEM
// ============================================================================
class _InfoItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _InfoItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withOpacity(0.6),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// VERTICAL DIVIDER
// ============================================================================
class _VerticalDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 60,
      color: Colors.white.withOpacity(0.1),
    );
  }
}

// ============================================================================
// VOICE CONTROL BUTTON
// ============================================================================
class _VoiceControlButton extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final Color activeColor;
  final VoidCallback onTap;

  const _VoiceControlButton({
    required this.icon,
    required this.isActive,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isActive 
              ? activeColor.withOpacity(0.2) 
              : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          color: isActive ? activeColor : Colors.white.withOpacity(0.4),
          size: 20,
        ),
      ),
    );
  }
}

// ============================================================================
// PLAYER CARD
// ============================================================================
class _PlayerCard extends StatelessWidget {
  final MockPlayer player;
  final bool isCurrentUser;
  final VoidCallback? onKick;
  final AnimationController pulseController;

  const _PlayerCard({
    required this.player,
    required this.isCurrentUser,
    this.onKick,
    required this.pulseController,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseController,
      builder: (context, child) {
        final pulseValue = 1.0 + (0.02 * pulseController.value);
        
        return Transform.scale(
          scale: isCurrentUser ? pulseValue : 1.0,
          child: child,
        );
      },
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isCurrentUser
                ? [
                    const Color(0xFF7C4DFF).withOpacity(0.3),
                    const Color(0xFF7C4DFF).withOpacity(0.1),
                  ]
                : [
                    const Color(0xFF243B53).withOpacity(0.8),
                    const Color(0xFF1B263B).withOpacity(0.8),
                  ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isCurrentUser
                ? const Color(0xFF7C4DFF).withOpacity(0.5)
                : Colors.white.withOpacity(0.1),
            width: isCurrentUser ? 2 : 1,
          ),
          boxShadow: isCurrentUser
              ? [
                  BoxShadow(
                    color: const Color(0xFF7C4DFF).withOpacity(0.3),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Stack(
          children: [
            // Main content
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Avatar
                  Stack(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: player.isHost
                                ? [const Color(0xFFFFD700), const Color(0xFFFFA000)]
                                : [const Color(0xFF7C4DFF), const Color(0xFFB47CFF)],
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: (player.isHost 
                                  ? const Color(0xFFFFD700) 
                                  : const Color(0xFF7C4DFF))
                                  .withOpacity(0.3),
                              blurRadius: 12,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            player.avatar,
                            style: const TextStyle(fontSize: 28),
                          ),
                        ),
                      ),
                      // Host crown
                      if (player.isHost)
                        Positioned(
                          top: -4,
                          right: -4,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Color(0xFF0D1B2A),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.star_rounded,
                              size: 14,
                              color: Color(0xFFFFD700),
                            ),
                          ),
                        ),
                    ],
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // Name
                  Text(
                    player.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  
                  const SizedBox(height: 4),
                  
                  // Status badge
                  _StatusBadge(
                    isHost: player.isHost,
                    isReady: player.isReady,
                  ),
                  
                  if (isCurrentUser) ...[
                    const SizedBox(height: 4),
                    Text(
                      '(You)',
                      style: TextStyle(
                        fontSize: 10,
                        color: const Color(0xFF7C4DFF).withOpacity(0.8),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            
            // Kick button
            if (onKick != null)
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    onKick?.call();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF5252).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: Color(0xFFFF5252),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// STATUS BADGE
// ============================================================================
class _StatusBadge extends StatelessWidget {
  final bool isHost;
  final bool isReady;

  const _StatusBadge({required this.isHost, required this.isReady});

  @override
  Widget build(BuildContext context) {
    final color = isHost
        ? const Color(0xFFFFD700)
        : (isReady ? const Color(0xFF00E676) : const Color(0xFFB0BEC5));
    final text = isHost ? 'HOST' : (isReady ? 'READY' : 'NOT READY');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ============================================================================
// EMPTY PLAYER SLOT
// ============================================================================
class _EmptyPlayerSlot extends StatelessWidget {
  final int index;

  const _EmptyPlayerSlot({required this.index});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.05),
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.person_add_rounded,
              color: Colors.white.withOpacity(0.2),
              size: 24,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Slot $index',
            style: TextStyle(
              color: Colors.white.withOpacity(0.3),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// ANIMATED READY BUTTON
// ============================================================================
class _AnimatedReadyButton extends StatelessWidget {
  final bool isReady;
  final VoidCallback onPressed;

  const _AnimatedReadyButton({
    required this.isReady,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isReady
              ? [const Color(0xFF00E676), const Color(0xFF00C853)]
              : [const Color(0xFF243B53), const Color(0xFF1B263B)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: isReady
            ? null
            : Border.all(color: const Color(0xFF7C4DFF), width: 2),
        boxShadow: isReady
            ? [
                BoxShadow(
                  color: const Color(0xFF00E676).withOpacity(0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isReady ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: isReady ? Colors.white : const Color(0xFF7C4DFF),
                ),
                const SizedBox(width: 8),
                Text(
                  isReady ? 'Ready!' : 'Click when ready',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: isReady ? Colors.white : const Color(0xFF7C4DFF),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// START GAME BUTTON
// ============================================================================
class _StartGameButton extends StatefulWidget {
  final bool canStart;
  final int currentPlayers;
  final int minPlayers;
  final VoidCallback? onPressed;

  const _StartGameButton({
    required this.canStart,
    required this.currentPlayers,
    required this.minPlayers,
    this.onPressed,
  });

  @override
  State<_StartGameButton> createState() => _StartGameButtonState();
}

class _StartGameButtonState extends State<_StartGameButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    if (widget.canStart) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_StartGameButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.canStart && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.canStart && _controller.isAnimating) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final needsMore = widget.minPlayers - widget.currentPlayers;
    
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = widget.canStart ? 1.0 + (0.02 * _controller.value) : 1.0;
        
        return Transform.scale(
          scale: scale,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: widget.canStart
                    ? [const Color(0xFF7C4DFF), const Color(0xFFB47CFF)]
                    : [const Color(0xFF37474F), const Color(0xFF455A64)],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: widget.canStart
                  ? [
                      BoxShadow(
                        color: const Color(0xFF7C4DFF).withOpacity(0.4 + (0.2 * _controller.value)),
                        blurRadius: 16 + (8 * _controller.value),
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onPressed,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        widget.canStart ? Icons.play_arrow_rounded : Icons.hourglass_empty,
                        color: Colors.white.withOpacity(widget.canStart ? 1 : 0.5),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.canStart
                            ? 'Start Game'
                            : needsMore > 0
                                ? 'Need $needsMore more player${needsMore > 1 ? 's' : ''}'
                                : 'Waiting for ready',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.white.withOpacity(widget.canStart ? 1 : 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ============================================================================
// MOCK PLAYER MODEL (for demonstration)
// ============================================================================
class MockPlayer {
  final String name;
  final bool isHost;
  bool isReady;
  final String avatar;

  MockPlayer({
    required this.name,
    required this.isHost,
    required this.isReady,
    required this.avatar,
  });
}
