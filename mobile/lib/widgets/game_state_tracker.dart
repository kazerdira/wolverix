import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/models.dart';
import '../providers/game_provider.dart';

class GameStateTracker extends StatelessWidget {
  const GameStateTracker({super.key});

  @override
  Widget build(BuildContext context) {
    final GameProvider gameProvider = Get.find<GameProvider>();

    return Obx(() {
      final session = gameProvider.session.value;
      final myPlayer = gameProvider.myPlayer.value;
      final phase = gameProvider.currentPhase;

      if (session == null || myPlayer == null) {
        return const SizedBox.shrink();
      }

      final alivePlayers = session.players.where((p) => p.isAlive).length;
      final totalPlayers = session.players.length;
      final phaseColor = _getPhaseColor(phase);
      final phaseIcon = _getPhaseIcon(phase);

      return Card(
        margin: const EdgeInsets.all(16),
        elevation: 4,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [phaseColor.withOpacity(0.1), Colors.white],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Phase Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: phaseColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(phaseIcon, color: phaseColor, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getPhaseTitle(phase),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: phaseColor,
                            ),
                          ),
                          Text(
                            'Day ${session.dayNumber}',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Timer
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: phaseColor, width: 2),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.timer, size: 16, color: phaseColor),
                          const SizedBox(width: 4),
                          Obx(() {
                            final time = gameProvider.phaseTimeRemaining.value;
                            return Text(
                              '${time.inMinutes}:${(time.inSeconds % 60).toString().padLeft(2, '0')}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: phaseColor,
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 12),

                // Player Status
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatusItem(
                      icon: Icons.person,
                      label: 'Alive',
                      value: '$alivePlayers/$totalPlayers',
                      color: Colors.green,
                    ),
                    _buildStatusItem(
                      icon: Icons.assignment_ind,
                      label: 'Your Role',
                      value: myPlayer.role != null
                          ? _getRoleDisplayName(myPlayer.role!)
                          : 'Unknown',
                      color: myPlayer.role != null
                          ? _getRoleColor(myPlayer.role!)
                          : Colors.grey,
                    ),
                    _buildStatusItem(
                      icon: myPlayer.isAlive
                          ? Icons.favorite
                          : Icons.heart_broken,
                      label: 'Status',
                      value: myPlayer.isAlive ? 'Alive' : 'Dead',
                      color: myPlayer.isAlive ? Colors.red : Colors.grey,
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Phase Description
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: phaseColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: phaseColor.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: phaseColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _getPhaseDescription(phase, myPlayer),
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _buildStatusItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Color _getPhaseColor(GamePhase phase) {
    switch (phase) {
      case GamePhase.night0:
      case GamePhase.cupidPhase:
      case GamePhase.werewolfPhase:
      case GamePhase.seerPhase:
      case GamePhase.witchPhase:
      case GamePhase.bodyguardPhase:
        return Colors.indigo;
      case GamePhase.dayDiscussion:
        return Colors.blue;
      case GamePhase.dayVoting:
      case GamePhase.finalVote:
        return Colors.amber;
      case GamePhase.defensePhase:
        return Colors.orange;
      case GamePhase.hunterPhase:
        return Colors.deepOrange;
      case GamePhase.mayorReveal:
        return Colors.purple;
      case GamePhase.gameOver:
        return Colors.grey;
    }
  }

  IconData _getPhaseIcon(GamePhase phase) {
    switch (phase) {
      case GamePhase.night0:
      case GamePhase.cupidPhase:
      case GamePhase.werewolfPhase:
      case GamePhase.seerPhase:
      case GamePhase.witchPhase:
      case GamePhase.bodyguardPhase:
        return Icons.nightlight_round;
      case GamePhase.dayDiscussion:
        return Icons.chat;
      case GamePhase.dayVoting:
      case GamePhase.finalVote:
        return Icons.how_to_vote;
      case GamePhase.defensePhase:
        return Icons.gavel;
      case GamePhase.hunterPhase:
        return Icons.my_location;
      case GamePhase.mayorReveal:
        return Icons.military_tech;
      case GamePhase.gameOver:
        return Icons.emoji_events;
    }
  }

  String _getPhaseTitle(GamePhase phase) {
    switch (phase) {
      case GamePhase.night0:
        return 'First Night';
      case GamePhase.cupidPhase:
        return 'Cupid Phase';
      case GamePhase.werewolfPhase:
        return 'Werewolf Hunt';
      case GamePhase.seerPhase:
        return 'Seer Vision';
      case GamePhase.witchPhase:
        return 'Witch Turn';
      case GamePhase.bodyguardPhase:
        return 'Bodyguard Protection';
      case GamePhase.dayDiscussion:
        return 'Day Discussion';
      case GamePhase.dayVoting:
        return 'Lynch Voting';
      case GamePhase.finalVote:
        return 'Final Vote';
      case GamePhase.defensePhase:
        return 'Defense';
      case GamePhase.hunterPhase:
        return 'Hunter\'s Revenge';
      case GamePhase.mayorReveal:
        return 'Mayor Reveal';
      case GamePhase.gameOver:
        return 'Game Over';
    }
  }

  String _getPhaseDescription(GamePhase phase, GamePlayer myPlayer) {
    final bool isMyTurn = Get.find<GameProvider>().isMyTurn;
    final bool isAlive = myPlayer.isAlive;

    if (!isAlive) {
      return 'You are dead. Watch and wait for the game to end.';
    }

    switch (phase) {
      case GamePhase.night0:
        if (isMyTurn) {
          return 'It\'s your turn! Perform your night action now.';
        }
        return 'Wait for other players to complete their actions.';

      case GamePhase.werewolfPhase:
        if (isMyTurn) {
          return 'Choose a player to eliminate tonight.';
        }
        return 'The werewolves are choosing their victim...';

      case GamePhase.seerPhase:
        if (isMyTurn) {
          return 'Use your power to discover a player\'s identity.';
        }
        return 'The seer is investigating...';

      case GamePhase.witchPhase:
        if (isMyTurn) {
          return 'Choose to save the victim or poison someone.';
        }
        return 'The witch is deciding...';

      case GamePhase.bodyguardPhase:
        if (isMyTurn) {
          return 'Select a player to protect from werewolves.';
        }
        return 'The bodyguard is choosing who to protect...';

      case GamePhase.cupidPhase:
        if (isMyTurn) {
          return 'Choose two players to become lovers.';
        }
        return 'Cupid is selecting the lovers...';

      case GamePhase.dayDiscussion:
        return 'Discuss and find the werewolves. Voting comes next.';

      case GamePhase.dayVoting:
        return 'Vote for who you think is a werewolf to lynch them.';

      case GamePhase.finalVote:
        return 'Final vote! Choose carefully.';

      case GamePhase.defensePhase:
        return 'The accused player is defending themselves.';

      case GamePhase.hunterPhase:
        if (isMyTurn) {
          return 'You\'re dying! Choose someone to take with you.';
        }
        return 'The hunter is taking their final shot...';

      case GamePhase.mayorReveal:
        return 'The mayor is being revealed.';

      case GamePhase.gameOver:
        return 'Game has ended. Check the results!';
    }
  }

  String _getRoleDisplayName(GameRole role) {
    switch (role) {
      case GameRole.werewolf:
        return 'Werewolf';
      case GameRole.seer:
        return 'Seer';
      case GameRole.witch:
        return 'Witch';
      case GameRole.bodyguard:
        return 'Bodyguard';
      case GameRole.cupid:
        return 'Cupid';
      case GameRole.hunter:
        return 'Hunter';
      case GameRole.villager:
        return 'Villager';
      case GameRole.mayor:
        return 'Mayor';
      case GameRole.medium:
        return 'Medium';
      case GameRole.tanner:
        return 'Tanner';
      case GameRole.littleGirl:
        return 'Little Girl';
    }
  }

  Color _getRoleColor(GameRole role) {
    switch (role) {
      case GameRole.werewolf:
        return Colors.red;
      case GameRole.seer:
        return Colors.purple;
      case GameRole.witch:
        return Colors.green;
      case GameRole.bodyguard:
        return Colors.blue;
      case GameRole.cupid:
        return Colors.pink;
      case GameRole.hunter:
        return Colors.orange;
      case GameRole.villager:
        return Colors.brown;
      case GameRole.mayor:
        return Colors.amber;
      case GameRole.medium:
        return Colors.deepPurple;
      case GameRole.tanner:
        return Colors.brown.shade700;
      case GameRole.littleGirl:
        return Colors.pinkAccent;
    }
  }
}
