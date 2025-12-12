import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../providers/game_provider.dart';
import '../../providers/voice_provider.dart';
import '../../models/models.dart';
import '../../utils/theme.dart';
import '../../widgets/game_state_tracker.dart';
import '../../widgets/night_action_panel.dart';
import '../../widgets/voting_panel.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  @override
  void initState() {
    super.initState();
    final sessionId = Get.parameters['sessionId'];
    if (sessionId != null) {
      Get.find<GameProvider>().loadGame(sessionId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Obx(() {
          final gameProvider = Get.find<GameProvider>();
          final session = gameProvider.session.value;
          final myPlayer = gameProvider.myPlayer.value;

          if (gameProvider.isLoading.value || session == null) {
            return const Center(child: CircularProgressIndicator());
          }

          // Game Over screen
          if (session.winner != null) {
            return _GameOverScreen(
              winner: session.winner!,
              myPlayer: myPlayer,
              players: session.players,
            );
          }

          return Column(
            children: [
              // Game State Tracker (new comprehensive info widget)
              const GameStateTracker(),

              // Voice controls
              _VoiceBar(),

              // Main game area
              Expanded(
                child: _GameArea(session: session, myPlayer: myPlayer),
              ),

              // Action panels
              if (myPlayer != null && myPlayer.isAlive) ...[
                const NightActionPanel(),
                const VotingPanel(),
              ],
            ],
          );
        }),
      ),
    );
  }
}

class _PhaseHeader extends StatelessWidget {
  final GamePhase phase;
  final int dayNumber;
  final Duration timeRemaining;

  const _PhaseHeader({
    required this.phase,
    required this.dayNumber,
    required this.timeRemaining,
  });

  @override
  Widget build(BuildContext context) {
    final isNight = phase.isNightPhase;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isNight
              ? [const Color(0xFF1a1a2e), const Color(0xFF16213e)]
              : [const Color(0xFF2e4057), const Color(0xFF4a6fa5)],
        ),
      ),
      child: Row(
        children: [
          Icon(
            isNight ? Icons.nightlight_round : Icons.wb_sunny,
            color: isNight ? Colors.amber : Colors.orange,
            size: 30,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isNight ? 'Night $dayNumber' : 'Day $dayNumber',
                  style: const TextStyle(fontSize: 14, color: Colors.white70),
                ),
                Text(
                  phase.displayName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // Timer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                const Icon(Icons.timer, size: 18),
                const SizedBox(width: 4),
                Text(
                  '${timeRemaining.inMinutes}:${(timeRemaining.inSeconds % 60).toString().padLeft(2, '0')}',
                  style: const TextStyle(
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
  }
}

class _RoleCard extends StatelessWidget {
  final GamePlayer player;

  const _RoleCard({required this.player});

  @override
  Widget build(BuildContext context) {
    final role = player.role;
    if (role == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WolverixTheme.getRoleColor(role.name).withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: WolverixTheme.getRoleColor(role.name),
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: WolverixTheme.getRoleColor(role.name),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_getRoleIcon(role), color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your Role: ${role.displayName}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  role.description,
                  style: TextStyle(
                    fontSize: 12,
                    color: WolverixTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // Status indicators
          Column(
            children: [
              if (player.loverId != null)
                const Icon(Icons.favorite, color: Colors.pink, size: 20),
              if (player.isMayor)
                const Icon(Icons.star, color: Colors.amber, size: 20),
            ],
          ),
        ],
      ),
    );
  }

  IconData _getRoleIcon(GameRole role) {
    switch (role) {
      case GameRole.werewolf:
        return Icons.pets;
      case GameRole.seer:
        return Icons.visibility;
      case GameRole.witch:
        return Icons.science;
      case GameRole.hunter:
        return Icons.gps_fixed;
      case GameRole.cupid:
        return Icons.favorite;
      case GameRole.bodyguard:
        return Icons.shield;
      case GameRole.tanner:
        return Icons.work;
      default:
        return Icons.person;
    }
  }
}

class _VoiceBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final voiceProvider = Get.find<VoiceProvider>();

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: WolverixTheme.surfaceColor,
        child: Row(
          children: [
            Icon(
              Icons.mic,
              size: 20,
              color: voiceProvider.isMuted.value
                  ? WolverixTheme.errorColor
                  : WolverixTheme.successColor,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                voiceProvider.isMuted.value ? 'Muted' : 'Speaking',
                style: TextStyle(
                  color: WolverixTheme.textSecondary,
                  fontSize: 14,
                ),
              ),
            ),
            IconButton(
              icon: Icon(
                voiceProvider.isMuted.value ? Icons.mic_off : Icons.mic,
              ),
              onPressed: () => voiceProvider.toggleMute(),
              color: voiceProvider.isMuted.value
                  ? WolverixTheme.errorColor
                  : WolverixTheme.primaryColor,
            ),
          ],
        ),
      );
    });
  }
}

class _GameArea extends StatelessWidget {
  final GameSession session;
  final GamePlayer? myPlayer;

  const _GameArea({required this.session, this.myPlayer});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.8,
      ),
      itemCount: session.players.length,
      itemBuilder: (context, index) {
        final player = session.players[index];
        return _PlayerCard(
          player: player,
          isMe: player.userId == myPlayer?.userId,
          canSelect: _canSelectPlayer(player),
          onTap: () => _selectPlayer(player),
        );
      },
    );
  }

  bool _canSelectPlayer(GamePlayer player) {
    if (myPlayer == null || !myPlayer!.isAlive) return false;
    if (!player.isAlive) return false;

    final gameProvider = Get.find<GameProvider>();
    if (!gameProvider.isMyTurn) return false;

    return gameProvider.getSelectablePlayers().contains(player);
  }

  void _selectPlayer(GamePlayer player) {
    final gameProvider = Get.find<GameProvider>();
    final phase = session.currentPhase;
    final role = myPlayer?.role;

    // Handle night_0 phase - route based on role
    if (phase == GamePhase.night0) {
      switch (role) {
        case GameRole.werewolf:
          gameProvider.werewolfVote(player.id);
          break;
        case GameRole.seer:
          gameProvider.seerDivine(player.id);
          break;
        case GameRole.witch:
          // Witch UI will need special handling (heal/poison buttons)
          // For now, just log
          print('Witch selected player: ${player.id}');
          break;
        case GameRole.bodyguard:
          gameProvider.bodyguardProtect(player.id);
          break;
        case GameRole.cupid:
          // Cupid needs to select TWO players - special handling needed
          print('Cupid selected player: ${player.id}');
          break;
        default:
          break;
      }
      return;
    }

    // Handle specific role phases
    switch (phase) {
      case GamePhase.werewolfPhase:
        gameProvider.werewolfVote(player.id);
        break;
      case GamePhase.seerPhase:
        gameProvider.seerDivine(player.id);
        break;
      case GamePhase.bodyguardPhase:
        gameProvider.bodyguardProtect(player.id);
        break;
      case GamePhase.dayVoting:
      case GamePhase.finalVote:
        gameProvider.vote(player.id);
        break;
      case GamePhase.hunterPhase:
        gameProvider.hunterShoot(player.id);
        break;
      case GamePhase.witchPhase:
        gameProvider.witchPoison(player.id);
        break;
      default:
        break;
    }
  }
}

class _PlayerCard extends StatelessWidget {
  final GamePlayer player;
  final bool isMe;
  final bool canSelect;
  final VoidCallback onTap;

  const _PlayerCard({
    required this.player,
    required this.isMe,
    required this.canSelect,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: canSelect ? onTap : null,
      child: Container(
        decoration: BoxDecoration(
          color: !player.isAlive
              ? Colors.grey.withOpacity(0.3)
              : (isMe
                  ? WolverixTheme.primaryColor.withOpacity(0.2)
                  : WolverixTheme.cardColor),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: canSelect
                ? WolverixTheme.primaryColor
                : (isMe
                    ? WolverixTheme.primaryColor.withOpacity(0.5)
                    : Colors.transparent),
            width: canSelect ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Avatar
            Stack(
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundColor: !player.isAlive
                      ? Colors.grey
                      : WolverixTheme.primaryColor,
                  child: Text(
                    (player.user?.username ?? 'P')
                        .substring(0, 1)
                        .toUpperCase(),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (!player.isAlive)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black54,
                      ),
                      child: const Icon(
                        Icons.close,
                        color: WolverixTheme.errorColor,
                        size: 30,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // Name
            Text(
              player.user?.username ?? 'Player ${player.seatPosition + 1}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: !player.isAlive ? Colors.grey : null,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            // Role (if dead or known)
            if (!player.isAlive && player.role != null)
              Text(
                player.role!.displayName,
                style: TextStyle(
                  fontSize: 10,
                  color: WolverixTheme.getRoleColor(player.role!.name),
                ),
              ),
            // Status icons
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (player.isMayor)
                  const Icon(Icons.star, size: 14, color: Colors.amber),
                if (player.loverId != null)
                  const Icon(Icons.favorite, size: 14, color: Colors.pink),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionPanel extends StatelessWidget {
  final GameSession session;
  final GamePlayer myPlayer;

  const _ActionPanel({required this.session, required this.myPlayer});

  @override
  Widget build(BuildContext context) {
    final gameProvider = Get.find<GameProvider>();
    final phase = session.currentPhase;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WolverixTheme.surfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _getActionPrompt(),
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          // Special actions based on phase/role
          if (phase == GamePhase.witchPhase && myPlayer.role == GameRole.witch)
            Row(
              children: [
                if (!myPlayer.hasUsedHeal)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => gameProvider.witchHeal(),
                      icon: const Icon(Icons.healing),
                      label: const Text('Use Heal'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: WolverixTheme.successColor,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                if (!myPlayer.hasUsedPoison)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Get.snackbar(
                          'Select Target',
                          'Tap a player to poison them',
                        );
                      },
                      icon: const Icon(Icons.science),
                      label: const Text('Use Poison'),
                    ),
                  ),
              ],
            ),
          if (phase == GamePhase.dayVoting)
            OutlinedButton(
              onPressed: () => gameProvider.vote(''), // Skip vote
              child: const Text('Skip Vote'),
            ),
          if (myPlayer.role == GameRole.mayor && !myPlayer.isMayor)
            OutlinedButton.icon(
              onPressed: () => gameProvider.mayorReveal(),
              icon: const Icon(Icons.star),
              label: const Text('Reveal as Mayor'),
            ),
        ],
      ),
    );
  }

  String _getActionPrompt() {
    final phase = session.currentPhase;
    final role = myPlayer.role;

    if (!Get.find<GameProvider>().isMyTurn) {
      return 'Wait for your turn...';
    }

    // Handle night_0 phase - show role-specific prompt
    if (phase == GamePhase.night0) {
      switch (role) {
        case GameRole.werewolf:
          return 'Choose a villager to eliminate';
        case GameRole.seer:
          return 'Choose a player to divine';
        case GameRole.witch:
          return 'Use your potions wisely';
        case GameRole.bodyguard:
          return 'Choose a player to protect';
        case GameRole.cupid:
          return 'Choose two players to become lovers';
        default:
          return 'Waiting for night actions...';
      }
    }

    switch (phase) {
      case GamePhase.werewolfPhase:
        return 'Choose a villager to eliminate';
      case GamePhase.seerPhase:
        return 'Choose a player to divine';
      case GamePhase.witchPhase:
        return 'Use your potions wisely';
      case GamePhase.bodyguardPhase:
        return 'Choose a player to protect';
      case GamePhase.cupidPhase:
        return 'Choose two players to become lovers';
      case GamePhase.dayVoting:
        return 'Vote for who you suspect';
      case GamePhase.hunterPhase:
        return 'Choose your final target';
      default:
        return 'Discuss with the village';
    }
  }
}

class _GameOverScreen extends StatelessWidget {
  final String winner;
  final GamePlayer? myPlayer;
  final List<GamePlayer> players;

  const _GameOverScreen({
    required this.winner,
    this.myPlayer,
    required this.players,
  });

  @override
  Widget build(BuildContext context) {
    final didWin = myPlayer?.team?.name == winner ||
        (winner == 'lovers' && myPlayer?.loverId != null);

    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            didWin ? Icons.emoji_events : Icons.sentiment_dissatisfied,
            size: 100,
            color: didWin ? Colors.amber : WolverixTheme.textSecondary,
          ),
          const SizedBox(height: 24),
          Text(
            didWin ? 'Victory!' : 'Defeat',
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.bold,
              color: didWin ? Colors.amber : WolverixTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _getWinnerMessage(),
            style: const TextStyle(fontSize: 18),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          // Player results
          Expanded(
            child: ListView.builder(
              itemCount: players.length,
              itemBuilder: (context, index) {
                final player = players[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: player.role != null
                        ? WolverixTheme.getRoleColor(player.role!.name)
                        : Colors.grey,
                    child: Text((player.user?.username ?? 'P').substring(0, 1)),
                  ),
                  title: Text(player.user?.username ?? 'Player'),
                  subtitle: Text(player.role?.displayName ?? 'Unknown'),
                  trailing: player.isAlive
                      ? const Icon(
                          Icons.check_circle,
                          color: WolverixTheme.successColor,
                        )
                      : const Icon(
                          Icons.cancel,
                          color: WolverixTheme.errorColor,
                        ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Get.find<GameProvider>().clearGame();
                Get.offAllNamed('/home');
              },
              child: const Text('Return to Home'),
            ),
          ),
        ],
      ),
    );
  }

  String _getWinnerMessage() {
    switch (winner) {
      case 'werewolves':
        return 'The Werewolves have devoured the village!';
      case 'villagers':
        return 'The Village has eliminated all the Werewolves!';
      case 'lovers':
        return 'Love conquers all! The Lovers win!';
      case 'tanner':
        return 'The Tanner got what they wanted!';
      default:
        return 'Game Over!';
    }
  }
}
