import 'dart:async';
import 'package:get/get.dart';

import '../models/models.dart';
import '../services/agora_service.dart';
import '../services/websocket_service.dart';

class VoiceProvider extends GetxController {
  final AgoraService _agora = Get.find<AgoraService>();
  final WebSocketService _ws = Get.find<WebSocketService>();

  final RxBool isInitialized = false.obs;
  final RxBool isInChannel = false.obs;
  final RxBool isMuted = false.obs;
  final RxBool isSpeakerOn = true.obs;
  final RxList<int> remoteUsers = <int>[].obs;
  final RxMap<int, bool> speakingUsers = <int, bool>{}.obs;
  final RxString currentChannel = ''.obs;

  StreamSubscription? _remoteUsersSubscription;

  @override
  void onInit() {
    super.onInit();
    _remoteUsersSubscription = _agora.remoteUsersStream.listen((users) {
      remoteUsers.value = users;
    });
  }

  Future<bool> initialize(String appId) async {
    final result = await _agora.initialize(appId);
    isInitialized.value = result;
    return result;
  }

  Future<bool> joinChannel(String channelName, {int uid = 0}) async {
    if (!isInitialized.value) {
      print('Agora not initialized');
      return false;
    }

    final result = await _agora.joinChannel(channelName, uid: uid);
    if (result) {
      isInChannel.value = true;
      currentChannel.value = channelName;
    }
    return result;
  }

  Future<void> leaveChannel() async {
    await _agora.leaveChannel();
    isInChannel.value = false;
    currentChannel.value = '';
    remoteUsers.clear();
    speakingUsers.clear();
  }

  Future<void> toggleMute() async {
    await _agora.toggleMute();
    isMuted.value = _agora.isMuted;

    // Notify others via WebSocket
    _ws.send('voice_state', {'muted': isMuted.value});
  }

  Future<void> setMute(bool muted) async {
    await _agora.setMute(muted);
    isMuted.value = muted;

    _ws.send('voice_state', {'muted': muted});
  }

  Future<void> toggleSpeaker() async {
    isSpeakerOn.value = !isSpeakerOn.value;
    await _agora.enableSpeakerphone(isSpeakerOn.value);
  }

  Future<void> muteRemoteUser(int uid, bool muted) async {
    await _agora.muteRemoteUser(uid, muted);
  }

  Future<void> switchChannel(String newChannelName) async {
    await _agora.switchChannel(newChannelName);
    currentChannel.value = newChannelName;
  }

  // For game phases, auto-mute based on role/phase
  void handlePhaseChange(GamePhase phase, GameRole? myRole, bool isAlive) {
    // Dead players should be muted except in dead channel
    if (!isAlive) {
      setMute(true);
      return;
    }

    // Night phases - only certain roles can speak
    if (phase.isNightPhase) {
      switch (phase) {
        case GamePhase.werewolfPhase:
          // Only werewolves can speak during werewolf phase
          setMute(myRole != GameRole.werewolf);
          break;
        default:
          // Other night phases - everyone muted
          setMute(true);
      }
    } else {
      // Day phases - everyone can speak
      setMute(false);
    }
  }

  @override
  void onClose() {
    _remoteUsersSubscription?.cancel();
    _agora.dispose();
    super.onClose();
  }
}
