package game

import (
	"context"
	"testing"

	"github.com/google/uuid"
	"github.com/kazerdira/wolverix/backend/internal/models"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestWinCondition_TannerWins tests that Tanner wins when lynched
func TestWinCondition_TannerWinsWhenLynched(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()

	winChecker := NewWinChecker(db)
	ctx := context.Background()

	sessionID := createTestGameSession(t, db, 6)
	players := getTestPlayers(t, db, sessionID)

	// Find tanner
	var tannerID uuid.UUID
	for _, p := range players {
		if p.Role == models.RoleTanner {
			tannerID = p.ID
			break
		}
	}
	require.NotEqual(t, uuid.Nil, tannerID, "Should have a tanner")

	// Lynch the tanner
	lynchPlayer(t, db, sessionID, tannerID, 1)
	setLastLynchedPlayer(t, db, sessionID, tannerID)

	// Check win condition
	winCondition, err := winChecker.CheckWinConditions(ctx, sessionID)
	require.NoError(t, err)

	// Tanner should win
	assert.True(t, winCondition.GameEnded, "Game should end")
	assert.Equal(t, WinTypeTannerLynched, winCondition.WinType)
	assert.Equal(t, models.TeamNeutral, *winCondition.WinningTeam)
	assert.Contains(t, winCondition.Winners, tannerID)
}

// TestWinCondition_TannerDoesNotWinIfKilledAtNight tests that Tanner must be LYNCHED to win
func TestWinCondition_TannerDoesNotWinIfKilledAtNight(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()

	winChecker := NewWinChecker(db)
	ctx := context.Background()

	sessionID := createTestGameSession(t, db, 6)
	players := getTestPlayers(t, db, sessionID)

	// Find tanner
	var tannerID uuid.UUID
	for _, p := range players {
		if p.Role == models.RoleTanner {
			tannerID = p.ID
			break
		}
	}

	// Kill tanner at night (not lynched)
	killPlayer(t, db, sessionID, tannerID)

	// Check win condition
	winCondition, err := winChecker.CheckWinConditions(ctx, sessionID)
	require.NoError(t, err)

	// Tanner should NOT win
	assert.False(t, winCondition.GameEnded || winCondition.WinType == WinTypeTannerLynched,
		"Tanner should not win when killed at night")
}

// TestWinCondition_LoversWin tests lovers victory
func TestWinCondition_LoversWinWhenLastTwo(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()

	winChecker := NewWinChecker(db)
	ctx := context.Background()

	sessionID := createTestGameSession(t, db, 6)
	players := getTestPlayers(t, db, sessionID)

	// Make first 2 players lovers
	lover1 := players[0]
	lover2 := players[1]
	makeLovers(t, db, sessionID, lover1.ID, lover2.ID)

	// Kill everyone else
	for i := 2; i < len(players); i++ {
		killPlayer(t, db, sessionID, players[i].ID)
	}

	// Check win condition
	winCondition, err := winChecker.CheckWinConditions(ctx, sessionID)
	require.NoError(t, err)

	// Lovers should win
	assert.True(t, winCondition.GameEnded, "Game should end")
	assert.Equal(t, WinTypeLoversVictory, winCondition.WinType)
	assert.Len(t, winCondition.Winners, 2)
}

// TestWinCondition_WerewolvesWinAtParity tests werewolves win at parity
func TestWinCondition_WerewolvesWinAtParity(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()

	winChecker := NewWinChecker(db)
	ctx := context.Background()

	sessionID := createTestGameSession(t, db, 6) // 2 werewolves, 4 villagers
	players := getTestPlayers(t, db, sessionID)

	// Kill villagers until 2 werewolves = 2 villagers
	villagersKilled := 0
	for _, p := range players {
		if p.Team == models.TeamVillagers && villagersKilled < 2 {
			killPlayer(t, db, sessionID, p.ID)
			villagersKilled++
		}
	}

	// Update alive counts
	updateAliveCounts(t, db, sessionID, 2, 2)

	// Check win condition
	winCondition, err := winChecker.CheckWinConditions(ctx, sessionID)
	require.NoError(t, err)

	// Werewolves should win at parity
	assert.True(t, winCondition.GameEnded, "Game should end at parity")
	assert.Equal(t, WinTypeWerewolvesParity, winCondition.WinType)
	assert.Equal(t, models.TeamWerewolves, *winCondition.WinningTeam)
}

// TestWinCondition_VillagersWin tests villagers win when all werewolves dead
func TestWinCondition_VillagersWinWhenAllWerewolvesDead(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()

	winChecker := NewWinChecker(db)
	ctx := context.Background()

	sessionID := createTestGameSession(t, db, 6)
	players := getTestPlayers(t, db, sessionID)

	// Kill all werewolves
	for _, p := range players {
		if p.Team == models.TeamWerewolves {
			killPlayer(t, db, sessionID, p.ID)
		}
	}

	// Update alive counts
	updateAliveCounts(t, db, sessionID, 0, 4)

	// Check win condition
	winCondition, err := winChecker.CheckWinConditions(ctx, sessionID)
	require.NoError(t, err)

	// Villagers should win
	assert.True(t, winCondition.GameEnded, "Game should end")
	assert.Equal(t, WinTypeVillagersVictory, winCondition.WinType)
	assert.Equal(t, models.TeamVillagers, *winCondition.WinningTeam)
}

// TestWinCondition_Priority tests that win conditions are checked in correct priority
func TestWinCondition_TannerPriorityOverLovers(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()

	winChecker := NewWinChecker(db)
	ctx := context.Background()

	sessionID := createTestGameSession(t, db, 6)
	players := getTestPlayers(t, db, sessionID)

	// Make 2 players lovers (one is tanner)
	var tannerID, villagerID uuid.UUID
	for _, p := range players {
		if p.Role == models.RoleTanner {
			tannerID = p.ID
		} else if p.Role == models.RoleVillager && villagerID == uuid.Nil {
			villagerID = p.ID
		}
	}
	makeLovers(t, db, sessionID, tannerID, villagerID)

	// Kill everyone except the 2 lovers
	for _, p := range players {
		if p.ID != tannerID && p.ID != villagerID {
			killPlayer(t, db, sessionID, p.ID)
		}
	}

	// Lynch the tanner
	lynchPlayer(t, db, sessionID, tannerID, 1)
	setLastLynchedPlayer(t, db, sessionID, tannerID)

	// Check win condition
	winCondition, err := winChecker.CheckWinConditions(ctx, sessionID)
	require.NoError(t, err)

	// Tanner should win (higher priority than lovers)
	assert.True(t, winCondition.GameEnded)
	assert.Equal(t, WinTypeTannerLynched, winCondition.WinType,
		"Tanner victory should have priority over lovers victory")
}

// All helper functions are in test_helpers.go
