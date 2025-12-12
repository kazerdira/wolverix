package game

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/kazerdira/wolverix/backend/internal/models"
)

// NightCoordinator manages the order and processing of night actions
type NightCoordinator struct {
	db *pgxpool.Pool
}

// NewNightCoordinator creates a new night coordinator
func NewNightCoordinator(db *pgxpool.Pool) *NightCoordinator {
	return &NightCoordinator{db: db}
}

// ProcessNightActions processes all night actions in the correct order
func (nc *NightCoordinator) ProcessNightActions(ctx context.Context, sessionID uuid.UUID) (*NightActionResults, error) {
	// Get current phase number
	var phaseNumber int
	err := nc.db.QueryRow(ctx, `
		SELECT phase_number FROM game_sessions WHERE id = $1
	`, sessionID).Scan(&phaseNumber)
	if err != nil {
		return nil, err
	}

	results := &NightActionResults{}

	// Process actions in correct order:
	// 1. Cupid (first night only) - already processed
	// 2. Werewolves - choose target
	// 3. Seer - divine player (doesn't affect deaths)
	// 4. Bodyguard - protect player
	// 5. Witch - heal or poison

	// COLLECT PHASE: Get all night actions from database
	// Step 1: Get werewolf target (majority vote)
	werewolfTarget, err := nc.getWerewolfTarget(ctx, sessionID, phaseNumber)
	if err != nil {
		return nil, fmt.Errorf("failed to get werewolf target: %w", err)
	}
	results.WerewolfTarget = werewolfTarget

	// Step 2: Get bodyguard protection target
	bodyguardTarget, err := nc.getBodyguardTarget(ctx, sessionID, phaseNumber)
	if err != nil {
		return nil, fmt.Errorf("failed to get bodyguard target: %w", err)
	}

	// Step 3: Get witch actions
	witchHealed, err := nc.getWitchHealTarget(ctx, sessionID, phaseNumber)
	if err != nil {
		return nil, fmt.Errorf("failed to get witch heal: %w", err)
	}

	poisonTarget, err := nc.getPoisonTarget(ctx, sessionID, phaseNumber)
	if err != nil {
		return nil, fmt.Errorf("failed to get poison target: %w", err)
	}
	results.PoisonTarget = poisonTarget

	// RESOLVE PHASE: Apply actions in canonical order
	// Step 4: Check if werewolf target is protected by bodyguard
	results.IsProtected = false
	if werewolfTarget != nil && bodyguardTarget != nil {
		results.IsProtected = (*werewolfTarget == *bodyguardTarget)
	}

	// Step 5: Check if witch healed (witch sees attack regardless of bodyguard protection)
	// But heal only works if bodyguard didn't already protect
	results.IsHealed = false
	if werewolfTarget != nil && witchHealed && !results.IsProtected {
		results.IsHealed = true
	}

	return results, nil
}

// GetRequiredActions returns which roles still need to act this night
func (nc *NightCoordinator) GetRequiredActions(ctx context.Context, sessionID uuid.UUID) ([]models.Role, error) {
	var stateJSON json.RawMessage
	err := nc.db.QueryRow(ctx, `
		SELECT state FROM game_sessions WHERE id = $1
	`, sessionID).Scan(&stateJSON)
	if err != nil {
		return nil, err
	}

	var state models.GameState
	if err := json.Unmarshal(stateJSON, &state); err != nil {
		return nil, err
	}

	// Convert string actions to roles
	var required []models.Role
	for action := range state.ActionsRemaining {
		role := models.Role(action)
		required = append(required, role)
	}

	return required, nil
}

// MarkActionComplete marks a role's action as complete
func (nc *NightCoordinator) MarkActionComplete(ctx context.Context, sessionID uuid.UUID, role models.Role) error {
	// Remove role from actions_remaining map by deleting the key
	_, err := nc.db.Exec(ctx, `
		UPDATE game_sessions
		SET state = jsonb_set(
			state, 
			'{actions_remaining}',
			(state->'actions_remaining') - $2
		)
		WHERE id = $1
	`, sessionID, string(role))
	return err
}

// IsNightPhaseComplete checks if all required night actions are done
func (nc *NightCoordinator) IsNightPhaseComplete(ctx context.Context, sessionID uuid.UUID) (bool, error) {
	var stateJSON json.RawMessage
	err := nc.db.QueryRow(ctx, `
		SELECT state FROM game_sessions WHERE id = $1
	`, sessionID).Scan(&stateJSON)
	if err != nil {
		return false, err
	}

	var state models.GameState
	if err := json.Unmarshal(stateJSON, &state); err != nil {
		return false, err
	}

	// Night is complete when actions_remaining is empty
	return len(state.ActionsRemaining) == 0, nil
}

// Internal helper methods

func (nc *NightCoordinator) getWerewolfTarget(ctx context.Context, sessionID uuid.UUID, phaseNumber int) (*uuid.UUID, error) {
	// Get all werewolf votes for this phase
	rows, err := nc.db.Query(ctx, `
		SELECT target_player_id, COUNT(*) as vote_count
		FROM game_actions
		WHERE session_id = $1 AND phase_number = $2 AND action_type = $3
		GROUP BY target_player_id
		ORDER BY vote_count DESC
		LIMIT 1
	`, sessionID, phaseNumber, models.ActionWerewolfVote)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	if rows.Next() {
		var targetID uuid.UUID
		var count int
		if err := rows.Scan(&targetID, &count); err != nil {
			return nil, err
		}
		return &targetID, nil
	}

	return nil, nil
}

func (nc *NightCoordinator) getBodyguardTarget(ctx context.Context, sessionID uuid.UUID, phaseNumber int) (*uuid.UUID, error) {
	var targetID *uuid.UUID
	err := nc.db.QueryRow(ctx, `
		SELECT target_player_id
		FROM game_actions
		WHERE session_id = $1 AND phase_number = $2 AND action_type = $3
		LIMIT 1
	`, sessionID, phaseNumber, models.ActionBodyguard).Scan(&targetID)
	if err != nil {
		if err.Error() == "no rows in result set" {
			return nil, nil
		}
		return nil, err
	}
	return targetID, nil
}

func (nc *NightCoordinator) getWitchHealTarget(ctx context.Context, sessionID uuid.UUID, phaseNumber int) (bool, error) {
	var count int
	err := nc.db.QueryRow(ctx, `
		SELECT COUNT(*)
		FROM game_actions
		WHERE session_id = $1 AND phase_number = $2 AND action_type = $3
	`, sessionID, phaseNumber, models.ActionWitchHeal).Scan(&count)
	if err != nil {
		return false, err
	}

	// The witch heal is recorded without a target (heals whoever was attacked)
	// We check if heal was used this night
	return count > 0, nil
}

// Deprecated: Use getBodyguardTarget instead
func (nc *NightCoordinator) isProtected(ctx context.Context, sessionID uuid.UUID, phaseNumber int, playerID uuid.UUID) (bool, error) {
	var count int
	err := nc.db.QueryRow(ctx, `
		SELECT COUNT(*)
		FROM game_actions
		WHERE session_id = $1 AND phase_number = $2 AND action_type = $3 AND target_player_id = $4
	`, sessionID, phaseNumber, models.ActionBodyguard, playerID).Scan(&count)
	if err != nil {
		return false, err
	}
	return count > 0, nil
}

// Deprecated: Use getWitchHealTarget instead
func (nc *NightCoordinator) isHealed(ctx context.Context, sessionID uuid.UUID, phaseNumber int, playerID uuid.UUID) (bool, error) {
	var count int
	err := nc.db.QueryRow(ctx, `
		SELECT COUNT(*)
		FROM game_actions
		WHERE session_id = $1 AND phase_number = $2 AND action_type = $3
	`, sessionID, phaseNumber, models.ActionWitchHeal).Scan(&count)
	if err != nil {
		return false, err
	}

	// The witch heal is recorded without a target (heals whoever was attacked)
	// We check if heal was used this night
	return count > 0, nil
}

func (nc *NightCoordinator) getPoisonTarget(ctx context.Context, sessionID uuid.UUID, phaseNumber int) (*uuid.UUID, error) {
	var targetID *uuid.UUID
	err := nc.db.QueryRow(ctx, `
		SELECT target_player_id
		FROM game_actions
		WHERE session_id = $1 AND phase_number = $2 AND action_type = $3
		LIMIT 1
	`, sessionID, phaseNumber, models.ActionWitchPoison).Scan(&targetID)
	if err != nil {
		if err.Error() == "no rows in result set" {
			return nil, nil
		}
		return nil, err
	}
	return targetID, nil
}

// ValidateAction checks if a role can perform an action at this time
func (nc *NightCoordinator) ValidateAction(ctx context.Context, sessionID uuid.UUID, role models.Role) error {
	// Get current phase
	var currentPhase models.GamePhase
	err := nc.db.QueryRow(ctx, `
		SELECT current_phase FROM game_sessions WHERE id = $1
	`, sessionID).Scan(&currentPhase)
	if err != nil {
		return fmt.Errorf("failed to get current phase: %w", err)
	}

	// Most night actions can only happen during night phase (including night_0)
	isNightPhase := currentPhase == models.GamePhaseNight || currentPhase == models.GamePhaseNight0
	if !isNightPhase {
		if role != models.RoleHunter { // Hunter can shoot when they die (any phase)
			return fmt.Errorf("this action can only be performed during night phase (current: %s)", currentPhase)
		}
	}

	// Check if this role's action is still required
	required, err := nc.GetRequiredActions(ctx, sessionID)
	if err != nil {
		return fmt.Errorf("failed to get required actions: %w", err)
	}

	// Check if role is in required list
	found := false
	for _, r := range required {
		if r == role {
			found = true
			break
		}
	}

	if !found && role != models.RoleHunter {
		return fmt.Errorf("this role has already acted this night")
	}

	return nil
}

// GetSeerDivineResult returns the result of a seer's divine action
func (nc *NightCoordinator) GetSeerDivineResult(ctx context.Context, sessionID, playerID uuid.UUID, phaseNumber int) (bool, error) {
	// Get the action data
	var actionDataJSON json.RawMessage
	err := nc.db.QueryRow(ctx, `
		SELECT action_data
		FROM game_actions
		WHERE session_id = $1 AND player_id = $2 AND phase_number = $3 AND action_type = $4
		LIMIT 1
	`, sessionID, playerID, phaseNumber, models.ActionSeerDivine).Scan(&actionDataJSON)
	if err != nil {
		return false, err
	}

	var actionData models.ActionData
	if err := json.Unmarshal(actionDataJSON, &actionData); err != nil {
		return false, err
	}

	return actionData.Result == "werewolf", nil
}
