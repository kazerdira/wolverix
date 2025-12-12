import 'dart:async';
import 'dart:convert';
import 'package:get/get.dart' as getx;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/models.dart';
import 'storage_service.dart';
import 'api_service.dart';

class WebSocketService extends getx.GetxService {
  WebSocketChannel? _channel;
  final StorageService _storage = getx.Get.find<StorageService>();

  final _messageController = StreamController<WSMessage>.broadcast();
  Stream<WSMessage> get messageStream => _messageController.stream;

  Timer? _pingTimer;
  Timer? _reconnectTimer;
  bool _isConnecting = false;
  bool _isConnected = false;
  String? _currentRoomId;

  // For Android Emulator use: ws://10.0.2.2:8080/api/v1/ws
  // For physical device use: ws://YOUR_COMPUTER_IP:8080/api/v1/ws
  static const String wsBaseUrl = 'ws://192.168.1.15:8080/api/v1/ws';

  bool get isConnected => _isConnected;

  Future<void> connect(String roomId) async {
    if (_isConnecting) return;
    if (_isConnected && _currentRoomId == roomId) return;

    _isConnecting = true;
    _currentRoomId = roomId;

    try {
      await disconnect();

      final token = await _storage.getAccessToken();
      if (token == null) {
        throw Exception('Not authenticated');
      }

      final uri = Uri.parse('$wsBaseUrl?room_id=$roomId&token=$token');
      _channel = WebSocketChannel.connect(uri);

      _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );

      _isConnected = true;
      _isConnecting = false;

      // Start ping timer to keep connection alive
      _startPingTimer();

      print('WebSocket connected to room: $roomId');
    } catch (e) {
      _isConnecting = false;
      print('WebSocket connection error: $e');
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic data) {
    try {
      final dataString = (data as String).trim();

      // Skip empty or invalid messages
      if (dataString.isEmpty || !dataString.startsWith('{')) {
        return;
      }

      // Handle multiple concatenated JSON objects
      final messages = <String>[];
      var buffer = '';
      var depth = 0;

      for (var i = 0; i < dataString.length; i++) {
        final char = dataString[i];
        buffer += char;

        if (char == '{') {
          depth++;
        } else if (char == '}') {
          depth--;
          if (depth == 0 && buffer.trim().isNotEmpty) {
            messages.add(buffer.trim());
            buffer = '';
          }
        }
      }

      // Process each complete JSON message
      for (final msgStr in messages) {
        try {
          final json = jsonDecode(msgStr);
          final message = WSMessage.fromJson(json);
          _messageController.add(message);
        } catch (e) {
          print('Failed to parse message - Error: $e');
          print('Raw message: $msgStr');
        }
      }
    } catch (e) {
      print('WebSocket message parse error: $e');
      if (data != null) {
        print('Raw data: $data');
      }
    }
  }

  void _onError(dynamic error) {
    print('WebSocket error: $error');
    _isConnected = false;
    _scheduleReconnect();
  }

  void _onDone() {
    print('WebSocket connection closed');
    _isConnected = false;
    _scheduleReconnect();
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_isConnected) {
        send('ping', {});
      }
    });
  }

  void _scheduleReconnect() {
    if (_currentRoomId == null) return;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (!_isConnected && _currentRoomId != null) {
        connect(_currentRoomId!);
      }
    });
  }

  void send(String type, Map<String, dynamic> payload) {
    if (_channel != null && _isConnected) {
      final message = WSMessage(type: type, payload: payload);
      _channel!.sink.add(jsonEncode(message.toJson()));
    }
  }

  Future<void> disconnect() async {
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _isConnected = false;

    if (_channel != null) {
      await _channel!.sink.close();
      _channel = null;
    }
  }

  // Convenience methods for common messages
  void sendChatMessage(String message) {
    send('chat_message', {'message': message});
  }

  void sendReady(bool ready) {
    send('player_ready', {'ready': ready});
  }

  void sendVote(String targetPlayerId) {
    send('vote', {'target_player_id': targetPlayerId});
  }

  void sendAction(String actionType, String? targetPlayerId) {
    send('game_action', {
      'action_type': actionType,
      'target_player_id': targetPlayerId,
    });
  }

  @override
  void onClose() {
    disconnect();
    _messageController.close();
    super.onClose();
  }
}
