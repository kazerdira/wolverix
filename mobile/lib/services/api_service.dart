import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:get/get.dart' as getx;

import '../models/models.dart';
import 'storage_service.dart';

class ApiService extends getx.GetxService {
  late final Dio _dio;
  final StorageService _storage = getx.Get.find<StorageService>();

  // For Android Emulator use: 10.0.2.2
  // For physical device use: your computer's IP address (e.g., 192.168.1.x)
  // For iOS Simulator use: localhost
  static const String baseUrl = 'http://192.168.1.44:8080/api/v1';

  @override
  void onInit() {
    super.onInit();
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    // Add interceptors
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _storage.getAccessToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (error, handler) async {
          if (error.response?.statusCode == 401) {
            // Try to refresh token
            final refreshed = await _refreshToken();
            if (refreshed) {
              // Retry the request
              final opts = error.requestOptions;
              final token = await _storage.getAccessToken();
              opts.headers['Authorization'] = 'Bearer $token';
              try {
                final response = await _dio.fetch(opts);
                return handler.resolve(response);
              } catch (e) {
                return handler.next(error);
              }
            }
          }
          return handler.next(error);
        },
      ),
    );
  }

  Future<bool> _refreshToken() async {
    try {
      final refreshToken = await _storage.getRefreshToken();
      if (refreshToken == null) return false;

      final response = await _dio.post(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );

      if (response.statusCode == 200) {
        await _storage.setAccessToken(response.data['access_token']);
        await _storage.setRefreshToken(response.data['refresh_token']);
        return true;
      }
    } catch (e) {
      await _storage.clearAuth();
    }
    return false;
  }

  // ============================================================================
  // AUTH ENDPOINTS
  // ============================================================================

  Future<AuthResponse> register(
    String username,
    String email,
    String password,
  ) async {
    final response = await _dio.post(
      '/auth/register',
      data: {'username': username, 'email': email, 'password': password},
    );
    return AuthResponse.fromJson(response.data);
  }

  Future<AuthResponse> login(String email, String password) async {
    final response = await _dio.post(
      '/auth/login',
      data: {'email': email, 'password': password},
    );
    return AuthResponse.fromJson(response.data);
  }

  Future<User> getCurrentUser() async {
    final response = await _dio.get('/users/me');
    return User.fromJson(response.data);
  }

  Future<User> updateUser(Map<String, dynamic> data) async {
    final response = await _dio.put('/users/me', data: data);
    return User.fromJson(response.data);
  }

  Future<UserStats> getUserStats() async {
    final storage = getx.Get.find<StorageService>();
    final userId = storage.getUserId();
    final response = await _dio.get('/users/$userId/stats');
    return UserStats.fromJson(response.data);
  }

  // ============================================================================
  // ROOM ENDPOINTS
  // ============================================================================

  Future<Room> createRoom({
    required String name,
    bool isPrivate = false,
    int maxPlayers = 12,
    String language = 'en',
    RoomConfig? config,
  }) async {
    final response = await _dio.post(
      '/rooms',
      data: {
        'name': name,
        'is_private': isPrivate,
        'max_players': maxPlayers,
        'language': language,
        'config': config?.toJson() ?? {},
      },
    );
    return Room.fromJson(response.data);
  }

  Future<List<Room>> getRooms() async {
    final response = await _dio.get('/rooms');
    return (response.data as List).map((r) => Room.fromJson(r)).toList();
  }

  Future<Room> getRoom(String roomId) async {
    final response = await _dio.get('/rooms/$roomId');
    return Room.fromJson(response.data);
  }

  Future<Map<String, dynamic>> joinRoom(String roomCode) async {
    final response = await _dio.post(
      '/rooms/join',
      data: {'room_code': roomCode},
    );
    return response.data;
  }

  Future<void> leaveRoom(String roomId) async {
    await _dio.post('/rooms/$roomId/leave');
  }

  Future<Map<String, dynamic>> forceLeaveAllRooms() async {
    final response = await _dio.post('/rooms/force-leave-all');
    return response.data;
  }

  Future<void> setReady(String roomId, bool ready) async {
    await _dio.post('/rooms/$roomId/ready', data: {'ready': ready});
  }

  Future<void> kickPlayer(String roomId, String playerId) async {
    await _dio.post('/rooms/$roomId/kick', data: {'player_id': playerId});
  }

  Future<GameSession> startGame(String roomId) async {
    final response = await _dio.post('/rooms/$roomId/start');
    return GameSession.fromJson(response.data);
  }

  Future<Map<String, dynamic>> extendRoomTimeout(String roomId) async {
    final response = await _dio.post('/rooms/$roomId/extend');
    return response.data;
  }

  // ============================================================================
  // GAME ENDPOINTS
  // ============================================================================

  Future<GameSession> getGameState(String sessionId) async {
    final response = await _dio.get('/games/$sessionId');
    return GameSession.fromJson(response.data);
  }

  Future<Map<String, dynamic>> performAction(
    String sessionId, {
    required String actionType,
    String? targetPlayerId,
    Map<String, dynamic>? data,
  }) async {
    final requestData = <String, dynamic>{
      'action_type': actionType,
    };

    if (targetPlayerId != null) {
      requestData['target_player_id'] = targetPlayerId;
    }

    // Merge additional data (for Cupid's second target, etc.)
    if (data != null) {
      requestData['data'] = data;
    }

    final response = await _dio.post(
      '/games/$sessionId/action',
      data: requestData,
    );
    return response.data;
  }

  Future<List<GameEvent>> getGameHistory(String sessionId) async {
    final response = await _dio.get('/games/$sessionId/history');
    return (response.data as List).map((e) => GameEvent.fromJson(e)).toList();
  }

  // ============================================================================
  // AGORA TOKEN
  // ============================================================================

  Future<AgoraToken> getAgoraToken(String channelName, int uid) async {
    final response = await _dio.post(
      '/agora/token',
      data: {'channel_name': channelName, 'uid': uid},
    );
    return AgoraToken.fromJson(response.data);
  }
}
