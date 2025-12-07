package game

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/kazerdira/wolverix/backend/internal/models"
)

// WinChecker determines if any team has won the game
type WinChecker struct {
	db *pgxpool.Pool
}

// NewWinChecker creates a new win checker
func NewWinChecker(db *pgxpool.Pool) *WinChecker {
	return &WinChecker{db: db}
}

// WinCondition represents the result of checking win conditions
type WinCondition struct {
	GameEnded   bool
	WinningTeam *models.Team
	WinType     WinType
	Winners     []uuid.UUID // Player IDs who won
	Message     string
}

type WinType string

const (
	WinTypeWerewolvesParity WinType = "werewolves_parity"
	WinTypeVillagersVictory WinType = "villagers_victory"
	WinTypeTannerLynched    WinType = "tanner_lynched"
	WinTypeLoversVictory    WinType = "lovers_victory"
)

// CheckWinConditions checks all win conditions and returns the result
func (wc *WinChecker) CheckWinConditions(ctx context.Context, sessionID uuid.UUID) (*WinCondition, error) {
	// Get game state
	gameState, err := wc.getGameState(ctx, sessionID)
	if err != nil {
		return nil, fmt.Errorf("failed to get game state: %w", err)
	}

	// Check in priority order:
	// 1. Tanner win (if just lynched)
	// 2. Lovers win (if only lovers remain)
	// 3. Werewolves win (parity)
	// 4. Villagers win (no werewolves)

	// Check Tanner win (check last lynched player)
	if tannerWin := wc.checkTannerWin(ctx, gameState); tannerWin != nil {
		return tannerWin, nil
	}

	// Check Lovers win
	if loversWin := wc.checkLoversWin(ctx, gameState); loversWin != nil {
		return loversWin, nil
	}

	// Check Werewolves win (parity or outnumber)
	if werewolvesWin := wc.checkWerewolvesWin(ctx, gameState); werewolvesWin != nil {
		return werewolvesWin, nil
	}

	// Check Villagers win (all werewolves dead)
	if villagersWin := wc.checkVillagersWin(ctx, gameState); villagersWin != nil {
		return villagersWin, nil
	}

	// No win condition met
	return &WinCondition{
		GameEnded: false,
	}, nil
}

// CheckAndFinalizeWin checks win conditions and ends the game if necessary
func (wc *WinChecker) CheckAndFinalizeWin(ctx context.Context, sessionID uuid.UUID) (*WinCondition, error) {
	winCondition, err := wc.CheckWinConditions(ctx, sessionID)
	if err != nil {
		return nil, err
	}

	if !winCondition.GameEnded {
		return winCondition, nil
	}

	// End the game
	if err := wc.finalizeGame(ctx, sessionID, winCondition); err != nil {
		return nil, fmt.Errorf("failed to finalize game: %w", err)
	}

	return winCondition, nil
}

// Internal helper methods

type gameState struct {
	SessionID       uuid.UUID
	WerewolvesAlive int
	VillagersAlive  int
	AlivePlayers    []alivePlayer
	LastLynched     *uuid.UUID
}

type alivePlayer struct {
	ID      uuid.UUID
	Role    models.Role
	Team    models.Team
	LoverID *uuid.UUID
}

func (wc *WinChecker) getGameState(ctx context.Context, sessionID uuid.UUID) (*gameState, error) {
	var gs gameState
	gs.SessionID = sessionID

	// Get alive counts
	var stateJSON json.RawMessage
	err := wc.db.QueryRow(ctx, `
		SELECT werewolves_alive, villagers_alive, state
		FROM game_sessions WHERE id = $1
	`, sessionID).Scan(&gs.WerewolvesAlive, &gs.VillagersAlive, &stateJSON)
	if err != nil {
		return nil, err
	}

	// Parse state to get last lynched player
	var state models.GameState
	if err := json.Unmarshal(stateJSON, &state); err != nil {
		return nil, fmt.Errorf("failed to parse game state: %w", err)
	}
	gs.LastLynched = state.LastLynchedPlayer

	// Get all alive players
	rows, err := wc.db.Query(ctx, `
		SELECT id, role, team, lover_id
		FROM game_players
		WHERE session_id = $1 AND is_alive = true
	`, sessionID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	for rows.Next() {
		var p alivePlayer
		err := rows.Scan(&p.ID, &p.Role, &p.Team, &p.LoverID)
		if err != nil {
			return nil, err
		}
		gs.AlivePlayers = append(gs.AlivePlayers, p)
	}

	return &gs, nil
}

func (wc *WinChecker) checkTannerWin(ctx context.Context, gs *gameState) *WinCondition {
	if gs.LastLynched == nil {
		return nil
	}

	// Query the last lynched player's role
	var role models.Role
	err := wc.db.QueryRow(ctx, `
		SELECT role FROM game_players
		WHERE session_id = $1 AND id = $2 AND death_reason = 'lynched'
	`, gs.SessionID, gs.LastLynched).Scan(&role)
	if err != nil {
		return nil
	}

	if role == models.RoleTanner {
		teamNeutral := models.TeamNeutral
		return &WinCondition{
			GameEnded:   true,
			WinningTeam: &teamNeutral,
			WinType:     WinTypeTannerLynched,
			Winners:     []uuid.UUID{*gs.LastLynched},
			Message:     "The Tanner wins! They successfully got themselves lynched!",
		}
	}

	return nil
}

func (wc *WinChecker) checkLoversWin(ctx context.Context, gs *gameState) *WinCondition {
	// Check if only 2 players remain and they are lovers
	if len(gs.AlivePlayers) != 2 {
		return nil
	}

	p1, p2 := gs.AlivePlayers[0], gs.AlivePlayers[1]

	// Check if they are lovers
	if p1.LoverID != nil && p2.LoverID != nil &&
		*p1.LoverID == p2.ID && *p2.LoverID == p1.ID {

		teamNeutral := models.TeamNeutral
		return &WinCondition{
			GameEnded:   true,
			WinningTeam: &teamNeutral,
			WinType:     WinTypeLoversVictory,
			Winners:     []uuid.UUID{p1.ID, p2.ID},
			Message:     "The Lovers win! They are the last two standing!",
		}
	}

	return nil
}

func (wc *WinChecker) checkWerewolvesWin(ctx context.Context, gs *gameState) *WinCondition {
	// Werewolves win when they equal or outnumber non-werewolves
	if gs.WerewolvesAlive >= gs.VillagersAlive && gs.WerewolvesAlive > 0 {
		// Get all werewolf player IDs
		var winners []uuid.UUID
		for _, p := range gs.AlivePlayers {
			if p.Team == models.TeamWerewolves {
				winners = append(winners, p.ID)
			}
		}

		teamWerewolves := models.TeamWerewolves
		return &WinCondition{
			GameEnded:   true,
			WinningTeam: &teamWerewolves,
			WinType:     WinTypeWerewolvesParity,
			Winners:     winners,
			Message:     fmt.Sprintf("The Werewolves win! They have achieved parity (%d werewolves vs %d villagers)", gs.WerewolvesAlive, gs.VillagersAlive),
		}
	}

	return nil
}

func (wc *WinChecker) checkVillagersWin(ctx context.Context, gs *gameState) *WinCondition {
	// Villagers win when all werewolves are dead
	if gs.WerewolvesAlive == 0 {
		// Get all surviving villager player IDs
		var winners []uuid.UUID
		for _, p := range gs.AlivePlayers {
			if p.Team == models.TeamVillagers || p.Team == models.TeamNeutral {
				winners = append(winners, p.ID)
			}
		}

		teamVillagers := models.TeamVillagers
		return &WinCondition{
			GameEnded:   true,
			WinningTeam: &teamVillagers,
			WinType:     WinTypeVillagersVictory,
			Winners:     winners,
			Message:     "The Villagers win! All werewolves have been eliminated!",
		}
	}

	return nil
}

func (wc *WinChecker) finalizeGame(ctx context.Context, sessionID uuid.UUID, win *WinCondition) error {
	tx, err := wc.db.Begin(ctx)
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	// Update game session
	winningTeamStr := ""
	if win.WinningTeam != nil {
		winningTeamStr = string(*win.WinningTeam)
	}

	_, err = tx.Exec(ctx, `
		UPDATE game_sessions
		SET status = 'finished', winning_team = $1, finished_at = NOW()
		WHERE id = $2
	`, winningTeamStr, sessionID)
	if err != nil {
		return fmt.Errorf("failed to update game session: %w", err)
	}

	// Update room status
	_, err = tx.Exec(ctx, `
		UPDATE rooms
		SET status = 'finished', finished_at = NOW()
		WHERE id = (SELECT room_id FROM game_sessions WHERE id = $1)
	`, sessionID)
	if err != nil {
		return fmt.Errorf("failed to update room: %w", err)
	}

	// Create game end event
	eventData := models.EventData{
		WinnerTeam: win.WinningTeam,
		Message:    win.Message,
	}
	eventDataJSON, _ := json.Marshal(eventData)

	var phaseNumber int
	err = tx.QueryRow(ctx, `SELECT phase_number FROM game_sessions WHERE id = $1`, sessionID).Scan(&phaseNumber)
	if err != nil {
		return fmt.Errorf("failed to get phase number: %w", err)
	}

	_, err = tx.Exec(ctx, `
		INSERT INTO game_events (id, session_id, phase_number, event_type, event_data, is_public)
		VALUES ($1, $2, $3, $4, $5, $6)
	`, uuid.New(), sessionID, phaseNumber, models.EventGameEnd, eventDataJSON, true)
	if err != nil {
		return fmt.Errorf("failed to create game end event: %w", err)
	}

	// Update player stats
	if err := wc.updatePlayerStats(ctx, tx, sessionID, win); err != nil {
		return fmt.Errorf("failed to update player stats: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("failed to commit transaction: %w", err)
	}

	return nil
}

func (wc *WinChecker) updatePlayerStats(ctx context.Context, tx pgx.Tx, sessionID uuid.UUID, win *WinCondition) error {
	// Get all players in the game
	rows, err := tx.Query(ctx, `
		SELECT user_id, role, team FROM game_players WHERE session_id = $1
	`, sessionID)
	if err != nil {
		return err
	}
	defer rows.Close()

	type playerInfo struct {
		UserID uuid.UUID
		Role   models.Role
		Team   models.Team
	}
	var players []playerInfo

	for rows.Next() {
		var p playerInfo
		if err := rows.Scan(&p.UserID, &p.Role, &p.Team); err != nil {
			return err
		}
		players = append(players, p)
	}

	// Update stats for each player
	for _, p := range players {
		isWinner := false
		for _, winnerID := range win.Winners {
			// Match player ID with winner ID
			var playerID uuid.UUID
			_ = tx.QueryRow(ctx, `SELECT id FROM game_players WHERE session_id = $1 AND user_id = $2`, sessionID, p.UserID).Scan(&playerID)
			if playerID == winnerID {
				isWinner = true
				break
			}
		}

		// Increment game count
		_, err := tx.Exec(ctx, `
			UPDATE user_stats
			SET total_games = total_games + 1,
			    total_wins = total_wins + CASE WHEN $1 THEN 1 ELSE 0 END,
			    total_losses = total_losses + CASE WHEN $1 THEN 0 ELSE 1 END
			WHERE user_id = $2
		`, isWinner, p.UserID)
		if err != nil {
			return err
		}

		// Update role-specific stats
		roleColumn := fmt.Sprintf("games_as_%s", p.Role)
		_, _ = tx.Exec(ctx, fmt.Sprintf(`
			UPDATE user_stats SET %s = %s + 1 WHERE user_id = $1
		`, roleColumn, roleColumn), p.UserID)

		// Update team wins
		if isWinner {
			if p.Team == models.TeamWerewolves {
				_, _ = tx.Exec(ctx, `
					UPDATE user_stats SET werewolf_wins = werewolf_wins + 1 WHERE user_id = $1
				`, p.UserID)
			} else {
				_, _ = tx.Exec(ctx, `
					UPDATE user_stats SET villager_wins = villager_wins + 1 WHERE user_id = $1
				`, p.UserID)
			}
		}
	}

	return nil
}
