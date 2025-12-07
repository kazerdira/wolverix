package game

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/yourusername/werewolf-voice/internal/models"
)

// ProcessAction processes a player's action during their phase
func (e *Engine) ProcessAction(ctx context.Context, sessionID, playerID uuid.UUID, action models.GameActionRequest) error {
	tx, err := e.db.Begin(ctx)
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	// Get current session state
	var session models.GameSession
	var stateJSON json.RawMessage
	err = tx.QueryRow(ctx, `
		SELECT id, current_phase, phase_number, state, status
		FROM game_sessions WHERE id = $1 AND status = 'active'
	`, sessionID).Scan(&session.ID, &session.CurrentPhase, &session.PhaseNumber, &stateJSON, &session.Status)
	if err != nil {
		return fmt.Errorf("session not found or not active: %w", err)
	}

	if err := json.Unmarshal(stateJSON, &session.State); err != nil {
		return fmt.Errorf("failed to parse session state: %w", err)
	}

	// Get player info
	var player models.GamePlayer
	var roleStateJSON json.RawMessage
	err = tx.QueryRow(ctx, `
		SELECT id, user_id, role, team, is_alive, role_state
		FROM game_players WHERE session_id = $1 AND user_id = $2
	`, sessionID, playerID).Scan(&player.ID, &player.UserID, &player.Role, &player.Team, &player.IsAlive, &roleStateJSON)
	if err != nil {
		return fmt.Errorf("player not found in session: %w", err)
	}

	if err := json.Unmarshal(roleStateJSON, &player.RoleState); err != nil {
		return fmt.Errorf("failed to parse role state: %w", err)
	}

	// Validate player can perform action
	if !player.IsAlive {
		return fmt.Errorf("dead players cannot perform actions")
	}

	// Process action based on type
	switch action.ActionType {
	case models.ActionWerewolfVote:
		if err := e.processWerewolfVote(ctx, tx, &session, &player, action.TargetID); err != nil {
			return err
		}
	case models.ActionSeerDivine:
		if err := e.processSeerDivine(ctx, tx, &session, &player, action.TargetID); err != nil {
			return err
		}
	case models.ActionWitchHeal:
		if err := e.processWitchHeal(ctx, tx, &session, &player); err != nil {
			return err
		}
	case models.ActionWitchPoison:
		if err := e.processWitchPoison(ctx, tx, &session, &player, action.TargetID); err != nil {
			return err
		}
	case models.ActionBodyguard:
		if err := e.processBodyguardProtect(ctx, tx, &session, &player, action.TargetID); err != nil {
			return err
		}
	case models.ActionCupidChoose:
		if err := e.processCupidChoose(ctx, tx, &session, &player, action.TargetID, action.Data); err != nil {
			return err
		}
	case models.ActionVoteLynch:
		if err := e.processLynchVote(ctx, tx, &session, &player, action.TargetID); err != nil {
			return err
		}
	default:
		return fmt.Errorf("unknown action type: %s", action.ActionType)
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("failed to commit transaction: %w", err)
	}

	return nil
}

func (e *Engine) processWerewolfVote(ctx context.Context, tx interface{ Exec(context.Context, string, ...interface{}) (interface{}, error) }, 
	session *models.GameSession, player *models.GamePlayer, targetID *uuid.UUID) error {
	
	if player.Role != models.RoleWerewolf {
		return fmt.Errorf("only werewolves can vote for kills")
	}

	if session.CurrentPhase != models.GamePhaseNight {
		return fmt.Errorf("werewolf votes only during night phase")
	}

	if targetID == nil {
		return fmt.Errorf("target is required for werewolf vote")
	}

	// Record the vote
	actionData := models.ActionData{Result: "voted"}
	actionDataJSON, _ := json.Marshal(actionData)
	
	_, err := tx.Exec(ctx, `
		INSERT INTO game_actions (id, session_id, player_id, phase_number, action_type, target_player_id, action_data)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
	`, uuid.New(), session.ID, player.ID, session.PhaseNumber, models.ActionWerewolfVote, targetID, actionDataJSON)
	
	return err
}

func (e *Engine) processSeerDivine(ctx context.Context, tx interface{ Exec(context.Context, string, ...interface{}) (interface{}, error); QueryRow(context.Context, string, ...interface{}) interface{ Scan(...interface{}) error } },
	session *models.GameSession, player *models.GamePlayer, targetID *uuid.UUID) error {
	
	if player.Role != models.RoleSeer {
		return fmt.Errorf("only seer can divine")
	}

	if session.CurrentPhase != models.GamePhaseNight {
		return fmt.Errorf("seer can only divine during night")
	}

	if targetID == nil {
		return fmt.Errorf("target is required for divine")
	}

	// Check if already divined this phase
	var count int
	err := tx.QueryRow(ctx, `
		SELECT COUNT(*) FROM game_actions 
		WHERE session_id = $1 AND player_id = $2 AND phase_number = $3 AND action_type = $4
	`, session.ID, player.ID, session.PhaseNumber, models.ActionSeerDivine).Scan(&count)
	if err != nil {
		return err
	}
	if count > 0 {
		return fmt.Errorf("seer already divined this night")
	}

	// Get target's role
	var targetRole models.Role
	err = tx.QueryRow(ctx, `
		SELECT role FROM game_players WHERE session_id = $1 AND id = $2
	`, session.ID, targetID).Scan(&targetRole)
	if err != nil {
		return fmt.Errorf("target not found: %w", err)
	}

	isWerewolf := targetRole == models.RoleWerewolf
	result := "not_werewolf"
	if isWerewolf {
		result = "werewolf"
	}

	actionData := models.ActionData{Result: result}
	actionDataJSON, _ := json.Marshal(actionData)
	
	_, err = tx.Exec(ctx, `
		INSERT INTO game_actions (id, session_id, player_id, phase_number, action_type, target_player_id, action_data)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
	`, uuid.New(), session.ID, player.ID, session.PhaseNumber, models.ActionSeerDivine, targetID, actionDataJSON)
	
	return err
}

func (e *Engine) processWitchHeal(ctx context.Context, tx interface{ Exec(context.Context, string, ...interface{}) (interface{}, error) },
	session *models.GameSession, player *models.GamePlayer) error {
	
	if player.Role != models.RoleWitch {
		return fmt.Errorf("only witch can heal")
	}

	if player.RoleState.HealUsed {
		return fmt.Errorf("heal potion already used")
	}

	if session.State.LastKilledPlayer == nil {
		return fmt.Errorf("no one to heal")
	}

	// Mark heal as used
	player.RoleState.HealUsed = true
	roleStateJSON, _ := json.Marshal(player.RoleState)
	
	_, err := tx.Exec(ctx, `
		UPDATE game_players SET role_state = $1 WHERE id = $2
	`, roleStateJSON, player.ID)
	if err != nil {
		return err
	}

	actionData := models.ActionData{Result: "healed"}
	actionDataJSON, _ := json.Marshal(actionData)
	
	_, err = tx.Exec(ctx, `
		INSERT INTO game_actions (id, session_id, player_id, phase_number, action_type, target_player_id, action_data)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
	`, uuid.New(), session.ID, player.ID, session.PhaseNumber, models.ActionWitchHeal, session.State.LastKilledPlayer, actionDataJSON)
	
	return err
}

func (e *Engine) processWitchPoison(ctx context.Context, tx interface{ Exec(context.Context, string, ...interface{}) (interface{}, error) },
	session *models.GameSession, player *models.GamePlayer, targetID *uuid.UUID) error {
	
	if player.Role != models.RoleWitch {
		return fmt.Errorf("only witch can poison")
	}

	if player.RoleState.PoisonUsed {
		return fmt.Errorf("poison already used")
	}

	if targetID == nil {
		return fmt.Errorf("target is required for poison")
	}

	player.RoleState.PoisonUsed = true
	roleStateJSON, _ := json.Marshal(player.RoleState)
	
	_, err := tx.Exec(ctx, `
		UPDATE game_players SET role_state = $1 WHERE id = $2
	`, roleStateJSON, player.ID)
	if err != nil {
		return err
	}

	actionData := models.ActionData{Result: "poisoned"}
	actionDataJSON, _ := json.Marshal(actionData)
	
	_, err = tx.Exec(ctx, `
		INSERT INTO game_actions (id, session_id, player_id, phase_number, action_type, target_player_id, action_data)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
	`, uuid.New(), session.ID, player.ID, session.PhaseNumber, models.ActionWitchPoison, targetID, actionDataJSON)
	
	return err
}

func (e *Engine) processBodyguardProtect(ctx context.Context, tx interface{ Exec(context.Context, string, ...interface{}) (interface{}, error) },
	session *models.GameSession, player *models.GamePlayer, targetID *uuid.UUID) error {
	
	if player.Role != models.RoleBodyguard {
		return fmt.Errorf("only bodyguard can protect")
	}

	if targetID == nil {
		return fmt.Errorf("target is required for protection")
	}

	// Check if protected same player last night (optional rule)
	if player.RoleState.LastProtected != nil && *player.RoleState.LastProtected == *targetID {
		return fmt.Errorf("cannot protect same player two nights in a row")
	}

	player.RoleState.LastProtected = targetID
	roleStateJSON, _ := json.Marshal(player.RoleState)
	
	_, err := tx.Exec(ctx, `
		UPDATE game_players SET role_state = $1 WHERE id = $2
	`, roleStateJSON, player.ID)
	if err != nil {
		return err
	}

	actionData := models.ActionData{Result: "protected"}
	actionDataJSON, _ := json.Marshal(actionData)
	
	_, err = tx.Exec(ctx, `
		INSERT INTO game_actions (id, session_id, player_id, phase_number, action_type, target_player_id, action_data)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
	`, uuid.New(), session.ID, player.ID, session.PhaseNumber, models.ActionBodyguard, targetID, actionDataJSON)
	
	return err
}

func (e *Engine) processCupidChoose(ctx context.Context, tx interface{ Exec(context.Context, string, ...interface{}) (interface{}, error) },
	session *models.GameSession, player *models.GamePlayer, targetID *uuid.UUID, data interface{}) error {
	
	if player.Role != models.RoleCupid {
		return fmt.Errorf("only cupid can choose lovers")
	}

	if player.RoleState.HasChosen {
		return fmt.Errorf("lovers already chosen")
	}

	if targetID == nil {
		return fmt.Errorf("first lover is required")
	}

	// Extract second lover from data
	dataMap, ok := data.(map[string]interface{})
	if !ok {
		return fmt.Errorf("invalid data format")
	}
	
	secondLoverStr, ok := dataMap["second_lover"].(string)
	if !ok {
		return fmt.Errorf("second lover is required")
	}

	secondLoverID, err := uuid.Parse(secondLoverStr)
	if err != nil {
		return fmt.Errorf("invalid second lover ID: %w", err)
	}

	// Set both players as lovers
	_, err = tx.Exec(ctx, `
		UPDATE game_players SET lover_id = $1 WHERE session_id = $2 AND id = $3
	`, secondLoverID, session.ID, targetID)
	if err != nil {
		return err
	}

	_, err = tx.Exec(ctx, `
		UPDATE game_players SET lover_id = $1 WHERE session_id = $2 AND id = $3
	`, targetID, session.ID, secondLoverID)
	if err != nil {
		return err
	}

	player.RoleState.HasChosen = true
	roleStateJSON, _ := json.Marshal(player.RoleState)
	
	_, err = tx.Exec(ctx, `
		UPDATE game_players SET role_state = $1 WHERE id = $2
	`, roleStateJSON, player.ID)
	if err != nil {
		return err
	}

	actionData := models.ActionData{SecondLover: &secondLoverID, Result: "lovers_chosen"}
	actionDataJSON, _ := json.Marshal(actionData)
	
	_, err = tx.Exec(ctx, `
		INSERT INTO game_actions (id, session_id, player_id, phase_number, action_type, target_player_id, action_data)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
	`, uuid.New(), session.ID, player.ID, session.PhaseNumber, models.ActionCupidChoose, targetID, actionDataJSON)
	
	return err
}

func (e *Engine) processLynchVote(ctx context.Context, tx interface{ Exec(context.Context, string, ...interface{}) (interface{}, error) },
	session *models.GameSession, player *models.GamePlayer, targetID *uuid.UUID) error {
	
	if session.CurrentPhase != models.GamePhaseVoting {
		return fmt.Errorf("can only vote during voting phase")
	}

	if targetID == nil {
		return fmt.Errorf("target is required for lynch vote")
	}

	// Record vote
	actionData := models.ActionData{Result: "voted"}
	actionDataJSON, _ := json.Marshal(actionData)
	
	_, err := tx.Exec(ctx, `
		INSERT INTO game_actions (id, session_id, player_id, phase_number, action_type, target_player_id, action_data)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		ON CONFLICT DO NOTHING
	`, uuid.New(), session.ID, player.ID, session.PhaseNumber, models.ActionVoteLynch, targetID, actionDataJSON)
	
	return err
}

// CheckPhaseCompletion checks if all required actions for current phase are complete
func (e *Engine) CheckPhaseCompletion(ctx context.Context, sessionID uuid.UUID) (bool, error) {
	// Get session state
	var currentPhase models.GamePhase
	var stateJSON json.RawMessage
	
	err := e.db.QueryRow(ctx, `
		SELECT current_phase, state FROM game_sessions WHERE id = $1
	`, sessionID).Scan(&currentPhase, &stateJSON)
	if err != nil {
		return false, err
	}

	var state models.GameState
	if err := json.Unmarshal(stateJSON, &state); err != nil {
		return false, err
	}

	// Check if actions remaining is empty
	if len(state.ActionsRemaining) == 0 {
		return true, nil
	}

	// Timeout check can be added here
	return false, nil
}
