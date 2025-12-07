import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:werewolf_voice/models/models.dart';

class ApiService {
  final Dio _dio;
  final Logger _logger = Logger();
  String? _token;

  static const String baseUrl = 'http://localhost:8080/api/v1'; // Change for production

  ApiService() : _dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
  )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (_token != null) {
          options.headers['Authorization'] = 'Bearer $_token';
        }
        _logger.d('${options.method} ${options.path}');
        return handler.next(options);
      },
      onError: (error, handler) {
        _logger.e('API Error: ${error.message}');
        return handler.next(error);
      },
    ));
  }

  void setToken(String token) {
    _token = token;
  }

  void clearToken() {
    _token = null;
  }

  // ============================================================================
  // AUTH
  // ============================================================================

  Future<AuthResponse> register({
    required String username,
    required String email,
    required String password,
    String language = 'en',
  }) async {
    try {
      final response = await _dio.post('/auth/register', data: {
        'username': username,
        'email': email,
        'password': password,
        'language': language,
      });
      return AuthResponse.fromJson(response.data);
    } catch (e) {
      _logger.e('Register failed: $e');
      rethrow;
    }
  }

  Future<AuthResponse> login({
    required String username,
    required String password,
  }) async {
    try {
      final response = await _dio.post('/auth/login', data: {
        'username': username,
        'password': password,
      });
      return AuthResponse.fromJson(response.data);
    } catch (e) {
      _logger.e('Login failed: $e');
      rethrow;
    }
  }

  // ============================================================================
  // ROOMS
  // ============================================================================

  Future<Room> createRoom({
    required String name,
    bool isPrivate = false,
    String? password,
    int maxPlayers = 12,
    String language = 'en',
    required RoomConfig config,
  }) async {
    try {
      final response = await _dio.post('/rooms', data: {
        'name': name,
        'is_private': isPrivate,
        'password': password,
        'max_players': maxPlayers,
        'language': language,
        'config': config.toJson(),
      });
      return Room.fromJson(response.data);
    } catch (e) {
      _logger.e('Create room failed: $e');
      rethrow;
    }
  }

  Future<List<Room>> getRooms() async {
    try {
      final response = await _dio.get('/rooms');
      return (response.data as List).map((json) => Room.fromJson(json)).toList();
    } catch (e) {
      _logger.e('Get rooms failed: $e');
      rethrow;
    }
  }

  Future<Room> getRoom(String roomId) async {
    try {
      final response = await _dio.get('/rooms/$roomId');
      return Room.fromJson(response.data);
    } catch (e) {
      _logger.e('Get room failed: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> joinRoom({
    required String roomCode,
    String? password,
  }) async {
    try {
      final response = await _dio.post('/rooms/join', data: {
        'room_code': roomCode,
        'password': password,
      });
      return response.data;
    } catch (e) {
      _logger.e('Join room failed: $e');
      rethrow;
    }
  }

  Future<void> leaveRoom(String roomId) async {
    try {
      await _dio.post('/rooms/$roomId/leave');
    } catch (e) {
      _logger.e('Leave room failed: $e');
      rethrow;
    }
  }

  Future<void> setReady(String roomId) async {
    try {
      await _dio.post('/rooms/$roomId/ready');
    } catch (e) {
      _logger.e('Set ready failed: $e');
      rethrow;
    }
  }

  Future<GameSession> startGame(String roomId) async {
    try {
      final response = await _dio.post('/rooms/$roomId/start');
      return GameSession.fromJson(response.data);
    } catch (e) {
      _logger.e('Start game failed: $e');
      rethrow;
    }
  }

  // ============================================================================
  // GAME
  // ============================================================================

  Future<void> performAction({
    required String sessionId,
    required String actionType,
    String? targetId,
    Map<String, dynamic>? data,
  }) async {
    try {
      await _dio.post('/games/$sessionId/action', data: {
        'action_type': actionType,
        'target_id': targetId,
        'data': data,
      });
    } catch (e) {
      _logger.e('Perform action failed: $e');
      rethrow;
    }
  }

  Future<GameSession> getGameState(String sessionId) async {
    try {
      final response = await _dio.get('/games/$sessionId');
      return GameSession.fromJson(response.data);
    } catch (e) {
      _logger.e('Get game state failed: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getMyRole(String sessionId) async {
    try {
      final response = await _dio.get('/games/$sessionId/my-role');
      return response.data;
    } catch (e) {
      _logger.e('Get my role failed: $e');
      rethrow;
    }
  }

  // ============================================================================
  // AGORA
  // ============================================================================

  Future<AgoraTokenResponse> getAgoraToken({
    required String channelName,
    required int uid,
  }) async {
    try {
      final response = await _dio.post('/agora/token', data: {
        'channel_name': channelName,
        'uid': uid,
      });
      return AgoraTokenResponse.fromJson(response.data);
    } catch (e) {
      _logger.e('Get Agora token failed: $e');
      rethrow;
    }
  }

  // ============================================================================
  // USER
  // ============================================================================

  Future<User> getProfile() async {
    try {
      final response = await _dio.get('/users/me');
      return User.fromJson(response.data);
    } catch (e) {
      _logger.e('Get profile failed: $e');
      rethrow;
    }
  }

  Future<UserStats> getStats() async {
    try {
      final response = await _dio.get('/users/me/stats');
      return UserStats.fromJson(response.data);
    } catch (e) {
      _logger.e('Get stats failed: $e');
      rethrow;
    }
  }
}
