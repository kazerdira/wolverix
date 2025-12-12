package models

import (
	"time"

	"github.com/google/uuid"
)

// ============================================================================
// USER MODELS
// ============================================================================

type User struct {
	ID              uuid.UUID  `json:"id"`
	Username        string     `json:"username"`
	Email           string     `json:"email"`
	PasswordHash    string     `json:"-"`
	AvatarURL       *string    `json:"avatar_url,omitempty"`
	DisplayName     *string    `json:"display_name,omitempty"`
	Language        string     `json:"language"`
	IsOnline        bool       `json:"is_online"`
	ReputationScore int        `json:"reputation_score"`
	IsBanned        bool       `json:"is_banned"`
	BannedUntil     *time.Time `json:"banned_until,omitempty"`
	CreatedAt       time.Time  `json:"created_at"`
	UpdatedAt       time.Time  `json:"updated_at"`
	LastSeenAt      *time.Time `json:"last_seen_at,omitempty"`
}

type UserStats struct {
	UserID          uuid.UUID `json:"user_id"`
	TotalGames      int       `json:"total_games"`
	TotalWins       int       `json:"total_wins"`
	TotalLosses     int       `json:"total_losses"`
	GamesAsVillager int       `json:"games_as_villager"`
	GamesAsWerewolf int       `json:"games_as_werewolf"`
	GamesAsSeer     int       `json:"games_as_seer"`
	GamesAsWitch    int       `json:"games_as_witch"`
	GamesAsHunter   int       `json:"games_as_hunter"`
	VillagerWins    int       `json:"villager_wins"`
	WerewolfWins    int       `json:"werewolf_wins"`
	CurrentStreak   int       `json:"current_streak"`
	BestStreak      int       `json:"best_streak"`
	TotalKills      int       `json:"total_kills"`
	TotalDeaths     int       `json:"total_deaths"`
	MVPCount        int       `json:"mvp_count"`
	CreatedAt       time.Time `json:"created_at"`
	UpdatedAt       time.Time `json:"updated_at"`
}

// ============================================================================
// ROOM MODELS
// ============================================================================

type Room struct {
	ID                   uuid.UUID  `json:"id"`
	RoomCode             string     `json:"room_code"`
	Name                 string     `json:"name"`
	HostUserID           uuid.UUID  `json:"host_user_id"`
	Status               RoomStatus `json:"status"`
	IsPrivate            bool       `json:"is_private"`
	PasswordHash         *string    `json:"-"`
	MaxPlayers           int        `json:"max_players"`
	CurrentPlayers       int        `json:"current_players"`
	Language             string     `json:"language"`
	Config               RoomConfig `json:"config"`
	AgoraChannelName     string     `json:"agora_channel_name"`
	AgoraAppID           *string    `json:"agora_app_id,omitempty"`
	CreatedAt            time.Time  `json:"created_at"`
	UpdatedAt            time.Time  `json:"updated_at"`
	StartedAt            *time.Time `json:"started_at,omitempty"`
	FinishedAt           *time.Time `json:"finished_at,omitempty"`
	LastActivityAt       time.Time  `json:"last_activity_at"`
	TimeoutWarningSent   bool       `json:"timeout_warning_sent"`
	TimeoutExtendedCount int        `json:"timeout_extended_count"`

	// Joined data (not in DB)
	Host    *User        `json:"host,omitempty"`
	Players []RoomPlayer `json:"players,omitempty"`
}

type RoomStatus string

const (
	RoomStatusWaiting   RoomStatus = "waiting"
	RoomStatusPlaying   RoomStatus = "playing"
	RoomStatusFinished  RoomStatus = "finished"
	RoomStatusAbandoned RoomStatus = "abandoned"
)

type RoomConfig struct {
	EnabledRoles      []string `json:"enabled_roles"`
	WerewolfCount     int      `json:"werewolf_count"`
	DayPhaseSeconds   int      `json:"day_phase_seconds"`
	NightPhaseSeconds int      `json:"night_phase_seconds"`
	VotingSeconds     int      `json:"voting_seconds"`
	AllowSpectators   bool     `json:"allow_spectators"`
	RequireReady      bool     `json:"require_ready"`
}

type RoomPlayer struct {
	ID           uuid.UUID  `json:"id"`
	RoomID       uuid.UUID  `json:"room_id"`
	UserID       uuid.UUID  `json:"user_id"`
	IsReady      bool       `json:"is_ready"`
	IsHost       bool       `json:"is_host"`
	SeatPosition *int       `json:"seat_position,omitempty"`
	JoinedAt     time.Time  `json:"joined_at"`
	LeftAt       *time.Time `json:"left_at,omitempty"`

	// Joined data
	User *User `json:"user,omitempty"`
}

// ============================================================================
// GAME MODELS
// ============================================================================

type GameSession struct {
	ID              uuid.UUID  `json:"id"`
	RoomID          uuid.UUID  `json:"room_id"`
	Status          GameStatus `json:"status"`
	CurrentPhase    GamePhase  `json:"current_phase"`
	PhaseNumber     int        `json:"phase_number"`
	DayNumber       int        `json:"day_number"`
	PhaseStartedAt  time.Time  `json:"phase_started_at"`
	PhaseEndsAt     *time.Time `json:"phase_ends_at,omitempty"`
	State           GameState  `json:"state"`
	WerewolvesAlive int        `json:"werewolves_alive"`
	VillagersAlive  int        `json:"villagers_alive"`
	WinningTeam     *string    `json:"winning_team,omitempty"`
	CreatedAt       time.Time  `json:"created_at"`
	UpdatedAt       time.Time  `json:"updated_at"`
	FinishedAt      *time.Time `json:"finished_at,omitempty"`

	// Joined data
	Players []GamePlayer `json:"players,omitempty"`
}

type GameStatus string

const (
	GameStatusActive   GameStatus = "active"
	GameStatusPaused   GameStatus = "paused"
	GameStatusFinished GameStatus = "finished"
)

type GamePhase string

const (
	GamePhaseNight0        GamePhase = "night_0"
	GamePhaseCupid         GamePhase = "cupid_phase"
	GamePhaseWerewolf      GamePhase = "werewolf_phase"
	GamePhaseSeer          GamePhase = "seer_phase"
	GamePhaseWitch         GamePhase = "witch_phase"
	GamePhaseBodyguard     GamePhase = "bodyguard_phase"
	GamePhaseDayDiscussion GamePhase = "day_discussion"
	GamePhaseDayVoting     GamePhase = "day_voting"
	GamePhaseDefense       GamePhase = "defense_phase"
	GamePhaseFinalVote     GamePhase = "final_vote"
	GamePhaseHunter        GamePhase = "hunter_phase"
	GamePhaseMayorReveal   GamePhase = "mayor_reveal"
	GamePhaseGameOver      GamePhase = "game_over"

	// Aliases for backward compatibility
	GamePhaseNight       = GamePhaseNight0
	GamePhaseNightAction = GamePhaseWerewolf
	GamePhaseDay         = GamePhaseDayDiscussion
	GamePhaseDiscussion  = GamePhaseDayDiscussion
	GamePhaseVoting      = GamePhaseDayVoting
	GamePhaseExecution   = GamePhaseDefense
)

type GameState struct {
	LastKilledPlayer  *uuid.UUID        `json:"last_killed_player,omitempty"`
	LastLynchedPlayer *uuid.UUID        `json:"last_lynched_player,omitempty"`
	WerewolfVotes     map[string]int    `json:"werewolf_votes,omitempty"` // targetID -> vote count
	LynchVotes        map[string]int    `json:"lynch_votes,omitempty"`    // targetID -> vote count
	CurrentVoteTarget *uuid.UUID        `json:"current_vote_target,omitempty"`
	ActionsCompleted  map[string]bool   `json:"actions_completed,omitempty"` // role -> completed
	ActionsRemaining  map[string]int    `json:"actions_remaining,omitempty"` // role -> remaining count
	ProtectedPlayer   *uuid.UUID        `json:"protected_player,omitempty"`
	PoisonedPlayer    *uuid.UUID        `json:"poisoned_player,omitempty"`
	HealedPlayer      *uuid.UUID        `json:"healed_player,omitempty"`
	RevealedRoles     map[string]string `json:"revealed_roles,omitempty"` // playerID -> role
	NightKills        []uuid.UUID       `json:"night_kills,omitempty"`
	PendingHunterShot bool              `json:"pending_hunter_shot,omitempty"`
	HunterPlayerID    *uuid.UUID        `json:"hunter_player_id,omitempty"`
}

type GamePlayer struct {
	ID                  uuid.UUID  `json:"id"`
	SessionID           uuid.UUID  `json:"session_id"`
	UserID              uuid.UUID  `json:"user_id"`
	Role                Role       `json:"role"`
	Team                Team       `json:"team"`
	IsAlive             bool       `json:"is_alive"`
	DiedAtPhase         *int       `json:"died_at_phase,omitempty"`
	DeathReason         *string    `json:"death_reason,omitempty"`
	RoleState           RoleState  `json:"role_state"`
	LoverID             *uuid.UUID `json:"lover_id,omitempty"`
	CurrentVoiceChannel string     `json:"current_voice_channel"`
	AllowedChatChannels []string   `json:"allowed_chat_channels"` // Which chat channels player can send to
	SeatPosition        int        `json:"seat_position"`
	JoinedAt            time.Time  `json:"joined_at"`

	// Joined data
	User *User `json:"user,omitempty"`
}

type Role string

const (
	RoleWerewolf   Role = "werewolf"
	RoleVillager   Role = "villager"
	RoleSeer       Role = "seer"
	RoleWitch      Role = "witch"
	RoleHunter     Role = "hunter"
	RoleCupid      Role = "cupid"
	RoleBodyguard  Role = "bodyguard"
	RoleMayor      Role = "mayor"
	RoleMedium     Role = "medium"
	RoleTanner     Role = "tanner"
	RoleLittleGirl Role = "little_girl"
)

type Team string

const (
	TeamWerewolves Team = "werewolves"
	TeamVillagers  Team = "villagers"
	TeamNeutral    Team = "neutral"
	TeamLovers     Team = "lovers"
)

type RoleState struct {
	// Witch specific
	HealUsed           bool       `json:"heal_used,omitempty"`
	PoisonUsed         bool       `json:"poison_used,omitempty"`
	CurrentNightVictim *uuid.UUID `json:"current_night_victim,omitempty"` // Shows Witch who wolves are targeting

	// Hunter specific
	HasShot bool `json:"has_shot,omitempty"`

	// Bodyguard specific
	LastProtected *uuid.UUID `json:"last_protected,omitempty"`

	// Seer specific
	DivinedPlayers []uuid.UUID `json:"divined_players,omitempty"`

	// Cupid specific
	HasChosen bool `json:"has_chosen,omitempty"`

	// Mayor specific
	IsRevealed bool `json:"is_revealed,omitempty"`
}

// ============================================================================
// ACTION MODELS
// ============================================================================

type GameAction struct {
	ID             uuid.UUID  `json:"id"`
	SessionID      uuid.UUID  `json:"session_id"`
	PlayerID       uuid.UUID  `json:"player_id"`
	PhaseNumber    int        `json:"phase_number"`
	ActionType     ActionType `json:"action_type"`
	TargetPlayerID *uuid.UUID `json:"target_player_id,omitempty"`
	ActionData     ActionData `json:"action_data,omitempty"`
	IsSuccessful   bool       `json:"is_successful"`
	CreatedAt      time.Time  `json:"created_at"`
}

type ActionType string

const (
	ActionWerewolfVote ActionType = "werewolf_vote"
	ActionSeerDivine   ActionType = "seer_divine"
	ActionWitchHeal    ActionType = "witch_heal"
	ActionWitchPoison  ActionType = "witch_poison"
	ActionWitchSkip    ActionType = "witch_skip"
	ActionVoteLynch    ActionType = "vote_lynch"
	ActionVoteSkip     ActionType = "vote_skip"
	ActionHunterShoot  ActionType = "hunter_shoot"
	ActionBodyguard    ActionType = "bodyguard_protect"
	ActionCupidChoose  ActionType = "cupid_choose"
	ActionMayorReveal  ActionType = "mayor_reveal"
)

type ActionData struct {
	Result      string     `json:"result,omitempty"`
	VoteCount   int        `json:"vote_count,omitempty"`
	SecondLover *uuid.UUID `json:"second_lover,omitempty"`
	Extra       any        `json:"extra,omitempty"`
}

// ============================================================================
// EVENT MODELS
// ============================================================================

type GameEvent struct {
	ID          uuid.UUID `json:"id"`
	SessionID   uuid.UUID `json:"session_id"`
	PhaseNumber int       `json:"phase_number"`
	EventType   EventType `json:"event_type"`
	EventData   EventData `json:"event_data"`
	IsPublic    bool      `json:"is_public"`
	CreatedAt   time.Time `json:"created_at"`
}

type EventType string

const (
	EventPhaseChange    EventType = "phase_change"
	EventPlayerDeath    EventType = "player_death"
	EventRoleReveal     EventType = "role_reveal"
	EventGameEnd        EventType = "game_end"
	EventVoteComplete   EventType = "vote_complete"
	EventHunterTrigger  EventType = "hunter_trigger"
	EventLoverDeath     EventType = "lover_death"
	EventWitchAction    EventType = "witch_action"
	EventSeerDivination EventType = "seer_divination"
)

type EventData struct {
	PlayerID   *uuid.UUID     `json:"player_id,omitempty"`
	TargetID   *uuid.UUID     `json:"target_id,omitempty"`
	NewPhase   *GamePhase     `json:"new_phase,omitempty"`
	Role       *Role          `json:"role,omitempty"`
	Reason     string         `json:"reason,omitempty"`
	WinnerTeam *Team          `json:"winner_team,omitempty"`
	Message    string         `json:"message,omitempty"`
	VoteResult map[string]int `json:"vote_result,omitempty"`
}

// ============================================================================
// VOICE MODELS
// ============================================================================

type VoiceChannel struct {
	ID               uuid.UUID   `json:"id"`
	RoomID           uuid.UUID   `json:"room_id"`
	ChannelName      string      `json:"channel_name"`
	ChannelType      ChannelType `json:"channel_type"`
	AgoraChannelName string      `json:"agora_channel_name"`
	IsActive         bool        `json:"is_active"`
	CreatedAt        time.Time   `json:"created_at"`
	ClosedAt         *time.Time  `json:"closed_at,omitempty"`
}

type ChannelType string

const (
	ChannelTypeMain      ChannelType = "main"
	ChannelTypeWerewolf  ChannelType = "werewolf"
	ChannelTypeDead      ChannelType = "dead"
	ChannelTypeSpectator ChannelType = "spectator"
)

// ============================================================================
// REQUEST/RESPONSE MODELS
// ============================================================================

type RegisterRequest struct {
	Username string `json:"username" binding:"required,min=3,max=30"`
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required,min=8"`
	Language string `json:"language"`
}

type LoginRequest struct {
	Username string `json:"username"`
	Email    string `json:"email"`
	Password string `json:"password" binding:"required"`
}

type AuthResponse struct {
	Token        string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	User         User   `json:"user"`
}

type RefreshTokenRequest struct {
	RefreshToken string `json:"refresh_token" binding:"required"`
}

type CreateRoomRequest struct {
	Name       string     `json:"name" binding:"required,min=3,max=100"`
	IsPrivate  bool       `json:"is_private"`
	Password   string     `json:"password"`
	MaxPlayers int        `json:"max_players"`
	Language   string     `json:"language"`
	Config     RoomConfig `json:"config"`
}

type JoinRoomRequest struct {
	RoomCode string `json:"room_code" binding:"required"`
	Password string `json:"password"`
}

type RoomActionRequest struct {
	Action string `json:"action" binding:"required"` // start, kick, ready, config
	Data   any    `json:"data,omitempty"`
}

type GameActionRequest struct {
	ActionType ActionType `json:"action_type" binding:"required"`
	TargetID   *uuid.UUID `json:"target_id"`
	Data       any        `json:"data,omitempty"`
}

type AgoraTokenRequest struct {
	ChannelName string `json:"channel_name" binding:"required"`
	UID         uint32 `json:"uid"`
}

type AgoraTokenResponse struct {
	Token       string `json:"token"`
	ChannelName string `json:"channel_name"`
	UID         uint32 `json:"uid"`
	ExpiresAt   int64  `json:"expires_at"`
}

// ============================================================================
// WEBSOCKET MESSAGES
// ============================================================================

type WSMessageType string

const (
	WSTypeRoomUpdate   WSMessageType = "room_update"
	WSTypeGameUpdate   WSMessageType = "game_update"
	WSTypePhaseChange  WSMessageType = "phase_change"
	WSTypePlayerAction WSMessageType = "player_action"
	WSTypePlayerDeath  WSMessageType = "player_death"
	WSTypeGameEnd      WSMessageType = "game_end"
	WSTypeVoiceUpdate  WSMessageType = "voice_update"
	WSTypeRoleReveal   WSMessageType = "role_reveal"
	WSTypeTimer        WSMessageType = "timer"
	WSTypeChat         WSMessageType = "chat"
	WSTypeError        WSMessageType = "error"
	WSTypePing         WSMessageType = "ping"
	WSTypePong         WSMessageType = "pong"
)

type WSMessage struct {
	Type      WSMessageType `json:"type"`
	Payload   any           `json:"payload"`
	Timestamp time.Time     `json:"timestamp"`
}

type WSErrorPayload struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}
