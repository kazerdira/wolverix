import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/models.dart';
import '../providers/game_provider.dart';

class PhaseTimerWidget extends StatelessWidget {
  const PhaseTimerWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final GameProvider gameProvider = Get.find<GameProvider>();

    return Obx(() {
      final phase = gameProvider.currentPhase;
      final timeRemaining = gameProvider.phaseTimeRemaining.value;

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _getPhaseGradient(phase),
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(
                  _getPhaseIcon(phase),
                  color: Colors.white,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _getPhaseDisplayName(phase),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Day ${gameProvider.session.value?.dayNumber ?? 0} • Phase ${gameProvider.session.value?.phaseNumber ?? 0}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (timeRemaining.inSeconds > 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: timeRemaining.inSeconds < 30
                      ? Colors.red.withOpacity(0.8)
                      : Colors.black.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.timer, color: Colors.white, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      '${timeRemaining.inMinutes}:${(timeRemaining.inSeconds % 60).toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
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

  List<Color> _getPhaseGradient(GamePhase phase) {
    switch (phase) {
      case GamePhase.night0:
      case GamePhase.cupidPhase:
      case GamePhase.werewolfPhase:
      case GamePhase.seerPhase:
      case GamePhase.witchPhase:
      case GamePhase.bodyguardPhase:
        return [Colors.indigo.shade900, Colors.indigo.shade700];
      case GamePhase.dayDiscussion:
      case GamePhase.dayVoting:
      case GamePhase.defensePhase:
      case GamePhase.finalVote:
        return [Colors.amber.shade700, Colors.amber.shade500];
      case GamePhase.hunterPhase:
        return [Colors.orange.shade700, Colors.orange.shade500];
      case GamePhase.mayorReveal:
        return [Colors.purple.shade700, Colors.purple.shade500];
      case GamePhase.gameOver:
        return [Colors.grey.shade700, Colors.grey.shade500];
      default:
        return [Colors.blue.shade700, Colors.blue.shade500];
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
      case GamePhase.dayVoting:
      case GamePhase.defensePhase:
      case GamePhase.finalVote:
        return Icons.wb_sunny;
      case GamePhase.hunterPhase:
        return Icons.gps_fixed;
      case GamePhase.mayorReveal:
        return Icons.emoji_events;
      case GamePhase.gameOver:
        return Icons.flag;
      default:
        return Icons.info;
    }
  }

  String _getPhaseDisplayName(GamePhase phase) {
    switch (phase) {
      case GamePhase.night0:
        return 'First Night';
      case GamePhase.cupidPhase:
        return 'Cupid Choosing';
      case GamePhase.werewolfPhase:
        return 'Werewolf Hunt';
      case GamePhase.seerPhase:
        return 'Seer Divination';
      case GamePhase.witchPhase:
        return 'Witch Decision';
      case GamePhase.bodyguardPhase:
        return 'Bodyguard Protection';
      case GamePhase.dayDiscussion:
        return 'Day Discussion';
      case GamePhase.dayVoting:
        return 'Voting Time';
      case GamePhase.defensePhase:
        return 'Defense Phase';
      case GamePhase.finalVote:
        return 'Final Vote';
      case GamePhase.hunterPhase:
        return 'Hunter Revenge';
      case GamePhase.mayorReveal:
        return 'Mayor Reveal';
      case GamePhase.gameOver:
        return 'Game Over';
      default:
        return phase.toString();
    }
  }
}
