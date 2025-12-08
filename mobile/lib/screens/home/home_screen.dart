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
          // Tabs for Active/History
          Expanded(
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  TabBar(
                    labelColor: WolverixTheme.primaryColor,
                    unselectedLabelColor: WolverixTheme.textSecondary,
                    indicatorColor: WolverixTheme.primaryColor,
                    tabs: const [
                      Tab(text: 'Active Rooms'),
                      Tab(text: 'History'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        // Active Rooms Tab
                        _buildActiveRoomsTab(),
                        // History Tab
                        _buildHistoryTab(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveRoomsTab() {
    return Obx(() {
      final roomProvider = Get.find<RoomProvider>();

      if (roomProvider.isLoading.value) {
        return const Center(child: CircularProgressIndicator());
      }

      final activeRooms = roomProvider.availableRooms
          .where((r) => r.status == RoomStatus.waiting)
          .toList();

      if (activeRooms.isEmpty) {
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
                'No active rooms',
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
          padding: const EdgeInsets.all(16),
          itemCount: activeRooms.length,
          itemBuilder: (context, index) {
            return _RoomCard(room: activeRooms[index]);
          },
        ),
      );
    });
  }

  Widget _buildHistoryTab() {
    return Obx(() {
      final roomProvider = Get.find<RoomProvider>();

      if (roomProvider.isLoading.value) {
        return const Center(child: CircularProgressIndicator());
      }

      final historyRooms = roomProvider.availableRooms
          .where((r) => r.status != RoomStatus.waiting)
          .toList();

      if (historyRooms.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.history,
                size: 80,
                color: WolverixTheme.textHint,
              ),
              const SizedBox(height: 16),
              Text(
                'No game history yet',
                style: TextStyle(
                  fontSize: 18,
                  color: WolverixTheme.textSecondary,
                ),
              ),
            ],
          ),
        );
      }

      return RefreshIndicator(
        onRefresh: () => roomProvider.fetchRooms(),
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: historyRooms.length,
          itemBuilder: (context, index) {
            return _RoomCard(room: historyRooms[index], isHistory: true);
          },
        ),
      );
    });
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
  final bool isHistory;

  const _RoomCard({required this.room, this.isHistory = false});

  @override
  Widget build(BuildContext context) {
    final cardColor = isHistory
        ? WolverixTheme.cardColor.withOpacity(0.5)
        : WolverixTheme.cardColor;
    final iconColor =
        isHistory ? WolverixTheme.textSecondary : WolverixTheme.primaryColor;
    final textOpacity = isHistory ? 0.6 : 1.0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: cardColor,
      child: InkWell(
        onTap: isHistory
            ? null
            : () async {
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
                  color: iconColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isHistory ? Icons.history : Icons.groups,
                  color: iconColor,
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
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color:
                            WolverixTheme.textPrimary.withOpacity(textOpacity),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Host: ${room.host?.username ?? "Unknown"}',
                      style: TextStyle(
                        fontSize: 14,
                        color: WolverixTheme.textSecondary
                            .withOpacity(textOpacity),
                      ),
                    ),
                    if (isHistory) ...[
                      const SizedBox(height: 4),
                      Text(
                        room.status.name.toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: WolverixTheme.textHint,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Player count
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${room.currentPlayers}/${room.maxPlayers}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: WolverixTheme.textPrimary.withOpacity(textOpacity),
                    ),
                  ),
                  Text(
                    'players',
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          WolverixTheme.textSecondary.withOpacity(textOpacity),
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
