import 'dart:async';
import 'package:get/get.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import '../services/storage_service.dart';

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
        case 'player_killed':
          _handlePlayerKilled(message.payload);
          break;
        case 'role_reveal':
          _handleRoleReveal(message.payload);
          break;
        case 'seer_result':
          _handleSeerResult(message.payload);
          break;
        case 'vote_update':
          _handleVoteUpdate(message.payload);
          break;
        case 'game_end':
          _handleGameEnd(message.payload);
          break;
        case 'action_result':
          _handleActionResult(message.payload);
          break;
      }
    });
  }

  Future<void> loadGame(String sessionId) async {
    try {
      isLoading.value = true;

      final gameSession = await _api.getGameState(sessionId);
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
      errorMessage.value = 'Failed to load game';
      print('Error loading game: $e');
    } finally {
      isLoading.value = false;
    }
  }

  Future<bool> performAction({
    required String actionType,
    String? targetPlayerId,
    String? secondaryTargetId,
  }) async {
    if (session.value == null) return false;

    try {
      final result = await _api.performAction(
        session.value!.id,
        actionType: actionType,
        targetPlayerId: targetPlayerId,
        secondaryTargetId: secondaryTargetId,
      );

      if (result['success'] == true) {
        return true;
      } else {
        errorMessage.value = result['message'] ?? 'Action failed';
        return false;
      }
    } catch (e) {
      errorMessage.value = 'Failed to perform action';
      return false;
    }
  }

  // Convenience action methods
  Future<bool> vote(String targetPlayerId) async {
    return performAction(
      actionType: 'lynch_vote',
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
      secondaryTargetId: lover2Id,
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
    final newPhase = GamePhase.fromString(payload['phase'] as String);
    if (session.value != null) {
      session.value = GameSession(
        id: session.value!.id,
        roomId: session.value!.roomId,
        currentPhase: newPhase,
        phaseNumber: payload['phase_number'] ?? session.value!.phaseNumber,
        dayNumber: payload['day_number'] ?? session.value!.dayNumber,
        phaseEndTime: payload['phase_end_time'] != null
            ? DateTime.parse(payload['phase_end_time'])
            : null,
        winner: session.value!.winner,
        state: session.value!.state,
        startedAt: session.value!.startedAt,
        players: session.value!.players,
      );
      _updatePhaseTimer();
    }
  }

  void _handlePlayerKilled(Map<String, dynamic> payload) {
    final playerId = payload['player_id'] as String;
    final reason = payload['reason'] as String?;

    if (session.value != null) {
      final updatedPlayers = session.value!.players.map((p) {
        if (p.id == playerId) {
          return GamePlayer(
            id: p.id,
            sessionId: p.sessionId,
            userId: p.userId,
            role: p.role,
            team: p.team,
            isAlive: false,
            diedAtPhase: session.value!.phaseNumber,
            deathReason: reason,
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

      // Update my player if it's me
      if (myPlayer.value?.id == playerId) {
        myPlayer.value = updatedPlayers.firstWhere((p) => p.id == playerId);
      }

      events.add(
        GameEvent(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          sessionId: session.value!.id,
          phaseNumber: session.value!.phaseNumber,
          eventType: 'player_killed',
          eventData: payload,
          isPublic: true,
          createdAt: DateTime.now(),
        ),
      );
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
    }
  }

  void _handleSeerResult(Map<String, dynamic> payload) {
    events.add(
      GameEvent(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        sessionId: session.value?.id ?? '',
        phaseNumber: session.value?.phaseNumber ?? 0,
        eventType: 'seer_result',
        eventData: payload,
        isPublic: false,
        createdAt: DateTime.now(),
      ),
    );

    // Show seer result dialog/notification
    final targetName = payload['target_name'] ?? 'Unknown';
    final isWerewolf = payload['is_werewolf'] as bool;
    Get.snackbar(
      'Vision Result',
      '$targetName is ${isWerewolf ? "a WEREWOLF!" : "NOT a werewolf"}',
      duration: const Duration(seconds: 5),
    );
  }

  void _handleVoteUpdate(Map<String, dynamic> payload) {
    loadGame(session.value!.id);
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

  void _handleActionResult(Map<String, dynamic> payload) {
    if (payload['success'] == false) {
      errorMessage.value = payload['message'] ?? 'Action failed';
    }
  }

  void _updatePhaseTimer() {
    _phaseTimer?.cancel();

    if (session.value?.phaseEndTime != null) {
      _phaseTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        final endTime = session.value!.phaseEndTime!;
        final remaining = endTime.difference(DateTime.now());

        if (remaining.isNegative) {
          phaseTimeRemaining.value = Duration.zero;
          _phaseTimer?.cancel();
        } else {
          phaseTimeRemaining.value = remaining;
        }
      });
    }
  }

  bool _checkIfMyTurn() {
    if (myPlayer.value == null || !myPlayer.value!.isAlive) return false;

    final phase = currentPhase;
    final role = myPlayer.value!.role;

    switch (phase) {
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
      case GamePhase.dayVoting:
      case GamePhase.finalVote:
        return true; // All alive players can vote
      case GamePhase.hunterPhase:
        return role == GameRole.hunter;
      default:
        return false;
    }
  }

  List<GamePlayer> getSelectablePlayers() {
    if (session.value == null) return [];

    final phase = currentPhase;
    final alivePlayers = session.value!.alivePlayers;

    switch (phase) {
      case GamePhase.werewolfPhase:
        // Werewolves can't target other werewolves
        return alivePlayers.where((p) => p.role != GameRole.werewolf).toList();
      case GamePhase.cupidPhase:
        // Cupid can choose any alive player
        return alivePlayers;
      default:
        // Most actions target any alive player
        return alivePlayers;
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
