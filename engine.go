package game

import (
	"context"
	"encoding/json"
	"fmt"
	"math/rand"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/yourusername/werewolf-voice/internal/models"
)

// Engine handles all game logic and state management
type Engine struct {
	db *pgxpool.Pool
}

// NewEngine creates a new game engine
func NewEngine(db *pgxpool.Pool) *Engine {
	return &Engine{db: db}
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
	err = tx.QueryRow(ctx, `
		SELECT id, room_code, name, host_user_id, max_players, current_players, config
		FROM rooms WHERE id = $1 AND status = 'waiting'
	`, roomID).Scan(&room.ID, &room.RoomCode, &room.Name, &room.HostUserID, 
		&room.MaxPlayers, &room.CurrentPlayers, &roomConfig)
	if err != nil {
		return nil, fmt.Errorf("room not found or not in waiting state: %w", err)
	}

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
		ActionsRemaining: []string{"cupid", "werewolf", "seer", "witch", "bodyguard"},
		RevealedRoles:    make(map[string]string),
		WerewolfVotes:    make(map[string]int),
	}
	stateJSON, _ := json.Marshal(initialState)

	_, err = tx.Exec(ctx, `
		INSERT INTO game_sessions (
			id, room_id, status, current_phase, phase_number, day_number,
			phase_started_at, phase_ends_at, state, werewolves_alive, villagers_alive
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
	`, sessionID, roomID, models.GameStatusActive, models.GamePhaseNight, 1, 0,
		now, phaseEndsAt, stateJSON, 
		roleAssignments.WerewolfCount, roleAssignments.VillagerCount)
	if err != nil {
		return nil, fmt.Errorf("failed to create game session: %w", err)
	}

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
	eventData := models.EventData{
		NewPhase: (*models.GamePhase)(&[]models.GamePhase{models.GamePhaseNight}[0]),
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

type RoleAssignment struct {
	UserID    uuid.UUID
	Role      models.Role
	Team      models.Team
	Position  int
	RoleState models.RoleState
}

type RoleAssignments struct {
	Assignments    []RoleAssignment
	WerewolfCount  int
	VillagerCount  int
}

// assignRoles assigns roles to players based on room configuration
func (e *Engine) assignRoles(players []struct {
	UserID   uuid.UUID
	Position int
	Username string
}, config models.RoomConfig) (*RoleAssignments, error) {
	
	playerCount := len(players)
	werewolfCount := config.WerewolfCount
	if werewolfCount == 0 {
		// Auto-calculate werewolf count based on player count
		werewolfCount = calculateWerewolfCount(playerCount)
	}

	// Build role pool
	rolePool := []models.Role{models.RoleWerewolf} // Ensure at least one werewolf
	for i := 1; i < werewolfCount; i++ {
		rolePool = append(rolePool, models.RoleWerewolf)
	}

	// Add special roles based on config
	enabledRoles := config.EnabledRoles
	if len(enabledRoles) == 0 {
		// Default roles
		enabledRoles = []string{"seer", "witch", "hunter", "cupid", "bodyguard"}
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
	rand.Seed(time.Now().UnixNano())
	rand.Shuffle(len(rolePool), func(i, j int) {
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
		Assignments:    assignments,
		WerewolfCount:  werewolfCount,
		VillagerCount:  villagerCount,
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
