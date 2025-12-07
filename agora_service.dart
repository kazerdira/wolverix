import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:logger/logger.dart';

class AgoraService {
  final Logger _logger = Logger();
  RtcEngine? _engine;
  bool _isInitialized = false;
  bool _isInChannel = false;
  
  String? _currentChannelName;
  int? _currentUid;
  
  // Callbacks
  Function(int uid, bool isSpeaking)? onUserSpeaking;
  Function(int uid)? onUserJoined;
  Function(int uid)? onUserLeft;
  Function(String error)? onError;
  
  // Singleton pattern
  static final AgoraService _instance = AgoraService._internal();
  factory AgoraService() => _instance;
  AgoraService._internal();

  /// Initialize Agora Engine
  Future<void> initialize(String appId) async {
    if (_isInitialized) {
      _logger.i('Agora already initialized');
      return;
    }

    try {
      // Request microphone permission
      if (await Permission.microphone.request().isDenied) {
        throw Exception('Microphone permission denied');
      }

      // Create Agora engine
      _engine = createAgoraRtcEngine();
      
      await _engine!.initialize(RtcEngineContext(
        appId: appId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ));

      // Enable audio
      await _engine!.enableAudio();
      
      // Set audio profile - high quality voice
      await _engine!.setAudioProfile(
        profile: AudioProfileType.audioProfileMusicHighQuality,
        scenario: AudioScenarioType.audioScenarioChatroom,
      );

      // Register event handlers
      _engine!.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
            _logger.i('Join channel success: ${connection.channelId}');
            _isInChannel = true;
          },
          onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
            _logger.i('User joined: $remoteUid');
            onUserJoined?.call(remoteUid);
          },
          onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
            _logger.i('User left: $remoteUid');
            onUserLeft?.call(remoteUid);
          },
          onLeaveChannel: (RtcConnection connection, RtcStats stats) {
            _logger.i('Left channel: ${connection.channelId}');
            _isInChannel = false;
          },
          onError: (ErrorCodeType err, String msg) {
            _logger.e('Agora error: $err - $msg');
            onError?.call('Agora error: $msg');
          },
          onAudioVolumeIndication: (RtcConnection connection, List<AudioVolumeInfo> speakers, int speakerNumber, int totalVolume) {
            for (var speaker in speakers) {
              bool isSpeaking = speaker.volume! > 10; // Threshold for speaking detection
              onUserSpeaking?.call(speaker.uid!, isSpeaking);
            }
          },
          onConnectionStateChanged: (RtcConnection connection, ConnectionStateType state, ConnectionChangedReasonType reason) {
            _logger.i('Connection state changed: $state, reason: $reason');
            
            if (state == ConnectionStateType.connectionStateFailed || 
                state == ConnectionStateType.connectionStateDisconnected) {
              onError?.call('Connection failed or disconnected');
            }
          },
        ),
      );

      // Enable audio volume indication
      await _engine!.enableAudioVolumeIndication(
        interval: 200, // Update every 200ms
        smooth: 3,
        reportVad: true,
      );

      _isInitialized = true;
      _logger.i('Agora initialized successfully');
    } catch (e) {
      _logger.e('Failed to initialize Agora: $e');
      rethrow;
    }
  }

  /// Join a voice channel
  Future<void> joinChannel({
    required String channelName,
    required String token,
    required int uid,
  }) async {
    if (!_isInitialized) {
      throw Exception('Agora not initialized');
    }

    if (_isInChannel) {
      await leaveChannel();
    }

    try {
      _currentChannelName = channelName;
      _currentUid = uid;

      await _engine!.joinChannel(
        token: token,
        channelId: channelName,
        uid: uid,
        options: const ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileCommunication,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          autoSubscribeAudio: true,
          publishMicrophoneTrack: true,
        ),
      );

      _logger.i('Joining channel: $channelName with UID: $uid');
    } catch (e) {
      _logger.e('Failed to join channel: $e');
      rethrow;
    }
  }

  /// Leave current channel
  Future<void> leaveChannel() async {
    if (!_isInChannel || _engine == null) {
      return;
    }

    try {
      await _engine!.leaveChannel();
      _currentChannelName = null;
      _currentUid = null;
      _isInChannel = false;
      _logger.i('Left channel successfully');
    } catch (e) {
      _logger.e('Failed to leave channel: $e');
      rethrow;
    }
  }

  /// Mute/unmute local microphone
  Future<void> muteLocalAudio(bool muted) async {
    if (_engine == null) return;
    
    try {
      await _engine!.muteLocalAudioStream(muted);
      _logger.i('Local audio ${muted ? 'muted' : 'unmuted'}');
    } catch (e) {
      _logger.e('Failed to mute/unmute: $e');
    }
  }

  /// Mute/unmute remote user
  Future<void> muteRemoteAudio(int uid, bool muted) async {
    if (_engine == null) return;
    
    try {
      await _engine!.muteRemoteAudioStream(uid: uid, mute: muted);
      _logger.i('Remote user $uid audio ${muted ? 'muted' : 'unmuted'}');
    } catch (e) {
      _logger.e('Failed to mute/unmute remote: $e');
    }
  }

  /// Set audio volume
  Future<void> setVolume(int volume) async {
    if (_engine == null) return;
    
    try {
      await _engine!.adjustRecordingSignalVolume(volume);
      _logger.i('Volume set to: $volume');
    } catch (e) {
      _logger.e('Failed to set volume: $e');
    }
  }

  /// Enable/disable speaker
  Future<void> setSpeakerEnabled(bool enabled) async {
    if (_engine == null) return;
    
    try {
      await _engine!.setEnableSpeakerphone(enabled);
      _logger.i('Speaker ${enabled ? 'enabled' : 'disabled'}');
    } catch (e) {
      _logger.e('Failed to toggle speaker: $e');
    }
  }

  /// Switch to a different channel (for werewolf/dead channels)
  Future<void> switchChannel({
    required String newChannelName,
    required String token,
  }) async {
    if (!_isInitialized || _currentUid == null) {
      throw Exception('Cannot switch channel: not initialized');
    }

    try {
      // Leave current channel
      await leaveChannel();
      
      // Join new channel with same UID
      await joinChannel(
        channelName: newChannelName,
        token: token,
        uid: _currentUid!,
      );
      
      _logger.i('Switched to channel: $newChannelName');
    } catch (e) {
      _logger.e('Failed to switch channel: $e');
      rethrow;
    }
  }

  /// Get current channel name
  String? get currentChannel => _currentChannelName;

  /// Check if in channel
  bool get isInChannel => _isInChannel;

  /// Dispose and clean up
  Future<void> dispose() async {
    if (_isInChannel) {
      await leaveChannel();
    }

    if (_engine != null) {
      await _engine!.release();
      _engine = null;
    }

    _isInitialized = false;
    _logger.i('Agora service disposed');
  }
}
