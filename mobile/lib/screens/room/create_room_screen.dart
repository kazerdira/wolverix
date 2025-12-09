import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../providers/room_provider.dart';
import '../../models/models.dart';

class CreateRoomScreen extends StatefulWidget {
  const CreateRoomScreen({super.key});

  @override
  State<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends State<CreateRoomScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _flameController;
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  int _maxPlayers = 10;
  bool _isPrivate = false;

  // Game settings
  int _dayPhaseSeconds = 120;
  int _nightPhaseSeconds = 60;
  int _votingSeconds = 60;
  bool _enableVoiceChat = true;

  @override
  void initState() {
    super.initState();
    _flameController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _flameController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _createRoom() async {
    if (!_formKey.currentState!.validate()) return;

    final roomProvider = Get.find<RoomProvider>();
    final room = await roomProvider.createRoom(
      name: _nameController.text.trim(),
      isPrivate: _isPrivate,
      maxPlayers: _maxPlayers,
      config: RoomConfig(
        dayPhaseSeconds: _dayPhaseSeconds,
        nightPhaseSeconds: _nightPhaseSeconds,
        votingSeconds: _votingSeconds,
        enableVoiceChat: _enableVoiceChat,
      ),
    );

    if (room != null) {
      Get.offNamed('/room/${room.id}');
    } else {
      Get.snackbar(
        'Error',
        roomProvider.errorMessage.value,
        backgroundColor: const Color(0xFFE94560),
        colorText: Colors.white,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Get.back(),
        ),
        title: const Text(
          'GATHER THE COUNCIL',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
            fontSize: 16,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // Animated night background
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _flameController,
              builder: (context, child) {
                return CustomPaint(
                  painter: _FirePainter(_flameController.value),
                );
              },
            ),
          ),

          // Content
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 20),

                    // Header illustration
                    Center(
                      child: AnimatedBuilder(
                        animation: _flameController,
                        builder: (context, child) {
                          return Icon(
                            Icons.local_fire_department,
                            size: 80,
                            color: Color.lerp(
                              const Color(0xFFFF6B35),
                              const Color(0xFFFFD700),
                              _flameController.value,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),

                    const Center(
                      child: Text(
                        'Light the Fire',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    Center(
                      child: Text(
                        'Create a gathering place for your council',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Village Name Card
                    _GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.villa,
                                  color: const Color(0xFFE94560), size: 20),
                              const SizedBox(width: 8),
                              const Text(
                                'VILLAGE NAME',
                                style: TextStyle(
                                  color: Color(0xFFE94560),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _nameController,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 16),
                            decoration: InputDecoration(
                              hintText: 'Enter village name...',
                              hintStyle: TextStyle(
                                  color: Colors.white.withOpacity(0.3)),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                    color: Colors.white.withOpacity(0.1)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                    color: Colors.white.withOpacity(0.1)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                    color: Color(0xFFE94560), width: 2),
                              ),
                              filled: true,
                              fillColor: Colors.black.withOpacity(0.2),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 16),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter a village name';
                              }
                              if (value.trim().length < 3) {
                                return 'Village name must be at least 3 characters';
                              }
                              if (value.trim().length > 100) {
                                return 'Village name must be less than 100 characters';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Council Size Card
                    _GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.groups,
                                  color: const Color(0xFF7C4DFF), size: 20),
                              const SizedBox(width: 8),
                              const Text(
                                'COUNCIL SIZE',
                                style: TextStyle(
                                  color: Color(0xFF7C4DFF),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 6),
                                decoration: BoxDecoration(
                                  color:
                                      const Color(0xFF7C4DFF).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: const Color(0xFF7C4DFF)
                                          .withOpacity(0.3)),
                                ),
                                child: Text(
                                  '$_maxPlayers',
                                  style: const TextStyle(
                                    color: Color(0xFF7C4DFF),
                                    fontWeight: FontWeight.w900,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Seats around the fire',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 12,
                            ),
                          ),
                          SliderTheme(
                            data: SliderThemeData(
                              activeTrackColor: const Color(0xFF7C4DFF),
                              inactiveTrackColor: Colors.white.withOpacity(0.1),
                              thumbColor: const Color(0xFF7C4DFF),
                              overlayColor:
                                  const Color(0xFF7C4DFF).withOpacity(0.2),
                              thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 8),
                              trackHeight: 4,
                            ),
                            child: Slider(
                              value: _maxPlayers.toDouble(),
                              min: 6,
                              max: 24,
                              divisions: 18,
                              onChanged: (value) {
                                setState(() {
                                  _maxPlayers = value.toInt();
                                });
                              },
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '6 (Intimate)',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.4),
                                  fontSize: 11,
                                ),
                              ),
                              Text(
                                '24 (Grand)',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.4),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Privacy Card
                    _GlassCard(
                      child: Row(
                        children: [
                          Icon(
                            _isPrivate ? Icons.lock : Icons.lock_open,
                            color: _isPrivate
                                ? const Color(0xFFFFB900)
                                : const Color(0xFF4CAF50),
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _isPrivate
                                      ? 'SECRET GATHERING'
                                      : 'OPEN COUNCIL',
                                  style: TextStyle(
                                    color: _isPrivate
                                        ? const Color(0xFFFFB900)
                                        : const Color(0xFF4CAF50),
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _isPrivate
                                      ? 'Only invited members can enter'
                                      : 'Anyone can discover this village',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.5),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _isPrivate,
                            activeColor: const Color(0xFFFFB900),
                            inactiveThumbColor: const Color(0xFF4CAF50),
                            inactiveTrackColor:
                                const Color(0xFF4CAF50).withOpacity(0.3),
                            onChanged: (value) {
                              setState(() {
                                _isPrivate = value;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Game Rules Header
                    Row(
                      children: [
                        Icon(Icons.auto_stories,
                            color: const Color(0xFFE94560), size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          'RITUAL TIMINGS',
                          style: TextStyle(
                            color: Color(0xFFE94560),
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Day phase duration
                    _GlassCard(
                      child: _DurationSetting(
                        icon: Icons.wb_sunny,
                        iconColor: const Color(0xFFFFD700),
                        label: 'Daybreak Discussion',
                        description: 'Time for council debates',
                        value: _dayPhaseSeconds,
                        min: 60,
                        max: 300,
                        onChanged: (value) {
                          setState(() {
                            _dayPhaseSeconds = value;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Night phase duration
                    _GlassCard(
                      child: _DurationSetting(
                        icon: Icons.nightlight_round,
                        iconColor: const Color(0xFF5E5CE6),
                        label: 'Moonlit Actions',
                        description: 'Time for secret moves',
                        value: _nightPhaseSeconds,
                        min: 30,
                        max: 120,
                        onChanged: (value) {
                          setState(() {
                            _nightPhaseSeconds = value;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Voting duration
                    _GlassCard(
                      child: _DurationSetting(
                        icon: Icons.how_to_vote,
                        iconColor: const Color(0xFFFF6B6B),
                        label: 'Judgment Period',
                        description: 'Time to cast votes',
                        value: _votingSeconds,
                        min: 30,
                        max: 120,
                        onChanged: (value) {
                          setState(() {
                            _votingSeconds = value;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Voice chat toggle
                    _GlassCard(
                      child: Row(
                        children: [
                          Icon(
                            _enableVoiceChat ? Icons.mic : Icons.mic_off,
                            color: _enableVoiceChat
                                ? const Color(0xFF00E676)
                                : Colors.grey,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'VOICE OF THE ELDERS',
                                  style: TextStyle(
                                    color: _enableVoiceChat
                                        ? const Color(0xFF00E676)
                                        : Colors.grey,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Real-time voice communication',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.5),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _enableVoiceChat,
                            activeColor: const Color(0xFF00E676),
                            onChanged: (value) {
                              setState(() {
                                _enableVoiceChat = value;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Create button
                    Obx(() {
                      final roomProvider = Get.find<RoomProvider>();
                      return Container(
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFE94560), Color(0xFFFF6B35)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFE94560).withOpacity(0.4),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed:
                              roomProvider.isLoading.value ? null : _createRoom,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: roomProvider.isLoading.value
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.local_fire_department,
                                        color: Colors.white),
                                    const SizedBox(width: 12),
                                    const Text(
                                      'IGNITE THE FIRE',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16,
                                        letterSpacing: 2,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      );
                    }),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Glass card widget
class _GlassCard extends StatelessWidget {
  final Widget child;

  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withOpacity(0.1),
              width: 1,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

// Duration setting widget
class _DurationSetting extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String description;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _DurationSetting({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.description,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: TextStyle(
                      color: iconColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                      letterSpacing: 1.2,
                    ),
                  ),
                  Text(
                    description,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: iconColor.withOpacity(0.3)),
              ),
              child: Text(
                '${value}s',
                style: TextStyle(
                  color: iconColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: iconColor,
            inactiveTrackColor: Colors.white.withOpacity(0.1),
            thumbColor: iconColor,
            overlayColor: iconColor.withOpacity(0.2),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            trackHeight: 3,
          ),
          child: Slider(
            value: value.toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: ((max - min) ~/ 10),
            onChanged: (v) => onChanged(v.toInt()),
          ),
        ),
      ],
    );
  }
}

// Fire painter for animated background
class _FirePainter extends CustomPainter {
  final double animation;

  _FirePainter(this.animation);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // Dark gradient background
    final rect = Offset.zero & size;
    final bgGradient = RadialGradient(
      center: Alignment.topCenter,
      radius: 1.5,
      colors: const [
        Color(0xFF1F2942),
        Color(0xFF0D1B2A),
      ],
    );

    canvas.drawRect(
      rect,
      Paint()..shader = bgGradient.createShader(rect),
    );

    // Floating embers
    final random = math.Random(42);
    final paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < 20; i++) {
      final x = random.nextDouble() * size.width;
      final baseY = random.nextDouble() * size.height;
      final y = baseY - (animation * 100) % size.height;

      final opacity =
          (0.2 + 0.3 * math.sin(animation * math.pi * 2 + i)).clamp(0.0, 1.0);
      final baseColor = Color.lerp(
            const Color(0xFFFF6B35),
            const Color(0xFFFFD700),
            random.nextDouble(),
          ) ??
          const Color(0xFFFF6B35);

      paint.color = baseColor.withOpacity(opacity);

      canvas.drawCircle(
        Offset(x, y),
        1 + random.nextDouble() * 2,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_FirePainter oldDelegate) => true;
}
