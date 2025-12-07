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

// DeathResolver handles all death mechanics including cascades and triggers
type DeathResolver struct {
	db *pgxpool.Pool
}

// NewDeathResolver creates a new death resolver
func NewDeathResolver(db *pgxpool.Pool) *DeathResolver {
	return &DeathResolver{db: db}
}

// DeathContext contains information about a death event
type DeathContext struct {
	SessionID   uuid.UUID
	PlayerID    uuid.UUID
	DeathReason string
	PhaseNumber int
	KillerID    *uuid.UUID // Optional: who caused the death
	BypassLover bool       // Set true to prevent lover cascade (for simultaneous lover deaths)
}

// DeathResult contains the outcome of death resolution
type DeathResult struct {
	DeadPlayers     []uuid.UUID       // All players who died (including cascades)
	HunterShot      *HunterShotResult // If hunter was killed
	LoverDeaths     []uuid.UUID       // Players who died from lover cascade
	RolesRevealed   map[uuid.UUID]models.Role
	WinConditionMet bool
	WinningTeam     *models.Team
}

type HunterShotResult struct {
	HunterID uuid.UUID
	TargetID *uuid.UUID // nil if hunter chose not to shoot or couldn't
}

// ProcessDeath handles a player death and all cascading effects
func (dr *DeathResolver) ProcessDeath(ctx context.Context, death DeathContext) (*DeathResult, error) {
	tx, err := dr.db.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	result := &DeathResult{
		DeadPlayers:   []uuid.UUID{death.PlayerID},
		RolesRevealed: make(map[uuid.UUID]models.Role),
	}

	// Get player info
	player, err := dr.getPlayer(ctx, tx, death.SessionID, death.PlayerID)
	if err != nil {
		return nil, fmt.Errorf("failed to get player: %w", err)
	}

	// Check if already dead
	if !player.IsAlive {
		return result, nil // Already dead, no-op
	}

	// Mark player as dead
	if err := dr.markPlayerDead(ctx, tx, death); err != nil {
		return nil, fmt.Errorf("failed to mark player dead: %w", err)
	}

	// Update alive counts
	if err := dr.updateAliveCounts(ctx, tx, death.SessionID, player.Team); err != nil {
		return nil, fmt.Errorf("failed to update alive counts: %w", err)
	}

	// Reveal role
	result.RolesRevealed[death.PlayerID] = player.Role

	// Create death event
	if err := dr.createDeathEvent(ctx, tx, death, player.Role); err != nil {
		return nil, fmt.Errorf("failed to create death event: %w", err)
	}

	// Handle Hunter death trigger
	if player.Role == models.RoleHunter && !player.RoleState.HasShot {
		hunterShot, err := dr.handleHunterDeath(ctx, tx, death.SessionID, death.PlayerID, death.PhaseNumber)
		if err != nil {
			return nil, fmt.Errorf("failed to handle hunter death: %w", err)
		}
		result.HunterShot = hunterShot

		// If hunter shot someone, recursively process that death
		if hunterShot.TargetID != nil {
			targetDeath := DeathContext{
				SessionID:   death.SessionID,
				PlayerID:    *hunterShot.TargetID,
				DeathReason: "hunter_shot",
				PhaseNumber: death.PhaseNumber,
				KillerID:    &death.PlayerID,
			}
			targetResult, err := dr.ProcessDeath(ctx, targetDeath)
			if err != nil {
				return nil, fmt.Errorf("failed to process hunter shot death: %w", err)
			}
			// Merge results
			result.DeadPlayers = append(result.DeadPlayers, targetResult.DeadPlayers...)
			for k, v := range targetResult.RolesRevealed {
				result.RolesRevealed[k] = v
			}
		}
	}

	// Handle Lover cascade
	if !death.BypassLover && player.LoverID != nil {
		loverDeath := DeathContext{
			SessionID:   death.SessionID,
			PlayerID:    *player.LoverID,
			DeathReason: "lover_death",
			PhaseNumber: death.PhaseNumber,
			BypassLover: true, // Prevent infinite loop
		}
		loverResult, err := dr.ProcessDeath(ctx, loverDeath)
		if err != nil {
			return nil, fmt.Errorf("failed to process lover death: %w", err)
		}
		result.LoverDeaths = loverResult.DeadPlayers
		result.DeadPlayers = append(result.DeadPlayers, loverResult.DeadPlayers...)
		for k, v := range loverResult.RolesRevealed {
			result.RolesRevealed[k] = v
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, fmt.Errorf("failed to commit transaction: %w", err)
	}

	return result, nil
}

// ProcessMultipleDeaths handles multiple deaths simultaneously (e.g., night kills + poison)
func (dr *DeathResolver) ProcessMultipleDeaths(ctx context.Context, deaths []DeathContext) (*DeathResult, error) {
	result := &DeathResult{
		DeadPlayers:   []uuid.UUID{},
		RolesRevealed: make(map[uuid.UUID]models.Role),
	}

	// Process each death
	for _, death := range deaths {
		deathResult, err := dr.ProcessDeath(ctx, death)
		if err != nil {
			return nil, err
		}

		// Merge results
		result.DeadPlayers = append(result.DeadPlayers, deathResult.DeadPlayers...)
		if deathResult.HunterShot != nil {
			result.HunterShot = deathResult.HunterShot
		}
		result.LoverDeaths = append(result.LoverDeaths, deathResult.LoverDeaths...)
		for k, v := range deathResult.RolesRevealed {
			result.RolesRevealed[k] = v
		}
	}

	return result, nil
}

// ResolveNightDeaths processes all deaths from night actions
func (dr *DeathResolver) ResolveNightDeaths(ctx context.Context, sessionID uuid.UUID, nightActions *NightActionResults) (*DeathResult, error) {
	var deaths []DeathContext

	phaseNumber, err := dr.getCurrentPhaseNumber(ctx, sessionID)
	if err != nil {
		return nil, err
	}

	// Werewolf kill (if not protected or healed)
	if nightActions.WerewolfTarget != nil && !nightActions.IsProtected && !nightActions.IsHealed {
		deaths = append(deaths, DeathContext{
			SessionID:   sessionID,
			PlayerID:    *nightActions.WerewolfTarget,
			DeathReason: "werewolf_kill",
			PhaseNumber: phaseNumber,
		})
	}

	// Witch poison (always succeeds, bypasses protection)
	if nightActions.PoisonTarget != nil {
		deaths = append(deaths, DeathContext{
			SessionID:   sessionID,
			PlayerID:    *nightActions.PoisonTarget,
			DeathReason: "poison",
			PhaseNumber: phaseNumber,
		})
	}

	return dr.ProcessMultipleDeaths(ctx, deaths)
}

// ResolveLynchDeath processes a lynch death
func (dr *DeathResolver) ResolveLynchDeath(ctx context.Context, sessionID, playerID uuid.UUID, phaseNumber int) (*DeathResult, error) {
	death := DeathContext{
		SessionID:   sessionID,
		PlayerID:    playerID,
		DeathReason: "lynched",
		PhaseNumber: phaseNumber,
	}
	return dr.ProcessDeath(ctx, death)
}

// Internal helper methods

func (dr *DeathResolver) getPlayer(ctx context.Context, tx pgx.Tx, sessionID, playerID uuid.UUID) (*models.GamePlayer, error) {
	var player models.GamePlayer
	var roleStateJSON json.RawMessage
	var loverID *uuid.UUID

	err := tx.QueryRow(ctx, `
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

func (dr *DeathResolver) markPlayerDead(ctx context.Context, tx pgx.Tx, death DeathContext) error {
	_, err := tx.Exec(ctx, `
		UPDATE game_players
		SET is_alive = false, died_at_phase = $1, death_reason = $2, current_voice_channel = 'dead'
		WHERE session_id = $3 AND id = $4
	`, death.PhaseNumber, death.DeathReason, death.SessionID, death.PlayerID)
	return err
}

func (dr *DeathResolver) updateAliveCounts(ctx context.Context, tx pgx.Tx, sessionID uuid.UUID, team models.Team) error {
	var column string
	switch team {
	case models.TeamWerewolves:
		column = "werewolves_alive"
	case models.TeamVillagers, models.TeamNeutral:
		column = "villagers_alive"
	default:
		return fmt.Errorf("unknown team: %s", team)
	}

	_, err := tx.Exec(ctx, fmt.Sprintf(`
		UPDATE game_sessions
		SET %s = %s - 1
		WHERE id = $1
	`, column, column), sessionID)
	return err
}

func (dr *DeathResolver) createDeathEvent(ctx context.Context, tx pgx.Tx, death DeathContext, role models.Role) error {
	eventData := models.EventData{
		PlayerID: &death.PlayerID,
		Role:     &role,
		Reason:   death.DeathReason,
		Message:  fmt.Sprintf("Player died: %s", death.DeathReason),
	}
	eventDataJSON, _ := json.Marshal(eventData)

	_, err := tx.Exec(ctx, `
		INSERT INTO game_events (id, session_id, phase_number, event_type, event_data, is_public)
		VALUES ($1, $2, $3, $4, $5, $6)
	`, uuid.New(), death.SessionID, death.PhaseNumber, models.EventPlayerDeath, eventDataJSON, true)
	return err
}

func (dr *DeathResolver) handleHunterDeath(ctx context.Context, tx pgx.Tx, sessionID, hunterID uuid.UUID, phaseNumber int) (*HunterShotResult, error) {
	// Mark hunter shot as used
	roleState := models.RoleState{HasShot: true}
	roleStateJSON, _ := json.Marshal(roleState)

	_, err := tx.Exec(ctx, `
		UPDATE game_players SET role_state = $1 WHERE session_id = $2 AND id = $3
	`, roleStateJSON, sessionID, hunterID)
	if err != nil {
		return nil, err
	}

	// In a real implementation, you'd wait for the hunter player to choose their target
	// For now, we'll record that the hunter died and can shoot
	// The actual shot would be processed via a separate action
	return &HunterShotResult{
		HunterID: hunterID,
		TargetID: nil, // Hunter must choose target via action
	}, nil
}

func (dr *DeathResolver) getCurrentPhaseNumber(ctx context.Context, sessionID uuid.UUID) (int, error) {
	var phaseNumber int
	err := dr.db.QueryRow(ctx, `
		SELECT phase_number FROM game_sessions WHERE id = $1
	`, sessionID).Scan(&phaseNumber)
	return phaseNumber, err
}

// NightActionResults contains the outcome of night phase actions
type NightActionResults struct {
	WerewolfTarget *uuid.UUID
	IsProtected    bool
	IsHealed       bool
	PoisonTarget   *uuid.UUID
}
