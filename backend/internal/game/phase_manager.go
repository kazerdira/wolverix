package game

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/kazerdira/wolverix/backend/internal/models"
)

// PhaseManager handles game phase transitions and timing
type PhaseManager struct {
	db            *pgxpool.Pool
	deathResolver *DeathResolver
	winChecker    *WinChecker
	nightCoord    *NightCoordinator
	scheduler     *GameScheduler
}

// NewPhaseManager creates a new phase manager
func NewPhaseManager(db *pgxpool.Pool, dr *DeathResolver, wc *WinChecker, nc *NightCoordinator) *PhaseManager {
	return &PhaseManager{
		db:            db,
		deathResolver: dr,
		winChecker:    wc,
		nightCoord:    nc,
		// scheduler will be set later via SetScheduler to avoid circular dependency
	}
}

// SetScheduler sets the game scheduler (called after Engine initialization)
func (pm *PhaseManager) SetScheduler(scheduler *GameScheduler) {
	pm.scheduler = scheduler
}

// PhaseTransition represents a phase change
type PhaseTransition struct {
	SessionID    uuid.UUID
	FromPhase    models.GamePhase
	ToPhase      models.GamePhase
	PhaseNumber  int
	DayNumber    int
	Deaths       []uuid.UUID
	WinCondition *WinCondition
	Message      string
}

// TransitionToDay moves from night to day phase
func (pm *PhaseManager) TransitionToDay(ctx context.Context, sessionID uuid.UUID) (*PhaseTransition, error) {
	tx, err := pm.db.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	// Get current state
	var currentPhase models.GamePhase
	var phaseNumber, dayNumber int
	err = tx.QueryRow(ctx, `
		SELECT current_phase, phase_number, day_number FROM game_sessions WHERE id = $1
	`, sessionID).Scan(&currentPhase, &phaseNumber, &dayNumber)
	if err != nil {
		return nil, fmt.Errorf("failed to get current phase: %w", err)
	}

	if currentPhase != models.GamePhaseNight {
		return nil, fmt.Errorf("can only transition to day from night phase")
	}

	// Process night actions and resolve deaths
	nightResults, err := pm.nightCoord.ProcessNightActions(ctx, sessionID)
	if err != nil {
		return nil, fmt.Errorf("failed to process night actions: %w", err)
	}

	deathResult, err := pm.deathResolver.ResolveNightDeaths(ctx, sessionID, nightResults)
	if err != nil {
		return nil, fmt.Errorf("failed to resolve night deaths: %w", err)
	}

	// Increment day number
	dayNumber++

	// Update to day phase
	phaseEndsAt := time.Now().Add(5 * time.Minute) // 5 minute day discussion
	_, err = tx.Exec(ctx, `
		UPDATE game_sessions
		SET current_phase = $1, phase_number = phase_number + 1, day_number = $2,
		    phase_started_at = NOW(), phase_ends_at = $3
		WHERE id = $4
	`, models.GamePhaseDay, dayNumber, phaseEndsAt, sessionID)
	if err != nil {
		return nil, fmt.Errorf("failed to update phase: %w", err)
	}

	// Create phase change event
	message := fmt.Sprintf("Day %d begins. ", dayNumber)
	if len(deathResult.DeadPlayers) > 0 {
		message += fmt.Sprintf("%d player(s) died during the night.", len(deathResult.DeadPlayers))
	} else {
		message += "No one died during the night."
	}

	newPhase := models.GamePhaseDay
	eventData := models.EventData{
		NewPhase: &newPhase,
		Message:  message,
	}
	eventDataJSON, _ := json.Marshal(eventData)

	_, err = tx.Exec(ctx, `
		INSERT INTO game_events (id, session_id, phase_number, event_type, event_data, is_public)
		VALUES ($1, $2, $3, $4, $5, $6)
	`, uuid.New(), sessionID, phaseNumber+1, models.EventPhaseChange, eventDataJSON, true)
	if err != nil {
		return nil, fmt.Errorf("failed to create phase change event: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, fmt.Errorf("failed to commit transaction: %w", err)
	}

	// Schedule automatic transition to voting phase (5 minutes)
	if pm.scheduler != nil {
		pm.scheduler.SchedulePhaseEnd(sessionID, 5*time.Minute)
	}

	// Check win conditions AFTER committing (separate transaction)
	winCondition, err := pm.winChecker.CheckAndFinalizeWin(ctx, sessionID)
	if err != nil {
		return nil, fmt.Errorf("failed to check win conditions: %w", err)
	}

	// Cancel scheduler if game ended
	if winCondition.GameEnded && pm.scheduler != nil {
		pm.scheduler.CancelPhaseEnd(sessionID)
	}

	transition := &PhaseTransition{
		SessionID:    sessionID,
		FromPhase:    models.GamePhaseNight,
		ToPhase:      models.GamePhaseDay,
		PhaseNumber:  phaseNumber + 1,
		DayNumber:    dayNumber,
		Deaths:       deathResult.DeadPlayers,
		WinCondition: winCondition,
		Message:      message,
	}

	return transition, nil
}

// TransitionToVoting moves from day to voting phase
func (pm *PhaseManager) TransitionToVoting(ctx context.Context, sessionID uuid.UUID) (*PhaseTransition, error) {
	tx, err := pm.db.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	var currentPhase models.GamePhase
	var phaseNumber, dayNumber int
	err = tx.QueryRow(ctx, `
		SELECT current_phase, phase_number, day_number FROM game_sessions WHERE id = $1
	`, sessionID).Scan(&currentPhase, &phaseNumber, &dayNumber)
	if err != nil {
		return nil, err
	}

	if currentPhase != models.GamePhaseDay {
		return nil, fmt.Errorf("can only transition to voting from day phase")
	}

	// Update to voting phase
	phaseEndsAt := time.Now().Add(1 * time.Minute) // 1 minute voting
	_, err = tx.Exec(ctx, `
		UPDATE game_sessions
		SET current_phase = $1, phase_number = phase_number + 1,
		    phase_started_at = NOW(), phase_ends_at = $2
		WHERE id = $3
	`, models.GamePhaseVoting, phaseEndsAt, sessionID)
	if err != nil {
		return nil, err
	}

	// Clear previous votes
	_, err = tx.Exec(ctx, `
		UPDATE game_sessions
		SET state = jsonb_set(state, '{lynch_votes}', '{}')
		WHERE id = $1
	`, sessionID)
	if err != nil {
		return nil, err
	}

	// Create event
	newPhase := models.GamePhaseVoting
	eventData := models.EventData{
		NewPhase: &newPhase,
		Message:  "Voting phase begins. Choose who to lynch.",
	}
	eventDataJSON, _ := json.Marshal(eventData)

	_, err = tx.Exec(ctx, `
		INSERT INTO game_events (id, session_id, phase_number, event_type, event_data, is_public)
		VALUES ($1, $2, $3, $4, $5, $6)
	`, uuid.New(), sessionID, phaseNumber+1, models.EventPhaseChange, eventDataJSON, true)
	if err != nil {
		return nil, err
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}

	// Schedule automatic transition to night phase (1 minute voting)
	if pm.scheduler != nil {
		pm.scheduler.SchedulePhaseEnd(sessionID, 1*time.Minute)
	}

	transition := &PhaseTransition{
		SessionID:   sessionID,
		FromPhase:   models.GamePhaseDay,
		ToPhase:     models.GamePhaseVoting,
		PhaseNumber: phaseNumber + 1,
		DayNumber:   dayNumber,
		Message:     "Voting phase begins.",
	}

	return transition, nil
}

// TransitionToNight moves from voting to night (after processing lynch)
func (pm *PhaseManager) TransitionToNight(ctx context.Context, sessionID uuid.UUID, lynchedPlayerID *uuid.UUID) (*PhaseTransition, error) {
	tx, err := pm.db.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	var currentPhase models.GamePhase
	var phaseNumber, dayNumber int
	err = tx.QueryRow(ctx, `
		SELECT current_phase, phase_number, day_number FROM game_sessions WHERE id = $1
	`, sessionID).Scan(&currentPhase, &phaseNumber, &dayNumber)
	if err != nil {
		return nil, err
	}

	if currentPhase != models.GamePhaseVoting {
		return nil, fmt.Errorf("can only transition to night from voting phase")
	}

	var deaths []uuid.UUID

	// Process lynch if someone was voted out
	if lynchedPlayerID != nil {
		// Update last lynched in state
		_, err = tx.Exec(ctx, `
			UPDATE game_sessions
			SET state = jsonb_set(state, '{last_lynched_player}', to_jsonb($1::text))
			WHERE id = $2
		`, lynchedPlayerID.String(), sessionID)
		if err != nil {
			return nil, err
		}

		// Must commit before calling death resolver
		if err := tx.Commit(ctx); err != nil {
			return nil, err
		}

		// Process lynch death (separate transaction)
		deathResult, err := pm.deathResolver.ResolveLynchDeath(ctx, sessionID, *lynchedPlayerID, phaseNumber)
		if err != nil {
			return nil, fmt.Errorf("failed to resolve lynch death: %w", err)
		}
		deaths = deathResult.DeadPlayers

		// Check win conditions
		winCondition, err := pm.winChecker.CheckAndFinalizeWin(ctx, sessionID)
		if err != nil {
			return nil, err
		}

		if winCondition.GameEnded {
			transition := &PhaseTransition{
				SessionID:    sessionID,
				FromPhase:    currentPhase,
				ToPhase:      models.GamePhaseNight,
				PhaseNumber:  phaseNumber + 1,
				DayNumber:    dayNumber,
				Deaths:       deaths,
				WinCondition: winCondition,
				Message:      "Lynch resulted in game end.",
			}
			return transition, nil
		}

		// Start new transaction for phase update
		tx, err = pm.db.Begin(ctx)
		if err != nil {
			return nil, err
		}
		defer tx.Rollback(ctx)
	}

	// Get alive players with night action roles
	rows, err := tx.Query(ctx, `
		SELECT DISTINCT role FROM game_players 
		WHERE session_id = $1 AND is_alive = true 
		AND role IN ('werewolf', 'seer', 'witch', 'bodyguard', 'cupid')
	`, sessionID)
	if err != nil {
		return nil, fmt.Errorf("failed to get alive roles: %w", err)
	}
	defer rows.Close()

	var aliveRoles []string
	for rows.Next() {
		var role string
		if err := rows.Scan(&role); err != nil {
			return nil, err
		}
		// Skip cupid after first night
		if role == "cupid" && dayNumber > 0 {
			continue
		}
		aliveRoles = append(aliveRoles, role)
	}

	// Convert to JSON array string
	rolesJSON, err := json.Marshal(aliveRoles)
	if err != nil {
		return nil, err
	}

	// Update to night phase
	phaseEndsAt := time.Now().Add(2 * time.Minute) // 2 minute night
	_, err = tx.Exec(ctx, `
		UPDATE game_sessions
		SET current_phase = $1, phase_number = phase_number + 1,
		    phase_started_at = NOW(), phase_ends_at = $2,
		    state = jsonb_set(state, '{actions_remaining}', $3::jsonb)
		WHERE id = $4
	`, models.GamePhaseNight, phaseEndsAt, rolesJSON, sessionID)
	if err != nil {
		return nil, err
	}

	// Create event
	message := fmt.Sprintf("Night falls on Day %d. ", dayNumber)
	if lynchedPlayerID != nil {
		message += fmt.Sprintf("A player was lynched. ")
	} else {
		message += "No one was lynched. "
	}
	message += "Roles, perform your actions."

	newPhase := models.GamePhaseNight
	eventData := models.EventData{
		NewPhase: &newPhase,
		Message:  message,
	}
	eventDataJSON, _ := json.Marshal(eventData)

	_, err = tx.Exec(ctx, `
		INSERT INTO game_events (id, session_id, phase_number, event_type, event_data, is_public)
		VALUES ($1, $2, $3, $4, $5, $6)
	`, uuid.New(), sessionID, phaseNumber+1, models.EventPhaseChange, eventDataJSON, true)
	if err != nil {
		return nil, err
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}

	// Schedule automatic transition to day phase (2 minute night)
	if pm.scheduler != nil {
		pm.scheduler.SchedulePhaseEnd(sessionID, 2*time.Minute)
	}

	transition := &PhaseTransition{
		SessionID:   sessionID,
		FromPhase:   models.GamePhaseVoting,
		ToPhase:     models.GamePhaseNight,
		PhaseNumber: phaseNumber + 1,
		DayNumber:   dayNumber,
		Deaths:      deaths,
		Message:     message,
	}

	return transition, nil
}

// CheckPhaseTimeout checks if current phase has timed out and auto-transitions
func (pm *PhaseManager) CheckPhaseTimeout(ctx context.Context, sessionID uuid.UUID) (bool, error) {
	var phaseEndsAt *time.Time
	var currentPhase models.GamePhase

	err := pm.db.QueryRow(ctx, `
		SELECT current_phase, phase_ends_at FROM game_sessions WHERE id = $1 AND status = 'active'
	`, sessionID).Scan(&currentPhase, &phaseEndsAt)
	if err != nil {
		return false, err
	}

	if phaseEndsAt == nil {
		return false, nil
	}

	// Check if timed out
	if time.Now().After(*phaseEndsAt) {
		// Auto-transition based on current phase
		switch currentPhase {
		case models.GamePhaseNight:
			_, err := pm.TransitionToDay(ctx, sessionID)
			return true, err
		case models.GamePhaseDay:
			_, err := pm.TransitionToVoting(ctx, sessionID)
			return true, err
		case models.GamePhaseVoting:
			// Process votes and transition to night
			// For timeout, no one is lynched (or the one with most votes)
			_, err := pm.TransitionToNight(ctx, sessionID, nil)
			return true, err
		}
	}

	return false, nil
}

// GetCurrentPhase returns the current game phase
func (pm *PhaseManager) GetCurrentPhase(ctx context.Context, sessionID uuid.UUID) (*GamePhaseInfo, error) {
	var info GamePhaseInfo
	err := pm.db.QueryRow(ctx, `
		SELECT current_phase, phase_number, day_number, phase_started_at, phase_ends_at
		FROM game_sessions WHERE id = $1
	`, sessionID).Scan(&info.Phase, &info.PhaseNumber, &info.DayNumber, &info.StartedAt, &info.EndsAt)
	if err != nil {
		return nil, err
	}
	info.SessionID = sessionID
	return &info, nil
}

type GamePhaseInfo struct {
	SessionID   uuid.UUID
	Phase       models.GamePhase
	PhaseNumber int
	DayNumber   int
	StartedAt   time.Time
	EndsAt      *time.Time
}
