import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

/// Integration tests for backend API
/// These tests make real HTTP calls to the backend server
///
/// Prerequisites:
/// - Backend server must be running on localhost:8080
/// - PostgreSQL database must be running
///
/// Run with: flutter test test/api_integration_test.dart

void main() {
  late Dio dio;
  const baseUrl = 'http://localhost:8080/api/v1';

  // Test user credentials
  final testUsername = 'testuser_${DateTime.now().millisecondsSinceEpoch}';
  final testEmail = 'test_${DateTime.now().millisecondsSinceEpoch}@example.com';
  const testPassword = 'password123';

  // Stored data between tests
  String? accessToken;
  String? userId;
  String? roomId;
  String? roomCode;
  String? sessionId;

  setUp(() {
    dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    // Add auth interceptor
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (accessToken != null) {
            options.headers['Authorization'] = 'Bearer $accessToken';
          }
          return handler.next(options);
        },
      ),
    );
  });

  group('Authentication APIs', () {
    test('Register new user', () async {
      final response = await dio.post(
        '/auth/register',
        data: {
          'username': testUsername,
          'email': testEmail,
          'password': testPassword,
        },
      );

      expect(response.statusCode, 201);
      expect(response.data, isA<Map<String, dynamic>>());
      expect(response.data['access_token'], isNotNull);
      expect(response.data['user'], isNotNull);
      expect(response.data['user']['username'], testUsername);
      expect(response.data['user']['email'], testEmail);

      // Store for next tests
      accessToken = response.data['access_token'];
      userId = response.data['user']['id'];

      print('✅ User registered: $testUsername (ID: $userId)');
    });

    test('Login with credentials', () async {
      final response = await dio.post(
        '/auth/login',
        data: {
          'email': testEmail,
          'password': testPassword,
        },
      );

      expect(response.statusCode, 200);
      expect(response.data['access_token'], isNotNull);
      expect(response.data['user']['email'], testEmail);

      accessToken = response.data['access_token'];
      print('✅ User logged in successfully');
    });

    test('Get current user profile', () async {
      final response = await dio.get('/users/me');

      expect(response.statusCode, 200);
      expect(response.data['id'], userId);
      expect(response.data['username'], testUsername);
      print('✅ Retrieved user profile');
    });
  });

  group('Room APIs', () {
    test('Create room', () async {
      final response = await dio.post(
        '/rooms',
        data: {
          'name': 'Test Room ${DateTime.now().millisecondsSinceEpoch}',
          'is_private': false,
          'max_players': 10,
          'language': 'en',
        },
      );

      expect(response.statusCode, 201);
      expect(response.data['id'], isNotNull);
      expect(response.data['room_code'], isNotNull);
      expect(response.data['host_user_id'], userId);

      roomId = response.data['id'];
      roomCode = response.data['room_code'];

      print('✅ Room created: $roomCode (ID: $roomId)');
    });

    test('Get room details', () async {
      expect(roomId, isNotNull, reason: 'Room must be created first');

      final response = await dio.get('/rooms/$roomId');

      expect(response.statusCode, 200);
      expect(response.data['id'], roomId);
      expect(response.data['room_code'], roomCode);
      print('✅ Retrieved room details');
    });

    test('List available rooms', () async {
      final response = await dio.get('/rooms');

      expect(response.statusCode, 200);
      expect(response.data, isA<List>());

      // Our room should be in the list
      final rooms = response.data as List;
      final ourRoom = rooms.firstWhere(
        (room) => room['id'] == roomId,
        orElse: () => null,
      );

      expect(ourRoom, isNotNull);
      print('✅ Listed ${rooms.length} available rooms');
    });

    test('Set player ready', () async {
      expect(roomId, isNotNull, reason: 'Room must be created first');

      final response = await dio.post(
        '/rooms/$roomId/ready',
        data: {'ready': true},
      );

      expect(response.statusCode, 200);
      print('✅ Player marked as ready');
    });
  });

  group('Game APIs - Join with Bots', () {
    test('Create game with 8 bot players', () async {
      expect(roomId, isNotNull, reason: 'Room must be created first');

      // Create and join 7 more bot players
      final botTokens = <String>[];

      for (int i = 2; i <= 8; i++) {
        final botUsername = 'bot$i${DateTime.now().millisecondsSinceEpoch}';
        final botEmail =
            'bot$i${DateTime.now().millisecondsSinceEpoch}@example.com';

        // Register bot
        final registerResponse = await dio.post(
          '/auth/register',
          data: {
            'username': botUsername,
            'email': botEmail,
            'password': 'password123',
          },
        );

        expect(registerResponse.statusCode, 201);
        final botToken = registerResponse.data['access_token'];
        botTokens.add(botToken);

        // Join room with bot
        final joinResponse = await Dio(
          BaseOptions(
            baseUrl: baseUrl,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $botToken',
            },
          ),
        ).post('/rooms/join', data: {'room_code': roomCode});

        expect(joinResponse.statusCode, 200);

        // Set bot ready
        await Dio(
          BaseOptions(
            baseUrl: baseUrl,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $botToken',
            },
          ),
        ).post('/rooms/$roomId/ready', data: {'ready': true});

        print('  ✅ Bot $i joined and ready');
      }

      print('✅ All 8 players ready in room');
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('Start game', () async {
      expect(roomId, isNotNull, reason: 'Room must be created first');

      final response = await dio.post('/rooms/$roomId/start');

      expect(response.statusCode, 200);
      expect(response.data['session_id'], isNotNull);

      sessionId = response.data['session_id'];
      print('✅ Game started: Session $sessionId');
    });

    test('Get game state', () async {
      expect(sessionId, isNotNull, reason: 'Game must be started first');

      // Wait a moment for game initialization
      await Future.delayed(const Duration(seconds: 1));

      final response = await dio.get('/games/$sessionId');

      expect(response.statusCode, 200);
      expect(response.data['id'], sessionId);
      expect(response.data['status'], isNotNull);
      expect(response.data['current_phase'], isNotNull);

      print('✅ Game state retrieved');
      print('   Phase: ${response.data['current_phase']}');
      print('   Status: ${response.data['status']}');
      print('   Day: ${response.data['day_number']}');

      // Check if players have roles
      if (response.data['players'] != null) {
        final players = response.data['players'] as List;
        print('   Players: ${players.length}');

        if (players.isNotEmpty) {
          final myPlayer = players.firstWhere(
            (p) => p['user_id'] == userId,
            orElse: () => null,
          );

          if (myPlayer != null && myPlayer['role'] != null) {
            print('   My role: ${myPlayer['role']}');
          }
        }
      }
    });

    test('Get game history', () async {
      expect(sessionId, isNotNull, reason: 'Game must be started first');

      final response = await dio.get('/games/$sessionId/history');

      expect(response.statusCode, 200);
      expect(response.data, isA<List>());

      final events = response.data as List;
      print('✅ Retrieved ${events.length} game events');

      if (events.isNotEmpty) {
        print('   Latest event: ${events.first['event_type']}');
      }
    });
  });

  group('Error Handling', () {
    test('Login with invalid credentials', () async {
      try {
        await dio.post(
          '/auth/login',
          data: {
            'email': 'nonexistent@example.com',
            'password': 'wrongpassword',
          },
        );
        fail('Should have thrown an error');
      } on DioException catch (e) {
        expect(e.response?.statusCode, anyOf([401, 400]));
        print('✅ Invalid login rejected correctly');
      }
    });

    test('Access protected route without token', () async {
      final dioNoAuth = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          headers: {'Content-Type': 'application/json'},
        ),
      );

      try {
        await dioNoAuth.get('/users/me');
        fail('Should have thrown an error');
      } on DioException catch (e) {
        expect(e.response?.statusCode, 401);
        print('✅ Unauthorized access blocked correctly');
      }
    });

    test('Join non-existent room', () async {
      try {
        await dio.post(
          '/rooms/join',
          data: {'room_code': 'INVALID'},
        );
        fail('Should have thrown an error');
      } on DioException catch (e) {
        expect(e.response?.statusCode, anyOf([404, 400]));
        print('✅ Invalid room code rejected correctly');
      }
    });

    test('Get non-existent game state', () async {
      final fakeSessionId = const Uuid().v4();

      try {
        await dio.get('/games/$fakeSessionId');
        fail('Should have thrown an error');
      } on DioException catch (e) {
        expect(e.response?.statusCode, 404);
        print('✅ Non-existent game rejected correctly');
      }
    });
  });

  group('Performance Tests', () {
    test('Response times are acceptable', () async {
      final stopwatch = Stopwatch()..start();

      await dio.get('/rooms');

      stopwatch.stop();
      final elapsed = stopwatch.elapsedMilliseconds;

      expect(elapsed, lessThan(1000),
          reason: 'API should respond within 1 second');
      print('✅ Response time: ${elapsed}ms');
    });
  });
}
