import 'package:flutter/material.dart';
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

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    Get.find<RoomProvider>().fetchRooms();
    Get.find<AuthProvider>().fetchUserStats();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WOLVERIX'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => Get.find<RoomProvider>().fetchRooms(),
          ),
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () => _showProfileSheet(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Action buttons
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    icon: Icons.add_circle_outline,
                    label: 'Create Room',
                    color: WolverixTheme.primaryColor,
                    onTap: () => Get.toNamed('/create-room'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _ActionButton(
                    icon: Icons.login,
                    label: 'Join Room',
                    color: WolverixTheme.secondaryColor,
                    onTap: () => Get.toNamed('/join-room'),
                  ),
                ),
              ],
            ),
          ),
          // Room list header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Available Rooms',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Obx(() {
                  final rooms = Get.find<RoomProvider>().availableRooms;
                  return Text(
                    '${rooms.length} rooms',
                    style: TextStyle(color: WolverixTheme.textSecondary),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Room list
          Expanded(
            child: Obx(() {
              final roomProvider = Get.find<RoomProvider>();

              if (roomProvider.isLoading.value) {
                return const Center(child: CircularProgressIndicator());
              }

              if (roomProvider.availableRooms.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.meeting_room_outlined,
                        size: 80,
                        color: WolverixTheme.textHint,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No rooms available',
                        style: TextStyle(
                          fontSize: 18,
                          color: WolverixTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Create one to start playing!',
                        style: TextStyle(color: WolverixTheme.textHint),
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: () => roomProvider.fetchRooms(),
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: roomProvider.availableRooms.length,
                  itemBuilder: (context, index) {
                    final room = roomProvider.availableRooms[index];
                    return _RoomCard(room: room);
                  },
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  void _showProfileSheet() {
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Profile header
            Obx(() {
              final user = Get.find<AuthProvider>().currentUser.value;
              return Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: WolverixTheme.primaryColor,
                    child: Text(
                      user?.username.substring(0, 1).toUpperCase() ?? 'U',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.username ?? 'User',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          user?.email ?? '',
                          style: TextStyle(color: WolverixTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }),
            const SizedBox(height: 24),
            // Stats
            Obx(() {
              final stats = Get.find<AuthProvider>().userStats.value;
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _StatItem(
                    label: 'Games',
                    value: '${stats?.gamesPlayed ?? 0}',
                  ),
                  _StatItem(label: 'Wins', value: '${stats?.gamesWon ?? 0}'),
                  _StatItem(
                    label: 'Win Rate',
                    value:
                        '${((stats?.winRate ?? 0) * 100).toStringAsFixed(0)}%',
                  ),
                ],
              );
            }),
            const SizedBox(height: 24),
            // Logout button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Get.back();
                  Get.find<AuthProvider>().logout();
                },
                icon: const Icon(Icons.logout, color: WolverixTheme.errorColor),
                label: const Text(
                  'Logout',
                  style: TextStyle(color: WolverixTheme.errorColor),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: WolverixTheme.errorColor),
                ),
              ),
            ),
          ],
        ),
      ),
      backgroundColor: WolverixTheme.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withOpacity(0.15),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            children: [
              Icon(icon, size: 32, color: color),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(fontWeight: FontWeight.w600, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  final Room room;

  const _RoomCard({required this.room});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () async {
          final roomProvider = Get.find<RoomProvider>();
          final success = await roomProvider.joinRoom(room.roomCode);
          if (success) {
            Get.toNamed('/room/${room.id}');
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Room icon
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: WolverixTheme.primaryColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.groups,
                  color: WolverixTheme.primaryColor,
                ),
              ),
              const SizedBox(width: 16),
              // Room info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      room.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Host: ${room.host?.username ?? "Unknown"}',
                      style: TextStyle(
                        fontSize: 14,
                        color: WolverixTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // Player count
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${room.currentPlayers}/${room.maxPlayers}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'players',
                    style: TextStyle(
                      fontSize: 12,
                      color: WolverixTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;

  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        Text(label, style: TextStyle(color: WolverixTheme.textSecondary)),
      ],
    );
  }
}
