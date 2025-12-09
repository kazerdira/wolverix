This is a complete redesign of your HomeScreen.

The Design Philosophy: We are moving from a "Utility App" look to an "RPG Character Menu" look.

Immersive Background: A "Night Forest" particle effect similar to the Lobby.

Player Identity: Your profile is now a "Hero Card" at the top, showing your stats (Win rate, games played) immediately.

Portal Actions: "Create Room" and "Join Room" are no longer simple buttons; they are large, illustrated cards that look like portals.

Village List: The rooms are displayed as "Village Signposts" with glassmorphism effects.

Here is the code. Copy this into lib/screens/home/home_screen.dart.

Dart

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../providers/auth_provider.dart';
import '../../providers/room_provider.dart';
import '../../models/models.dart';
import '../../utils/theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late AnimationController _backgroundController;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Background animation
    _backgroundController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();

    // Data Fetching
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Get.find<RoomProvider>().fetchRooms();
      Get.find<AuthProvider>().fetchUserStats();
    });
  }

  @override
  void dispose() {
    _backgroundController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'WOLVERIX', 
          style: TextStyle(
            letterSpacing: 4, 
            fontWeight: FontWeight.w900,
            fontSize: 24,
            color: Colors.white70
          )
        ),
        actions: [
          _GlassIconButton(
            icon: Icons.refresh,
            onTap: () => Get.find<RoomProvider>().fetchRooms(),
          ),
          const SizedBox(width: 8),
          _GlassIconButton(
            icon: Icons.logout,
            color: Colors.redAccent,
            onTap: () => _showLogoutDialog(),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Stack(
        children: [
          // 1. Animated Night Background
          Positioned.fill(
            child: _NightSkyBackground(controller: _backgroundController),
          ),

          // 2. Main Content
          SafeArea(
            child: RefreshIndicator(
              onRefresh: () async => Get.find<RoomProvider>().fetchRooms(),
              color: const Color(0xFFE94560),
              backgroundColor: const Color(0xFF1A1A2E),
              child: CustomScrollView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(),
                slivers: [
                  const SliverToBoxAdapter(child: SizedBox(height: 20)),
                  
                  // 3. User Hero Card
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: _HeroProfileCard(),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 30)),

                  // 4. Main Actions (Create / Join)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: _ActionPortals(),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 30)),

                  // 5. Section Title
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        children: [
                          const Icon(Icons.night_shelter, color: Color(0xFF4CAF50), size: 20),
                          const SizedBox(width: 8),
                          Text(
                            "ACTIVE VILLAGES",
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 16)),

                  // 6. Room List
                  _RoomListSliver(),
                  
                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog() {
    Get.dialog(
      AlertDialog(
        backgroundColor: const Color(0xFF16213E),
        title: const Text('Retreat from the Village?', style: TextStyle(color: Colors.white)),
        content: const Text('Are you sure you want to logout?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Stay')),
          ElevatedButton(
            onPressed: () {
              Get.back();
              Get.find<AuthProvider>().logout();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 🧙‍♂️ WIDGET: Hero Profile Card
// -----------------------------------------------------------------------------
class _HeroProfileCard extends StatelessWidget {
  const _HeroProfileCard();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final user = Get.find<AuthProvider>().currentUser.value;
      final stats = Get.find<AuthProvider>().userStats.value;

      return Container(
        height: 140,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: [Color(0xFF2E2E4E), Color(0xFF1A1A2E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
            BoxShadow(
              color: const Color(0xFF7C4DFF).withOpacity(0.2),
              blurRadius: 20,
              spreadRadius: -5,
            )
          ],
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Stack(
          children: [
            // Background Pattern
            Positioned(
              right: -20,
              top: -20,
              child: Icon(
                Icons.person,
                size: 180,
                color: Colors.white.withOpacity(0.03),
              ),
            ),
            
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                children: [
                  // Avatar with Level Ring
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFE94560), width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFE94560).withOpacity(0.4),
                          blurRadius: 15,
                        )
                      ]
                    ),
                    child: CircleAvatar(
                      backgroundColor: const Color(0xFF0D1B2A),
                      backgroundImage: user?.avatarUrl != null ? NetworkImage(user!.avatarUrl!) : null,
                      child: user?.avatarUrl == null 
                        ? Text(user?.username[0].toUpperCase() ?? "U", style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)) 
                        : null,
                    ),
                  ),
                  const SizedBox(width: 20),
                  
                  // Stats Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          user?.username ?? "Unknown Hunter",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF7C4DFF).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            user?.email ?? "",
                            style: const TextStyle(color: Color(0xFFB47CFF), fontSize: 10),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                             _MiniStat(
                               label: "WINS", 
                               value: "${stats?.gamesWon ?? 0}",
                               color: const Color(0xFF4CAF50),
                             ),
                             const SizedBox(width: 16),
                             _MiniStat(
                               label: "GAMES", 
                               value: "${stats?.gamesPlayed ?? 0}",
                               color: Colors.white70,
                             ),
                             const SizedBox(width: 16),
                             _MiniStat(
                               label: "RATE", 
                               value: "${((stats?.winRate ?? 0) * 100).toInt()}%",
                               color: Colors.amber,
                             ),
                          ],
                        )
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
        Text(label, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 8, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// 🚪 WIDGET: Action Portals (Create / Join)
// -----------------------------------------------------------------------------
class _ActionPortals extends StatelessWidget {
  const _ActionPortals();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // CREATE ROOM CARD
        Expanded(
          child: GestureDetector(
            onTap: () => Get.toNamed('/create-room'),
            child: Container(
              height: 160,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(
                  colors: [Color(0xFFE94560), Color(0xFF9C27B0)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(color: const Color(0xFFE94560).withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 6))
                ]
              ),
              child: Stack(
                children: [
                  Positioned(
                    bottom: -20, right: -20,
                    child: Icon(Icons.add_circle, size: 100, color: Colors.white.withOpacity(0.2)),
                  ),
                  const Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.campfire, color: Colors.white, size: 32),
                        Spacer(),
                        Text("HOST\nA GAME", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18, height: 1.1)),
                        SizedBox(height: 4),
                        Text("Create Village", style: TextStyle(color: Colors.white70, fontSize: 11)),
                      ],
                    ),
                  )
                ],
              ),
            ),
          ),
        ),
        
        const SizedBox(width: 16),

        // JOIN ROOM CARD
        Expanded(
          child: GestureDetector(
            onTap: () => Get.toNamed('/join-room'),
            child: Container(
              height: 160,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: const Color(0xFF243B53),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))
                ]
              ),
              child: Stack(
                children: [
                  Positioned(
                    bottom: -20, right: -20,
                    child: Icon(Icons.login, size: 100, color: Colors.white.withOpacity(0.05)),
                  ),
                  const Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.search, color: Color(0xFF40C4FF), size: 32),
                        Spacer(),
                        Text("FIND\nA GAME", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18, height: 1.1)),
                        SizedBox(height: 4),
                        Text("Enter Code", style: TextStyle(color: Colors.white54, fontSize: 11)),
                      ],
                    ),
                  )
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// 📜 WIDGET: Room List Sliver
// -----------------------------------------------------------------------------
class _RoomListSliver extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final roomProvider = Get.find<RoomProvider>();
      
      if (roomProvider.isLoading.value) {
        return const SliverToBoxAdapter(
          child: Center(child: CircularProgressIndicator(color: Color(0xFFE94560))),
        );
      }

      final rooms = roomProvider.availableRooms
          .where((r) => r.status == RoomStatus.waiting)
          .toList();

      if (rooms.isEmpty) {
        return const SliverToBoxAdapter(
          child: _EmptyVillageState(),
        );
      }

      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final room = rooms[index];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: _VillageCard(room: room),
            );
          },
          childCount: rooms.length,
        ),
      );
    });
  }
}

class _VillageCard extends StatelessWidget {
  final Room room;

  const _VillageCard({required this.room});

  @override
  Widget build(BuildContext context) {
    bool isFull = room.currentPlayers >= room.maxPlayers;

    return GestureDetector(
      onTap: isFull 
        ? null 
        : () async {
            final success = await Get.find<RoomProvider>().joinRoom(room.roomCode);
            if (success) Get.toNamed('/room/${room.id}');
          },
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          color: const Color(0xFF16213E).withOpacity(0.8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Row(
          children: [
            // Left Status Strip
            Container(
              width: 6,
              decoration: BoxDecoration(
                color: isFull ? Colors.red : const Color(0xFF00E676),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16)
                )
              ),
            ),
            
            // Icon
            Container(
              width: 80,
              alignment: Alignment.center,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (isFull ? Colors.red : const Color(0xFF00E676)).withOpacity(0.1),
                ),
                child: Icon(
                  isFull ? Icons.lock : Icons.meeting_room,
                  color: isFull ? Colors.red : const Color(0xFF00E676),
                ),
              ),
            ),

            // Info
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    room.name, 
                    style: const TextStyle(
                      color: Colors.white, 
                      fontWeight: FontWeight.bold, 
                      fontSize: 16
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.person_outline, size: 12, color: Colors.white.withOpacity(0.5)),
                      const SizedBox(width: 4),
                      Text(
                        "Host: ${room.host?.username ?? 'Unknown'}",
                        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Room Code Pill (Small)
                  if (!room.isPrivate)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(4)
                    ),
                    child: Text(
                      "CODE: ${room.roomCode}",
                      style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 9, letterSpacing: 1),
                    ),
                  )
                ],
              ),
            ),

            // Player Count
            Padding(
              padding: const EdgeInsets.only(right: 20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "${room.currentPlayers}",
                    style: TextStyle(
                      fontSize: 24, 
                      fontWeight: FontWeight.bold, 
                      color: isFull ? Colors.red : Colors.white
                    ),
                  ),
                  Text(
                    "/${room.maxPlayers}",
                    style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}

class _EmptyVillageState extends StatelessWidget {
  const _EmptyVillageState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(40),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.nights_stay_outlined, size: 60, color: Colors.white.withOpacity(0.2)),
          const SizedBox(height: 16),
          Text(
            "The Village is Quiet...",
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16),
          ),
          Text(
            "Start a fire to gather players.",
            style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 🌌 WIDGET: Night Sky Background Painter
// -----------------------------------------------------------------------------
class _NightSkyBackground extends StatelessWidget {
  final AnimationController controller;

  const _NightSkyBackground({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _MistPainter(controller.value),
        );
      },
    );
  }
}

class _MistPainter extends CustomPainter {
  final double animationValue;

  _MistPainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    
    // 1. Deep Gradient Base
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final gradient = RadialGradient(
      center: const Alignment(0, -0.5), // Moon positionish
      radius: 1.5,
      colors: const [
        Color(0xFF1F2942), // Dark Blue Grey
        Color(0xFF0D1B2A), // Deepest Black/Blue
      ],
      stops: const [0.0, 1.0],
    );
    paint.shader = gradient.createShader(rect);
    canvas.drawRect(rect, paint);

    // 2. Animated Particles (Fireflies)
    final random = math.Random(42); // Fixed seed for consistent placement pattern
    final particlePaint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < 30; i++) {
      // Calculate position based on animation loop
      double speed = 0.2 + (random.nextDouble() * 0.8);
      double x = (random.nextDouble() * size.width) + (math.sin(animationValue * 2 * math.pi * speed) * 20);
      double y = (random.nextDouble() * size.height) - (animationValue * size.height * speed * 0.5);
      
      // Wrap around Y
      if (y < 0) y += size.height;

      // Pulse opacity
      double opacity = 0.3 + (0.5 * math.sin((animationValue + i) * math.pi));
      
      particlePaint.color = const Color(0xFFF5F3CE).withOpacity(opacity.abs().clamp(0.0, 0.8));
      canvas.drawCircle(Offset(x, y), 1.5 + random.nextDouble(), particlePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// -----------------------------------------------------------------------------
// 🪟 WIDGET: Glass Icon Button
// -----------------------------------------------------------------------------
class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  const _GlassIconButton({required this.icon, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.1))
            ),
            child: Icon(icon, color: color ?? Colors.white, size: 20),
          ),
        ),
      ),
    );
  }
}