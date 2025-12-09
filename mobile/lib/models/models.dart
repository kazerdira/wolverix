import 'package:uuid/uuid.dart';

// ============================================================================
// USER MODELS
// ============================================================================

class User {
  final String id;
  final String username;
  final String email;
  final String? avatarUrl;
  final String language;
  final bool isOnline;
  final DateTime? lastSeenAt;
  final DateTime createdAt;

  User({
    required this.id,
    required this.username,
    required this.email,
    this.avatarUrl,
    this.language = 'en',
    this.isOnline = false,
    this.lastSeenAt,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      username: json['username'],
      email: json['email'],
      avatarUrl: json['avatar_url'],
      language: json['language'] ?? 'en',
      isOnline: json['is_online'] ?? false,
      lastSeenAt: json['last_seen_at'] != null
          ? DateTime.parse(json['last_seen_at'])
          : null,
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'avatar_url': avatarUrl,
      'language': language,
      'is_online': isOnline,
      'last_seen_at': lastSeenAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class UserStats {
  final String userId;
  final int gamesPlayed;
  final int gamesWon;
  final int gamesLost;
  final int gamesAsWerewolf;
  final int gamesWonAsWerewolf;
  final int gamesAsVillager;
  final int gamesWonAsVillager;
  final double winRate;
  final String? favoriteRole;

  UserStats({
    required this.userId,
    this.gamesPlayed = 0,
    this.gamesWon = 0,
    this.gamesLost = 0,
    this.gamesAsWerewolf = 0,
    this.gamesWonAsWerewolf = 0,
    this.gamesAsVillager = 0,
    this.gamesWonAsVillager = 0,
    this.winRate = 0.0,
    this.favoriteRole,
  });

  factory UserStats.fromJson(Map<String, dynamic> json) {
    return UserStats(
      userId: json['user_id'],
      gamesPlayed: json['games_played'] ?? 0,
      gamesWon: json['games_won'] ?? 0,
      gamesLost: json['games_lost'] ?? 0,
      gamesAsWerewolf: json['games_as_werewolf'] ?? 0,
      gamesWonAsWerewolf: json['games_won_as_werewolf'] ?? 0,
      gamesAsVillager: json['games_as_villager'] ?? 0,
      gamesWonAsVillager: json['games_won_as_villager'] ?? 0,
      winRate: json['win_rate']?.toDouble() ?? 0.0,
      favoriteRole: json['favorite_role'],
    );
  }
}

// ============================================================================
// ROOM MODELS
// ============================================================================

class Room {
  final String id;
  final String roomCode;
  final String name;
  final String hostUserId;
  final RoomStatus status;
  final bool isPrivate;
  final int maxPlayers;
  final int currentPlayers;
  final String language;
  final RoomConfig config;
  final String? agoraChannelName;
  final String? agoraAppId;
  final DateTime createdAt;
  final DateTime? lastActivityAt;
  final bool? timeoutWarningSent;
  final int? timeoutExtendedCount;
  final User? host;
  final List<RoomPlayer> players;

  Room({
    required this.id,
    required this.roomCode,
    required this.name,
    required this.hostUserId,
    this.status = RoomStatus.waiting,
    this.isPrivate = false,
    this.maxPlayers = 12,
    this.currentPlayers = 0,
    this.language = 'en',
    required this.config,
    this.agoraChannelName,
    this.agoraAppId,
    required this.createdAt,
    this.lastActivityAt,
    this.timeoutWarningSent,
    this.timeoutExtendedCount,
    this.host,
    this.players = const [],
  });

  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      id: json['id'],
      roomCode: json['room_code'],
      name: json['name'],
      hostUserId: json['host_user_id'],
      status: RoomStatus.fromString(json['status']),
      isPrivate: json['is_private'] ?? false,
      maxPlayers: json['max_players'] ?? 12,
      currentPlayers: json['current_players'] ?? 0,
      language: json['language'] ?? 'en',
      config: json['config'] != null
          ? RoomConfig.fromJson(json['config'])
          : RoomConfig(),
      agoraChannelName: json['agora_channel_name'],
      agoraAppId: json['agora_app_id'],
      createdAt: DateTime.parse(json['created_at']),
      lastActivityAt: json['last_activity_at'] != null
          ? DateTime.parse(json['last_activity_at'])
          : null,
      timeoutWarningSent: json['timeout_warning_sent'],
      timeoutExtendedCount: json['timeout_extended_count'],
      host: json['host'] != null ? User.fromJson(json['host']) : null,
      players: (json['players'] as List<dynamic>?)
              ?.map((p) => RoomPlayer.fromJson(p))
              .toList() ??
          [],
    );
  }

  bool get isFull => currentPlayers >= maxPlayers;
}

enum RoomStatus {
  waiting,
  starting,
  playing,
  paused,
  finished,
  abandoned;

  static RoomStatus fromString(String value) {
    return RoomStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => RoomStatus.waiting,
    );
  }
}

class RoomConfig {
  final int dayPhaseSeconds;
  final int nightPhaseSeconds;
  final int votingSeconds;
  final bool allowMayorReveal;
  final bool enableVoiceChat;
  final Map<String, int> roleDistribution;

  RoomConfig({
    this.dayPhaseSeconds = 120,
    this.nightPhaseSeconds = 60,
    this.votingSeconds = 60,
    this.allowMayorReveal = true,
    this.enableVoiceChat = true,
    this.roleDistribution = const {},
  });

  factory RoomConfig.fromJson(Map<String, dynamic> json) {
    return RoomConfig(
      dayPhaseSeconds: json['day_phase_seconds'] ?? 120,
      nightPhaseSeconds: json['night_phase_seconds'] ?? 60,
      votingSeconds: json['voting_seconds'] ?? 60,
      allowMayorReveal: json['allow_mayor_reveal'] ?? true,
      enableVoiceChat: json['enable_voice_chat'] ?? true,
      roleDistribution: Map<String, int>.from(json['role_distribution'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'day_phase_seconds': dayPhaseSeconds,
      'night_phase_seconds': nightPhaseSeconds,
      'voting_seconds': votingSeconds,
      'allow_mayor_reveal': allowMayorReveal,
      'enable_voice_chat': enableVoiceChat,
      'role_distribution': roleDistribution,
    };
  }
}

class RoomPlayer {
  final String id;
  final String roomId;
  final String userId;
  final bool isReady;
  final bool isHost;
  final int seatPosition;
  final DateTime joinedAt;
  final User? user;

  RoomPlayer({
    required this.id,
    required this.roomId,
    required this.userId,
    this.isReady = false,
    this.isHost = false,
    this.seatPosition = 0,
    required this.joinedAt,
    this.user,
  });

  factory RoomPlayer.fromJson(Map<String, dynamic> json) {
    return RoomPlayer(
      id: json['id'],
      roomId: json['room_id'] ?? '',
      userId: json['user_id'],
      isReady: json['is_ready'] ?? false,
      isHost: json['is_host'] ?? false,
      seatPosition: json['seat_position'] ?? 0,
      joinedAt: json['joined_at'] != null
          ? DateTime.parse(json['joined_at'])
          : DateTime.now(),
      user: json['user'] != null ? User.fromJson(json['user']) : null,
    );
  }
}

// ============================================================================
// GAME MODELS
// ============================================================================

class GameSession {
  final String id;
  final String roomId;
  final GamePhase currentPhase;
  final int phaseNumber;
  final int dayNumber;
  final DateTime? phaseEndTime;
  final String? winner;
  final GameState state;
  final DateTime startedAt;
  final List<GamePlayer> players;

  GameSession({
    required this.id,
    required this.roomId,
    this.currentPhase = GamePhase.night0,
    this.phaseNumber = 0,
    this.dayNumber = 0,
    this.phaseEndTime,
    this.winner,
    required this.state,
    required this.startedAt,
    this.players = const [],
  });

  factory GameSession.fromJson(Map<String, dynamic> json) {
    return GameSession(
      id: json['id'],
      roomId: json['room_id'],
      currentPhase: GamePhase.fromString(json['current_phase']),
      phaseNumber: json['phase_number'] ?? 0,
      dayNumber: json['day_number'] ?? 0,
      phaseEndTime: json['phase_ends_at'] != null
          ? DateTime.parse(json['phase_ends_at'])
          : null,
      winner: json['winning_team'],
      state: GameState.fromJson(json['state'] ?? {}),
      startedAt: DateTime.parse(json['created_at']),
      players: (json['players'] as List<dynamic>?)
              ?.map((p) => GamePlayer.fromJson(p))
              .toList() ??
          [],
    );
  }

  bool get isGameOver => winner != null;

  List<GamePlayer> get alivePlayers => players.where((p) => p.isAlive).toList();

  List<GamePlayer> get deadPlayers => players.where((p) => !p.isAlive).toList();
}

enum GamePhase {
  night0,
  cupidPhase,
  werewolfPhase,
  seerPhase,
  witchPhase,
  bodyguardPhase,
  dayDiscussion,
  dayVoting,
  defensePhase,
  finalVote,
  hunterPhase,
  mayorReveal,
  gameOver;

  static GamePhase fromString(String value) {
    final mapping = {
      'night_0': GamePhase.night0,
      'cupid_phase': GamePhase.cupidPhase,
      'werewolf_phase': GamePhase.werewolfPhase,
      'seer_phase': GamePhase.seerPhase,
      'witch_phase': GamePhase.witchPhase,
      'bodyguard_phase': GamePhase.bodyguardPhase,
      'day_discussion': GamePhase.dayDiscussion,
      'day_voting': GamePhase.dayVoting,
      'defense_phase': GamePhase.defensePhase,
      'final_vote': GamePhase.finalVote,
      'hunter_phase': GamePhase.hunterPhase,
      'mayor_reveal': GamePhase.mayorReveal,
      'game_over': GamePhase.gameOver,
    };
    return mapping[value] ?? GamePhase.night0;
  }

  String get displayName {
    switch (this) {
      case GamePhase.night0:
        return 'Night Falls';
      case GamePhase.cupidPhase:
        return 'Cupid\'s Turn';
      case GamePhase.werewolfPhase:
        return 'Werewolves Hunt';
      case GamePhase.seerPhase:
        return 'Seer\'s Vision';
      case GamePhase.witchPhase:
        return 'Witch\'s Choice';
      case GamePhase.bodyguardPhase:
        return 'Bodyguard Protects';
      case GamePhase.dayDiscussion:
        return 'Village Discussion';
      case GamePhase.dayVoting:
        return 'Vote for Suspect';
      case GamePhase.defensePhase:
        return 'Defense Speech';
      case GamePhase.finalVote:
        return 'Final Judgment';
      case GamePhase.hunterPhase:
        return 'Hunter\'s Revenge';
      case GamePhase.mayorReveal:
        return 'Mayor Election';
      case GamePhase.gameOver:
        return 'Game Over';
    }
  }

  bool get isNightPhase {
    return [
      GamePhase.night0,
      GamePhase.cupidPhase,
      GamePhase.werewolfPhase,
      GamePhase.seerPhase,
      GamePhase.witchPhase,
      GamePhase.bodyguardPhase,
    ].contains(this);
  }
}

class GameState {
  final String? lastKilledPlayer;
  final String? lastLynchedPlayer;
  final Map<String, int> werewolfVotes;
  final Map<String, int> lynchVotes;
  final String? currentVoteTarget;
  final Map<String, bool> actionsCompleted;
  final Map<String, int> actionsRemaining;
  final String? protectedPlayer;
  final String? poisonedPlayer;
  final String? healedPlayer;
  final Map<String, String> revealedRoles;
  final List<String> nightKills;
  final bool pendingHunterShot;
  final String? hunterPlayerId;

  GameState({
    this.lastKilledPlayer,
    this.lastLynchedPlayer,
    this.werewolfVotes = const {},
    this.lynchVotes = const {},
    this.currentVoteTarget,
    this.actionsCompleted = const {},
    this.actionsRemaining = const {},
    this.protectedPlayer,
    this.poisonedPlayer,
    this.healedPlayer,
    this.revealedRoles = const {},
    this.nightKills = const [],
    this.pendingHunterShot = false,
    this.hunterPlayerId,
  });

  factory GameState.fromJson(Map<String, dynamic> json) {
    return GameState(
      lastKilledPlayer: json['last_killed_player'],
      lastLynchedPlayer: json['last_lynched_player'],
      werewolfVotes: (json['werewolf_votes'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as int)) ??
          {},
      lynchVotes: (json['lynch_votes'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as int)) ??
          {},
      currentVoteTarget: json['current_vote_target'],
      actionsCompleted: (json['actions_completed'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as bool)) ??
          {},
      actionsRemaining: (json['actions_remaining'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as int)) ??
          {},
      protectedPlayer: json['protected_player'],
      poisonedPlayer: json['poisoned_player'],
      healedPlayer: json['healed_player'],
      revealedRoles: (json['revealed_roles'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as String)) ??
          {},
      nightKills: (json['night_kills'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      pendingHunterShot: json['pending_hunter_shot'] ?? false,
      hunterPlayerId: json['hunter_player_id'],
    );
  }
}

class GamePlayer {
  final String id;
  final String sessionId;
  final String userId;
  final GameRole? role;
  final GameTeam? team;
  final bool isAlive;
  final int? diedAtPhase;
  final String? deathReason;
  final bool hasUsedHeal;
  final bool hasUsedPoison;
  final bool hasShot;
  final bool isProtected;
  final bool isMayor;
  final String? loverId;
  final String? currentVoiceChannel;
  final int seatPosition;
  final User? user;

  GamePlayer({
    required this.id,
    required this.sessionId,
    required this.userId,
    this.role,
    this.team,
    this.isAlive = true,
    this.diedAtPhase,
    this.deathReason,
    this.hasUsedHeal = false,
    this.hasUsedPoison = false,
    this.hasShot = false,
    this.isProtected = false,
    this.isMayor = false,
    this.loverId,
    this.currentVoiceChannel,
    this.seatPosition = 0,
    this.user,
  });

  factory GamePlayer.fromJson(Map<String, dynamic> json) {
    final roleState = json['role_state'] as Map<String, dynamic>? ?? {};

    return GamePlayer(
      id: json['id'],
      sessionId: json['session_id'] ?? '',
      userId: json['user_id'],
      role: json['role'] != null ? GameRole.fromString(json['role']) : null,
      team: json['team'] != null ? GameTeam.fromString(json['team']) : null,
      isAlive: json['is_alive'] ?? true,
      diedAtPhase: json['died_at_phase'],
      deathReason: json['death_reason'],
      hasUsedHeal: roleState['heal_used'] ?? false,
      hasUsedPoison: roleState['poison_used'] ?? false,
      hasShot: roleState['has_shot'] ?? false,
      isProtected: false, // This is from game state, not player state
      isMayor: roleState['is_revealed'] ?? false,
      loverId: json['lover_id'],
      currentVoiceChannel: json['current_voice_channel'],
      seatPosition: json['seat_position'] ?? 0,
      user: json['user'] != null ? User.fromJson(json['user']) : null,
    );
  }

  String get displayName => user?.username ?? 'Player ${seatPosition + 1}';
}

enum GameRole {
  werewolf,
  villager,
  seer,
  witch,
  hunter,
  cupid,
  bodyguard,
  mayor,
  medium,
  tanner,
  littleGirl;

  static GameRole fromString(String value) {
    final mapping = {
      'werewolf': GameRole.werewolf,
      'villager': GameRole.villager,
      'seer': GameRole.seer,
      'witch': GameRole.witch,
      'hunter': GameRole.hunter,
      'cupid': GameRole.cupid,
      'bodyguard': GameRole.bodyguard,
      'mayor': GameRole.mayor,
      'medium': GameRole.medium,
      'tanner': GameRole.tanner,
      'little_girl': GameRole.littleGirl,
    };
    return mapping[value] ?? GameRole.villager;
  }

  String get displayName {
    switch (this) {
      case GameRole.werewolf:
        return 'Werewolf';
      case GameRole.villager:
        return 'Villager';
      case GameRole.seer:
        return 'Seer';
      case GameRole.witch:
        return 'Witch';
      case GameRole.hunter:
        return 'Hunter';
      case GameRole.cupid:
        return 'Cupid';
      case GameRole.bodyguard:
        return 'Bodyguard';
      case GameRole.mayor:
        return 'Mayor';
      case GameRole.medium:
        return 'Medium';
      case GameRole.tanner:
        return 'Tanner';
      case GameRole.littleGirl:
        return 'Little Girl';
    }
  }

  String get description {
    switch (this) {
      case GameRole.werewolf:
        return 'Hunt villagers at night. Know your fellow wolves.';
      case GameRole.villager:
        return 'Find and eliminate the werewolves to survive.';
      case GameRole.seer:
        return 'Divine one player each night to learn their true nature.';
      case GameRole.witch:
        return 'Use your heal potion to save, or poison to kill. Once each.';
      case GameRole.hunter:
        return 'If killed, shoot one player to take them down with you.';
      case GameRole.cupid:
        return 'Choose two lovers on night one. They share their fate.';
      case GameRole.bodyguard:
        return 'Protect one player each night from werewolf attacks.';
      case GameRole.mayor:
        return 'Can reveal for a double vote. Succession passes on death.';
      case GameRole.medium:
        return 'Speak with the dead to gather information.';
      case GameRole.tanner:
        return 'Win alone if lynched by the village.';
      case GameRole.littleGirl:
        return 'Peek at werewolves at night, but risk being caught.';
    }
  }

  String get iconAsset {
    return 'assets/icons/roles/${name}.svg';
  }
}

enum GameTeam {
  werewolves,
  villagers,
  neutral;

  static GameTeam fromString(String value) {
    return GameTeam.values.firstWhere(
      (e) => e.name == value,
      orElse: () => GameTeam.villagers,
    );
  }
}

// ============================================================================
// GAME ACTION MODELS
// ============================================================================

class GameAction {
  final String id;
  final String sessionId;
  final String playerId;
  final String actionType;
  final String? targetPlayerId;
  final String? secondaryTargetId;
  final int phaseNumber;
  final Map<String, dynamic> actionData;
  final DateTime createdAt;

  GameAction({
    required this.id,
    required this.sessionId,
    required this.playerId,
    required this.actionType,
    this.targetPlayerId,
    this.secondaryTargetId,
    required this.phaseNumber,
    this.actionData = const {},
    required this.createdAt,
  });

  factory GameAction.fromJson(Map<String, dynamic> json) {
    return GameAction(
      id: json['id'],
      sessionId: json['session_id'],
      playerId: json['player_id'],
      actionType: json['action_type'],
      targetPlayerId: json['target_player_id'],
      secondaryTargetId: json['secondary_target_id'],
      phaseNumber: json['phase_number'],
      actionData: Map<String, dynamic>.from(json['action_data'] ?? {}),
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class GameEvent {
  final String id;
  final String sessionId;
  final int phaseNumber;
  final String eventType;
  final Map<String, dynamic> eventData;
  final bool isPublic;
  final DateTime createdAt;

  GameEvent({
    required this.id,
    required this.sessionId,
    required this.phaseNumber,
    required this.eventType,
    this.eventData = const {},
    this.isPublic = false,
    required this.createdAt,
  });

  factory GameEvent.fromJson(Map<String, dynamic> json) {
    return GameEvent(
      id: json['id'],
      sessionId: json['session_id'],
      phaseNumber: json['phase_number'],
      eventType: json['event_type'],
      eventData: Map<String, dynamic>.from(json['event_data'] ?? {}),
      isPublic: json['is_public'] ?? false,
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

// ============================================================================
// WEBSOCKET MESSAGE MODELS
// ============================================================================

class WSMessage {
  final String type;
  final Map<String, dynamic> payload;

  WSMessage({required this.type, required this.payload});

  factory WSMessage.fromJson(Map<String, dynamic> json) {
    return WSMessage(
      type: json['type'],
      payload: Map<String, dynamic>.from(json['payload'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() {
    return {'type': type, 'payload': payload};
  }
}

// ============================================================================
// REQUEST/RESPONSE MODELS
// ============================================================================

class AuthResponse {
  final User user;
  final String accessToken;
  final String refreshToken;

  AuthResponse({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      user: User.fromJson(json['user']),
      accessToken: json['access_token'],
      refreshToken: json['refresh_token'],
    );
  }
}

class AgoraToken {
  final String token;
  final String channelName;
  final int uid;
  final int expiresAt;

  AgoraToken({
    required this.token,
    required this.channelName,
    required this.uid,
    required this.expiresAt,
  });

  factory AgoraToken.fromJson(Map<String, dynamic> json) {
    return AgoraToken(
      token: json['token'],
      channelName: json['channel_name'],
      uid: json['uid'],
      expiresAt: json['expires_at'],
    );
  }
}
