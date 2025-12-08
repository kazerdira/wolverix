package game

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/kazerdira/wolverix/backend/internal/models"
)

// Test database setup (placeholder - needs actual implementation)
func setupTestDB(t *testing.T) (*pgxpool.Pool, func()) {
	// TODO: For now, skip tests that need DB
	// In future, set up a test PostgreSQL database
	t.Skip("Database setup not implemented - tests are documentation for now")

	// Example future implementation:
	// 1. Create test database: wolverix_test
	// 2. Run migrations
	// 3. Return connection pool
	// 4. Cleanup function drops test data

	return nil, func() {}
}

// Create a test game session with specified number of players
func createTestGameSession(t *testing.T, db *pgxpool.Pool, playerCount int) uuid.UUID {
	ctx := context.Background()
	sessionID := uuid.New()
	roomID := uuid.New()

	// Create room
	_, err := db.Exec(ctx, `
		INSERT INTO rooms (id, room_code, name, host_user_id, max_players, current_players, status)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
	`, roomID, "TEST", "Test Room", uuid.New(), playerCount, playerCount, models.RoomStatusPlaying)
	if err != nil {
		t.Fatalf("Failed to create test room: %v", err)
	}

	// Create game session
	now := time.Now()
	phaseEndsAt := now.Add(2 * time.Minute)
	initialState := models.GameState{
		ActionsRemaining: map[string]int{},
		ActionsCompleted: map[string]bool{},
		RevealedRoles:    map[string]string{},
		WerewolfVotes:    map[string]int{},
		LynchVotes:       map[string]int{},
	}
	stateJSON, _ := json.Marshal(initialState)

	werewolfCount := 2
	villagerCount := playerCount - 2 - 4 // Subtract werewolves and special roles

	_, err = db.Exec(ctx, `
		INSERT INTO game_sessions (
			id, room_id, status, current_phase, phase_number, day_number,
			phase_started_at, phase_ends_at, state, werewolves_alive, villagers_alive
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
	`, sessionID, roomID, models.GameStatusActive, models.GamePhaseNight, 1, 0,
		now, phaseEndsAt, stateJSON, werewolfCount, villagerCount)
	if err != nil {
		t.Fatalf("Failed to create test session: %v", err)
	}

	// Create test players with roles
	roles := []models.Role{
		models.RoleWerewolf,
		models.RoleWerewolf,
		models.RoleSeer,
		models.RoleWitch,
		models.RoleCupid,
		models.RoleBodyguard,
	}

	// Add villagers if needed
	for i := len(roles); i < playerCount; i++ {
		roles = append(roles, models.RoleVillager)
	}

	for i := 0; i < playerCount; i++ {
		userID := uuid.New()
		playerID := uuid.New()
		role := roles[i]
		team := models.TeamVillagers
		if role == models.RoleWerewolf {
			team = models.TeamWerewolves
		}

		roleState := models.RoleState{}
		roleStateJSON, _ := json.Marshal(roleState)

		_, err = db.Exec(ctx, `
			INSERT INTO game_players (
				id, session_id, user_id, role, team, is_alive,
				role_state, current_voice_channel, seat_position
			) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
		`, playerID, sessionID, userID, role, team, true, roleStateJSON, "main", i)
		if err != nil {
			t.Fatalf("Failed to create test player: %v", err)
		}
	}

	return sessionID
}

// Get all players for a session
func getTestPlayers(t *testing.T, db *pgxpool.Pool, sessionID uuid.UUID) []models.GamePlayer {
	ctx := context.Background()
	rows, err := db.Query(ctx, `
		SELECT id, session_id, user_id, role, team, is_alive, role_state, lover_id, seat_position
		FROM game_players
		WHERE session_id = $1
		ORDER BY seat_position
	`, sessionID)
	if err != nil {
		t.Fatalf("Failed to get players: %v", err)
	}
	defer rows.Close()

	var players []models.GamePlayer
	for rows.Next() {
		var p models.GamePlayer
		var roleStateJSON json.RawMessage
		var loverID *uuid.UUID

		err := rows.Scan(&p.ID, &p.SessionID, &p.UserID, &p.Role, &p.Team,
			&p.IsAlive, &roleStateJSON, &loverID, &p.SeatPosition)
		if err != nil {
			t.Fatalf("Failed to scan player: %v", err)
		}

		json.Unmarshal(roleStateJSON, &p.RoleState)
		p.LoverID = loverID
		players = append(players, p)
	}

	return players
}

// Get a specific player by user ID
func getPlayerByUserID(t *testing.T, db *pgxpool.Pool, sessionID, userID uuid.UUID) *models.GamePlayer {
	ctx := context.Background()
	var p models.GamePlayer
	var roleStateJSON json.RawMessage
	var loverID *uuid.UUID

	err := db.QueryRow(ctx, `
		SELECT id, session_id, user_id, role, team, is_alive, role_state, lover_id, seat_position
		FROM game_players
		WHERE session_id = $1 AND user_id = $2
	`, sessionID, userID).Scan(&p.ID, &p.SessionID, &p.UserID, &p.Role, &p.Team,
		&p.IsAlive, &roleStateJSON, &loverID, &p.SeatPosition)
	if err != nil {
		t.Fatalf("Failed to get player: %v", err)
	}

	json.Unmarshal(roleStateJSON, &p.RoleState)
	p.LoverID = loverID
	return &p
}

// Get game session
func getGameSession(t *testing.T, db *pgxpool.Pool, sessionID uuid.UUID) *models.GameSession {
	ctx := context.Background()
	var session models.GameSession
	var stateJSON json.RawMessage

	err := db.QueryRow(ctx, `
		SELECT id, room_id, status, current_phase, phase_number, day_number,
		       phase_started_at, phase_ends_at, state, werewolves_alive, villagers_alive
		FROM game_sessions WHERE id = $1
	`, sessionID).Scan(
		&session.ID, &session.RoomID, &session.Status, &session.CurrentPhase,
		&session.PhaseNumber, &session.DayNumber, &session.PhaseStartedAt,
		&session.PhaseEndsAt, &stateJSON, &session.WerewolvesAlive, &session.VillagersAlive,
	)
	if err != nil {
		t.Fatalf("Failed to get session: %v", err)
	}

	json.Unmarshal(stateJSON, &session.State)
	return &session
}

// Make two players lovers
func makeLovers(t *testing.T, db *pgxpool.Pool, sessionID, player1ID, player2ID uuid.UUID) {
	ctx := context.Background()

	_, err := db.Exec(ctx, `
		UPDATE game_players 
		SET lover_id = $1, team = $2
		WHERE session_id = $3 AND id = $4
	`, player2ID, models.TeamLovers, sessionID, player1ID)
	if err != nil {
		t.Fatalf("Failed to set lover 1: %v", err)
	}

	_, err = db.Exec(ctx, `
		UPDATE game_players 
		SET lover_id = $1, team = $2
		WHERE session_id = $3 AND id = $4
	`, player1ID, models.TeamLovers, sessionID, player2ID)
	if err != nil {
		t.Fatalf("Failed to set lover 2: %v", err)
	}
}

// Kill a player
func killPlayer(t *testing.T, db *pgxpool.Pool, sessionID, playerID uuid.UUID) {
	ctx := context.Background()
	_, err := db.Exec(ctx, `
		UPDATE game_players
		SET is_alive = false, died_at_phase = 1, death_reason = 'test_kill'
		WHERE session_id = $1 AND id = $2
	`, sessionID, playerID)
	if err != nil {
		t.Fatalf("Failed to kill player: %v", err)
	}
}

// Set phase_ends_at for scheduler tests
func setPhaseEndsAt(t *testing.T, db *pgxpool.Pool, sessionID uuid.UUID, endsAt time.Time) {
	ctx := context.Background()
	_, err := db.Exec(ctx, `
		UPDATE game_sessions
		SET phase_ends_at = $1
		WHERE id = $2
	`, endsAt, sessionID)
	if err != nil {
		t.Fatalf("Failed to set phase_ends_at: %v", err)
	}
}

// Record action helper functions
func recordWerewolfVote(t *testing.T, db *pgxpool.Pool, sessionID uuid.UUID, phaseNumber int, targetID uuid.UUID) {
	ctx := context.Background()
	actionData := models.ActionData{Result: "voted"}
	actionDataJSON, _ := json.Marshal(actionData)

	_, err := db.Exec(ctx, `
		INSERT INTO game_actions (id, session_id, player_id, phase_number, action_type, target_player_id, action_data)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
	`, uuid.New(), sessionID, uuid.New(), phaseNumber, models.ActionWerewolfVote, targetID, actionDataJSON)
	if err != nil {
		t.Fatalf("Failed to record werewolf vote: %v", err)
	}
}

func recordBodyguardProtect(t *testing.T, db *pgxpool.Pool, sessionID uuid.UUID, phaseNumber int, bodyguardID, targetID uuid.UUID) {
	ctx := context.Background()
	actionData := models.ActionData{Result: "protected"}
	actionDataJSON, _ := json.Marshal(actionData)

	_, err := db.Exec(ctx, `
		INSERT INTO game_actions (id, session_id, player_id, phase_number, action_type, target_player_id, action_data)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
	`, uuid.New(), sessionID, bodyguardID, phaseNumber, models.ActionBodyguard, targetID, actionDataJSON)
	if err != nil {
		t.Fatalf("Failed to record bodyguard protect: %v", err)
	}
}

func recordWitchHeal(t *testing.T, db *pgxpool.Pool, sessionID uuid.UUID, phaseNumber int, witchID uuid.UUID) {
	ctx := context.Background()
	actionData := models.ActionData{Result: "healed"}
	actionDataJSON, _ := json.Marshal(actionData)

	_, err := db.Exec(ctx, `
		INSERT INTO game_actions (id, session_id, player_id, phase_number, action_type, action_data)
		VALUES ($1, $2, $3, $4, $5, $6)
	`, uuid.New(), sessionID, witchID, phaseNumber, models.ActionWitchHeal, actionDataJSON)
	if err != nil {
		t.Fatalf("Failed to record witch heal: %v", err)
	}
}

func recordWitchPoison(t *testing.T, db *pgxpool.Pool, sessionID uuid.UUID, phaseNumber int, witchID, targetID uuid.UUID) {
	ctx := context.Background()
	actionData := models.ActionData{Result: "poisoned"}
	actionDataJSON, _ := json.Marshal(actionData)

	_, err := db.Exec(ctx, `
		INSERT INTO game_actions (id, session_id, player_id, phase_number, action_type, target_player_id, action_data)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
	`, uuid.New(), sessionID, witchID, phaseNumber, models.ActionWitchPoison, targetID, actionDataJSON)
	if err != nil {
		t.Fatalf("Failed to record witch poison: %v", err)
	}
}

func lynchPlayer(t *testing.T, db *pgxpool.Pool, sessionID, playerID uuid.UUID, phaseNumber int) {
	ctx := context.Background()
	_, err := db.Exec(ctx, `
		UPDATE game_players
		SET is_alive = false, died_at_phase = $1, death_reason = 'lynched'
		WHERE session_id = $2 AND id = $3
	`, phaseNumber, sessionID, playerID)
	if err != nil {
		t.Fatalf("Failed to lynch player: %v", err)
	}
}

func setLastLynchedPlayer(t *testing.T, db *pgxpool.Pool, sessionID, playerID uuid.UUID) {
	ctx := context.Background()
	_, err := db.Exec(ctx, `
		UPDATE game_sessions
		SET state = jsonb_set(state, '{last_lynched_player}', to_jsonb($1::text))
		WHERE id = $2
	`, playerID.String(), sessionID)
	if err != nil {
		t.Fatalf("Failed to set last lynched player: %v", err)
	}
}

func updateAliveCounts(t *testing.T, db *pgxpool.Pool, sessionID uuid.UUID, werewolves, villagers int) {
	ctx := context.Background()
	_, err := db.Exec(ctx, `
		UPDATE game_sessions
		SET werewolves_alive = $1, villagers_alive = $2
		WHERE id = $3
	`, werewolves, villagers, sessionID)
	if err != nil {
		t.Fatalf("Failed to update alive counts: %v", err)
	}
}

// Get database connection string from environment
func getTestDBConnectionString() string {
	host := os.Getenv("TEST_DB_HOST")
	if host == "" {
		host = "localhost"
	}

	port := os.Getenv("TEST_DB_PORT")
	if port == "" {
		port = "5432"
	}

	user := os.Getenv("TEST_DB_USER")
	if user == "" {
		user = "wolverix"
	}

	password := os.Getenv("TEST_DB_PASSWORD")
	if password == "" {
		password = "wolverix_password"
	}

	dbname := os.Getenv("TEST_DB_NAME")
	if dbname == "" {
		dbname = "wolverix_test"
	}

	return fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=disable",
		host, port, user, password, dbname)
}
