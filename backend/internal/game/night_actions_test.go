package game

import (
	"context"
	"testing"

	"github.com/kazerdira/wolverix/backend/internal/models"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestNightActionOrder tests that night actions are resolved in correct order
func TestNightActionOrder_BodyguardProtectsBeforeWitch(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()

	coordinator := NewNightCoordinator(db)
	ctx := context.Background()

	// Setup: Werewolves vote for Player A, Bodyguard protects Player A, Witch wants to heal
	sessionID := createTestGameSession(t, db, 8)
	players := getTestPlayers(t, db, sessionID)

	var targetPlayer, bodyguardPlayer, witchPlayer models.GamePlayer
	for _, p := range players {
		if p.Role == models.RoleVillager {
			targetPlayer = p
		} else if p.Role == models.RoleBodyguard {
			bodyguardPlayer = p
		} else if p.Role == models.RoleWitch {
			witchPlayer = p
		}
	}

	phaseNumber := 1

	// Record actions in database
	recordWerewolfVote(t, db, sessionID, phaseNumber, targetPlayer.ID)
	recordBodyguardProtect(t, db, sessionID, phaseNumber, bodyguardPlayer.ID, targetPlayer.ID)
	recordWitchHeal(t, db, sessionID, phaseNumber, witchPlayer.ID)

	// Process night actions
	result, err := coordinator.ProcessNightActions(ctx, sessionID)
	require.NoError(t, err)

	// Verify: Target is protected by bodyguard, so NOT killed
	assert.Equal(t, targetPlayer.ID, *result.WerewolfTarget, "Werewolves targeted player")
	assert.True(t, result.IsProtected, "Player should be protected by bodyguard")

	// CRITICAL: Witch heal should NOT apply because bodyguard already protected
	assert.False(t, result.IsHealed, "Witch heal should not apply when bodyguard protects")

	// In death resolution, target should survive
}

// TestNightActionOrder_WitchHealsWithoutBodyguard tests witch can heal when no bodyguard
func TestNightActionOrder_WitchHealsWithoutBodyguard(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()

	coordinator := NewNightCoordinator(db)
	ctx := context.Background()

	sessionID := createTestGameSession(t, db, 8)
	players := getTestPlayers(t, db, sessionID)

	var targetPlayer, witchPlayer models.GamePlayer
	for _, p := range players {
		if p.Role == models.RoleVillager {
			targetPlayer = p
		} else if p.Role == models.RoleWitch {
			witchPlayer = p
		}
	}

	phaseNumber := 1

	// Record actions: Werewolves vote for target, Witch heals (no bodyguard)
	recordWerewolfVote(t, db, sessionID, phaseNumber, targetPlayer.ID)
	recordWitchHeal(t, db, sessionID, phaseNumber, witchPlayer.ID)

	// Process night actions
	result, err := coordinator.ProcessNightActions(ctx, sessionID)
	require.NoError(t, err)

	// Verify: Target is NOT protected but IS healed
	assert.Equal(t, targetPlayer.ID, *result.WerewolfTarget, "Werewolves targeted player")
	assert.False(t, result.IsProtected, "Player should NOT be protected")
	assert.True(t, result.IsHealed, "Player should be healed by witch")

	// In death resolution, target should survive due to witch heal
}

// TestNightActionOrder_PoisonOverridesProtection tests poison always kills
func TestNightActionOrder_PoisonAlwaysKills(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()

	coordinator := NewNightCoordinator(db)
	ctx := context.Background()

	sessionID := createTestGameSession(t, db, 8)
	players := getTestPlayers(t, db, sessionID)

	var targetPlayer, bodyguardPlayer, witchPlayer models.GamePlayer
	for _, p := range players {
		if p.Role == models.RoleVillager {
			targetPlayer = p
		} else if p.Role == models.RoleBodyguard {
			bodyguardPlayer = p
		} else if p.Role == models.RoleWitch {
			witchPlayer = p
		}
	}

	phaseNumber := 1

	// Bodyguard protects target, but Witch poisons target
	recordBodyguardProtect(t, db, sessionID, phaseNumber, bodyguardPlayer.ID, targetPlayer.ID)
	recordWitchPoison(t, db, sessionID, phaseNumber, witchPlayer.ID, targetPlayer.ID)

	// Process night actions
	result, err := coordinator.ProcessNightActions(ctx, sessionID)
	require.NoError(t, err)

	// Verify: Poison target is set (bodyguard protection doesn't matter)
	assert.Equal(t, targetPlayer.ID, *result.PoisonTarget, "Witch poisoned target")

	// In death resolution, target should die from poison regardless of protection
}

// TestNightActionOrder_SimultaneousDeaths tests when multiple players die same night
func TestNightActionOrder_WerewolfKillAndPoisonDifferentTargets(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()

	coordinator := NewNightCoordinator(db)
	ctx := context.Background()

	sessionID := createTestGameSession(t, db, 8)
	players := getTestPlayers(t, db, sessionID)

	target1 := players[0]
	target2 := players[1]
	witchPlayer := players[2]

	phaseNumber := 1

	// Werewolves kill target1, Witch poisons target2
	recordWerewolfVote(t, db, sessionID, phaseNumber, target1.ID)
	recordWitchPoison(t, db, sessionID, phaseNumber, witchPlayer.ID, target2.ID)

	// Process night actions
	result, err := coordinator.ProcessNightActions(ctx, sessionID)
	require.NoError(t, err)

	// Verify: Both targets should be marked for death
	assert.Equal(t, target1.ID, *result.WerewolfTarget, "Werewolves targeted player 1")
	assert.Equal(t, target2.ID, *result.PoisonTarget, "Witch poisoned player 2")
	assert.False(t, result.IsProtected, "No protection")
	assert.False(t, result.IsHealed, "No heal")

	// In death resolution, BOTH should die
}

// TestNightPhaseComplete tests that night phase doesn't complete until all actions done
func TestNightPhaseComplete_WaitsForAllActions(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()

	coordinator := NewNightCoordinator(db)
	ctx := context.Background()

	sessionID := createTestGameSession(t, db, 8)

	// Initially, night is NOT complete
	complete, err := coordinator.IsNightPhaseComplete(ctx, sessionID)
	require.NoError(t, err)
	assert.False(t, complete, "Night should not be complete initially")

	// TODO: Mark actions as complete and verify
}

// TestNightPhaseComplete_SkipsDeadPlayers tests that dead players don't block night phase
func TestNightPhaseComplete_SkipsDeadPlayers(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()

	coordinator := NewNightCoordinator(db)
	ctx := context.Background()

	sessionID := createTestGameSession(t, db, 8)
	players := getTestPlayers(t, db, sessionID)

	// Kill the seer
	var seerPlayer models.GamePlayer
	for _, p := range players {
		if p.Role == models.RoleSeer {
			seerPlayer = p
			break
		}
	}
	killPlayer(t, db, sessionID, seerPlayer.ID)

	// Check if night can complete even though seer didn't act (because they're dead)
	// TODO: Implement logic to remove dead players from actions_remaining
	complete, err := coordinator.IsNightPhaseComplete(ctx, sessionID)
	require.NoError(t, err)

	// Should be able to complete without seer action since they're dead
	t.Log("Night phase complete:", complete)
}

// All helper functions are in test_helpers.go
