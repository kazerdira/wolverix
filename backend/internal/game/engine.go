package game

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"math/rand"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/kazerdira/wolverix/backend/internal/models"
)

// Engine is the main game engine that coordinates all game systems
type Engine struct {
	db            *pgxpool.Pool
	deathResolver *DeathResolver
	winChecker    *WinChecker
	phaseManager  *PhaseManager
	nightCoord    *NightCoordinator
	voteManager   *VoteManager
	scheduler     *GameScheduler
}

// NewEngine creates a new game engine with all subsystems
func NewEngine(db *pgxpool.Pool) *Engine {
	deathResolver := NewDeathResolver(db)
	winChecker := NewWinChecker(db)
	nightCoord := NewNightCoordinator(db)
	phaseManager := NewPhaseManager(db, deathResolver, winChecker, nightCoord)
	voteManager := NewVoteManager(db)

	engine := &Engine{
		db:            db,
		deathResolver: deathResolver,
		winChecker:    winChecker,
		phaseManager:  phaseManager,
		nightCoord:    nightCoord,
		voteManager:   voteManager,
	}

	// Create scheduler and set it in phase manager (after engine is created to avoid circular dependency)
	scheduler := NewGameScheduler(db, engine)
	engine.scheduler = scheduler
	phaseManager.SetScheduler(scheduler)

	return engine
}

// GetScheduler returns the game scheduler
func (e *Engine) GetScheduler() *GameScheduler {
	return e.scheduler
}

// StartGame initializes a new game session from a room
func (e *Engine) StartGame(ctx context.Context, roomID uuid.UUID) (*models.GameSession, error) {
	tx, err := e.db.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	// Get room and players
	var room models.Room
	var roomConfig json.RawMessage
	log.Printf("🎮 StartGame: Looking for room %s with status IN ('waiting', 'starting')", roomID)

	err = tx.QueryRow(ctx, `
		SELECT id, room_code, name, host_user_id, max_players, current_players, config, status
		FROM rooms WHERE id = $1 AND status IN ('waiting', 'starting')
	`, roomID).Scan(&room.ID, &room.RoomCode, &room.Name, &room.HostUserID,
		&room.MaxPlayers, &room.CurrentPlayers, &roomConfig, &room.Status)
	if err != nil {
		// Log what the actual room status is
		var actualStatus string
		e.db.QueryRow(ctx, "SELECT status FROM rooms WHERE id = $1", roomID).Scan(&actualStatus)
		log.Printf("❌ StartGame failed: Room %s has status '%s', error: %v", roomID, actualStatus, err)
		return nil, fmt.Errorf("room not found or not ready to start (status: %s): %w", actualStatus, err)
	}

	log.Printf("✅ StartGame: Found room %s with status '%s'", roomID, room.Status)

	if err := json.Unmarshal(roomConfig, &room.Config); err != nil {
		return nil, fmt.Errorf("failed to parse room config: %w", err)
	}

	// Get players in room
	rows, err := tx.Query(ctx, `
		SELECT rp.user_id, rp.seat_position, u.username
		FROM room_players rp
		JOIN users u ON rp.user_id = u.id
		WHERE rp.room_id = $1 AND rp.left_at IS NULL
		ORDER BY rp.seat_position
	`, roomID)
	if err != nil {
		return nil, fmt.Errorf("failed to get players: %w", err)
	}
	defer rows.Close()

	var players []struct {
		UserID   uuid.UUID
		Position int
		Username string
	}

	for rows.Next() {
		var p struct {
			UserID   uuid.UUID
			Position int
			Username string
		}
		if err := rows.Scan(&p.UserID, &p.Position, &p.Username); err != nil {
			return nil, fmt.Errorf("failed to scan player: %w", err)
		}
		players = append(players, p)
	}

	if len(players) < 6 {
		return nil, fmt.Errorf("not enough players to start game (minimum 6)")
	}

	// Assign roles
	roleAssignments, err := e.assignRoles(players, room.Config)
	if err != nil {
		return nil, fmt.Errorf("failed to assign roles: %w", err)
	}

	// Create game session
	sessionID := uuid.New()
	now := time.Now()
	phaseEndsAt := now.Add(2 * time.Minute) // Initial night phase

	initialState := models.GameState{
		ActionsRemaining: make(map[string]int),
		ActionsCompleted: make(map[string]bool),
		RevealedRoles:    make(map[string]string),
		WerewolfVotes:    make(map[string]int),
		LynchVotes:       make(map[string]int),
	}
	stateJSON, _ := json.Marshal(initialState)

	phaseValue := string(models.GamePhaseNight)
	log.Printf("🔍 DEBUG: About to insert - phase value: '%s', status: '%s'", phaseValue, models.GameStatusActive)
	_, err = tx.Exec(ctx, `
		INSERT INTO game_sessions (
			id, room_id, status, current_phase, phase_number, day_number,
			phase_started_at, phase_ends_at, state, werewolves_alive, villagers_alive
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
	`, sessionID, roomID, models.GameStatusActive, phaseValue, 1, 0,
		now, phaseEndsAt, stateJSON,
		roleAssignments.WerewolfCount, roleAssignments.VillagerCount)
	if err != nil {
		log.Printf("❌ DEBUG: Insert failed - phase='%s', status='%s', error: %v", phaseValue, models.GameStatusActive, err)
		return nil, fmt.Errorf("failed to create game session: %w", err)
	}
	log.Printf("✅ DEBUG: Game session inserted successfully with phase='%s'", phaseValue)

	// Insert game players with roles
	for _, assignment := range roleAssignments.Assignments {
		roleStateJSON, _ := json.Marshal(assignment.RoleState)
		_, err = tx.Exec(ctx, `
			INSERT INTO game_players (
				id, session_id, user_id, role, team, is_alive,
				role_state, current_voice_channel, seat_position
			) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
		`, uuid.New(), sessionID, assignment.UserID, assignment.Role, assignment.Team,
			true, roleStateJSON, "main", assignment.Position)
		if err != nil {
			return nil, fmt.Errorf("failed to insert game player: %w", err)
		}
	}

	// Update room status
	_, err = tx.Exec(ctx, `
		UPDATE rooms SET status = 'playing', started_at = $1 WHERE id = $2
	`, now, roomID)
	if err != nil {
		return nil, fmt.Errorf("failed to update room status: %w", err)
	}

	// Create initial event
	nightPhase := models.GamePhaseNight
	eventData := models.EventData{
		NewPhase: &nightPhase,
		Message:  "Night falls on the village. Roles are being assigned...",
	}
	eventDataJSON, _ := json.Marshal(eventData)
	_, err = tx.Exec(ctx, `
		INSERT INTO game_events (id, session_id, phase_number, event_type, event_data, is_public)
		VALUES ($1, $2, $3, $4, $5, $6)
	`, uuid.New(), sessionID, 1, models.EventPhaseChange, eventDataJSON, true)
	if err != nil {
		return nil, fmt.Errorf("failed to create initial event: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, fmt.Errorf("failed to commit transaction: %w", err)
	}

	// Schedule automatic transition to day phase (2 minute initial night)
	if e.scheduler != nil {
		e.scheduler.SchedulePhaseEnd(sessionID, 2*time.Minute)
	}

	// Return the created session
	session := &models.GameSession{
		ID:              sessionID,
		RoomID:          roomID,
		Status:          models.GameStatusActive,
		CurrentPhase:    models.GamePhaseNight,
		PhaseNumber:     1,
		DayNumber:       0,
		PhaseStartedAt:  now,
		PhaseEndsAt:     &phaseEndsAt,
		State:           initialState,
		WerewolvesAlive: roleAssignments.WerewolfCount,
		VillagersAlive:  roleAssignments.VillagerCount,
		CreatedAt:       now,
		UpdatedAt:       now,
	}

	return session, nil
}

// ProcessAction delegates to appropriate subsystem
func (e *Engine) ProcessAction(ctx context.Context, sessionID, userID uuid.UUID, action models.GameActionRequest) error {
	switch action.ActionType {
	case models.ActionWerewolfVote:
		return e.processWerewolfVote(ctx, sessionID, userID, action.TargetID)
	case models.ActionSeerDivine:
		return e.processSeerDivine(ctx, sessionID, userID, action.TargetID)
	case models.ActionWitchHeal:
		return e.processWitchHeal(ctx, sessionID, userID)
	case models.ActionWitchPoison:
		return e.processWitchPoison(ctx, sessionID, userID, action.TargetID)
	case models.ActionBodyguard:
		return e.processBodyguardProtect(ctx, sessionID, userID, action.TargetID)
	case models.ActionCupidChoose:
		return e.processCupidChoose(ctx, sessionID, userID, action.TargetID, action.Data)
	case models.ActionVoteLynch:
		return e.voteManager.CastVote(ctx, sessionID, userID, *action.TargetID)
	case models.ActionHunterShoot:
		return e.processHunterShoot(ctx, sessionID, userID, action.TargetID)
	default:
		return fmt.Errorf("unknown action type: %s", action.ActionType)
	}
}

// TransitionPhase handles phase transitions
func (e *Engine) TransitionPhase(ctx context.Context, sessionID uuid.UUID) (*PhaseTransition, error) {
	// Get current phase
	var currentPhase models.GamePhase
	err := e.db.QueryRow(ctx, `
		SELECT current_phase FROM game_sessions WHERE id = $1
	`, sessionID).Scan(&currentPhase)
	if err != nil {
		return nil, err
	}

	// Transition based on current phase
	switch currentPhase {
	case models.GamePhaseNight:
		return e.phaseManager.TransitionToDay(ctx, sessionID)
	case models.GamePhaseDay:
		return e.phaseManager.TransitionToVoting(ctx, sessionID)
	case models.GamePhaseVoting:
		// Tally votes first
		voteResult, err := e.voteManager.TallyVotes(ctx, sessionID)
		if err != nil {
			return nil, fmt.Errorf("failed to tally votes: %w", err)
		}
		return e.phaseManager.TransitionToNight(ctx, sessionID, voteResult.LynchedPlayerID)
	default:
		return nil, fmt.Errorf("invalid phase for transition: %s", currentPhase)
	}
}

// CheckPhaseTimeout checks if current phase has timed out
func (e *Engine) CheckPhaseTimeout(ctx context.Context, sessionID uuid.UUID) (bool, error) {
	return e.phaseManager.CheckPhaseTimeout(ctx, sessionID)
}

// GetGameState returns current game state
func (e *Engine) GetGameState(ctx context.Context, sessionID uuid.UUID) (*models.GameSession, error) {
	var session models.GameSession
	var stateJSON json.RawMessage

	err := e.db.QueryRow(ctx, `
		SELECT id, room_id, status, current_phase, phase_number, day_number,
		       phase_started_at, phase_ends_at, state, werewolves_alive, villagers_alive,
		       winner, started_at, updated_at, ended_at
		FROM game_sessions WHERE id = $1
	`, sessionID).Scan(
		&session.ID, &session.RoomID, &session.Status, &session.CurrentPhase,
		&session.PhaseNumber, &session.DayNumber, &session.PhaseStartedAt,
		&session.PhaseEndsAt, &stateJSON, &session.WerewolvesAlive,
		&session.VillagersAlive, &session.WinningTeam, &session.CreatedAt,
		&session.UpdatedAt, &session.FinishedAt,
	)
	if err != nil {
		return nil, err
	}

	if err := json.Unmarshal(stateJSON, &session.State); err != nil {
		return nil, fmt.Errorf("failed to parse state: %w", err)
	}

	// Load players
	rows, err := e.db.Query(ctx, `
		SELECT gp.id, gp.session_id, gp.user_id, gp.role, gp.team, gp.is_alive,
		       gp.died_at_phase, gp.death_reason, gp.lover_id, gp.current_voice_channel,
		       gp.seat_position, gp.role_state,
		       u.username, u.avatar_url
		FROM game_players gp
		JOIN users u ON gp.user_id = u.id
		WHERE gp.session_id = $1
		ORDER BY gp.seat_position
	`, sessionID)
	if err != nil {
		return nil, fmt.Errorf("failed to load players: %w", err)
	}
	defer rows.Close()

	for rows.Next() {
		var player models.GamePlayer
		var roleStateJSON []byte
		var username string
		var avatarURL *string

		err := rows.Scan(
			&player.ID, &player.SessionID, &player.UserID, &player.Role, &player.Team,
			&player.IsAlive, &player.DiedAtPhase, &player.DeathReason, &player.LoverID,
			&player.CurrentVoiceChannel, &player.SeatPosition, &roleStateJSON,
			&username, &avatarURL,
		)
		if err != nil {
			return nil, fmt.Errorf("failed to scan player: %w", err)
		}

		// Parse role state
		if len(roleStateJSON) > 0 {
			if err := json.Unmarshal(roleStateJSON, &player.RoleState); err != nil {
				return nil, fmt.Errorf("failed to parse role state: %w", err)
			}
		}

		// Set user info
		player.User = &models.User{
			ID:        player.UserID,
			Username:  username,
			AvatarURL: avatarURL,
		}

		session.Players = append(session.Players, player)
	}

	return &session, nil
}

// Internal helpers - same role assignment logic
type RoleAssignment struct {
	UserID    uuid.UUID
	Role      models.Role
	Team      models.Team
	Position  int
	RoleState models.RoleState
}

type RoleAssignments struct {
	Assignments   []RoleAssignment
	WerewolfCount int
	VillagerCount int
}

func (e *Engine) assignRoles(players []struct {
	UserID   uuid.UUID
	Position int
	Username string
}, config models.RoomConfig) (*RoleAssignments, error) {

	playerCount := len(players)
	werewolfCount := config.WerewolfCount
	if werewolfCount == 0 {
		werewolfCount = calculateWerewolfCount(playerCount)
	}

	// Build role pool
	rolePool := make([]models.Role, 0, playerCount)
	for i := 0; i < werewolfCount; i++ {
		rolePool = append(rolePool, models.RoleWerewolf)
	}

	// Add special roles
	enabledRoles := config.EnabledRoles
	if len(enabledRoles) == 0 {
		// TODO: Re-enable hunter once revenge mechanism is implemented
		enabledRoles = []string{"seer", "witch", "cupid", "bodyguard"}
	}

	for _, roleName := range enabledRoles {
		role := models.Role(roleName)
		rolePool = append(rolePool, role)
	}

	// Fill remaining slots with villagers
	villagersNeeded := playerCount - len(rolePool)
	for i := 0; i < villagersNeeded; i++ {
		rolePool = append(rolePool, models.RoleVillager)
	}

	// Shuffle roles
	r := rand.New(rand.NewSource(time.Now().UnixNano()))
	r.Shuffle(len(rolePool), func(i, j int) {
		rolePool[i], rolePool[j] = rolePool[j], rolePool[i]
	})

	// Assign roles to players
	assignments := make([]RoleAssignment, len(players))
	villagerCount := 0

	for i, player := range players {
		role := rolePool[i]
		team := getTeam(role)

		if team == models.TeamVillagers {
			villagerCount++
		}

		assignments[i] = RoleAssignment{
			UserID:    player.UserID,
			Role:      role,
			Team:      team,
			Position:  player.Position,
			RoleState: getInitialRoleState(role),
		}
	}

	return &RoleAssignments{
		Assignments:   assignments,
		WerewolfCount: werewolfCount,
		VillagerCount: villagerCount,
	}, nil
}

func calculateWerewolfCount(playerCount int) int {
	if playerCount <= 8 {
		return 2
	} else if playerCount <= 12 {
		return 3
	} else if playerCount <= 18 {
		return 4
	}
	return 5
}

func getTeam(role models.Role) models.Team {
	switch role {
	case models.RoleWerewolf:
		return models.TeamWerewolves
	case models.RoleTanner:
		return models.TeamNeutral
	default:
		return models.TeamVillagers
	}
}

func getInitialRoleState(role models.Role) models.RoleState {
	state := models.RoleState{}
	switch role {
	case models.RoleWitch:
		state.HealUsed = false
		state.PoisonUsed = false
	case models.RoleHunter:
		state.HasShot = false
	case models.RoleSeer:
		state.DivinedPlayers = []uuid.UUID{}
	case models.RoleCupid:
		state.HasChosen = false
	}
	return state
}
