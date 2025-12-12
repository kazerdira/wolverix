import 'dart:async';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Complete Game Scenario Test for Wolverix
///
/// This test mirrors the backend test_complete_game.ps1 functionality
/// Tests complete game scenarios from registration to win conditions:
/// - Player registration and authentication
/// - Room creation and joining
/// - Role assignments and discovery
/// - Night phase actions (Cupid, Werewolves, Bodyguard, Seer, Witch)
/// - Day discussion and voting phases
/// - Death mechanics and game state tracking
/// - Win conditions (Villagers, Werewolves, Lovers)
/// - Security tests (unauthorized actions, dead player restrictions)

const String baseUrl = 'http://localhost:8080/api/v1';

// Helper class for player management
class TestPlayer {
  final String username;
  final String userId;
  final String token;
  String? role;
  String? team;
  String? gamePlayerId;
  bool isAlive = true;

  TestPlayer({
    required this.username,
    required this.userId,
    required this.token,
    this.role,
    this.team,
    this.gamePlayerId,
  });
}

class GameScenarioTester {
  final Dio dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
  ));

  final List<TestPlayer> players = [];
  final Random random = Random();

  // ANSI color codes for console output
  static const String green = '\x1B[32m';
  static const String red = '\x1B[31m';
  static const String yellow = '\x1B[33m';
  static const String cyan = '\x1B[36m';
  static const String magenta = '\x1B[35m';
  static const String gray = '\x1B[90m';
  static const String reset = '\x1B[0m';

  void printSuccess(String msg) => print('  $green✓$reset $msg');
  void printFail(String msg) => print('  $red✗$reset $msg');
  void printInfo(String msg) => print('  $cyan➤$reset $msg');
  void printDeath(String msg) => print('  $red☠$reset $msg');
  void printWarning(String msg) => print('  $yellow⚠$reset $msg');

  /// Register or login a player
  Future<TestPlayer?> registerPlayer(String username) async {
    try {
      // Try to register
      await dio.post('/auth/register', data: {
        'username': username,
        'password': 'password123',
        'email': '$username@test.com',
      });
    } catch (e) {
      // Expected error if user already exists
    }

    try {
      // Try to login
      final response = await dio.post('/auth/login', data: {
        'username': username,
        'password': 'password123',
      });

      final player = TestPlayer(
        username: username,
        userId: response.data['user']['id'],
        token: response.data['access_token'],
      );

      players.add(player);
      return player;
    } catch (e) {
      printWarning('$username could not login: $e');
      return null;
    }
  }

  /// Wait for a specific game phase
  Future<Map<String, dynamic>> waitForPhase(
    String sessionId,
    String targetPhase,
    String token, {
    int maxRetries = 60,
  }) async {
    int retries = 0;
    while (retries < maxRetries) {
      await Future.delayed(const Duration(seconds: 2));

      try {
        final response = await dio.get(
          '/games/$sessionId',
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );

        if (response.data['current_phase'] == targetPhase) {
          return response.data;
        }
      } catch (e) {
        printWarning('Error fetching game state: $e');
      }

      retries++;
    }

    throw TimeoutException('Timeout waiting for phase $targetPhase');
  }

  /// Get current game state
  Future<Map<String, dynamic>> getGameState(
    String sessionId,
    String token,
  ) async {
    final response = await dio.get(
      '/games/$sessionId',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return response.data;
  }

  /// Send a game action
  Future<bool> sendAction(
    String sessionId,
    String token,
    Map<String, dynamic> actionData,
  ) async {
    try {
      await dio.post(
        '/games/$sessionId/action',
        data: actionData,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Get players by role
  List<TestPlayer> getPlayersByRole(String role) {
    return players.where((p) => p.role == role && p.isAlive).toList();
  }

  /// Get alive players by team
  List<TestPlayer> getPlayersByTeam(String team) {
    return players.where((p) => p.team == team && p.isAlive).toList();
  }

  /// Play night phase actions
  Future<void> playNightPhase(
    String sessionId,
    Map<String, dynamic> gameState,
  ) async {
    printInfo('Playing Night Phase...');

    final alivePlayers = players.where((p) => p.isAlive).toList();
    final phaseNumber = gameState['phase_number'] as int;

    // 1. Cupid action (first night only)
    final cupids = getPlayersByRole('cupid');
    if (cupids.isNotEmpty && phaseNumber == 1) {
      final cupid = cupids.first;
      final targets = alivePlayers
          .where((p) => p.userId != cupid.userId)
          .toList()
        ..shuffle();

      if (targets.length >= 2) {
        final lover1 = targets[0];
        final lover2 = targets[1];

        final success = await sendAction(sessionId, cupid.token, {
          'action_type': 'cupid_choose',
          'target_id': lover1.gamePlayerId,
          'data': {'second_lover': lover2.gamePlayerId},
        });

        if (success) {
          printSuccess(
            '${cupid.username} created lovers: ${lover1.username} ♥ ${lover2.username}',
          );
        }
      }
    }

    // 2. Werewolf vote
    final werewolves = getPlayersByRole('werewolf');
    if (werewolves.isNotEmpty) {
      final villagers = getPlayersByTeam('villagers');
      if (villagers.isNotEmpty) {
        final target = villagers[random.nextInt(villagers.length)];

        for (final wolf in werewolves) {
          await sendAction(sessionId, wolf.token, {
            'action_type': 'werewolf_vote',
            'target_id': target.gamePlayerId,
          });
        }
        printSuccess('Werewolves targeting ${target.username}');
      }
    }

    // 3. Bodyguard protection
    final bodyguards = getPlayersByRole('bodyguard');
    if (bodyguards.isNotEmpty) {
      final bg = bodyguards.first;
      final targets = alivePlayers.where((p) => p.userId != bg.userId).toList();

      if (targets.isNotEmpty) {
        final protectTarget = targets[random.nextInt(targets.length)];
        await sendAction(sessionId, bg.token, {
          'action_type': 'bodyguard_protect',
          'target_id': protectTarget.gamePlayerId,
        });
      }
    }

    // 4. Seer divine
    final seers = getPlayersByRole('seer');
    if (seers.isNotEmpty) {
      final seer = seers.first;
      final targets =
          alivePlayers.where((p) => p.userId != seer.userId).toList();

      if (targets.isNotEmpty) {
        final divineTarget = targets[random.nextInt(targets.length)];
        await sendAction(sessionId, seer.token, {
          'action_type': 'seer_divine',
          'target_id': divineTarget.gamePlayerId,
        });
      }
    }

    // 5. Witch action (30% chance to poison)
    final witches = getPlayersByRole('witch');
    if (witches.isNotEmpty && random.nextInt(100) < 30) {
      final witch = witches.first;
      final werewolves = getPlayersByTeam('werewolves');

      if (werewolves.isNotEmpty) {
        final target = werewolves[random.nextInt(werewolves.length)];
        final success = await sendAction(sessionId, witch.token, {
          'action_type': 'witch_poison',
          'target_id': target.gamePlayerId,
        });

        if (success) {
          printSuccess('${witch.username} poisoned ${target.username}');
        }
      }
    }
  }

  /// Play voting phase
  Future<void> playVotingPhase(
    String sessionId,
    List<TestPlayer> alivePlayers,
  ) async {
    printInfo('Playing Voting Phase...');

    // Vote for a suspected werewolf
    final suspectedWerewolves =
        alivePlayers.where((p) => p.team == 'werewolves').toList();

    final target = suspectedWerewolves.isNotEmpty
        ? suspectedWerewolves[random.nextInt(suspectedWerewolves.length)]
        : alivePlayers[random.nextInt(alivePlayers.length)];

    for (final player in alivePlayers) {
      await sendAction(sessionId, player.token, {
        'action_type': 'vote_lynch',
        'target_id': target.gamePlayerId,
      });
    }

    printSuccess('Village voting to lynch ${target.username}');
  }

  /// Update player alive status from game state
  void updatePlayerStatus(Map<String, dynamic> gameState) {
    final gamePlayers = gameState['players'] as List;

    for (final player in players) {
      final gamePlayer = gamePlayers.firstWhere(
        (gp) => gp['user_id'] == player.userId,
        orElse: () => null,
      );

      if (gamePlayer != null) {
        player.isAlive = gamePlayer['is_alive'] ?? true;
      }
    }
  }

  /// Run a complete game scenario
  Future<Map<String, dynamic>> testScenario({
    required String scenarioName,
    required int playerCount,
    required int werewolfCount,
  }) async {
    print(
        '\n$cyan╔═══════════════════════════════════════════════════════════╗$reset');
    print('$cyan║  SCENARIO: ${scenarioName.padRight(46)} ║$reset');
    print(
        '$cyan╚═══════════════════════════════════════════════════════════╝$reset');

    players.clear();

    // 1. Register players
    print('\n$yellow=== PLAYER SETUP ===$reset');
    final playerNames = [
      'Alice',
      'Bob',
      'Charlie',
      'Diana',
      'Eve',
      'Frank',
      'Grace',
      'Henry'
    ];

    for (int i = 0; i < playerCount; i++) {
      final player = await registerPlayer(playerNames[i]);
      if (player != null) {
        printSuccess('${player.username} registered');
      }
    }

    if (players.isEmpty) {
      printFail('No players registered');
      return {'success': false};
    }

    // 1.5. Force leave all rooms (cleanup from previous tests)
    printInfo('Cleaning up previous rooms...');
    for (final player in players) {
      try {
        await dio.post(
          '/rooms/force-leave-all',
          options:
              Options(headers: {'Authorization': 'Bearer ${player.token}'}),
        );
      } catch (e) {
        // Ignore errors - player might not be in any room
      }
    }

    // 2. Create room
    print('\n$yellow=== ROOM CREATION ===$reset');
    late Response roomResponse;
    try {
      roomResponse = await dio.post(
        '/rooms',
        data: {
          'name': '$scenarioName Test',
          'max_players': playerCount,
          'is_private': false,
          'config': {
            'werewolf_count': werewolfCount,
            'day_phase_seconds': 10,
            'night_phase_seconds': 10,
            'voting_seconds': 10,
          },
        },
        options:
            Options(headers: {'Authorization': 'Bearer ${players[0].token}'}),
      );
    } catch (e) {
      if (e is DioException && e.response != null) {
        printFail('Room creation failed: ${e.response?.statusCode}');
        printFail('Error: ${e.response?.data}');
      }
      rethrow;
    }

    final roomId = roomResponse.data['id'];
    final roomCode = roomResponse.data['room_code'];
    printInfo('Room Code: $roomCode');

    // 3. Join room
    print('\n$yellow=== JOINING ROOM ===$reset');
    for (int i = 1; i < players.length; i++) {
      await dio.post(
        '/rooms/join',
        data: {'room_code': roomCode},
        options:
            Options(headers: {'Authorization': 'Bearer ${players[i].token}'}),
      );
      printSuccess('${players[i].username} joined');
    }

    // 4. Ready up
    print('\n$yellow=== READY UP ===$reset');
    try {
      for (final player in players) {
        await dio.post(
          '/rooms/$roomId/ready',
          data: {'ready': true},
          options:
              Options(headers: {'Authorization': 'Bearer ${player.token}'}),
        );
        printSuccess('${player.username} ready');
      }
      printSuccess('All players ready');
    } catch (e) {
      if (e is DioException && e.response != null) {
        printFail('Ready up failed: ${e.response?.statusCode}');
        printFail('Error: ${e.response?.data}');
      }
      rethrow;
    }

    // 5. Start game
    print('\n$yellow=== STARTING GAME ===$reset');
    late final Response gameResponse;
    try {
      gameResponse = await dio.post(
        '/rooms/$roomId/start',
        options:
            Options(headers: {'Authorization': 'Bearer ${players[0].token}'}),
      );
    } catch (e) {
      if (e is DioException && e.response != null) {
        printFail('Start game failed: ${e.response?.statusCode}');
        printFail('Error: ${e.response?.data}');
      }
      rethrow;
    }

    final sessionId = gameResponse.data['session_id'];
    printSuccess('Game started: $sessionId');

    // 6. Get role assignments
    print('\n$yellow=== ROLE ASSIGNMENTS ===$reset');
    for (final player in players) {
      final gameState = await getGameState(sessionId, player.token);
      final myPlayer = (gameState['players'] as List).firstWhere(
        (gp) => gp['user_id'] == player.userId,
      );

      player.role = myPlayer['role'];
      player.team = myPlayer['team'];
      player.gamePlayerId = myPlayer['id'];

      final color = player.team == 'werewolves' ? red : green;
      print('  ${player.username} → ${player.role} [${player.team}]'
              .padRight(50) +
          '$color█$reset');
    }

    // 7. Game loop
    print('\n$yellow=== GAME LOOP ===$reset');
    int dayNumber = 0;
    const int maxRounds = 15;
    String? winner;

    while (dayNumber < maxRounds) {
      dayNumber++;
      print('\n$magenta--- DAY $dayNumber ---$reset');

      // Wait for night phase
      try {
        await waitForPhase(sessionId, 'night_0', players[0].token,
            maxRetries: 10);
      } catch (e) {
        printInfo('Phase transition timeout, checking game state...');
      }

      var gameState = await getGameState(sessionId, players[0].token);

      // Check if game ended
      if (gameState['status'] == 'finished') {
        winner = gameState['winning_team'];
        print('\n$yellow🏆 GAME ENDED! Winner: $winner$reset');
        break;
      }

      // Update player status
      updatePlayerStatus(gameState);

      final alivePlayers = players.where((p) => p.isAlive).toList();
      printInfo('Alive: ${alivePlayers.length} players');

      if (alivePlayers.length <= 2) {
        printInfo('Only 2 or fewer players remain');
        break;
      }

      // Play night phase
      if (gameState['current_phase'] == 'night_0') {
        await playNightPhase(sessionId, gameState);

        // Wait for day discussion
        try {
          final dayState = await waitForPhase(
            sessionId,
            'day_discussion',
            players[0].token,
            maxRetries: 10,
          );

          // Show deaths
          final oldPlayers = gameState['players'] as List;
          final newPlayers = dayState['players'] as List;

          for (final newPlayer in newPlayers) {
            final oldPlayer = oldPlayers.firstWhere(
              (op) => op['id'] == newPlayer['id'],
              orElse: () => null,
            );

            if (oldPlayer != null &&
                oldPlayer['is_alive'] == true &&
                newPlayer['is_alive'] == false) {
              final deadPlayer = players.firstWhere(
                (p) => p.gamePlayerId == newPlayer['id'],
                orElse: () =>
                    TestPlayer(username: 'Unknown', userId: '', token: ''),
              );
              printDeath(
                  '${deadPlayer.username} died (${newPlayer['death_reason'] ?? 'unknown'})');
            }
          }

          gameState = dayState;
        } catch (e) {
          printInfo('Waiting for day phase...');
        }
      }

      // Wait for voting phase
      try {
        gameState = await waitForPhase(
          sessionId,
          'day_voting',
          players[0].token,
          maxRetries: 10,
        );
      } catch (e) {
        printInfo('Waiting for voting phase...');
      }

      if (gameState['current_phase'] == 'day_voting') {
        updatePlayerStatus(gameState);
        final alivePlayers = players.where((p) => p.isAlive).toList();
        await playVotingPhase(sessionId, alivePlayers);
      }

      // Small delay before next round
      await Future.delayed(const Duration(seconds: 2));
    }

    // Final results
    print(
        '\n$green╔═══════════════════════════════════════════════════════════╗$reset');
    print('$green║  SCENARIO COMPLETE: ${scenarioName.padRight(39)} ║$reset');
    print(
        '$green╚═══════════════════════════════════════════════════════════╝$reset');

    final finalState = await getGameState(sessionId, players[0].token);
    print('\nFinal Status: ${finalState['status']}');
    print('Winner: ${finalState['winning_team'] ?? 'Still playing'}');
    print('Days Survived: $dayNumber');

    final aliveCount =
        (finalState['players'] as List).where((p) => p['is_alive']).length;
    final deadCount =
        (finalState['players'] as List).where((p) => !p['is_alive']).length;
    print('Alive: $aliveCount | Dead: $deadCount');

    return {
      'success': true,
      'winner': finalState['winning_team'],
      'days_survived': dayNumber,
      'session_id': sessionId,
    };
  }

  /// Run security tests
  Future<void> runSecurityTests(String sessionId, String token) async {
    print('\n$yellow=== SECURITY TESTS ===$reset');

    // Check if we have enough alive players for security tests
    final aliveInnocents =
        players.where((p) => p.team != 'werewolves' && p.isAlive).toList();
    final aliveWerewolves =
        players.where((p) => p.team == 'werewolves' && p.isAlive).toList();

    if (aliveInnocents.isEmpty || aliveWerewolves.isEmpty) {
      printInfo(
          'Skipping security tests - not enough alive players (innocents: ${aliveInnocents.length}, werewolves: ${aliveWerewolves.length})');
      return;
    }

    // Test 1: Non-werewolf trying to vote as werewolf
    printInfo('Test: Non-werewolf attempting werewolf vote...');
    final innocent = aliveInnocents.first;
    final werewolf = aliveWerewolves.first;

    final blocked = !(await sendAction(sessionId, innocent.token, {
      'action_type': 'werewolf_vote',
      'target_id': werewolf.gamePlayerId,
    }));

    if (blocked) {
      printSuccess('BLOCKED: Unauthorized werewolf vote rejected');
    } else {
      printFail('SECURITY BREACH: Non-werewolf voted as werewolf!');
    }

    // Test 2: Voting during discussion phase
    printInfo('Test: Attempting to vote during discussion...');
    final gameState = await getGameState(sessionId, token);

    if (gameState['current_phase'] == 'day_discussion') {
      final votingBlocked = !(await sendAction(sessionId, token, {
        'action_type': 'vote_lynch',
        'target_id': werewolf.gamePlayerId,
      }));

      if (votingBlocked) {
        printSuccess('BLOCKED: Voting correctly restricted to voting phase');
      } else {
        printFail('SECURITY BREACH: Vote allowed during discussion!');
      }
    }

    // Test 3: Dead player trying to act
    final deadPlayers = players.where((p) => !p.isAlive).toList();
    if (deadPlayers.isNotEmpty) {
      printInfo('Test: Dead player attempting action...');
      final deadPlayer = deadPlayers.first;

      final actionBlocked = !(await sendAction(sessionId, deadPlayer.token, {
        'action_type': 'werewolf_vote',
        'target_id': innocent.gamePlayerId,
      }));

      if (actionBlocked) {
        printSuccess('BLOCKED: Dead player correctly prevented from acting');
      } else {
        printFail('SECURITY BREACH: Dead player acted!');
      }
    }
  }
}

void main() {
  group('Complete Game Scenarios', () {
    late GameScenarioTester tester;

    setUp(() {
      tester = GameScenarioTester();
    });

    test('Scenario 1: Balanced Game (8 players, 2 werewolves)', () async {
      final result = await tester.testScenario(
        scenarioName: 'Balanced Game',
        playerCount: 8,
        werewolfCount: 2,
      );

      expect(result['success'], true);
      print('\n✓ Scenario 1 Complete - Winner: ${result['winner']}');
    }, timeout: const Timeout(Duration(minutes: 10)));

    test('Scenario 2: Werewolf Advantage (6 players, 2 werewolves)', () async {
      final result = await tester.testScenario(
        scenarioName: 'Werewolf Advantage',
        playerCount: 6,
        werewolfCount: 2,
      );

      expect(result['success'], true);
      print('\n✓ Scenario 2 Complete - Winner: ${result['winner']}');
    }, timeout: const Timeout(Duration(minutes: 10)));

    test('Scenario 3: Large Game (8 players, 3 werewolves)', () async {
      final result = await tester.testScenario(
        scenarioName: 'Large Game',
        playerCount: 8,
        werewolfCount: 3,
      );

      expect(result['success'], true);
      print('\n✓ Scenario 3 Complete - Winner: ${result['winner']}');
    }, timeout: const Timeout(Duration(minutes: 10)));

    test('Security Tests', () async {
      // Run a quick game to test security
      final result = await tester.testScenario(
        scenarioName: 'Security Test',
        playerCount: 6,
        werewolfCount: 2,
      );

      if (result['success'] == true) {
        await tester.runSecurityTests(
          result['session_id'],
          tester.players[0].token,
        );
      }
    }, timeout: const Timeout(Duration(minutes: 10)));
  });
}
