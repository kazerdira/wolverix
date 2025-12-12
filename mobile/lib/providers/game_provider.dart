import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import '../services/storage_service.dart';
import '../utils/error_handler.dart';
import '../screens/game/role_reveal_screen.dart';
import '../widgets/death_overlay.dart';
import 'voice_provider.dart';

class GameProvider extends GetxController {
  final ApiService _api = Get.find<ApiService>();
  final WebSocketService _ws = Get.find<WebSocketService>();
  final StorageService _storage = Get.find<StorageService>();

  final Rx<GameSession?> session = Rx<GameSession?>(null);
  final Rx<GamePlayer?> myPlayer = Rx<GamePlayer?>(null);
  final RxList<GameEvent> events = <GameEvent>[].obs;
  final RxBool isLoading = false.obs;
  final RxString errorMessage = ''.obs;
  final Rx<Duration> phaseTimeRemaining = Duration.zero.obs;

  // NEW: Vote tracking
  final RxMap<String, String> currentVotes =
      <String, String>{}.obs; // voterId -> targetId
  final RxMap<String, int> voteCount = <String, int>{}.obs; // targetId -> count
  final RxInt totalVotes = 0.obs;

  Timer? _phaseTimer;
  StreamSubscription? _wsSubscription;

  GameSession? get currentSession => session.value;
  GamePlayer? get me => myPlayer.value;
  GamePhase get currentPhase => session.value?.currentPhase ?? GamePhase.night0;
  bool get isMyTurn => _checkIfMyTurn();
  bool get amIAlive => myPlayer.value?.isAlive ?? false;
  bool get isGameOver => session.value?.winner != null;

  @override
  void onInit() {
    super.onInit();
    _subscribeToWebSocket();
  }

  void _subscribeToWebSocket() {
    _wsSubscription = _ws.messageStream.listen((message) {
      switch (message.type) {
        case 'game_update':
          _handleGameUpdate(message.payload);
          break;
        case 'phase_change':
          _handlePhaseChange(message.payload);
          break;
        case 'player_death': // Backend uses 'player_death' not 'player_killed'
          _handlePlayerDeath(message.payload);
          break;
        case 'role_reveal':
          _handleRoleReveal(message.payload);
          break;
        case 'timer': // Backend sends 'timer' for phase countdowns
          _handleTimer(message.payload);
          break;
        case 'player_action': // Backend sends action notifications
          _handlePlayerAction(message.payload);
          break;
        case 'player_voted': // NEW: Vote synchronization
          _handlePlayerVoted(message.payload);
          break;
        case 'vote_result': // NEW: Vote count updates
          _handleVoteResult(message.payload);
          break;
        case 'night_actions_complete': // NEW: All actions submitted
          _handleNightActionsComplete(message.payload);
          break;
        case 'game_end':
          _handleGameEnd(message.payload);
          break;
        case 'error':
          _handleError(message.payload);
          break;
        case 'pong': // Handle ping/pong
          break;
      }
    });
  }

  Future<void> loadGame(String sessionId) async {
    try {
      isLoading.value = true;

      final gameSession = await _api.getGameState(sessionId);
      print(
          '📊 Game session loaded: phaseEndTime = ${gameSession.phaseEndTime}');
      session.value = gameSession;

      // Find my player
      final userId = _storage.getUserId();
      myPlayer.value = gameSession.players.firstWhereOrNull(
        (p) => p.userId == userId,
      );

      // Load history
      final history = await _api.getGameHistory(sessionId);
      events.value = history;

      // Start phase timer
      _updatePhaseTimer();
    } catch (e) {
      final error = ErrorHandler().parseError(e);
      errorMessage.value = error.message;
      ErrorHandler().showError(
        error,
        onRetry: () => loadGame(sessionId),
      );
    } finally {
      isLoading.value = false;
    }
  }

  Future<bool> performAction({
    required String actionType,
    String? targetPlayerId,
    Map<String, dynamic>? data,
  }) async {
    if (session.value == null) return false;

    try {
      final result = await _api.performAction(
        session.value!.id,
        actionType: actionType,
        targetPlayerId: targetPlayerId,
        data: data,
      );

      if (result['success'] == true) {
        return true;
      } else {
        errorMessage.value = result['message'] ?? 'Action failed';
        return false;
      }
    } catch (e) {
      final error = ErrorHandler().parseError(e);
      errorMessage.value = error.message;
      ErrorHandler().showError(
        error,
        onRetry: () => performAction(
          actionType: actionType,
          targetPlayerId: targetPlayerId,
          data: data,
        ),
      );
      return false;
    }
  }

  // Convenience action methods
  Future<bool> vote(String targetPlayerId) async {
    return performAction(
      actionType: 'vote_lynch',
      targetPlayerId: targetPlayerId,
    );
  }

  Future<bool> werewolfVote(String targetPlayerId) async {
    return performAction(
      actionType: 'werewolf_vote',
      targetPlayerId: targetPlayerId,
    );
  }

  Future<bool> seerDivine(String targetPlayerId) async {
    return performAction(
      actionType: 'seer_divine',
      targetPlayerId: targetPlayerId,
    );
  }

  Future<bool> witchHeal() async {
    return performAction(actionType: 'witch_heal');
  }

  Future<bool> witchPoison(String targetPlayerId) async {
    return performAction(
      actionType: 'witch_poison',
      targetPlayerId: targetPlayerId,
    );
  }

  Future<bool> bodyguardProtect(String targetPlayerId) async {
    return performAction(
      actionType: 'bodyguard_protect',
      targetPlayerId: targetPlayerId,
    );
  }

  Future<bool> cupidChooseLovers(String lover1Id, String lover2Id) async {
    return performAction(
      actionType: 'cupid_choose',
      targetPlayerId: lover1Id,
      data: {
        'second_lover': lover2Id
      }, // Backend expects second lover in data field
    );
  }

  Future<bool> hunterShoot(String targetPlayerId) async {
    return performAction(
      actionType: 'hunter_shoot',
      targetPlayerId: targetPlayerId,
    );
  }

  Future<bool> mayorReveal() async {
    return performAction(actionType: 'mayor_reveal');
  }

  // WebSocket handlers
  void _handleGameUpdate(Map<String, dynamic> payload) {
    if (session.value != null) {
      loadGame(session.value!.id);
    }
  }

  void _handlePhaseChange(Map<String, dynamic> payload) {
    print('🔄 Phase change received: $payload');
    final newPhase = GamePhase.fromString(payload['phase'] as String);
    final newPhaseEndTime = payload['phase_end_time'] != null
        ? DateTime.parse(payload['phase_end_time'])
        : null;

    print('📅 New phase: $newPhase, End time: $newPhaseEndTime');

    // Clear votes when phase changes
    currentVotes.clear();
    voteCount.clear();
    totalVotes.value = 0;

    if (session.value != null) {
      session.value = GameSession(
        id: session.value!.id,
        roomId: session.value!.roomId,
        currentPhase: newPhase,
        phaseNumber: payload['phase_number'] ?? session.value!.phaseNumber,
        dayNumber: payload['day_number'] ?? session.value!.dayNumber,
        phaseEndTime: newPhaseEndTime,
        winner: session.value!.winner,
        state: session.value!.state,
        startedAt: session.value!.startedAt,
        players: session.value!.players,
      );
      _updatePhaseTimer();

      // NEW: Automatic voice channel switching
      _handleVoiceChannelSwitch(newPhase);
    }
  }

  void _handleVoiceChannelSwitch(GamePhase newPhase) {
    // Only manage voice if player is alive and we have a session
    if (myPlayer.value == null ||
        !myPlayer.value!.isAlive ||
        session.value == null) {
      return;
    }

    try {
      final voiceProvider = Get.find<VoiceProvider>();
      final sessionId = session.value!.id;
      final myRole = myPlayer.value!.role;

      // Determine target channel based on phase and role
      String channelName = 'game_${sessionId}_all'; // Default: all players

      // Werewolf-specific phase: only werewolves join werewolf channel
      if (newPhase == GamePhase.werewolfPhase ||
          newPhase == GamePhase.night0 && myRole == GameRole.werewolf) {
        if (myRole == GameRole.werewolf) {
          channelName = 'game_${sessionId}_werewolves';
        }
      }
      // Day phases: everyone in main channel
      else if (newPhase == GamePhase.dayDiscussion ||
          newPhase == GamePhase.dayVoting ||
          newPhase == GamePhase.defensePhase ||
          newPhase == GamePhase.finalVote) {
        channelName = 'game_${sessionId}_all';
      }
      // Other night phases: everyone in main channel but muted
      else {
        channelName = 'game_${sessionId}_all';
      }

      // Switch channel if different from current
      if (voiceProvider.isInitialized.value &&
          voiceProvider.currentChannel.value != channelName) {
        print(
            '🔊 Switching voice channel: ${voiceProvider.currentChannel.value} → $channelName');
        voiceProvider.switchChannel(channelName);
      }

      // Handle muting based on phase and role
      voiceProvider.handlePhaseChange(
          newPhase, myRole, myPlayer.value!.isAlive);
    } catch (e) {
      print('⚠️ Voice channel switch error: $e');
      // Don't block game if voice fails
    }
  }

  void _handleRoleReveal(Map<String, dynamic> payload) {
    final role = GameRole.fromString(payload['your_role'] as String);
    final team = GameTeam.fromString(payload['your_team'] as String);

    if (myPlayer.value != null) {
      myPlayer.value = GamePlayer(
        id: myPlayer.value!.id,
        sessionId: myPlayer.value!.sessionId,
        userId: myPlayer.value!.userId,
        role: role,
        team: team,
        isAlive: myPlayer.value!.isAlive,
        diedAtPhase: myPlayer.value!.diedAtPhase,
        deathReason: myPlayer.value!.deathReason,
        hasUsedHeal: myPlayer.value!.hasUsedHeal,
        hasUsedPoison: myPlayer.value!.hasUsedPoison,
        hasShot: myPlayer.value!.hasShot,
        isProtected: myPlayer.value!.isProtected,
        isMayor: myPlayer.value!.isMayor,
        loverId: myPlayer.value!.loverId,
        currentVoiceChannel: myPlayer.value!.currentVoiceChannel,
        seatPosition: myPlayer.value!.seatPosition,
        user: myPlayer.value!.user,
      );

      // Show dramatic role reveal screen
      _showRoleReveal(role, team, payload);
    }
  }

  void _showRoleReveal(
      GameRole role, GameTeam team, Map<String, dynamic> payload) {
    // Get role info
    final roleInfo = _getRoleInfo(role);

    // Get teammates if werewolf
    List<String>? teammates;
    if (role == GameRole.werewolf && session.value != null) {
      teammates = session.value!.players
          .where((p) =>
              p.role == GameRole.werewolf && p.userId != _storage.getUserId())
          .map((p) => p.user?.username ?? 'Unknown')
          .toList();
    }

    // Navigate to role reveal screen
    Get.to(() => RoleRevealScreen(
          roleName: roleInfo['name'] as String,
          roleDescription: roleInfo['description'] as String,
          team: team == GameTeam.werewolves ? 'werewolves' : 'villagers',
          teammates: teammates,
          onComplete: () {
            Get.back();
          },
        ));
  }

  Map<String, String> _getRoleInfo(GameRole role) {
    switch (role) {
      case GameRole.werewolf:
        return {
          'name': 'Werewolf',
          'description':
              'Hunt villagers at night. Your goal is to eliminate all villagers without being caught.',
        };
      case GameRole.seer:
        return {
          'name': 'Seer',
          'description':
              'Each night, you can inspect one player to learn their true identity. Use this power wisely to guide the village.',
        };
      case GameRole.witch:
        return {
          'name': 'Witch',
          'description':
              'You have two potions: one to save a life and one to take it. Use them strategically - you can only use each once.',
        };
      case GameRole.hunter:
        return {
          'name': 'Hunter',
          'description':
              'If you die, you can take someone down with you. Choose your final shot carefully.',
        };
      case GameRole.cupid:
        return {
          'name': 'Cupid',
          'description':
              'On the first night, you create a bond between two players. If one dies, the other dies of heartbreak.',
        };
      case GameRole.bodyguard:
        return {
          'name': 'Bodyguard',
          'description':
              'Each night, you can protect one player from werewolf attacks. You cannot protect the same person twice in a row.',
        };
      case GameRole.villager:
        return {
          'name': 'Villager',
          'description':
              'You have no special powers, but your vote and voice matter. Use logic and deduction to find the werewolves.',
        };
      default:
        return {
          'name': 'Unknown',
          'description': 'Your role is unknown.',
        };
    }
  }

  void _handleGameEnd(Map<String, dynamic> payload) {
    final winner = payload['winning_team'] as String;
    if (session.value != null) {
      session.value = GameSession(
        id: session.value!.id,
        roomId: session.value!.roomId,
        currentPhase: GamePhase.gameOver,
        phaseNumber: session.value!.phaseNumber,
        dayNumber: session.value!.dayNumber,
        phaseEndTime: null,
        winner: winner,
        state: session.value!.state,
        startedAt: session.value!.startedAt,
        players: session.value!.players,
      );
    }
    _phaseTimer?.cancel();
  }

  void _handlePlayerDeath(Map<String, dynamic> payload) {
    // Renamed from _handlePlayerKilled to match backend 'player_death'
    final playerId = payload['player_id'] as String?;
    if (playerId != null && session.value != null) {
      final updatedPlayers = session.value!.players.map((p) {
        if (p.id == playerId) {
          return GamePlayer(
            id: p.id,
            sessionId: p.sessionId,
            userId: p.userId,
            role: p.role,
            team: p.team,
            isAlive: false,
            diedAtPhase: payload['phase_number'] as int?,
            deathReason: payload['death_reason'] as String?,
            hasUsedHeal: p.hasUsedHeal,
            hasUsedPoison: p.hasUsedPoison,
            hasShot: p.hasShot,
            isProtected: p.isProtected,
            isMayor: p.isMayor,
            loverId: p.loverId,
            currentVoiceChannel: p.currentVoiceChannel,
            seatPosition: p.seatPosition,
            user: p.user,
          );
        }
        return p;
      }).toList();

      session.value = GameSession(
        id: session.value!.id,
        roomId: session.value!.roomId,
        currentPhase: session.value!.currentPhase,
        phaseNumber: session.value!.phaseNumber,
        dayNumber: session.value!.dayNumber,
        phaseEndTime: session.value!.phaseEndTime,
        winner: session.value!.winner,
        state: session.value!.state,
        startedAt: session.value!.startedAt,
        players: updatedPlayers,
      );

      if (myPlayer.value?.id == playerId) {
        myPlayer.value = updatedPlayers.firstWhere((p) => p.id == playerId);

        // NEW: Handle voice when I die
        _handleDeathVoiceChannel();

        // Show death overlay with animation
        final deathReason = payload['death_reason'] as String? ?? 'eliminated';
        _showDeathOverlay(myPlayer.value!.user?.username ?? 'You', deathReason);
      }
    }
  }

  void _showDeathOverlay(String playerName, String deathReason) {
    Get.dialog(
      DeathOverlay(
        playerName: playerName,
        deathReason: deathReason,
        onDismiss: () {
          Get.back();
        },
      ),
      barrierDismissible: false,
      barrierColor: Colors.transparent,
    );
  }

  void _handleDeathVoiceChannel() {
    // When player dies, mute them permanently
    try {
      final voiceProvider = Get.find<VoiceProvider>();
      if (voiceProvider.isInitialized.value) {
        // Mute the dead player
        voiceProvider.setMute(true);

        // Optional: Move to dead channel (if backend supports it)
        // final sessionId = session.value?.id;
        // if (sessionId != null) {
        //   voiceProvider.switchChannel('game_${sessionId}_dead');
        // }
      }
    } catch (e) {
      print('⚠️ Voice handling on death error: $e');
    }
  }

  void _handleTimer(Map<String, dynamic> payload) {
    // Backend sends timer updates for phase countdown synchronization
    // Priority 1: Use time_remaining_seconds for direct sync
    if (payload['time_remaining_seconds'] != null) {
      final remainingSeconds = payload['time_remaining_seconds'] as int;
      if (remainingSeconds >= 0) {
        phaseTimeRemaining.value = Duration(seconds: remainingSeconds);
      }
    }
    // Priority 2: Use phase_ends_at for calculation
    else if (payload['phase_ends_at'] != null) {
      final endsAt = DateTime.parse(payload['phase_ends_at'] as String);
      if (session.value != null) {
        session.value = GameSession(
          id: session.value!.id,
          roomId: session.value!.roomId,
          currentPhase: session.value!.currentPhase,
          phaseNumber: session.value!.phaseNumber,
          dayNumber: session.value!.dayNumber,
          phaseEndTime: endsAt,
          winner: session.value!.winner,
          state: session.value!.state,
          startedAt: session.value!.startedAt,
          players: session.value!.players,
        );
        _updatePhaseTimer();
      }
    }
  }

  void _handlePlayerAction(Map<String, dynamic> payload) {
    // Backend notifies when a player performs an action (for UI feedback)
    final actionType = payload['action_type'] as String?;
    final playerName = payload['player_name'] as String?;
    final actionDisplay = payload['action_display'] as String?;

    if (actionType != null) {
      // Add to event history
      events.add(
        GameEvent(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          sessionId: session.value?.id ?? '',
          phaseNumber: session.value?.phaseNumber ?? 0,
          eventType: 'player_action',
          eventData: payload,
          isPublic: payload['is_public'] as bool? ?? false,
          createdAt: DateTime.now(),
        ),
      );

      // Show notification for public/visible actions
      final isPublic = payload['is_public'] as bool? ?? false;
      if (isPublic && actionDisplay != null) {
        Get.snackbar(
          'Action Performed',
          actionDisplay,
          duration: const Duration(seconds: 3),
          snackPosition: SnackPosition.TOP,
          backgroundColor: Get.theme.colorScheme.surface.withOpacity(0.9),
        );
      }

      // Show generic feedback for private actions (just that someone acted)
      else if (!isPublic && actionType != 'skip' && playerName == null) {
        // Don't reveal who, just that actions are happening
        _showActionProgress();
      }
    }
  }

  void _showActionProgress() {
    // Show subtle progress that actions are being submitted
    // This creates tension without revealing information
    update(); // Refresh UI to show any action counters
  }

  void _handleError(Map<String, dynamic> payload) {
    errorMessage.value = payload['message'] as String? ?? 'Unknown error';
    Get.snackbar(
      'Error',
      errorMessage.value,
      duration: const Duration(seconds: 3),
    );
  }

  void _handlePlayerVoted(Map<String, dynamic> payload) {
    // Real-time vote notification
    final voterId = payload['voter_id'] as String?;
    final voterName = payload['voter_name'] as String?;
    final targetId = payload['target_id'] as String?;
    final targetName = payload['target_name'] as String?;
    final voteType = payload['vote_type'] as String? ?? 'lynch';

    if (voterId != null && targetId != null) {
      // Track the vote
      currentVotes[voterId] = targetId;
      totalVotes.value = currentVotes.length;

      // Recalculate vote counts
      _recalculateVoteCounts();

      // Add to events for history
      if (voterName != null && targetName != null) {
        events.add(
          GameEvent(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            sessionId: session.value?.id ?? '',
            phaseNumber: session.value?.phaseNumber ?? 0,
            eventType: 'player_voted',
            eventData: payload,
            isPublic:
                voteType == 'lynch', // Lynch votes public, werewolf private
            createdAt: DateTime.now(),
          ),
        );

        // Show subtle notification (only for public votes)
        if (voteType == 'lynch') {
          Get.snackbar(
            'Vote Cast',
            '$voterName voted for $targetName',
            duration: const Duration(seconds: 2),
            snackPosition: SnackPosition.TOP,
            backgroundColor: Get.theme.colorScheme.surface.withOpacity(0.9),
          );
        }
      }
    }
  }

  void _recalculateVoteCounts() {
    // Clear and recalculate vote counts
    final counts = <String, int>{};
    for (final targetId in currentVotes.values) {
      counts[targetId] = (counts[targetId] ?? 0) + 1;
    }
    voteCount.value = counts;
  }

  void _handleVoteResult(Map<String, dynamic> payload) {
    // Update vote counts in real-time (alternative to tracking individual votes)
    final targetId = payload['target_id'] as String?;
    final count = payload['vote_count'] as int?;
    final total = payload['total_votes'] as int?;

    if (targetId != null && count != null) {
      voteCount[targetId] = count;
      if (total != null) {
        totalVotes.value = total;
      }

      // Optional: Show vote progress
      if (total != null && session.value != null) {
        final alivePlayers =
            session.value!.players.where((p) => p.isAlive).length;
        if (total == alivePlayers) {
          Get.snackbar(
            'All Votes In',
            'Everyone has voted! Phase ending soon...',
            duration: const Duration(seconds: 3),
            backgroundColor: Get.theme.colorScheme.primary.withOpacity(0.9),
          );
        }
      }
    }
  }

  void _handleNightActionsComplete(Map<String, dynamic> payload) {
    // Notify when all night actions are submitted
    final allSubmitted = payload['all_submitted'] as bool? ?? false;

    if (allSubmitted) {
      Get.snackbar(
        'Night Actions Complete',
        'All players have submitted their actions. Phase ending...',
        duration: const Duration(seconds: 3),
        backgroundColor: Get.theme.colorScheme.primary.withOpacity(0.9),
      );
    }
  }

  void _updatePhaseTimer() {
    _phaseTimer?.cancel();

    print(
        '⏰ Updating phase timer: phaseEndTime = ${session.value?.phaseEndTime}');

    if (session.value?.phaseEndTime != null) {
      // Update immediately
      final endTime = session.value!.phaseEndTime!;
      final remaining = endTime.difference(DateTime.now());

      if (remaining.isNegative) {
        phaseTimeRemaining.value = Duration.zero;
        print('⚠️ Phase already ended! Time remaining: 0');
      } else {
        phaseTimeRemaining.value = remaining;
        print(
            '✅ Timer started: ${remaining.inMinutes}:${remaining.inSeconds % 60}');

        // Then update every second
        _phaseTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          final newRemaining = endTime.difference(DateTime.now());

          if (newRemaining.isNegative) {
            phaseTimeRemaining.value = Duration.zero;
            _phaseTimer?.cancel();
          } else {
            phaseTimeRemaining.value = newRemaining;
          }
        });
      }
    } else {
      print('❌ Phase end time is null, timer will not start');
      phaseTimeRemaining.value = Duration.zero;
    }
  }

  bool _checkIfMyTurn() {
    if (myPlayer.value == null || !myPlayer.value!.isAlive) return false;

    final phase = currentPhase;
    final role = myPlayer.value!.role;

    switch (phase) {
      // Night phase (night_0) - all night roles can act simultaneously
      case GamePhase.night0:
        return role == GameRole.werewolf ||
            role == GameRole.seer ||
            role == GameRole.witch ||
            role == GameRole.bodyguard ||
            role == GameRole.cupid;

      // Specific role phases (if backend ever uses them)
      case GamePhase.cupidPhase:
        return role == GameRole.cupid;
      case GamePhase.werewolfPhase:
        return role == GameRole.werewolf;
      case GamePhase.seerPhase:
        return role == GameRole.seer;
      case GamePhase.witchPhase:
        return role == GameRole.witch;
      case GamePhase.bodyguardPhase:
        return role == GameRole.bodyguard;

      // Day phases
      case GamePhase.dayDiscussion:
        return false; // Discussion phase - no actions, just chat
      case GamePhase.dayVoting:
      case GamePhase.finalVote:
        return true; // All alive players can vote

      // Special phases
      case GamePhase.hunterPhase:
        return role == GameRole.hunter;
      case GamePhase.defensePhase:
        // Player being lynched can defend themselves
        // TODO: Check if myPlayer is the one on trial
        return false;
      case GamePhase.mayorReveal:
      case GamePhase.gameOver:
        return false;
    }
  }

  List<GamePlayer> getSelectablePlayers() {
    if (session.value == null) return [];

    final phase = currentPhase;
    final role = myPlayer.value?.role;
    final alivePlayers = session.value!.alivePlayers;

    // Handle night_0 phase - filter based on role
    if (phase == GamePhase.night0) {
      switch (role) {
        case GameRole.werewolf:
          // Werewolves can't target other werewolves
          return alivePlayers
              .where((p) => p.role != GameRole.werewolf)
              .toList();
        case GameRole.seer:
        case GameRole.bodyguard:
        case GameRole.cupid:
          // Can target any alive player
          return alivePlayers;
        case GameRole.witch:
          // Witch can target any alive player (for poison)
          // TODO: Heal action needs special handling (no target selection)
          return alivePlayers;
        default:
          return [];
      }
    }

    switch (phase) {
      case GamePhase.werewolfPhase:
        // Werewolves can't target other werewolves
        return alivePlayers.where((p) => p.role != GameRole.werewolf).toList();
      case GamePhase.cupidPhase:
        // Cupid can choose any alive player
        return alivePlayers;
      case GamePhase.seerPhase:
      case GamePhase.bodyguardPhase:
      case GamePhase.hunterPhase:
      case GamePhase.dayVoting:
      case GamePhase.finalVote:
        // Can target any alive player
        return alivePlayers;
      case GamePhase.witchPhase:
        // Witch can target any alive player
        return alivePlayers;
      default:
        return [];
    }
  }

  void clearGame() {
    _phaseTimer?.cancel();
    session.value = null;
    myPlayer.value = null;
    events.clear();
    phaseTimeRemaining.value = Duration.zero;
  }

  @override
  void onClose() {
    _phaseTimer?.cancel();
    _wsSubscription?.cancel();
    super.onClose();
  }
}
