import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/models.dart';
import '../providers/game_provider.dart';

class GameOverScreen extends StatelessWidget {
  const GameOverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final GameProvider gameProvider = Get.find<GameProvider>();

    return Obx(() {
      final session = gameProvider.session.value;
      if (session == null || session.winner == null) {
        return const SizedBox.shrink();
      }

      final winner = session.winner!;
      final myPlayer = gameProvider.myPlayer.value;
      final didIWin = _didPlayerWin(myPlayer, winner, session.players);

      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: didIWin
                ? [Colors.green.shade700, Colors.green.shade500]
                : [Colors.red.shade700, Colors.red.shade500],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 40),
              Icon(
                didIWin ? Icons.emoji_events : Icons.sentiment_dissatisfied,
                size: 100,
                color: Colors.white,
              ),
              const SizedBox(height: 24),
              Text(
                didIWin ? 'VICTORY!' : 'DEFEAT',
                style: const TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _getWinnerText(winner),
                style: const TextStyle(
                  fontSize: 24,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: _buildPlayersList(session.players, winner),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          gameProvider.clearGame();
                          Get.offAllNamed('/home');
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Colors.white,
                          foregroundColor: didIWin ? Colors.green : Colors.red,
                        ),
                        child: const Text(
                          'Return to Lobby',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  bool _didPlayerWin(
      GamePlayer? myPlayer, String winner, List<GamePlayer> allPlayers) {
    if (myPlayer == null) return false;

    switch (winner) {
      case 'werewolves':
        return myPlayer.team == GameTeam.werewolves;
      case 'villagers':
        return myPlayer.team == GameTeam.villagers;
      case 'lovers':
        return myPlayer.loverId != null;
      case 'tanner':
        return myPlayer.role == GameRole.tanner;
      default:
        return false;
    }
  }

  String _getWinnerText(String winner) {
    switch (winner) {
      case 'werewolves':
        return 'The Werewolves Win!';
      case 'villagers':
        return 'The Villagers Win!';
      case 'lovers':
        return 'The Lovers Win!';
      case 'tanner':
        return 'The Tanner Wins!';
      default:
        return 'Game Over';
    }
  }

  Widget _buildPlayersList(List<GamePlayer> players, String winner) {
    return ListView(
      children: [
        const Text(
          'Final Roles',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        ...players.map((player) {
          final isWinner = _isPlayerWinner(player, winner);

          return Card(
            color: isWinner ? Colors.amber.shade50 : null,
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: isWinner ? Colors.amber : Colors.grey,
                child: Text(
                  player.seatPosition.toString(),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              title: Row(
                children: [
                  Text(
                    player.user?.username ?? 'Player ${player.seatPosition}',
                    style: TextStyle(
                      fontWeight:
                          isWinner ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  if (isWinner) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.emoji_events,
                        color: Colors.amber, size: 16),
                  ],
                ],
              ),
              subtitle: Text(
                '${_getRoleDisplayName(player.role)} • ${_getTeamDisplayName(player.team)}${player.loverId != null ? ' • Lover' : ''}',
              ),
              trailing: player.isAlive
                  ? const Icon(Icons.favorite, color: Colors.red)
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.close, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          player.deathReason ?? 'Dead',
                          style:
                              const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
            ),
          );
        }).toList(),
      ],
    );
  }

  bool _isPlayerWinner(GamePlayer player, String winner) {
    switch (winner) {
      case 'werewolves':
        return player.team == GameTeam.werewolves;
      case 'villagers':
        return player.team == GameTeam.villagers;
      case 'lovers':
        return player.loverId != null;
      case 'tanner':
        return player.role == GameRole.tanner;
      default:
        return false;
    }
  }

  String _getRoleDisplayName(GameRole? role) {
    if (role == null) return 'Unknown';

    switch (role) {
      case GameRole.werewolf:
        return 'Werewolf';
      case GameRole.villager:
        return 'Villager';
      case GameRole.seer:
        return 'Seer';
      case GameRole.witch:
        return 'Witch';
      case GameRole.hunter:
        return 'Hunter';
      case GameRole.cupid:
        return 'Cupid';
      case GameRole.bodyguard:
        return 'Bodyguard';
      case GameRole.mayor:
        return 'Mayor';
      case GameRole.medium:
        return 'Medium';
      case GameRole.tanner:
        return 'Tanner';
      case GameRole.littleGirl:
        return 'Little Girl';
      default:
        return role.toString();
    }
  }

  String _getTeamDisplayName(GameTeam? team) {
    if (team == null) return 'Unknown';

    switch (team) {
      case GameTeam.werewolves:
        return 'Werewolves';
      case GameTeam.villagers:
        return 'Villagers';
      case GameTeam.neutral:
        return 'Neutral';
      default:
        return team.toString();
    }
  }
}
