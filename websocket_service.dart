import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:logger/logger.dart';
import 'package:werewolf_voice/models/models.dart';

class WebSocketService {
  final Logger _logger = Logger();
  WebSocketChannel? _channel;
  bool _isConnected = false;
  String? _token;
  String? _roomId;

  // Callbacks
  Function(WSMessage message)? onMessage;
  Function()? onConnected;
  Function()? onDisconnected;
  Function(String error)? onError;

  // Singleton pattern
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  /// Connect to WebSocket
  Future<void> connect({
    required String token,
    required String roomId,
    String baseUrl = 'ws://localhost:8080',
  }) async {
    if (_isConnected) {
      _logger.w('Already connected to WebSocket');
      return;
    }

    try {
      _token = token;
      _roomId = roomId;

      final wsUrl = Uri.parse('$baseUrl/api/v1/ws?room_id=$roomId');
      
      _channel = WebSocketChannel.connect(
        wsUrl,
        protocols: ['Bearer', token],
      );

      // Listen to messages
      _channel!.stream.listen(
        (data) {
          try {
            final json = jsonDecode(data);
            final message = WSMessage.fromJson(json);
            _handleMessage(message);
          } catch (e) {
            _logger.e('Failed to parse WebSocket message: $e');
          }
        },
        onError: (error) {
          _logger.e('WebSocket error: $error');
          _isConnected = false;
          onError?.call(error.toString());
          onDisconnected?.call();
        },
        onDone: () {
          _logger.i('WebSocket connection closed');
          _isConnected = false;
          onDisconnected?.call();
        },
      );

      _isConnected = true;
      onConnected?.call();
      _logger.i('Connected to WebSocket: $wsUrl');
      
      // Start ping/pong
      _startHeartbeat();
    } catch (e) {
      _logger.e('Failed to connect to WebSocket: $e');
      onError?.call(e.toString());
      rethrow;
    }
  }

  /// Handle incoming messages
  void _handleMessage(WSMessage message) {
    _logger.d('Received WebSocket message: ${message.type}');
    
    switch (message.type) {
      case 'pong':
        // Heartbeat response
        break;
      case 'error':
        final error = message.payload['message'] ?? 'Unknown error';
        _logger.e('Server error: $error');
        onError?.call(error);
        break;
      default:
        // Forward to callback
        onMessage?.call(message);
        break;
    }
  }

  /// Send a message
  void send(WSMessage message) {
    if (!_isConnected || _channel == null) {
      _logger.w('Cannot send message: not connected');
      return;
    }

    try {
      final json = jsonEncode(message.toJson());
      _channel!.sink.add(json);
      _logger.d('Sent WebSocket message: ${message.type}');
    } catch (e) {
      _logger.e('Failed to send message: $e');
    }
  }

  /// Start heartbeat (ping/pong)
  void _startHeartbeat() {
    Future.delayed(const Duration(seconds: 30), () {
      if (_isConnected) {
        send(WSMessage(
          type: 'ping',
          payload: {},
          timestamp: DateTime.now(),
        ));
        _startHeartbeat();
      }
    });
  }

  /// Disconnect from WebSocket
  Future<void> disconnect() async {
    if (!_isConnected) {
      return;
    }

    try {
      await _channel?.sink.close();
      _channel = null;
      _isConnected = false;
      _token = null;
      _roomId = null;
      _logger.i('Disconnected from WebSocket');
    } catch (e) {
      _logger.e('Error disconnecting: $e');
    }
  }

  /// Check if connected
  bool get isConnected => _isConnected;

  /// Get current room ID
  String? get roomId => _roomId;
}
