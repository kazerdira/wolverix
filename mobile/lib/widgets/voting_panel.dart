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

              // Vote progress indicator
              Obx(() {
                final totalVoted = gameProvider.totalVotes.value;
                final alivePlayers = gameProvider.session.value?.players
                        .where((p) => p.isAlive)
                        .length ??
                    0;

                if (alivePlayers > 0) {
                  return Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Votes: $totalVoted / $alivePlayers',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            '${((totalVoted / alivePlayers) * 100).toStringAsFixed(0)}%',
                            style: TextStyle(
                              color: totalVoted == alivePlayers
                                  ? Colors.green
                                  : Colors.grey,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: totalVoted / alivePlayers,
                        backgroundColor: Colors.grey.shade300,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          totalVoted == alivePlayers
                              ? Colors.green
                              : Colors.amber,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  );
                }
                return const SizedBox.shrink();
              }),

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
        final votes = gameProvider.voteCount[player.id] ?? 0;
        final hasVotes = votes > 0;

        return Card(
          elevation: isSelected ? 4 : 1,
          color: isSelected
              ? Colors.amber.shade50
              : (hasVotes ? Colors.red.shade50 : null),
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isSelected
                  ? Colors.amber
                  : (hasVotes ? Colors.red : Colors.grey),
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
            subtitle: isSelected
                ? const Text('Your vote')
                : (hasVotes
                    ? Text('$votes vote${votes > 1 ? 's' : ''}')
                    : null),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasVotes)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$votes',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                  ),
                if (isSelected)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(Icons.check_circle, color: Colors.amber),
                  ),
              ],
            ),
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
