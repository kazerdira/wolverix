// Simplified models for Flutter app
// Full models match backend structure

class User {
  final String id;
  final String username;
  final String email;
  final String? avatarUrl;
  final String? displayName;
  final String language;
  final int reputationScore;
  final bool isBanned;
  final DateTime createdAt;

  User({
    required this.id,
    required this.username,
    required this.email,
    this.avatarUrl,
    this.displayName,
    required this.language,
    required this.reputationScore,
    required this.isBanned,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      username: json['username'],
      email: json['email'],
      avatarUrl: json['avatar_url'],
      displayName: json['display_name'],
      language: json['language'] ?? 'en',
      reputationScore: json['reputation_score'] ?? 100,
      isBanned: json['is_banned'] ?? false,
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class UserStats {
  final int totalGames;
  final int totalWins;
  final int totalLosses;
  final int currentStreak;
  final int bestStreak;
  final int mvpCount;

  UserStats({
    required this.totalGames,
    required this.totalWins,
    required this.totalLosses,
    required this.currentStreak,
    required this.bestStreak,
    required this.mvpCount,
  });

  factory UserStats.fromJson(Map<String, dynamic> json) {
    return UserStats(
      totalGames: json['total_games'] ?? 0,
      totalWins: json['total_wins'] ?? 0,
      totalLosses: json['total_losses'] ?? 0,
      currentStreak: json['current_streak'] ?? 0,
      bestStreak: json['best_streak'] ?? 0,
      mvpCount: json['mvp_count'] ?? 0,
    );
  }
}

class AuthResponse {
  final String token;
  final String refreshToken;
  final User user;

  AuthResponse({
    required this.token,
    required this.refreshToken,
    required this.user,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      token: json['token'],
      refreshToken: json['refresh_token'],
      user: User.fromJson(json['user']),
    );
  }
}

class RoomConfig {
  final List<String> enabledRoles;
  final int werewolfCount;
  final int dayPhaseSeconds;
  final int nightPhaseSeconds;
  final int votingSeconds;
  final bool allowSpectators;
  final bool requireReady;

  RoomConfig({
    required this.enabledRoles,
    this.werewolfCount = 0,
    this.dayPhaseSeconds = 300,
    this.nightPhaseSeconds = 120,
    this.votingSeconds = 60,
    this.allowSpectators = true,
    this.requireReady = true,
  });

  Map<String, dynamic> toJson() {
    return {
      'enabled_roles': enabledRoles,
      'werewolf_count': werewolfCount,
      'day_phase_seconds': dayPhaseSeconds,
      'night_phase_seconds': nightPhaseSeconds,
      'voting_seconds': votingSeconds,
      'allow_spectators': allowSpectators,
      'require_ready': requireReady,
    };
  }

  factory RoomConfig.fromJson(Map<String, dynamic> json) {
    return RoomConfig(
      enabledRoles: List<String>.from(json['enabled_roles'] ?? []),
      werewolfCount: json['werewolf_count'] ?? 0,
      dayPhaseSeconds: json['day_phase_seconds'] ?? 300,
      nightPhaseSeconds: json['night_phase_seconds'] ?? 120,
      votingSeconds: json['voting_seconds'] ?? 60,
      allowSpectators: json['allow_spectators'] ?? true,
      requireReady: json['require_ready'] ?? true,
    );
  }
}

class Room {
  final String id;
  final String roomCode;
  final String name;
  final String hostUserId;
  final String status;
  final bool isPrivate;
  final int maxPlayers;
  final int currentPlayers;
  final String language;
  final RoomConfig config;
  final String agoraChannelName;
  final String? agoraAppId;
  final DateTime createdAt;
  final User? host;
  final List<RoomPlayer>? players;

  Room({
    required this.id,
    required this.roomCode,
    required this.name,
    required this.hostUserId,
    required this.status,
    required this.isPrivate,
    required this.maxPlayers,
    required this.currentPlayers,
    required this.language,
    required this.config,
    required this.agoraChannelName,
    this.agoraAppId,
    required this.createdAt,
    this.host,
    this.players,
  });

  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      id: json['id'],
      roomCode: json['room_code'],
      name: json['name'],
      hostUserId: json['host_user_id'],
      status: json['status'],
      isPrivate: json['is_private'] ?? false,
      maxPlayers: json['max_players'],
      currentPlayers: json['current_players'],
      language: json['language'] ?? 'en',
      config: RoomConfig.fromJson(json['config'] ?? {}),
      agoraChannelName: json['agora_channel_name'],
      agoraAppId: json['agora_app_id'],
      createdAt: DateTime.parse(json['created_at']),
      host: json['host'] != null ? User.fromJson(json['host']) : null,
      players: json['players'] != null 
        ? (json['players'] as List).map((p) => RoomPlayer.fromJson(p)).toList()
        : null,
    );
  }
}

class RoomPlayer {
  final String id;
  final String roomId;
  final String userId;
  final bool isReady;
  final bool isHost;
  final int? seatPosition;
  final DateTime joinedAt;
  final User? user;

  RoomPlayer({
    required this.id,
    required this.roomId,
    required this.userId,
    required this.isReady,
    required this.isHost,
    this.seatPosition,
    required this.joinedAt,
    this.user,
  });

  factory RoomPlayer.fromJson(Map<String, dynamic> json) {
    return RoomPlayer(
      id: json['id'],
      roomId: json['room_id'],
      userId: json['user_id'],
      isReady: json['is_ready'] ?? false,
      isHost: json['is_host'] ?? false,
      seatPosition: json['seat_position'],
      joinedAt: DateTime.parse(json['joined_at']),
      user: json['user'] != null ? User.fromJson(json['user']) : null,
    );
  }
}

class GameSession {
  final String id;
  final String roomId;
  final String status;
  final String currentPhase;
  final int phaseNumber;
  final int dayNumber;
  final DateTime phaseStartedAt;
  final DateTime? phaseEndsAt;
  final int werewolvesAlive;
  final int villagersAlive;
  final String? winningTeam;
  final List<GamePlayer>? players;

  GameSession({
    required this.id,
    required this.roomId,
    required this.status,
    required this.currentPhase,
    required this.phaseNumber,
    required this.dayNumber,
    required this.phaseStartedAt,
    this.phaseEndsAt,
    required this.werewolvesAlive,
    required this.villagersAlive,
    this.winningTeam,
    this.players,
  });

  factory GameSession.fromJson(Map<String, dynamic> json) {
    return GameSession(
      id: json['id'],
      roomId: json['room_id'],
      status: json['status'],
      currentPhase: json['current_phase'],
      phaseNumber: json['phase_number'],
      dayNumber: json['day_number'],
      phaseStartedAt: DateTime.parse(json['phase_started_at']),
      phaseEndsAt: json['phase_ends_at'] != null ? DateTime.parse(json['phase_ends_at']) : null,
      werewolvesAlive: json['werewolves_alive'],
      villagersAlive: json['villagers_alive'],
      winningTeam: json['winning_team'],
      players: json['players'] != null
        ? (json['players'] as List).map((p) => GamePlayer.fromJson(p)).toList()
        : null,
    );
  }
}

class GamePlayer {
  final String id;
  final String sessionId;
  final String userId;
  final String role;
  final String team;
  final bool isAlive;
  final int? diedAtPhase;
  final String? deathReason;
  final String currentVoiceChannel;
  final int seatPosition;
  final User? user;

  GamePlayer({
    required this.id,
    required this.sessionId,
    required this.userId,
    required this.role,
    required this.team,
    required this.isAlive,
    this.diedAtPhase,
    this.deathReason,
    required this.currentVoiceChannel,
    required this.seatPosition,
    this.user,
  });

  factory GamePlayer.fromJson(Map<String, dynamic> json) {
    return GamePlayer(
      id: json['id'],
      sessionId: json['session_id'],
      userId: json['user_id'],
      role: json['role'],
      team: json['team'],
      isAlive: json['is_alive'] ?? true,
      diedAtPhase: json['died_at_phase'],
      deathReason: json['death_reason'],
      currentVoiceChannel: json['current_voice_channel'] ?? 'main',
      seatPosition: json['seat_position'],
      user: json['user'] != null ? User.fromJson(json['user']) : null,
    );
  }
}

class AgoraTokenResponse {
  final String token;
  final String channelName;
  final int uid;
  final int expiresAt;

  AgoraTokenResponse({
    required this.token,
    required this.channelName,
    required this.uid,
    required this.expiresAt,
  });

  factory AgoraTokenResponse.fromJson(Map<String, dynamic> json) {
    return AgoraTokenResponse(
      token: json['token'],
      channelName: json['channel_name'],
      uid: json['uid'],
      expiresAt: json['expires_at'],
    );
  }
}

class WSMessage {
  final String type;
  final Map<String, dynamic> payload;
  final DateTime timestamp;

  WSMessage({
    required this.type,
    required this.payload,
    required this.timestamp,
  });

  factory WSMessage.fromJson(Map<String, dynamic> json) {
    return WSMessage(
      type: json['type'],
      payload: Map<String, dynamic>.from(json['payload'] ?? {}),
      timestamp: DateTime.parse(json['timestamp']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'payload': payload,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}
