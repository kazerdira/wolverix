package game

import (
	"context"
	"fmt"
	"log"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/kazerdira/wolverix/backend/internal/models"
)

// GameScheduler manages automatic phase transitions based on timeouts
type GameScheduler struct {
	db     *pgxpool.Pool
	engine *Engine
	timers map[uuid.UUID]*time.Timer
	mu     sync.Mutex
	ctx    context.Context
	cancel context.CancelFunc
}

// NewGameScheduler creates a new game scheduler
func NewGameScheduler(db *pgxpool.Pool, engine *Engine) *GameScheduler {
	ctx, cancel := context.WithCancel(context.Background())
	return &GameScheduler{
		db:     db,
		engine: engine,
		timers: make(map[uuid.UUID]*time.Timer),
		ctx:    ctx,
		cancel: cancel,
	}
}

// SchedulePhaseEnd schedules an automatic phase transition
func (gs *GameScheduler) SchedulePhaseEnd(sessionID uuid.UUID, duration time.Duration) {
	gs.mu.Lock()
	defer gs.mu.Unlock()

	// Cancel existing timer for this session
	if timer, exists := gs.timers[sessionID]; exists {
		timer.Stop()
		delete(gs.timers, sessionID)
	}

	// Schedule automatic transition
	timer := time.AfterFunc(duration, func() {
		ctx := context.Background()
		log.Printf("[Scheduler] Auto-transitioning phase for session %s", sessionID)

		_, err := gs.engine.TransitionPhase(ctx, sessionID)
		if err != nil {
			log.Printf("[Scheduler] Auto-transition failed for session %s: %v", sessionID, err)
		} else {
			log.Printf("[Scheduler] Auto-transition succeeded for session %s", sessionID)
		}

		// Clean up timer
		gs.mu.Lock()
		delete(gs.timers, sessionID)
		gs.mu.Unlock()
	})

	gs.timers[sessionID] = timer
	log.Printf("[Scheduler] Scheduled phase end for session %s in %v", sessionID, duration)
}

// CancelPhaseEnd cancels a scheduled phase transition (e.g., when game ends)
func (gs *GameScheduler) CancelPhaseEnd(sessionID uuid.UUID) {
	gs.mu.Lock()
	defer gs.mu.Unlock()

	if timer, exists := gs.timers[sessionID]; exists {
		timer.Stop()
		delete(gs.timers, sessionID)
		log.Printf("[Scheduler] Cancelled scheduled phase end for session %s", sessionID)
	}
}

// StartPhaseTimeoutChecker starts a background goroutine that checks for expired phases
// This is a fallback mechanism in case timers fail
func (gs *GameScheduler) StartPhaseTimeoutChecker() {
	ticker := time.NewTicker(10 * time.Second)

	go func() {
		for {
			select {
			case <-ticker.C:
				gs.checkAndTransitionExpiredPhases()
			case <-gs.ctx.Done():
				ticker.Stop()
				log.Println("[Scheduler] Phase timeout checker stopped")
				return
			}
		}
	}()

	log.Println("[Scheduler] Phase timeout checker started")
}

// checkAndTransitionExpiredPhases finds and transitions all games with expired phases
func (gs *GameScheduler) checkAndTransitionExpiredPhases() {
	ctx := context.Background()

	// Find all active sessions with expired phases
	rows, err := gs.db.Query(ctx, `
		SELECT id, current_phase, phase_ends_at
		FROM game_sessions
		WHERE status = $1 
		  AND phase_ends_at IS NOT NULL 
		  AND phase_ends_at < NOW()
		ORDER BY phase_ends_at ASC
		LIMIT 100
	`, models.GameStatusActive)
	if err != nil {
		log.Printf("[Scheduler] Failed to query expired phases: %v", err)
		return
	}
	defer rows.Close()

	expiredSessions := []struct {
		ID        uuid.UUID
		Phase     models.GamePhase
		ExpiredAt time.Time
	}{}

	for rows.Next() {
		var session struct {
			ID        uuid.UUID
			Phase     models.GamePhase
			ExpiredAt time.Time
		}
		if err := rows.Scan(&session.ID, &session.Phase, &session.ExpiredAt); err != nil {
			log.Printf("[Scheduler] Failed to scan expired session: %v", err)
			continue
		}
		expiredSessions = append(expiredSessions, session)
	}

	if len(expiredSessions) == 0 {
		return
	}

	log.Printf("[Scheduler] Found %d expired phases to transition", len(expiredSessions))

	// Transition each expired session
	for _, session := range expiredSessions {
		timeSinceExpiry := time.Since(session.ExpiredAt)
		log.Printf("[Scheduler] Transitioning expired phase for session %s (phase: %s, expired %v ago)",
			session.ID, session.Phase, timeSinceExpiry)

		_, err := gs.engine.TransitionPhase(ctx, session.ID)
		if err != nil {
			log.Printf("[Scheduler] Failed to transition expired phase for session %s: %v", session.ID, err)
		} else {
			log.Printf("[Scheduler] Successfully transitioned expired phase for session %s", session.ID)
		}
	}
}

// Stop stops the scheduler and cancels all timers
func (gs *GameScheduler) Stop() {
	gs.cancel()

	gs.mu.Lock()
	defer gs.mu.Unlock()

	// Cancel all active timers
	for sessionID, timer := range gs.timers {
		timer.Stop()
		log.Printf("[Scheduler] Cancelled timer for session %s during shutdown", sessionID)
	}
	gs.timers = make(map[uuid.UUID]*time.Timer)

	log.Println("[Scheduler] Scheduler stopped")
}

// GetActiveTimers returns the number of active timers (for monitoring)
func (gs *GameScheduler) GetActiveTimers() int {
	gs.mu.Lock()
	defer gs.mu.Unlock()
	return len(gs.timers)
}

// RescheduleActiveSessions reschedules phase transitions for all active sessions
// Useful when restarting the server
func (gs *GameScheduler) RescheduleActiveSessions(ctx context.Context) error {
	rows, err := gs.db.Query(ctx, `
		SELECT id, phase_ends_at
		FROM game_sessions
		WHERE status = $1 
		  AND phase_ends_at IS NOT NULL 
		  AND phase_ends_at > NOW()
	`, models.GameStatusActive)
	if err != nil {
		return fmt.Errorf("failed to query active sessions: %w", err)
	}
	defer rows.Close()

	count := 0
	for rows.Next() {
		var sessionID uuid.UUID
		var phaseEndsAt time.Time
		if err := rows.Scan(&sessionID, &phaseEndsAt); err != nil {
			log.Printf("[Scheduler] Failed to scan active session: %v", err)
			continue
		}

		duration := time.Until(phaseEndsAt)
		if duration > 0 {
			gs.SchedulePhaseEnd(sessionID, duration)
			count++
		}
	}

	log.Printf("[Scheduler] Rescheduled %d active sessions", count)
	return nil
}
