import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:get/get.dart' as getx;
import 'package:permission_handler/permission_handler.dart';

import '../models/models.dart';
import 'api_service.dart';

class AgoraService extends getx.GetxService {
  RtcEngine? _engine;
  final ApiService _api = getx.Get.find<ApiService>();

  String? _currentChannel;
  String? _appId;
  int? _localUid;
  bool _isMuted = false;

  final _remoteUsersController = StreamController<List<int>>.broadcast();
  Stream<List<int>> get remoteUsersStream => _remoteUsersController.stream;

  final _connectionStateController =
      StreamController<RtcConnection>.broadcast();
  Stream<RtcConnection> get connectionStateStream =>
      _connectionStateController.stream;

  final List<int> _remoteUsers = [];
  List<int> get remoteUsers => List.unmodifiable(_remoteUsers);

  bool get isInitialized => _engine != null;
  bool get isMuted => _isMuted;
  String? get currentChannel => _currentChannel;

  Future<bool> initialize(String appId) async {
    if (_engine != null) return true;

    _appId = appId;

    try {
      // Request permissions
      final micPermission = await Permission.microphone.request();
      if (!micPermission.isGranted) {
        print('Microphone permission denied');
        return false;
      }

      // Create RTC engine
      _engine = createAgoraRtcEngine();
      await _engine!.initialize(
        RtcEngineContext(
          appId: appId,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );

      // Register event handlers
      _engine!.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (connection, elapsed) {
            print('Joined channel: ${connection.channelId}');
            _localUid = connection.localUid;
          },
          onUserJoined: (connection, remoteUid, elapsed) {
            print('Remote user joined: $remoteUid');
            if (!_remoteUsers.contains(remoteUid)) {
              _remoteUsers.add(remoteUid);
              _remoteUsersController.add(_remoteUsers);
            }
          },
          onUserOffline: (connection, remoteUid, reason) {
            print('Remote user left: $remoteUid');
            _remoteUsers.remove(remoteUid);
            _remoteUsersController.add(_remoteUsers);
          },
          onConnectionStateChanged: (connection, state, reason) {
            print('Connection state: $state, reason: $reason');
            _connectionStateController.add(connection);
          },
          onError: (err, msg) {
            print('Agora error: $err - $msg');
          },
          onAudioVolumeIndication:
              (connection, speakers, speakerNumber, totalVolume) {
                // Can be used to show who is speaking
              },
        ),
      );

      // Configure audio
      await _engine!.enableAudio();
      await _engine!.setAudioProfile(
        profile: AudioProfileType.audioProfileMusicHighQuality,
        scenario: AudioScenarioType.audioScenarioChatroom,
      );

      // Enable volume indicator
      await _engine!.enableAudioVolumeIndication(
        interval: 200,
        smooth: 3,
        reportVad: true,
      );

      return true;
    } catch (e) {
      print('Agora initialization error: $e');
      return false;
    }
  }

  Future<bool> joinChannel(String channelName, {int uid = 0}) async {
    if (_engine == null || _appId == null) {
      print('Agora not initialized');
      return false;
    }

    try {
      // Get token from server
      final tokenResponse = await _api.getAgoraToken(channelName, uid);

      _currentChannel = channelName;
      _remoteUsers.clear();

      await _engine!.joinChannel(
        token: tokenResponse.token,
        channelId: channelName,
        uid: uid,
        options: const ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          channelProfile: ChannelProfileType.channelProfileCommunication,
          autoSubscribeAudio: true,
          publishMicrophoneTrack: true,
        ),
      );

      return true;
    } catch (e) {
      print('Join channel error: $e');
      return false;
    }
  }

  Future<void> leaveChannel() async {
    if (_engine == null) return;

    try {
      await _engine!.leaveChannel();
      _currentChannel = null;
      _remoteUsers.clear();
      _remoteUsersController.add(_remoteUsers);
    } catch (e) {
      print('Leave channel error: $e');
    }
  }

  Future<void> toggleMute() async {
    if (_engine == null) return;

    _isMuted = !_isMuted;
    await _engine!.muteLocalAudioStream(_isMuted);
  }

  Future<void> setMute(bool muted) async {
    if (_engine == null) return;

    _isMuted = muted;
    await _engine!.muteLocalAudioStream(_isMuted);
  }

  Future<void> muteRemoteUser(int uid, bool muted) async {
    if (_engine == null) return;

    await _engine!.muteRemoteAudioStream(uid: uid, mute: muted);
  }

  Future<void> setVolume(int volume) async {
    if (_engine == null) return;

    await _engine!.adjustRecordingSignalVolume(volume);
    await _engine!.adjustPlaybackSignalVolume(volume);
  }

  Future<void> enableSpeakerphone(bool enabled) async {
    if (_engine == null) return;

    await _engine!.setEnableSpeakerphone(enabled);
  }

  Future<void> switchChannel(String newChannelName) async {
    await leaveChannel();
    await Future.delayed(const Duration(milliseconds: 500));
    await joinChannel(newChannelName);
  }

  Future<void> dispose() async {
    if (_engine != null) {
      await leaveChannel();
      await _engine!.release();
      _engine = null;
    }
    _remoteUsersController.close();
    _connectionStateController.close();
  }

  @override
  void onClose() {
    dispose();
    super.onClose();
  }
}
