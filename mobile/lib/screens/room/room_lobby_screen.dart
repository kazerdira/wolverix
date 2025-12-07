import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../providers/room_provider.dart';
import '../../providers/voice_provider.dart';
import '../../models/models.dart';
import '../../utils/theme.dart';
import '../../services/storage_service.dart';

class RoomLobbyScreen extends StatefulWidget {
  const RoomLobbyScreen({super.key});

  @override
  State<RoomLobbyScreen> createState() => _RoomLobbyScreenState();
}

class _RoomLobbyScreenState extends State<RoomLobbyScreen> {
  @override
  void initState() {
    super.initState();
    _initializeVoice();
  }

  Future<void> _initializeVoice() async {
    final roomProvider = Get.find<RoomProvider>();
    final voiceProvider = Get.find<VoiceProvider>();
    final room = roomProvider.currentRoom.value;

    if (room != null && room.agoraAppId != null) {
      await voiceProvider.initialize(room.agoraAppId!);
      if (room.agoraChannelName != null) {
        await voiceProvider.joinChannel(room.agoraChannelName!);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        _showLeaveDialog();
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Obx(() {
            final room = Get.find<RoomProvider>().currentRoom.value;
            return Text(room?.name ?? 'Room');
          }),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _showLeaveDialog,
          ),
          actions: [
            // Copy room code
            Obx(() {
              final room = Get.find<RoomProvider>().currentRoom.value;
              return TextButton.icon(
                onPressed: () {
                  if (room != null) {
                    Clipboard.setData(ClipboardData(text: room.roomCode));
                    Get.snackbar(
                      'Copied!',
                      'Room code copied to clipboard',
                      duration: const Duration(seconds: 2),
                    );
                  }
                },
                icon: const Icon(Icons.copy, size: 18),
                label: Text(room?.roomCode ?? ''),
              );
            }),
          ],
        ),
        body: Obx(() {
          final room = Get.find<RoomProvider>().currentRoom.value;

          if (room == null) {
            return const Center(child: CircularProgressIndicator());
          }

          return Column(
            children: [
              // Room info card
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: WolverixTheme.cardColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _InfoItem(
                      icon: Icons.people,
                      label: 'Players',
                      value: '${room.currentPlayers}/${room.maxPlayers}',
                    ),
                    _InfoItem(
                      icon: Icons.language,
                      label: 'Language',
                      value: room.language.toUpperCase(),
                    ),
                    _InfoItem(
                      icon: Icons.timer,
                      label: 'Day Time',
                      value: '${room.config.dayPhaseSeconds}s',
                    ),
                  ],
                ),
              ),

              // Voice controls
              _VoiceControls(),

              // Players list
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: room.players.length,
                  itemBuilder: (context, index) {
                    final player = room.players[index];
                    return _PlayerTile(
                      player: player,
                      isHost: player.isHost,
                      isCurrentUser:
                          player.userId ==
                          Get.find<StorageService>().getUserId(),
                      onKick:
                          room.hostUserId ==
                              Get.find<StorageService>().getUserId()
                          ? () => _kickPlayer(player)
                          : null,
                    );
                  },
                ),
              ),

              // Bottom actions
              Container(
                padding: const EdgeInsets.all(16),
                child: _buildBottomActions(room),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildBottomActions(Room room) {
    final currentUserId = Get.find<StorageService>().getUserId();
    final isHost = room.hostUserId == currentUserId;
    final roomProvider = Get.find<RoomProvider>();

    // Find current player
    final currentPlayer = room.players.firstWhereOrNull(
      (p) => p.userId == currentUserId,
    );

    return Row(
      children: [
        // Ready toggle (for non-hosts)
        if (!isHost)
          Expanded(
            child: ElevatedButton(
              onPressed: () {
                roomProvider.setReady(!(currentPlayer?.isReady ?? false));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: currentPlayer?.isReady == true
                    ? WolverixTheme.successColor
                    : WolverixTheme.cardColor,
              ),
              child: Text(
                currentPlayer?.isReady == true ? 'Ready ✓' : 'Not Ready',
              ),
            ),
          ),

        // Start game (for host)
        if (isHost) ...[
          Expanded(
            child: Obx(() {
              final allReady = room.players
                  .where((p) => !p.isHost)
                  .every((p) => p.isReady);
              final enoughPlayers = room.currentPlayers >= 5;
              final canStart = allReady && enoughPlayers;

              return ElevatedButton(
                onPressed: canStart
                    ? () async {
                        final session = await roomProvider.startGame();
                        if (session != null) {
                          Get.offNamed('/game/${session.id}');
                        }
                      }
                    : null,
                child: roomProvider.isLoading.value
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        !enoughPlayers
                            ? 'Need ${5 - room.currentPlayers} more players'
                            : !allReady
                            ? 'Waiting for players'
                            : 'Start Game',
                      ),
              );
            }),
          ),
        ],
      ],
    );
  }

  void _showLeaveDialog() {
    Get.dialog(
      AlertDialog(
        title: const Text('Leave Room?'),
        content: const Text('Are you sure you want to leave this room?'),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Get.back();
              await Get.find<VoiceProvider>().leaveChannel();
              await Get.find<RoomProvider>().leaveRoom();
              Get.offAllNamed('/home');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: WolverixTheme.errorColor,
            ),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
  }

  void _kickPlayer(RoomPlayer player) {
    Get.dialog(
      AlertDialog(
        title: const Text('Kick Player?'),
        content: Text(
          'Remove ${player.user?.username ?? "this player"} from the room?',
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Get.back();
              Get.find<RoomProvider>().kickPlayer(player.userId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: WolverixTheme.errorColor,
            ),
            child: const Text('Kick'),
          ),
        ],
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: WolverixTheme.primaryColor),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: WolverixTheme.textSecondary),
        ),
      ],
    );
  }
}

class _VoiceControls extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final voiceProvider = Get.find<VoiceProvider>();

      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: WolverixTheme.surfaceColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              voiceProvider.isInChannel.value ? Icons.mic : Icons.mic_off,
              color: voiceProvider.isInChannel.value
                  ? WolverixTheme.successColor
                  : WolverixTheme.textSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                voiceProvider.isInChannel.value
                    ? 'Connected to voice'
                    : 'Voice not connected',
                style: TextStyle(
                  color: voiceProvider.isInChannel.value
                      ? WolverixTheme.textPrimary
                      : WolverixTheme.textSecondary,
                ),
              ),
            ),
            if (voiceProvider.isInChannel.value) ...[
              IconButton(
                icon: Icon(
                  voiceProvider.isMuted.value ? Icons.mic_off : Icons.mic,
                  color: voiceProvider.isMuted.value
                      ? WolverixTheme.errorColor
                      : WolverixTheme.primaryColor,
                ),
                onPressed: () => voiceProvider.toggleMute(),
              ),
              IconButton(
                icon: Icon(
                  voiceProvider.isSpeakerOn.value
                      ? Icons.volume_up
                      : Icons.volume_off,
                  color: WolverixTheme.primaryColor,
                ),
                onPressed: () => voiceProvider.toggleSpeaker(),
              ),
            ],
          ],
        ),
      );
    });
  }
}

class _PlayerTile extends StatelessWidget {
  final RoomPlayer player;
  final bool isHost;
  final bool isCurrentUser;
  final VoidCallback? onKick;

  const _PlayerTile({
    required this.player,
    required this.isHost,
    required this.isCurrentUser,
    this.onKick,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Stack(
          children: [
            CircleAvatar(
              backgroundColor: isHost
                  ? WolverixTheme.accentColor
                  : WolverixTheme.primaryColor,
              child: Text(
                (player.user?.username ?? 'U').substring(0, 1).toUpperCase(),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            if (isHost)
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: WolverixTheme.backgroundColor,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.star, size: 14, color: Colors.amber),
                ),
              ),
          ],
        ),
        title: Row(
          children: [
            Text(player.user?.username ?? 'Player'),
            if (isCurrentUser)
              const Text(
                ' (You)',
                style: TextStyle(color: WolverixTheme.textSecondary),
              ),
          ],
        ),
        subtitle: Text(
          isHost ? 'Host' : (player.isReady ? 'Ready' : 'Not Ready'),
          style: TextStyle(
            color: isHost
                ? WolverixTheme.accentColor
                : (player.isReady
                      ? WolverixTheme.successColor
                      : WolverixTheme.textSecondary),
          ),
        ),
        trailing: onKick != null && !isCurrentUser && !isHost
            ? IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                color: WolverixTheme.errorColor,
                onPressed: onKick,
              )
            : (player.isReady && !isHost
                  ? const Icon(
                      Icons.check_circle,
                      color: WolverixTheme.successColor,
                    )
                  : null),
      ),
    );
  }
}
