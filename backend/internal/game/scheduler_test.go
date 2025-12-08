package game

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/kazerdira/wolverix/backend/internal/models"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestPhaseTimeoutScheduler tests that phases automatically transition on timeout
func TestPhaseTimeoutScheduler_AutoTransition(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()

	engine := NewEngine(db)
	scheduler := NewGameScheduler(db, engine)
	defer scheduler.Stop()

	sessionID := createTestGameSession(t, db, 6)

	// Schedule a phase end in 1 second
	scheduler.SchedulePhaseEnd(sessionID, 1*time.Second)

	// Verify timer is active
	assert.Equal(t, 1, scheduler.GetActiveTimers(), "Should have 1 active timer")

	// Wait for auto-transition
	time.Sleep(1500 * time.Millisecond)

	// Verify phase changed
	session := getGameSession(t, db, sessionID)
	// Phase should have transitioned from Night to Day
	assert.NotEqual(t, models.GamePhaseNight, session.CurrentPhase, "Phase should have transitioned")

	// Verify timer was cleaned up
	assert.Equal(t, 0, scheduler.GetActiveTimers(), "Timer should be cleaned up after transition")
}

// TestPhaseTimeoutScheduler_CancelTimer tests that timers can be cancelled
func TestPhaseTimeoutScheduler_CancelTimer(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()

	engine := NewEngine(db)
	scheduler := NewGameScheduler(db, engine)
	defer scheduler.Stop()

	sessionID := uuid.New()

	// Schedule a phase end
	scheduler.SchedulePhaseEnd(sessionID, 5*time.Second)
	assert.Equal(t, 1, scheduler.GetActiveTimers(), "Should have 1 active timer")

	// Cancel it
	scheduler.CancelPhaseEnd(sessionID)
	assert.Equal(t, 0, scheduler.GetActiveTimers(), "Timer should be cancelled")

	// Wait to ensure it doesn't fire
	time.Sleep(1 * time.Second)
	// If it fired, it would log an error, but won't affect this test
}

// TestPhaseTimeoutScheduler_ReplaceTimer tests that scheduling again replaces old timer
func TestPhaseTimeoutScheduler_ReplaceTimer(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()

	engine := NewEngine(db)
	scheduler := NewGameScheduler(db, engine)
	defer scheduler.Stop()

	sessionID := uuid.New()

	// Schedule first timer
	scheduler.SchedulePhaseEnd(sessionID, 10*time.Second)
	assert.Equal(t, 1, scheduler.GetActiveTimers(), "Should have 1 active timer")

	// Schedule again (should replace)
	scheduler.SchedulePhaseEnd(sessionID, 1*time.Second)
	assert.Equal(t, 1, scheduler.GetActiveTimers(), "Should still have only 1 active timer")

	// Old timer should be cancelled, only new one fires
	time.Sleep(1500 * time.Millisecond)
	assert.Equal(t, 0, scheduler.GetActiveTimers(), "Timer should have fired and been cleaned up")
}

// TestPhaseTimeoutChecker tests the background fallback mechanism
func TestPhaseTimeoutChecker_DetectsExpiredPhases(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()

	engine := NewEngine(db)
	scheduler := NewGameScheduler(db, engine)
	defer scheduler.Stop()

	// Create a game session with expired phase_ends_at
	sessionID := createTestGameSession(t, db, 6)

	// Manually set phase_ends_at to the past
	setPhaseEndsAt(t, db, sessionID, time.Now().Add(-10*time.Second))

	// Start the background checker
	scheduler.StartPhaseTimeoutChecker()

	// Wait for it to detect and transition
	time.Sleep(12 * time.Second) // Checker runs every 10 seconds

	// Verify phase was transitioned
	session := getGameSession(t, db, sessionID)
	_ = session // TODO: Verify phase changed
}

// TestPhaseTimeoutScheduler_MultipleGames tests handling multiple concurrent games
func TestPhaseTimeoutScheduler_MultipleGames(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()

	engine := NewEngine(db)
	scheduler := NewGameScheduler(db, engine)
	defer scheduler.Stop()

	// Schedule 5 different games
	sessions := make([]uuid.UUID, 5)
	for i := 0; i < 5; i++ {
		sessions[i] = uuid.New()
		scheduler.SchedulePhaseEnd(sessions[i], time.Duration(i+1)*time.Second)
	}

	assert.Equal(t, 5, scheduler.GetActiveTimers(), "Should have 5 active timers")

	// Wait for all to fire
	time.Sleep(6 * time.Second)

	assert.Equal(t, 0, scheduler.GetActiveTimers(), "All timers should have fired")
}

// TestPhaseTimeoutScheduler_RescheduleOnRestart tests recovering timers after restart
func TestPhaseTimeoutScheduler_RescheduleOnRestart(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()

	engine := NewEngine(db)
	ctx := context.Background()

	// Create game sessions with future phase_ends_at
	session1ID := createTestGameSession(t, db, 6)
	session2ID := createTestGameSession(t, db, 6)

	setPhaseEndsAt(t, db, session1ID, time.Now().Add(5*time.Second))
	setPhaseEndsAt(t, db, session2ID, time.Now().Add(10*time.Second))

	// Create new scheduler (simulating server restart)
	scheduler := NewGameScheduler(db, engine)
	defer scheduler.Stop()

	// Reschedule active sessions
	err := scheduler.RescheduleActiveSessions(ctx)
	require.NoError(t, err)

	// Verify timers were created
	assert.Equal(t, 2, scheduler.GetActiveTimers(), "Should have rescheduled 2 sessions")
}

// TestPhaseManager_SchedulesNextPhase tests that phase transitions schedule next phase
func TestPhaseManager_SchedulesNextPhase(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()

	engine := NewEngine(db)
	scheduler := NewGameScheduler(db, engine)
	defer scheduler.Stop()

	engine.phaseManager.SetScheduler(scheduler)

	ctx := context.Background()
	sessionID := createTestGameSession(t, db, 6)

	// Start in night phase
	// Transition to day
	_, err := engine.phaseManager.TransitionToDay(ctx, sessionID)
	require.NoError(t, err)

	// Verify scheduler has a timer for next phase
	assert.Equal(t, 1, scheduler.GetActiveTimers(), "Should schedule next phase end")

	// Get the phase_ends_at
	session := getGameSession(t, db, sessionID)
	assert.NotNil(t, session.PhaseEndsAt, "Should have phase_ends_at set")

	// Should be ~5 minutes in future (day phase duration)
	timeUntilEnd := time.Until(*session.PhaseEndsAt)
	assert.Greater(t, timeUntilEnd, 4*time.Minute, "Should be at least 4 minutes")
	assert.Less(t, timeUntilEnd, 6*time.Minute, "Should be at most 6 minutes")
}

// All helper functions are in test_helpers.go
