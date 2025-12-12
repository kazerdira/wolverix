import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/models.dart';
import '../providers/game_provider.dart';

class NightActionPanel extends StatefulWidget {
  const NightActionPanel({super.key});

  @override
  State<NightActionPanel> createState() => _NightActionPanelState();
}

class _NightActionPanelState extends State<NightActionPanel> {
  final GameProvider gameProvider = Get.find<GameProvider>();
  String? selectedTarget1;
  String? selectedTarget2;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final myPlayer = gameProvider.myPlayer.value;
      if (myPlayer == null || !myPlayer.isAlive) {
        return const SizedBox.shrink();
      }

      if (!gameProvider.isMyTurn) {
        return _buildWaitingPanel();
      }

      final phase = gameProvider.currentPhase;

      switch (phase) {
        case GamePhase.cupidPhase:
          return _buildCupidPanel();
        case GamePhase.werewolfPhase:
          return _buildWerewolfPanel();
        case GamePhase.seerPhase:
          return _buildSeerPanel();
        case GamePhase.witchPhase:
          return _buildWitchPanel();
        case GamePhase.bodyguardPhase:
          return _buildBodyguardPanel();
        case GamePhase.hunterPhase:
          return _buildHunterPanel();
        default:
          return const SizedBox.shrink();
      }
    });
  }

  Widget _buildWaitingPanel() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.nightlight_round, size: 48, color: Colors.indigo),
            const SizedBox(height: 12),
            const Text(
              'Waiting for other players...',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Obx(() => Text(
                  'Time remaining: ${gameProvider.phaseTimeRemaining.value.inMinutes}:${(gameProvider.phaseTimeRemaining.value.inSeconds % 60).toString().padLeft(2, '0')}',
                  style: const TextStyle(color: Colors.grey),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildCupidPanel() {
    final selectablePlayers = gameProvider.getSelectablePlayers();

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.favorite, color: Colors.pink, size: 32),
                SizedBox(width: 12),
                Text(
                  'Cupid: Choose Two Lovers',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Select the first lover:',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            _buildPlayerDropdown(selectablePlayers, selectedTarget1, (value) {
              setState(() => selectedTarget1 = value);
            }),
            const SizedBox(height: 16),
            const Text(
              'Select the second lover:',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            _buildPlayerDropdown(
              selectablePlayers.where((p) => p.id != selectedTarget1).toList(),
              selectedTarget2,
              (value) {
                setState(() => selectedTarget2 = value);
              },
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: selectedTarget1 != null && selectedTarget2 != null
                    ? () => _submitCupidChoice()
                    : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.pink,
                ),
                child: const Text('Bind Them Together'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWerewolfPanel() {
    final selectablePlayers = gameProvider.getSelectablePlayers();

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.pets, color: Colors.red, size: 32),
                SizedBox(width: 12),
                Text(
                  'Werewolf: Choose Your Prey',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildPlayerDropdown(selectablePlayers, selectedTarget1, (value) {
              setState(() => selectedTarget1 = value);
            }),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: selectedTarget1 != null
                    ? () => _submitWerewolfVote()
                    : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.red,
                ),
                child: const Text('Cast Vote'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeerPanel() {
    final selectablePlayers = gameProvider.getSelectablePlayers();

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.remove_red_eye, color: Colors.purple, size: 32),
                SizedBox(width: 12),
                Text(
                  'Seer: Divine a Player',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildPlayerDropdown(selectablePlayers, selectedTarget1, (value) {
              setState(() => selectedTarget1 = value);
            }),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: selectedTarget1 != null
                    ? () => _submitSeerDivination()
                    : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.purple,
                ),
                child: const Text('Divine'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWitchPanel() {
    final selectablePlayers = gameProvider.getSelectablePlayers();
    final myPlayer = gameProvider.myPlayer.value!;

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.science, color: Colors.green, size: 32),
                SizedBox(width: 12),
                Text(
                  'Witch: Choose Your Potion',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Potion Status Display
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildPotionStatus(
                        icon: Icons.healing,
                        label: 'Heal Potion',
                        used: myPlayer.hasUsedHeal,
                        color: Colors.green,
                      ),
                      _buildPotionStatus(
                        icon: Icons.dangerous,
                        label: 'Poison Potion',
                        used: myPlayer.hasUsedPoison,
                        color: Colors.deepPurple,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            if (!myPlayer.hasUsedHeal)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _submitWitchHeal(),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.green,
                  ),
                  icon: const Icon(Icons.healing),
                  label: const Text('Use Healing Potion (Save Victim)'),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.grey),
                    SizedBox(width: 8),
                    Text(
                      'Healing potion already used',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),

            if (!myPlayer.hasUsedHeal && !myPlayer.hasUsedPoison)
              const SizedBox(height: 12),

            if (!myPlayer.hasUsedPoison) ...[
              const Divider(height: 24),
              const Text(
                'Select target to poison:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _buildPlayerDropdown(selectablePlayers, selectedTarget1, (value) {
                setState(() => selectedTarget1 = value);
              }),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: selectedTarget1 != null
                      ? () => _submitWitchPoison()
                      : null,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.deepPurple,
                  ),
                  icon: const Icon(Icons.dangerous),
                  label: const Text('Use Poison (Kill Target)'),
                ),
              ),
            ] else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.grey),
                    SizedBox(width: 8),
                    Text(
                      'Poison already used',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _skipAction(),
                child: const Text('Skip Turn'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPotionStatus({
    required IconData icon,
    required String label,
    required bool used,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: used ? Colors.grey.shade300 : color.withOpacity(0.2),
            shape: BoxShape.circle,
            border: Border.all(
              color: used ? Colors.grey : color,
              width: 2,
            ),
          ),
          child: Icon(
            icon,
            color: used ? Colors.grey : color,
            size: 32,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: used ? Colors.grey : Colors.black87,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          used ? 'Used' : 'Available',
          style: TextStyle(
            fontSize: 10,
            color: used ? Colors.grey : color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildBodyguardPanel() {
    final selectablePlayers = gameProvider.getSelectablePlayers();

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.shield, color: Colors.blue, size: 32),
                SizedBox(width: 12),
                Text(
                  'Bodyguard: Protect a Player',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildPlayerDropdown(selectablePlayers, selectedTarget1, (value) {
              setState(() => selectedTarget1 = value);
            }),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: selectedTarget1 != null
                    ? () => _submitBodyguardProtection()
                    : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.blue,
                ),
                child: const Text('Protect'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHunterPanel() {
    final selectablePlayers = gameProvider.getSelectablePlayers();

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.gps_fixed, color: Colors.orange, size: 32),
                SizedBox(width: 12),
                Text(
                  'Hunter: Take Your Revenge',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'You\'re dying! Choose someone to take with you:',
              style: TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 12),
            _buildPlayerDropdown(selectablePlayers, selectedTarget1, (value) {
              setState(() => selectedTarget1 = value);
            }),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed:
                    selectedTarget1 != null ? () => _submitHunterShot() : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.orange,
                ),
                child: const Text('Shoot!'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerDropdown(
    List<GamePlayer> players,
    String? selectedValue,
    ValueChanged<String?> onChanged,
  ) {
    return DropdownButtonFormField<String>(
      value: selectedValue,
      decoration: InputDecoration(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      items: players.map((player) {
        return DropdownMenuItem<String>(
          value: player.id,
          child: Text(player.user?.username ?? 'Player ${player.seatPosition}'),
        );
      }).toList(),
      onChanged: onChanged,
      hint: const Text('Select a player'),
    );
  }

  Future<void> _submitCupidChoice() async {
    if (selectedTarget1 != null && selectedTarget2 != null) {
      final success = await gameProvider.cupidChooseLovers(
        selectedTarget1!,
        selectedTarget2!,
      );
      if (success) {
        Get.snackbar('Success', 'Lovers have been chosen');
        setState(() {
          selectedTarget1 = null;
          selectedTarget2 = null;
        });
      }
    }
  }

  Future<void> _submitWerewolfVote() async {
    if (selectedTarget1 != null) {
      final success = await gameProvider.werewolfVote(selectedTarget1!);
      if (success) {
        Get.snackbar('Success', 'Vote cast');
        setState(() => selectedTarget1 = null);
      }
    }
  }

  Future<void> _submitSeerDivination() async {
    if (selectedTarget1 != null) {
      final success = await gameProvider.seerDivine(selectedTarget1!);
      if (success) {
        setState(() => selectedTarget1 = null);
      }
    }
  }

  Future<void> _submitWitchHeal() async {
    final success = await gameProvider.witchHeal();
    if (success) {
      Get.snackbar('Success', 'Healing potion used');
    }
  }

  Future<void> _submitWitchPoison() async {
    if (selectedTarget1 != null) {
      final success = await gameProvider.witchPoison(selectedTarget1!);
      if (success) {
        Get.snackbar('Success', 'Poison used');
        setState(() => selectedTarget1 = null);
      }
    }
  }

  Future<void> _submitBodyguardProtection() async {
    if (selectedTarget1 != null) {
      final success = await gameProvider.bodyguardProtect(selectedTarget1!);
      if (success) {
        Get.snackbar('Success', 'Protection granted');
        setState(() => selectedTarget1 = null);
      }
    }
  }

  Future<void> _submitHunterShot() async {
    if (selectedTarget1 != null) {
      final success = await gameProvider.hunterShoot(selectedTarget1!);
      if (success) {
        Get.snackbar('Success', 'Shot taken');
        setState(() => selectedTarget1 = null);
      }
    }
  }

  Future<void> _skipAction() async {
    // Backend will auto-complete after timeout
    Get.snackbar('Skipped', 'You chose not to act this night');
  }
}
