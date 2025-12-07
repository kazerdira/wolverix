package game

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/kazerdira/wolverix/backend/internal/models"
)

// VoteManager handles voting mechanics and tie resolution
type VoteManager struct {
	db *pgxpool.Pool
}

// NewVoteManager creates a new vote manager
func NewVoteManager(db *pgxpool.Pool) *VoteManager {
	return &VoteManager{db: db}
}

// VoteResult contains the outcome of a vote
type VoteResult struct {
	LynchedPlayerID *uuid.UUID              // nil if no one lynched
	VoteCounts      map[uuid.UUID]int       // player ID -> vote count
	TotalVotes      int
	WasTie          bool
	TiePlayerIDs    []uuid.UUID             // Players tied for most votes
	TieBreaker      *uuid.UUID              // Who broke the tie (e.g., Mayor)
}

// CastVote records a player's lynch vote
func (vm *VoteManager) CastVote(ctx context.Context, sessionID, voterID, targetID uuid.UUID) error {
	// Get current phase
	var currentPhase models.GamePhase
	var phaseNumber int
	err := vm.db.QueryRow(ctx, `
		SELECT current_phase, phase_number FROM game_sessions WHERE id = $1
	`, sessionID).Scan(&currentPhase, &phaseNumber)
	if err != nil {
		return fmt.Errorf("failed to get game state: %w", err)
	}

	if currentPhase != models.GamePhaseVoting {
		return fmt.Errorf("can only vote during voting phase")
	}

	// Check if voter is alive
	var isAlive bool
	err = vm.db.QueryRow(ctx, `
		SELECT is_alive FROM game_players WHERE session_id = $1 AND user_id = $2
	`, sessionID, voterID).Scan(&isAlive)
	if err != nil {
		return fmt.Errorf("voter not found: %w", err)
	}

	if !isAlive {
		return fmt.Errorf("dead players cannot vote")
	}

	// Check if target is alive
	err = vm.db.QueryRow(ctx, `
		SELECT is_alive FROM game_players WHERE session_id = $1 AND user_id = $2
	`, sessionID, targetID).Scan(&isAlive)
	if err != nil {
		return fmt.Errorf("target not found: %w", err)
	}

	if !isAlive {
		return fmt.Errorf("cannot vote for dead players")
	}

	// Delete any existing vote from this voter (allow vote changes)
	_, err = vm.db.Exec(ctx, `
		DELETE FROM game_actions
		WHERE session_id = $1 AND user_id = (SELECT user_id FROM game_players WHERE session_id = $1 AND user_id = $2)
		      AND phase_number = $3 AND action_type = $4
	`, sessionID, voterID, phaseNumber, models.ActionVoteLynch)
	if err != nil {
		return fmt.Errorf("failed to clear old vote: %w", err)
	}

	// Record new vote
	actionData := models.ActionData{Result: "voted"}
	actionDataJSON, _ := json.Marshal(actionData)

	// Get player ID (not user ID) for the voter
	var playerID uuid.UUID
	err = vm.db.QueryRow(ctx, `
		SELECT id FROM game_players WHERE session_id = $1 AND user_id = $2
	`, sessionID, voterID).Scan(&playerID)
	if err != nil {
		return err
	}

	// Get target player ID
	var targetPlayerID uuid.UUID
	err = vm.db.QueryRow(ctx, `
		SELECT id FROM game_players WHERE session_id = $1 AND user_id = $2
	`, sessionID, targetID).Scan(&targetPlayerID)
	if err != nil {
		return err
	}

	_, err = vm.db.Exec(ctx, `
		INSERT INTO game_actions (id, session_id, player_id, phase_number, action_type, target_player_id, action_data)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
	`, uuid.New(), sessionID, playerID, phaseNumber, models.ActionVoteLynch, targetPlayerID, actionDataJSON)
	if err != nil {
		return fmt.Errorf("failed to record vote: %w", err)
	}

	// Update game state with vote counts
	if err := vm.updateVoteCounts(ctx, sessionID, phaseNumber); err != nil {
		return fmt.Errorf("failed to update vote counts: %w", err)
	}

	return nil
}

// TallyVotes counts all votes and determines the lynch result
func (vm *VoteManager) TallyVotes(ctx context.Context, sessionID uuid.UUID) (*VoteResult, error) {
	var phaseNumber int
	err := vm.db.QueryRow(ctx, `
		SELECT phase_number FROM game_sessions WHERE id = $1
	`, sessionID).Scan(&phaseNumber)
	if err != nil {
		return nil, err
	}

	// Get vote counts
	rows, err := vm.db.Query(ctx, `
		SELECT target_player_id, COUNT(*) as vote_count
		FROM game_actions
		WHERE session_id = $1 AND phase_number = $2 AND action_type = $3
		GROUP BY target_player_id
		ORDER BY vote_count DESC
	`, sessionID, phaseNumber, models.ActionVoteLynch)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	voteCounts := make(map[uuid.UUID]int)
	totalVotes := 0

	for rows.Next() {
		var playerID uuid.UUID
		var count int
		if err := rows.Scan(&playerID, &count); err != nil {
			return nil, err
		}
		voteCounts[playerID] = count
		totalVotes += count
	}

	result := &VoteResult{
		VoteCounts: voteCounts,
		TotalVotes: totalVotes,
	}

	// No votes cast
	if len(voteCounts) == 0 {
		return result, nil
	}

	// Find player(s) with most votes
	maxVotes := 0
	var topPlayers []uuid.UUID

	for playerID, count := range voteCounts {
		if count > maxVotes {
			maxVotes = count
			topPlayers = []uuid.UUID{playerID}
		} else if count == maxVotes {
			topPlayers = append(topPlayers, playerID)
		}
	}

	// Check for tie
	if len(topPlayers) > 1 {
		result.WasTie = true
		result.TiePlayerIDs = topPlayers

		// Try to resolve tie
		lynchedPlayer, tieBreaker, err := vm.resolveTie(ctx, sessionID, topPlayers)
		if err != nil {
			return nil, fmt.Errorf("failed to resolve tie: %w", err)
		}

		result.LynchedPlayerID = lynchedPlayer
		result.TieBreaker = tieBreaker
	} else {
		// Clear winner
		result.LynchedPlayerID = &topPlayers[0]
	}

	return result, nil
}

// resolveTie attempts to resolve a voting tie
func (vm *VoteManager) resolveTie(ctx context.Context, sessionID uuid.UUID, tiedPlayers []uuid.UUID) (*uuid.UUID, *uuid.UUID, error) {
	// Strategy 1: Check if there's a Mayor who can break tie
	mayorID, err := vm.getMayor(ctx, sessionID)
	if err == nil && mayorID != nil {
		// Mayor breaks tie (in a real game, you'd prompt the mayor to choose)
		// For now, we'll return nil to indicate no lynch (tie unresolved)
		return nil, mayorID, nil
	}

	// Strategy 2: No mayor or mayor can't decide -> no lynch
	return nil, nil, nil
}

// getMayor returns the mayor's player ID if one exists and is alive
func (vm *VoteManager) getMayor(ctx context.Context, sessionID uuid.UUID) (*uuid.UUID, error) {
	var mayorID uuid.UUID
	err := vm.db.QueryRow(ctx, `
		SELECT id FROM game_players
		WHERE session_id = $1 AND role = $2 AND is_alive = true
	`, sessionID, models.RoleMayor).Scan(&mayorID)
	if err != nil {
		if err.Error() == "no rows in result set" {
			return nil, nil
		}
		return nil, err
	}
	return &mayorID, nil
}

// updateVoteCounts updates the game state with current vote counts
func (vm *VoteManager) updateVoteCounts(ctx context.Context, sessionID uuid.UUID, phaseNumber int) error {
	// Get vote counts
	rows, err := vm.db.Query(ctx, `
		SELECT target_player_id, COUNT(*) as vote_count
		FROM game_actions
		WHERE session_id = $1 AND phase_number = $2 AND action_type = $3
		GROUP BY target_player_id
	`, sessionID, phaseNumber, models.ActionVoteLynch)
	if err != nil {
		return err
	}
	defer rows.Close()

	voteCounts := make(map[string]int)
	for rows.Next() {
		var playerID uuid.UUID
		var count int
		if err := rows.Scan(&playerID, &count); err != nil {
			return err
		}
		voteCounts[playerID.String()] = count
	}

	voteCountsJSON, _ := json.Marshal(voteCounts)

	// Update game state
	_, err = vm.db.Exec(ctx, `
		UPDATE game_sessions
		SET state = jsonb_set(state, '{lynch_votes}', $1)
		WHERE id = $2
	`, voteCountsJSON, sessionID)
	return err
}

// GetCurrentVotes returns the current vote counts
func (vm *VoteManager) GetCurrentVotes(ctx context.Context, sessionID uuid.UUID) (map[uuid.UUID]int, error) {
	var phaseNumber int
	err := vm.db.QueryRow(ctx, `
		SELECT phase_number FROM game_sessions WHERE id = $1
	`, sessionID).Scan(&phaseNumber)
	if err != nil {
		return nil, err
	}

	rows, err := vm.db.Query(ctx, `
		SELECT target_player_id, COUNT(*) as vote_count
		FROM game_actions
		WHERE session_id = $1 AND phase_number = $2 AND action_type = $3
		GROUP BY target_player_id
	`, sessionID, phaseNumber, models.ActionVoteLynch)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	voteCounts := make(map[uuid.UUID]int)
	for rows.Next() {
		var playerID uuid.UUID
		var count int
		if err := rows.Scan(&playerID, &count); err != nil {
			return nil, err
		}
		voteCounts[playerID] = count
	}

	return voteCounts, nil
}

// HasPlayerVoted checks if a player has already voted
func (vm *VoteManager) HasPlayerVoted(ctx context.Context, sessionID, voterID uuid.UUID) (bool, error) {
	var phaseNumber int
	err := vm.db.QueryRow(ctx, `
		SELECT phase_number FROM game_sessions WHERE id = $1
	`, sessionID).Scan(&phaseNumber)
	if err != nil {
		return false, err
	}

	var count int
	err = vm.db.QueryRow(ctx, `
		SELECT COUNT(*)
		FROM game_actions ga
		JOIN game_players gp ON ga.player_id = gp.id
		WHERE ga.session_id = $1 AND gp.user_id = $2 AND ga.phase_number = $3 AND ga.action_type = $4
	`, sessionID, voterID, phaseNumber, models.ActionVoteLynch).Scan(&count)
	if err != nil {
		return false, err
	}

	return count > 0, nil
}

// GetPlayerVote returns who a player voted for
func (vm *VoteManager) GetPlayerVote(ctx context.Context, sessionID, voterID uuid.UUID) (*uuid.UUID, error) {
	var phaseNumber int
	err := vm.db.QueryRow(ctx, `
		SELECT phase_number FROM game_sessions WHERE id = $1
	`, sessionID).Scan(&phaseNumber)
	if err != nil {
		return nil, err
	}

	var targetPlayerID uuid.UUID
	err = vm.db.QueryRow(ctx, `
		SELECT ga.target_player_id
		FROM game_actions ga
		JOIN game_players gp ON ga.player_id = gp.id
		WHERE ga.session_id = $1 AND gp.user_id = $2 AND ga.phase_number = $3 AND ga.action_type = $4
	`, sessionID, voterID, phaseNumber, models.ActionVoteLynch).Scan(&targetPlayerID)
	if err != nil {
		if err.Error() == "no rows in result set" {
			return nil, nil
		}
		return nil, err
	}

	return &targetPlayerID, nil
}

// ClearVotes removes all votes for the current phase
func (vm *VoteManager) ClearVotes(ctx context.Context, sessionID uuid.UUID) error {
	var phaseNumber int
	err := vm.db.QueryRow(ctx, `
		SELECT phase_number FROM game_sessions WHERE id = $1
	`, sessionID).Scan(&phaseNumber)
	if err != nil {
		return err
	}

	_, err = vm.db.Exec(ctx, `
		DELETE FROM game_actions
		WHERE session_id = $1 AND phase_number = $2 AND action_type = $3
	`, sessionID, phaseNumber, models.ActionVoteLynch)
	return err
}
