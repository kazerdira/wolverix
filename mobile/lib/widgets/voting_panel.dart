import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/models.dart';
import '../providers/game_provider.dart';

class VotingPanel extends StatefulWidget {
  const VotingPanel({super.key});

  @override
  State<VotingPanel> createState() => _VotingPanelState();
}

class _VotingPanelState extends State<VotingPanel> {
  final GameProvider gameProvider = Get.find<GameProvider>();
  String? selectedTarget;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final myPlayer = gameProvider.myPlayer.value;
      final phase = gameProvider.currentPhase;

      if (myPlayer == null || !myPlayer.isAlive) {
        return const SizedBox.shrink();
      }

      if (phase != GamePhase.dayVoting && phase != GamePhase.finalVote) {
        return const SizedBox.shrink();
      }

      return Card(
        margin: const EdgeInsets.all(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.how_to_vote, color: Colors.amber, size: 32),
                  const SizedBox(width: 12),
                  Text(
                    phase == GamePhase.finalVote
                        ? 'Final Vote'
                        : 'Vote to Lynch',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (phase == GamePhase.finalVote)
                const Text(
                  'This is the final vote. The player with the most votes will be lynched.',
                  style:
                      TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
                ),
              const SizedBox(height: 12),
              _buildVoteList(),
              const SizedBox(height: 16),
              Obx(() => Text(
                    'Time remaining: ${gameProvider.phaseTimeRemaining.value.inMinutes}:${(gameProvider.phaseTimeRemaining.value.inSeconds % 60).toString().padLeft(2, '0')}',
                    style: const TextStyle(color: Colors.grey),
                  )),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildVoteList() {
    final selectablePlayers = gameProvider.getSelectablePlayers();

    return Column(
      children: selectablePlayers.map((player) {
        final isSelected = selectedTarget == player.id;

        return Card(
          elevation: isSelected ? 4 : 1,
          color: isSelected ? Colors.amber.shade50 : null,
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isSelected ? Colors.amber : Colors.grey,
              child: Text(
                player.seatPosition.toString(),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(
              player.user?.username ?? 'Player ${player.seatPosition}',
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            subtitle: isSelected ? const Text('Your vote') : null,
            trailing: isSelected
                ? const Icon(Icons.check_circle, color: Colors.amber)
                : null,
            onTap: () => _castVote(player.id),
          ),
        );
      }).toList(),
    );
  }

  Future<void> _castVote(String targetId) async {
    setState(() => selectedTarget = targetId);

    final success = await gameProvider.vote(targetId);
    if (success) {
      Get.snackbar(
        'Vote Cast',
        'Your vote has been recorded',
        backgroundColor: Colors.amber.withOpacity(0.9),
        colorText: Colors.black,
      );
    } else {
      setState(() => selectedTarget = null);
    }
  }
}
