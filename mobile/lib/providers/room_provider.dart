import 'dart:async';
import 'package:get/get.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import '../services/storage_service.dart';

class RoomProvider extends GetxController {
  final ApiService _api = Get.find<ApiService>();
  final WebSocketService _ws = Get.find<WebSocketService>();

  final Rx<Room?> currentRoom = Rx<Room?>(null);
  final RxList<Room> availableRooms = <Room>[].obs;
  final RxBool isLoading = false.obs;
  final RxString errorMessage = ''.obs;

  StreamSubscription? _wsSubscription;

  Room? get room => currentRoom.value;
  List<RoomPlayer> get players => currentRoom.value?.players ?? [];
  bool get isHost =>
      currentRoom.value?.hostUserId == Get.find<StorageService>().getUserId();

  @override
  void onInit() {
    super.onInit();
    _subscribeToWebSocket();
  }

  void _subscribeToWebSocket() {
    _wsSubscription = _ws.messageStream.listen((message) {
      switch (message.type) {
        case 'room_update':
          final action = message.payload['action'];
          if (action == 'timeout_warning') {
            _handleTimeoutWarning(message.payload);
          } else if (action == 'room_closed') {
            _handleRoomClosed(message.payload);
          } else if (action == 'timeout_extended') {
            _handleTimeoutExtended(message.payload);
          } else {
            _handleRoomUpdate(message.payload);
          }
          break;
        case 'player_joined':
          _handlePlayerJoined(message.payload);
          break;
        case 'player_left':
          _handlePlayerLeft(message.payload);
          break;
        case 'player_ready':
          _handlePlayerReady(message.payload);
          break;
        case 'player_kicked':
          _handlePlayerKicked(message.payload);
          break;
        case 'game_started':
          _handleGameStarted(message.payload);
          break;
      }
    });
  }

  Future<void> fetchRooms() async {
    try {
      isLoading.value = true;
      final rooms = await _api.getRooms();
      availableRooms.value = rooms;
    } catch (e) {
      errorMessage.value = 'Failed to fetch rooms';
      print('Error fetching rooms: $e');
    } finally {
      isLoading.value = false;
    }
  }

  Future<Room?> createRoom({
    required String name,
    bool isPrivate = false,
    int maxPlayers = 12,
    RoomConfig? config,
  }) async {
    try {
      isLoading.value = true;
      errorMessage.value = '';

      final room = await _api.createRoom(
        name: name,
        isPrivate: isPrivate,
        maxPlayers: maxPlayers,
        config: config,
      );

      currentRoom.value = room;
      await _ws.connect(room.id);

      return room;
    } catch (e) {
      if (e.toString().contains('already in an active room')) {
        errorMessage.value =
            'You are already in an active room. Please leave it first.';
      } else {
        errorMessage.value = 'Failed to create room';
      }
      return null;
    } finally {
      isLoading.value = false;
    }
  }

  Future<bool> joinRoom(String roomCode) async {
    try {
      isLoading.value = true;
      errorMessage.value = '';

      final result = await _api.joinRoom(roomCode);
      final roomId = result['room_id'] as String;

      // Fetch full room details
      final room = await _api.getRoom(roomId);
      currentRoom.value = room;

      await _ws.connect(room.id);

      return true;
    } catch (e) {
      if (e.toString().contains('404')) {
        errorMessage.value = 'Room not found';
      } else if (e.toString().contains('full')) {
        errorMessage.value = 'Room is full';
      } else if (e.toString().contains('already in an active room')) {
        errorMessage.value =
            'You are already in an active room. Please leave it first.';
      } else {
        errorMessage.value = 'Failed to join room';
      }
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> leaveRoom() async {
    if (currentRoom.value == null) return;

    try {
      await _api.leaveRoom(currentRoom.value!.id);
      await _ws.disconnect();
      currentRoom.value = null;
    } catch (e) {
      print('Error leaving room: $e');
    }
  }

  Future<void> setReady(bool ready) async {
    if (currentRoom.value == null) return;

    try {
      await _api.setReady(currentRoom.value!.id, ready);
    } catch (e) {
      print('Error setting ready: $e');
    }
  }

  Future<void> kickPlayer(String playerId) async {
    if (currentRoom.value == null) return;

    try {
      await _api.kickPlayer(currentRoom.value!.id, playerId);
    } catch (e) {
      errorMessage.value = 'Failed to kick player';
    }
  }

  Future<GameSession?> startGame() async {
    if (currentRoom.value == null) return null;

    try {
      isLoading.value = true;
      final session = await _api.startGame(currentRoom.value!.id);
      return session;
    } catch (e) {
      errorMessage.value = _extractStartGameError(e);
      return null;
    } finally {
      isLoading.value = false;
    }
  }

  Future<bool> extendRoomTimeout() async {
    if (currentRoom.value == null) return false;

    try {
      await _api.extendRoomTimeout(currentRoom.value!.id);
      Get.snackbar(
        'Success',
        'Room timeout extended',
        snackPosition: SnackPosition.BOTTOM,
      );
      return true;
    } catch (e) {
      if (e.toString().contains('403')) {
        errorMessage.value = 'Only the host can extend room timeout';
      } else if (e.toString().contains('not in waiting')) {
        errorMessage.value = 'Can only extend timeout for waiting rooms';
      } else {
        errorMessage.value = 'Failed to extend room timeout';
      }
      Get.snackbar(
        'Error',
        errorMessage.value,
        snackPosition: SnackPosition.BOTTOM,
      );
      return false;
    }
  }

  Future<void> refreshRoom() async {
    if (currentRoom.value == null) return;

    try {
      final room = await _api.getRoom(currentRoom.value!.id);
      currentRoom.value = room;
    } catch (e) {
      print('Error refreshing room: $e');
    }
  }

  // WebSocket handlers
  void _handleRoomUpdate(Map<String, dynamic> payload) {
    refreshRoom();
  }

  void _handlePlayerJoined(Map<String, dynamic> payload) {
    refreshRoom();
  }

  void _handlePlayerLeft(Map<String, dynamic> payload) {
    refreshRoom();
  }

  void _handlePlayerReady(Map<String, dynamic> payload) {
    final userId = payload['user_id'] as String;
    final ready = payload['ready'] as bool;

    if (currentRoom.value != null) {
      final players = currentRoom.value!.players.map((p) {
        if (p.userId == userId) {
          return RoomPlayer(
            id: p.id,
            roomId: p.roomId,
            userId: p.userId,
            isReady: ready,
            isHost: p.isHost,
            seatPosition: p.seatPosition,
            joinedAt: p.joinedAt,
            user: p.user,
          );
        }
        return p;
      }).toList();

      currentRoom.value = Room(
        id: currentRoom.value!.id,
        roomCode: currentRoom.value!.roomCode,
        name: currentRoom.value!.name,
        hostUserId: currentRoom.value!.hostUserId,
        status: currentRoom.value!.status,
        isPrivate: currentRoom.value!.isPrivate,
        maxPlayers: currentRoom.value!.maxPlayers,
        currentPlayers: currentRoom.value!.currentPlayers,
        language: currentRoom.value!.language,
        config: currentRoom.value!.config,
        agoraChannelName: currentRoom.value!.agoraChannelName,
        agoraAppId: currentRoom.value!.agoraAppId,
        createdAt: currentRoom.value!.createdAt,
        lastActivityAt: currentRoom.value!.lastActivityAt,
        timeoutWarningSent: currentRoom.value!.timeoutWarningSent,
        timeoutExtendedCount: currentRoom.value!.timeoutExtendedCount,
        host: currentRoom.value!.host,
        players: players,
      );
    }
  }

  void _handlePlayerKicked(Map<String, dynamic> payload) {
    final kickedUserId = payload['user_id'] as String;
    final currentUserId = Get.find<StorageService>().getUserId();

    if (kickedUserId == currentUserId) {
      currentRoom.value = null;
      _ws.disconnect();
      Get.offAllNamed('/home');
      Get.snackbar('Kicked', 'You were kicked from the room');
    } else {
      refreshRoom();
    }
  }

  void _handleGameStarted(Map<String, dynamic> payload) {
    final sessionId = payload['session_id'] as String;
    Get.toNamed('/game/$sessionId');
  }

  void _handleTimeoutWarning(Map<String, dynamic> payload) {
    final minutesLeft = payload['minutes_left'] as int?;
    final message = payload['message'] as String? ??
        'Room will close in $minutesLeft minutes due to inactivity';

    Get.snackbar(
      'Room Timeout Warning',
      message,
      snackPosition: SnackPosition.TOP,
      duration: const Duration(seconds: 10),
      backgroundColor: Get.theme.colorScheme.errorContainer,
      colorText: Get.theme.colorScheme.onErrorContainer,
    );
  }

  void _handleRoomClosed(Map<String, dynamic> payload) {
    final reason = payload['reason'] as String?;
    final message = payload['message'] as String? ?? 'Room has been closed';

    currentRoom.value = null;
    _ws.disconnect();

    Get.offAllNamed('/home');
    Get.snackbar(
      'Room Closed',
      message,
      snackPosition: SnackPosition.TOP,
      duration: const Duration(seconds: 5),
      backgroundColor: Get.theme.colorScheme.errorContainer,
      colorText: Get.theme.colorScheme.onErrorContainer,
    );
  }

  void _handleTimeoutExtended(Map<String, dynamic> payload) {
    Get.snackbar(
      'Timeout Extended',
      'Host extended the room timeout',
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 3),
    );
    refreshRoom();
  }

  String _extractStartGameError(dynamic error) {
    final errorStr = error.toString().toLowerCase();
    if (errorStr.contains('not enough')) {
      return 'Need at least 5 players to start';
    } else if (errorStr.contains('not ready')) {
      return 'All players must be ready';
    }
    return 'Failed to start game';
  }

  @override
  void onClose() {
    _wsSubscription?.cancel();
    super.onClose();
  }
}
