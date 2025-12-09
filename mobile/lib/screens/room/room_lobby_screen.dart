import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../providers/room_provider.dart';
import '../../providers/voice_provider.dart';
import '../../models/models.dart';
import '../../services/storage_service.dart';

class RoomLobbyScreen extends StatefulWidget {
  const RoomLobbyScreen({super.key});

  @override
  State<RoomLobbyScreen> createState() => _RoomLobbyScreenState();
}

class _RoomLobbyScreenState extends State<RoomLobbyScreen>
    with SingleTickerProviderStateMixin {
  // Animation controller for the "breathing" effect of the circle
  late AnimationController _breathingController;

  @override
  void initState() {
    super.initState();
    _initializeVoice();
    _breathingController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _breathingController.dispose();
    super.dispose();
  }

  Future<void> _initializeVoice() async {
    // TODO: Uncomment for voice support (requires Agora setup on web or native platform)
    // try {
    //   final roomProvider = Get.find<RoomProvider>();
    //   final voiceProvider = Get.find<VoiceProvider>();
    //   final room = roomProvider.currentRoom.value;

    //   if (room != null && room.agoraAppId != null) {
    //     await voiceProvider.initialize(room.agoraAppId!);
    //     if (room.agoraChannelName != null) {
    //       await voiceProvider.joinChannel(room.agoraChannelName!);
    //     }
    //   }
    // } catch (e) {
    //   print('Voice initialization skipped (web platform): $e');
    //   // Continue without voice - game still works
    // }
  }

  @override
  Widget build(BuildContext context) {
    // Determine screen dimensions for the arch calculation
    final size = MediaQuery.of(context).size;

    return WillPopScope(
      onWillPop: () async {
        _showLeaveDialog();
        return false;
      },
      child: Scaffold(
        // Dark mysterious background
        backgroundColor: const Color(0xFF1A1A2E),
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white70),
            onPressed: _showLeaveDialog,
          ),
          centerTitle: true,
          title: Obx(() {
            final room = Get.find<RoomProvider>().currentRoom.value;
            return Column(
              children: [
                Text(room?.name ?? 'The Council',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                // Room Code Pill
                GestureDetector(
                  onTap: () {
                    if (room != null) {
                      Clipboard.setData(ClipboardData(text: room.roomCode));
                      Get.snackbar('Copied', 'Code copied',
                          backgroundColor: Colors.white24,
                          colorText: Colors.white);
                    }
                  },
                  child: Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white24)),
                    child: Text("CODE: ${room?.roomCode ?? '...'}",
                        style: const TextStyle(
                            fontSize: 10,
                            color: Colors.amberAccent,
                            letterSpacing: 1.5)),
                  ),
                )
              ],
            );
          }),
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.2), // Center glow slightly up
              radius: 1.2,
              colors: [
                Color(0xFF2E2E4E), // Lighter center
                Color(0xFF121212), // Dark edges
              ],
            ),
          ),
          child: Stack(
            children: [
              // 1. Background Particles or decorative circle lines (Static for now)
              Positioned.fill(
                child: CustomPaint(
                  painter: _CouncilRingPainter(_breathingController),
                ),
              ),

              // 2. The Players (The Arch)
              Obx(() {
                final room = Get.find<RoomProvider>().currentRoom.value;
                if (room == null)
                  return const Center(child: CircularProgressIndicator());

                return _buildPlayerArch(size, room);
              }),

              // 3. The Central Action Zone (Ready/Start Button)
              Obx(() => _buildCenterStage(
                  Get.find<RoomProvider>().currentRoom.value)),

              // 4. Extend Timeout Button (Host Only)
              Obx(() {
                final room = Get.find<RoomProvider>().currentRoom.value;
                final currentUserId = Get.find<StorageService>().getUserId();
                final isHost = room?.hostUserId == currentUserId;

                if (!isHost) return const SizedBox.shrink();

                return Positioned(
                  top: 100,
                  right: 16,
                  child: _ExtendTimeoutButton(),
                );
              }),

              // 5. Voice Controls & Info (Bottom Floating Pill)
              Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: _GlassVoiceControls(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Calculates positions for players in a circle/oval
  Widget _buildPlayerArch(Size screenSize, Room room) {
    final players = room.players;
    final totalPlayers = players.length;
    final currentUser = Get.find<StorageService>().getUserId();

    // Geometry settings with safe margins
    final double centerX = screenSize.width / 2;
    final double centerY = screenSize.height * 0.45; // Slightly above center

    // Reduced radius to prevent corner overflow (with 60px safe margin)
    final double radiusX = (screenSize.width / 2) - 60; // Horizontal radius
    final double radiusY =
        screenSize.height * 0.22; // Vertical radius (reduced)

    List<Widget> playerWidgets = [];

    for (int i = 0; i < totalPlayers; i++) {
      // Distribute players in a circle
      // Starting from -90 degrees (top) or arranging them nicely
      final double angleStep = (2 * math.pi) / totalPlayers;
      final double angle = (i * angleStep) - (math.pi / 2); // Start at top

      final double x = centerX + (radiusX * math.cos(angle));
      final double y = centerY + (radiusY * math.sin(angle));

      playerWidgets.add(Positioned(
        left: x - 35, // Offset by half widget size (70px width)
        top: y - 35, // Offset by half widget size (70px height)
        child: _PresenceTotem(
          player: players[i],
          isCurrentUser: players[i].userId == currentUser,
          isHost: players[i].isHost,
          onKick: (room.hostUserId == currentUser &&
                  players[i].userId != currentUser)
              ? () => _kickPlayer(players[i])
              : null,
        ),
      ));
    }

    return Stack(children: playerWidgets);
  }

  Widget _buildCenterStage(Room? room) {
    if (room == null) return const SizedBox.shrink();

    final currentUserId = Get.find<StorageService>().getUserId();
    final isHost = room.hostUserId == currentUserId;
    final currentPlayer =
        room.players.firstWhereOrNull((p) => p.userId == currentUserId);
    final roomProvider = Get.find<RoomProvider>();

    bool allReady =
        room.players.where((p) => !p.isHost).every((p) => p.isReady);
    bool enoughPlayers = room.currentPlayers >= 5; // Minimum 5 players
    bool canStart = allReady && enoughPlayers;

    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 60), // Push it down a bit
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Status Text
            if (!isHost)
              Text(
                currentPlayer?.isReady == true
                    ? "WAITING FOR HOST"
                    : "ARE YOU READY?",
                style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    letterSpacing: 2,
                    fontSize: 12),
              ),

            const SizedBox(height: 16),

            // MAIN BUTTON
            GestureDetector(
              onTap: () async {
                if (isHost) {
                  if (canStart) {
                    final session = await roomProvider.startGame();
                    if (session != null) Get.offNamed('/game/${session.id}');
                  }
                } else {
                  roomProvider.setReady(!(currentPlayer?.isReady ?? false));
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isHost
                          ? (canStart
                              ? [
                                  const Color(0xFFE94560),
                                  const Color(0xFF53354A)
                                ]
                              : [Colors.grey.shade700, Colors.grey.shade900])
                          : (currentPlayer?.isReady == true
                              ? [
                                  const Color(0xFF0F3460),
                                  const Color(0xFF16213E)
                                ] // Ready (Blue/Calm)
                              : [
                                  const Color(0xFFE94560).withOpacity(0.8),
                                  const Color(0xFF53354A)
                                ]), // Not Ready (Red/Urgent)
                    ),
                    boxShadow: [
                      BoxShadow(
                          color: (isHost && canStart) ||
                                  (!isHost &&
                                      !(currentPlayer?.isReady ?? false))
                              ? const Color(0xFFE94560).withOpacity(0.5)
                              : Colors.blue.withOpacity(0.3),
                          blurRadius: 30,
                          spreadRadius: 5)
                    ],
                    border: Border.all(
                        color: Colors.white.withOpacity(0.2), width: 2)),
                child: Center(
                  child: roomProvider.isLoading.value
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isHost
                                  ? Icons.play_arrow_rounded
                                  : (currentPlayer?.isReady == true
                                      ? Icons.check
                                      : Icons.fingerprint),
                              size: 40,
                              color: Colors.white,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isHost
                                  ? (canStart ? "START" : "WAITING")
                                  : (currentPlayer?.isReady == true
                                      ? "READY"
                                      : "TAP TO\nREADY"),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14),
                            )
                          ],
                        ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Player Count Subtitle
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(20)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.people, size: 14, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text("${room.currentPlayers}/${room.maxPlayers} PLAYERS",
                      style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  void _showLeaveDialog() {
    Get.dialog(
      AlertDialog(
        backgroundColor: const Color(0xFF16213E),
        title: const Text('Leave the Council?',
            style: TextStyle(color: Colors.white)),
        content: const Text('Are you sure you want to leave this room?',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Get.back(),
              child: const Text('Stay', style: TextStyle(color: Colors.white))),
          ElevatedButton(
            onPressed: () async {
              Get.back();
              await Get.find<VoiceProvider>().leaveChannel();
              await Get.find<RoomProvider>().leaveRoom();
              Get.offAllNamed('/home');
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE94560)),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
  }

  void _kickPlayer(RoomPlayer player) {
    Get.dialog(
      AlertDialog(
        backgroundColor: const Color(0xFF16213E),
        title:
            const Text('Kick Player?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Remove ${player.user?.username ?? "this player"} from the council?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
              onPressed: () => Get.back(),
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.white))),
          ElevatedButton(
            onPressed: () {
              Get.back();
              Get.find<RoomProvider>().kickPlayer(player.userId);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE94560)),
            child: const Text('Kick'),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------
// ✨ NEW WIDGETS FOR THE "EXCITING" UI
// --------------------------------------------------------

/// The "Presence Totem" - Replaces the boring card
class _PresenceTotem extends StatelessWidget {
  final RoomPlayer player;
  final bool isHost;
  final bool isCurrentUser;
  final VoidCallback? onKick;

  const _PresenceTotem({
    required this.player,
    required this.isHost,
    required this.isCurrentUser,
    this.onKick,
  });

  @override
  Widget build(BuildContext context) {
    final bool isReady = player.isReady;

    return SizedBox(
      width: 70,
      height: 85, // Reduced from 110 to bring name closer
      child: Stack(
        alignment: Alignment.topCenter,
        clipBehavior: Clip.none,
        children: [
          // 1. The Glow Ring
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            width: 64,
            height: 64,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isHost
                      ? Colors.amber
                      : (isReady
                          ? const Color(0xFF4CAF50)
                          : Colors.grey.withOpacity(0.3)),
                  width: isReady || isHost ? 3 : 1,
                ),
                boxShadow: [
                  if (isReady || isHost)
                    BoxShadow(
                      color: isHost
                          ? Colors.amber.withOpacity(0.4)
                          : const Color(0xFF4CAF50).withOpacity(0.4),
                      blurRadius: 12,
                      spreadRadius: 2,
                    )
                ]),
          ),

          // 2. The Avatar
          Positioned(
            top: 4,
            child: CircleAvatar(
              radius: 28,
              backgroundColor: const Color(0xFF1A1A2E),
              child: Text(
                (player.user?.username ?? "?")[0].toUpperCase(),
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white70),
              ),
            ),
          ),

          // 3. Status Badge (Crown or Check)
          if (isHost)
            Positioned(
              top: -4,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                    color: Colors.black,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.amber, blurRadius: 4)]),
                child: const Icon(Icons.star, color: Colors.amber, size: 12),
              ),
            )
          else if (isReady)
            Positioned(
              top: 46,
              right: 2,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                    color: Colors.black, shape: BoxShape.circle),
                child: const Icon(Icons.check_circle,
                    color: Color(0xFF4CAF50), size: 16),
              ),
            ),

          // 4. Name Tag - Closer to avatar
          Positioned(
            bottom: 0,
            child: Column(
              children: [
                Container(
                  constraints: const BoxConstraints(maxWidth: 80),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    player.user?.username ?? "Unknown",
                    style: TextStyle(
                        color:
                            isCurrentUser ? Colors.amberAccent : Colors.white,
                        fontSize: 10,
                        fontWeight: isCurrentUser
                            ? FontWeight.bold
                            : FontWeight.normal),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
                if (onKick != null)
                  GestureDetector(
                    onTap: onKick,
                    child: const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child:
                          Icon(Icons.cancel, color: Colors.redAccent, size: 14),
                    ),
                  )
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Glassmorphism Voice Control Bar
class _GlassVoiceControls extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.1))),
          child: Obx(() {
            final voiceProvider = Get.find<VoiceProvider>();
            final isConnected = voiceProvider.isInChannel.value;

            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _VoiceButton(
                  active: isConnected,
                  icon: isConnected ? Icons.link : Icons.link_off,
                  color: isConnected ? const Color(0xFF4CAF50) : Colors.grey,
                  onTap:
                      () {}, // Handled automatically usually, or add reconnect logic
                ),
                const SizedBox(width: 16),
                Container(width: 1, height: 24, color: Colors.white24),
                const SizedBox(width: 16),
                _VoiceButton(
                  active: !voiceProvider.isMuted.value,
                  icon: voiceProvider.isMuted.value ? Icons.mic_off : Icons.mic,
                  color: voiceProvider.isMuted.value
                      ? Colors.redAccent
                      : Colors.white,
                  onTap: () {
                    // TODO: Uncomment for voice support
                    // try {
                    //   voiceProvider.toggleMute();
                    // } catch (e) {
                    //   print('Voice control disabled: $e');
                    // }
                  },
                ),
                const SizedBox(width: 16),
                _VoiceButton(
                  active: voiceProvider.isSpeakerOn.value,
                  icon: voiceProvider.isSpeakerOn.value
                      ? Icons.volume_up
                      : Icons.volume_off,
                  color: Colors.white,
                  onTap: () {
                    // TODO: Uncomment for voice support
                    // try {
                    //   voiceProvider.toggleSpeaker();
                    // } catch (e) {
                    //   print('Voice control disabled: $e');
                    // }
                  },
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

class _VoiceButton extends StatelessWidget {
  final bool active;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _VoiceButton(
      {required this.active,
      required this.icon,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
            color: active ? Colors.white.withOpacity(0.1) : Colors.transparent,
            shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 24),
      ),
    );
  }
}

/// Extend Timeout Button for Host
class _ExtendTimeoutButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final roomProvider = Get.find<RoomProvider>();

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withOpacity(0.1),
              width: 1,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () async {
                final success = await roomProvider.extendRoomTimeout();
                if (success) {
                  Get.snackbar(
                    'Success',
                    'Room timeout extended by 20 minutes',
                    snackPosition: SnackPosition.TOP,
                    backgroundColor: const Color(0xFF4CAF50).withOpacity(0.9),
                    colorText: Colors.white,
                    duration: const Duration(seconds: 3),
                    icon: const Icon(Icons.access_time, color: Colors.white),
                  );
                }
              },
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.schedule,
                      color: const Color(0xFFFFB900),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'EXTEND',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the mystical rings on the background
class _CouncilRingPainter extends CustomPainter {
  final AnimationController animation;

  _CouncilRingPainter(this.animation) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.45);
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Draw concentric circles
    canvas.drawCircle(center, size.width * 0.38, paint); // Main player ring

    // Breathing inner ring
    final double breathingScale = 1.0 + (0.05 * animation.value);
    paint.color = const Color(0xFFE94560).withOpacity(0.03);
    paint.strokeWidth = 2.0;
    canvas.drawCircle(center, (size.width * 0.25) * breathingScale, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
