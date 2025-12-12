package game

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/google/uuid"
	"github.com/kazerdira/wolverix/backend/internal/models"
)

// Action processing methods for the Engine

func (e *Engine) processWerewolfVote(ctx context.Context, sessionID, userID uuid.UUID, targetID *uuid.UUID) error {
	if targetID == nil {
		return fmt.Errorf("target is required for werewolf vote")
	}

	// Get player and verify role
	player, err := e.getPlayerByUserID(ctx, sessionID, userID)
	if err != nil {
		return fmt.Errorf("player not found: %w", err)
	}

	if player.Role != models.RoleWerewolf {
		return fmt.Errorf("invalid action")
	}

	if !player.IsAlive {
		return fmt.Errorf("dead players cannot act")
	}

	// Validate it's night phase (werewolves can change vote, so don't check "already acted")
	var currentPhase models.GamePhase
	err = e.db.QueryRow(ctx, `SELECT current_phase FROM game_sessions WHERE id = $1`, sessionID).Scan(&currentPhase)
	if err != nil {
		return fmt.Errorf("failed to get current phase: %w", err)
	}
	if currentPhase != models.GamePhaseNight && currentPhase != models.GamePhaseNight0 {
		return fmt.Errorf("werewolf vote can only be performed during night phase")
	}

	// Get target player (targetID is game_players.id, not user_id)
	target, err := e.getPlayerByID(ctx, sessionID, *targetID)
	if err != nil {
		return fmt.Errorf("target not found: %w", err)
	}

	if !target.IsAlive {
		return fmt.Errorf("cannot target dead players")
	}

	if target.Team == models.TeamWerewolves {
		return fmt.Errorf("invalid target")
	}

	// Get phase number
	var phaseNumber int
	err = e.db.QueryRow(ctx, `
		SELECT phase_number FROM game_sessions WHERE id = $1
	`, sessionID).Scan(&phaseNumber)
	if err != nil {
		return err
	}

	// Record vote
	actionData := models.ActionData{Result: "voted"}
	actionDataJSON, _ := json.Marshal(actionData)

	_, err = e.db.Exec(ctx, `
		INSERT INTO game_actions (id, session_id, player_id, phase_number, action_type, target_player_id, action_data)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		ON CONFLICT (session_id, player_id, phase_number, action_type) 
		DO UPDATE SET target_player_id = $6, action_data = $7
	`, uuid.New(), sessionID, player.ID, phaseNumber, models.ActionWerewolfVote, target.ID, actionDataJSON)

	if err != nil {
		return err
	}

	// CRITICAL: Update real-time vote tally so Witch can see the current target
	if err := e.updateWerewolfVoteTally(ctx, sessionID, phaseNumber); err != nil {
		// Log but don't fail the action
		fmt.Printf("Warning: failed to update werewolf vote tally: %v\n", err)
	}

	return nil
}

// updateWerewolfVoteTally updates the session state with current werewolf vote counts
// This allows the Witch to see in real-time who is being targeted
func (e *Engine) updateWerewolfVoteTally(ctx context.Context, sessionID uuid.UUID, phaseNumber int) error {
	// Query all werewolf votes for this phase
	rows, err := e.db.Query(ctx, `
		SELECT target_player_id, COUNT(*) 
		FROM game_actions 
		WHERE session_id = $1 AND phase_number = $2 AND action_type = $3
		GROUP BY target_player_id
	`, sessionID, phaseNumber, models.ActionWerewolfVote)
	if err != nil {
		return err
	}
	defer rows.Close()

	voteMap := make(map[string]int)
	for rows.Next() {
		var pid uuid.UUID
		var count int
		if err := rows.Scan(&pid, &count); err != nil {
			continue
		}
		voteMap[pid.String()] = count
	}

	votesJSON, _ := json.Marshal(voteMap)
	_, err = e.db.Exec(ctx, `
		UPDATE game_sessions 
		SET state = jsonb_set(state, '{werewolf_votes}', $1)
		WHERE id = $2
	`, votesJSON, sessionID)
	return err
}

func (e *Engine) processSeerDivine(ctx context.Context, sessionID, userID uuid.UUID, targetID *uuid.UUID) error {
	if targetID == nil {
		return fmt.Errorf("target is required for divine")
	}

	player, err := e.getPlayerByUserID(ctx, sessionID, userID)
	if err != nil {
		return err
	}

	if player.Role != models.RoleSeer {
		return fmt.Errorf("invalid action")
	}

	if !player.IsAlive {
		return fmt.Errorf("dead players cannot act")
	}

	if err := e.nightCoord.ValidateAction(ctx, sessionID, models.RoleSeer); err != nil {
		return err
	}

	var phaseNumber int
	err = e.db.QueryRow(ctx, `
		SELECT phase_number FROM game_sessions WHERE id = $1
	`, sessionID).Scan(&phaseNumber)
	if err != nil {
		return err
	}

	// Check if already divined this phase
	var count int
	err = e.db.QueryRow(ctx, `
		SELECT COUNT(*) FROM game_actions
		WHERE session_id = $1 AND player_id = $2 AND phase_number = $3 AND action_type = $4
	`, sessionID, player.ID, phaseNumber, models.ActionSeerDivine).Scan(&count)
	if err != nil {
		return err
	}
	if count > 0 {
		return fmt.Errorf("seer already divined this night")
	}

	// Get target's role (targetID is game_players.id)
	target, err := e.getPlayerByID(ctx, sessionID, *targetID)
	if err != nil {
		return fmt.Errorf("target not found: %w", err)
	}

	if !target.IsAlive {
		return fmt.Errorf("cannot divine dead players")
	}

	isWerewolf := target.Role == models.RoleWerewolf
	result := "not_werewolf"
	if isWerewolf {
		result = "werewolf"
	}

	actionData := models.ActionData{Result: result}
	actionDataJSON, _ := json.Marshal(actionData)

	_, err = e.db.Exec(ctx, `
		INSERT INTO game_actions (id, session_id, player_id, phase_number, action_type, target_player_id, action_data)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
	`, uuid.New(), sessionID, player.ID, phaseNumber, models.ActionSeerDivine, target.ID, actionDataJSON)

	// Mark action complete
	if err == nil {
		_ = e.nightCoord.MarkActionComplete(ctx, sessionID, models.RoleSeer)
	}

	return err
}

func (e *Engine) processWitchHeal(ctx context.Context, sessionID, userID uuid.UUID) error {
	player, err := e.getPlayerByUserID(ctx, sessionID, userID)
	if err != nil {
		return err
	}

	if player.Role != models.RoleWitch {
		return fmt.Errorf("invalid action")
	}

	if !player.IsAlive {
		return fmt.Errorf("dead players cannot act")
	}

	if player.RoleState.HealUsed {
		return fmt.Errorf("heal potion already used")
	}

	if err := e.nightCoord.ValidateAction(ctx, sessionID, models.RoleWitch); err != nil {
		return err
	}

	// Get state to find current werewolf target (provisional victim)
	var stateJSON json.RawMessage
	var phaseNumber int
	err = e.db.QueryRow(ctx, `
		SELECT state, phase_number FROM game_sessions WHERE id = $1
	`, sessionID).Scan(&stateJSON, &phaseNumber)
	if err != nil {
		return err
	}

	var state models.GameState
	if err := json.Unmarshal(stateJSON, &state); err != nil {
		return err
	}

	// Find the current provisional victim from werewolf votes (not last night's victim)
	provisionalVictim := calculateProvisionalVictim(state.WerewolfVotes)
	if provisionalVictim == nil {
		return fmt.Errorf("no one is being targeted by werewolves yet")
	}

	// Mark heal as used
	player.RoleState.HealUsed = true
	roleStateJSON, _ := json.Marshal(player.RoleState)

	_, err = e.db.Exec(ctx, `
		UPDATE game_players SET role_state = $1 WHERE id = $2
	`, roleStateJSON, player.ID)
	if err != nil {
		return err
	}

	// Update session state to mark that healed player
	_, err = e.db.Exec(ctx, `
		UPDATE game_sessions 
		SET state = jsonb_set(state, '{healed_player}', to_jsonb($1::text))
		WHERE id = $2
	`, provisionalVictim.String(), sessionID)
	if err != nil {
		return err
	}

	actionData := models.ActionData{Result: "healed"}
	actionDataJSON, _ := json.Marshal(actionData)

	_, err = e.db.Exec(ctx, `
		INSERT INTO game_actions (id, session_id, player_id, phase_number, action_type, target_player_id, action_data)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
	`, uuid.New(), sessionID, player.ID, phaseNumber, models.ActionWitchHeal, provisionalVictim, actionDataJSON)

	return err
}

// calculateProvisionalVictim finds the player with the most werewolf votes
func calculateProvisionalVictim(votes map[string]int) *uuid.UUID {
	if votes == nil || len(votes) == 0 {
		return nil
	}

	var maxVotes int
	var victimID string
	for playerID, count := range votes {
		if count > maxVotes {
			maxVotes = count
			victimID = playerID
		}
	}

	if victimID == "" {
		return nil
	}

	parsed, err := uuid.Parse(victimID)
	if err != nil {
		return nil
	}
	return &parsed
}

func (e *Engine) processWitchPoison(ctx context.Context, sessionID, userID uuid.UUID, targetID *uuid.UUID) error {
	if targetID == nil {
		return fmt.Errorf("target is required for poison")
	}

	player, err := e.getPlayerByUserID(ctx, sessionID, userID)
	if err != nil {
		return err
	}

	if player.Role != models.RoleWitch {
		return fmt.Errorf("invalid action")
	}

	if !player.IsAlive {
		return fmt.Errorf("dead players cannot act")
	}

	if player.RoleState.PoisonUsed {
		return fmt.Errorf("poison already used")
	}

	// Get target (targetID is game_players.id)
	target, err := e.getPlayerByID(ctx, sessionID, *targetID)
	if err != nil {
		return fmt.Errorf("target not found: %w", err)
	}

	if !target.IsAlive {
		return fmt.Errorf("cannot poison dead players")
	}

	var phaseNumber int
	err = e.db.QueryRow(ctx, `
		SELECT phase_number FROM game_sessions WHERE id = $1
	`, sessionID).Scan(&phaseNumber)
	if err != nil {
		return err
	}

	// Mark poison as used
	player.RoleState.PoisonUsed = true
	roleStateJSON, _ := json.Marshal(player.RoleState)

	_, err = e.db.Exec(ctx, `
		UPDATE game_players SET role_state = $1 WHERE id = $2
	`, roleStateJSON, player.ID)
	if err != nil {
		return err
	}

	actionData := models.ActionData{Result: "poisoned"}
	actionDataJSON, _ := json.Marshal(actionData)

	_, err = e.db.Exec(ctx, `
		INSERT INTO game_actions (id, session_id, player_id, phase_number, action_type, target_player_id, action_data)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
	`, uuid.New(), sessionID, player.ID, phaseNumber, models.ActionWitchPoison, target.ID, actionDataJSON)

	return err
}

func (e *Engine) processBodyguardProtect(ctx context.Context, sessionID, userID uuid.UUID, targetID *uuid.UUID) error {
	if targetID == nil {
		return fmt.Errorf("target is required for protection")
	}

	player, err := e.getPlayerByUserID(ctx, sessionID, userID)
	if err != nil {
		return err
	}

	if player.Role != models.RoleBodyguard {
		return fmt.Errorf("invalid action")
	}

	if !player.IsAlive {
		return fmt.Errorf("dead players cannot act")
	}

	if err := e.nightCoord.ValidateAction(ctx, sessionID, models.RoleBodyguard); err != nil {
		return err
	}

	// Get target (targetID is game_players.id)
	target, err := e.getPlayerByID(ctx, sessionID, *targetID)
	if err != nil {
		return fmt.Errorf("target not found: %w", err)
	}

	if !target.IsAlive {
		return fmt.Errorf("cannot protect dead players")
	}

	// Check if protected same player last night
	if player.RoleState.LastProtected != nil && *player.RoleState.LastProtected == target.ID {
		return fmt.Errorf("cannot protect same player two nights in a row")
	}

	var phaseNumber int
	err = e.db.QueryRow(ctx, `
		SELECT phase_number FROM game_sessions WHERE id = $1
	`, sessionID).Scan(&phaseNumber)
	if err != nil {
		return err
	}

	// Update role state
	player.RoleState.LastProtected = &target.ID
	roleStateJSON, _ := json.Marshal(player.RoleState)

	_, err = e.db.Exec(ctx, `
		UPDATE game_players SET role_state = $1 WHERE id = $2
	`, roleStateJSON, player.ID)
	if err != nil {
		return err
	}

	actionData := models.ActionData{Result: "protected"}
	actionDataJSON, _ := json.Marshal(actionData)

	_, err = e.db.Exec(ctx, `
		INSERT INTO game_actions (id, session_id, player_id, phase_number, action_type, target_player_id, action_data)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
	`, uuid.New(), sessionID, player.ID, phaseNumber, models.ActionBodyguard, target.ID, actionDataJSON)

	if err == nil {
		_ = e.nightCoord.MarkActionComplete(ctx, sessionID, models.RoleBodyguard)
	}

	return err
}

func (e *Engine) processCupidChoose(ctx context.Context, sessionID, userID uuid.UUID, targetID *uuid.UUID, data interface{}) error {
	if targetID == nil {
		return fmt.Errorf("first lover is required")
	}

	player, err := e.getPlayerByUserID(ctx, sessionID, userID)
	if err != nil {
		return err
	}

	if player.Role != models.RoleCupid {
		return fmt.Errorf("invalid action")
	}

	if !player.IsAlive {
		return fmt.Errorf("dead players cannot act")
	}

	if player.RoleState.HasChosen {
		return fmt.Errorf("lovers already chosen")
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

	// Get targets (targetID and secondLoverID are game_players.id)
	target1, err := e.getPlayerByID(ctx, sessionID, *targetID)
	if err != nil {
		return fmt.Errorf("first lover not found: %w", err)
	}

	target2, err := e.getPlayerByID(ctx, sessionID, secondLoverID)
	if err != nil {
		return fmt.Errorf("second lover not found: %w", err)
	}

	var phaseNumber int
	err = e.db.QueryRow(ctx, `
		SELECT phase_number FROM game_sessions WHERE id = $1
	`, sessionID).Scan(&phaseNumber)
	if err != nil {
		return err
	}

	// Set both players as lovers (keep their original team for win conditions)
	_, err = e.db.Exec(ctx, `
		UPDATE game_players SET lover_id = $1 WHERE session_id = $2 AND id = $3
	`, target2.ID, sessionID, target1.ID)
	if err != nil {
		return err
	}

	_, err = e.db.Exec(ctx, `
		UPDATE game_players SET lover_id = $1 WHERE session_id = $2 AND id = $3
	`, target1.ID, sessionID, target2.ID)
	if err != nil {
		return err
	}

	// Note: We keep lovers on their original team (werewolves/villagers) because:
	// 1. Lovers still count towards their original team for win conditions
	// 2. They maintain their original role and team affiliation
	// 3. Only when checking for lovers win condition do we check if last 2 alive are both lovers

	// Mark cupid action as complete
	player.RoleState.HasChosen = true
	roleStateJSON, _ := json.Marshal(player.RoleState)

	_, err = e.db.Exec(ctx, `
		UPDATE game_players SET role_state = $1 WHERE id = $2
	`, roleStateJSON, player.ID)
	if err != nil {
		return err
	}

	actionData := models.ActionData{SecondLover: &target2.ID, Result: "lovers_chosen"}
	actionDataJSON, _ := json.Marshal(actionData)

	_, err = e.db.Exec(ctx, `
		INSERT INTO game_actions (id, session_id, player_id, phase_number, action_type, target_player_id, action_data)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
	`, uuid.New(), sessionID, player.ID, phaseNumber, models.ActionCupidChoose, target1.ID, actionDataJSON)

	if err == nil {
		_ = e.nightCoord.MarkActionComplete(ctx, sessionID, models.RoleCupid)
	}

	return err
}

func (e *Engine) processHunterShoot(ctx context.Context, sessionID, userID uuid.UUID, targetID *uuid.UUID) error {
	if targetID == nil {
		return fmt.Errorf("target is required for hunter shot")
	}

	player, err := e.getPlayerByUserID(ctx, sessionID, userID)
	if err != nil {
		return err
	}

	if player.Role != models.RoleHunter {
		return fmt.Errorf("only hunter can shoot")
	}

	if player.IsAlive {
		return fmt.Errorf("hunter can only shoot when dying")
	}

	if player.RoleState.HasShot {
		return fmt.Errorf("hunter already shot")
	}

	// Get target (targetID is game_players.id)
	target, err := e.getPlayerByID(ctx, sessionID, *targetID)
	if err != nil {
		return fmt.Errorf("target not found: %w", err)
	}

	if !target.IsAlive {
		return fmt.Errorf("cannot shoot dead players")
	}

	var phaseNumber int
	err = e.db.QueryRow(ctx, `
		SELECT phase_number FROM game_sessions WHERE id = $1
	`, sessionID).Scan(&phaseNumber)
	if err != nil {
		return err
	}

	// Mark shot as used
	player.RoleState.HasShot = true
	roleStateJSON, _ := json.Marshal(player.RoleState)

	_, err = e.db.Exec(ctx, `
		UPDATE game_players SET role_state = $1 WHERE id = $2
	`, roleStateJSON, player.ID)
	if err != nil {
		return err
	}

	// Process the shot death
	death := DeathContext{
		SessionID:   sessionID,
		PlayerID:    target.ID,
		DeathReason: "hunter_shot",
		PhaseNumber: phaseNumber,
		KillerID:    &player.ID,
	}

	_, err = e.deathResolver.ProcessDeath(ctx, death)
	if err != nil {
		return fmt.Errorf("failed to process hunter shot death: %w", err)
	}

	actionData := models.ActionData{Result: "shot"}
	actionDataJSON, _ := json.Marshal(actionData)

	_, err = e.db.Exec(ctx, `
		INSERT INTO game_actions (id, session_id, player_id, phase_number, action_type, target_player_id, action_data)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
	`, uuid.New(), sessionID, player.ID, phaseNumber, models.ActionHunterShoot, target.ID, actionDataJSON)

	// Check win conditions after hunter shot
	_, err = e.winChecker.CheckAndFinalizeWin(ctx, sessionID)

	return err
}

// Helper method
func (e *Engine) getPlayerByUserID(ctx context.Context, sessionID, userID uuid.UUID) (*models.GamePlayer, error) {
	var player models.GamePlayer
	var roleStateJSON json.RawMessage
	var loverID *uuid.UUID

	err := e.db.QueryRow(ctx, `
		SELECT id, session_id, user_id, role, team, is_alive, role_state, lover_id, seat_position
		FROM game_players
		WHERE session_id = $1 AND user_id = $2
	`, sessionID, userID).Scan(
		&player.ID, &player.SessionID, &player.UserID, &player.Role,
		&player.Team, &player.IsAlive, &roleStateJSON, &loverID, &player.SeatPosition,
	)
	if err != nil {
		return nil, err
	}

	if err := json.Unmarshal(roleStateJSON, &player.RoleState); err != nil {
		return nil, fmt.Errorf("failed to parse role state: %w", err)
	}

	player.LoverID = loverID
	return &player, nil
}

// getPlayerByID gets a player by their game_players.id (not user_id)
func (e *Engine) getPlayerByID(ctx context.Context, sessionID, playerID uuid.UUID) (*models.GamePlayer, error) {
	var player models.GamePlayer
	var roleStateJSON json.RawMessage
	var loverID *uuid.UUID

	err := e.db.QueryRow(ctx, `
		SELECT id, session_id, user_id, role, team, is_alive, role_state, lover_id, seat_position
		FROM game_players
		WHERE session_id = $1 AND id = $2
	`, sessionID, playerID).Scan(
		&player.ID, &player.SessionID, &player.UserID, &player.Role,
		&player.Team, &player.IsAlive, &roleStateJSON, &loverID, &player.SeatPosition,
	)
	if err != nil {
		return nil, err
	}

	if err := json.Unmarshal(roleStateJSON, &player.RoleState); err != nil {
		return nil, fmt.Errorf("failed to parse role state: %w", err)
	}

	player.LoverID = loverID
	return &player, nil
}
