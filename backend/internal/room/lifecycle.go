package room

import (
	"context"
	"log"
	"time"

	"github.com/google/uuid"
	"github.com/kazerdira/wolverix/backend/internal/database"
	"github.com/kazerdira/wolverix/backend/internal/models"
	ws "github.com/kazerdira/wolverix/backend/internal/websocket"
)

// Lifecycle manager handles room timeouts and cleanup
type LifecycleManager struct {
	db    *database.Database
	wsHub *ws.Hub
}

// Configuration constants
const (
	// Timeouts
	InactivityTimeout    = 20 * time.Minute // Close if no activity
	AbsoluteTimeout      = 1 * time.Hour    // Max time for waiting rooms
	WarningBeforeTimeout = 5 * time.Minute  // Warning sent before closure
	CleanupInterval      = 2 * time.Minute  // How often to run cleanup

	// Retention periods
	AbandonedRetention = 24 * time.Hour     // Keep abandoned rooms for 24h
	CompletedRetention = 7 * 24 * time.Hour // Keep completed games for 7 days
)

func NewLifecycleManager(db *database.Database, wsHub *ws.Hub) *LifecycleManager {
	return &LifecycleManager{
		db:    db,
		wsHub: wsHub,
	}
}

// Start begins the background cleanup process
func (lm *LifecycleManager) Start(ctx context.Context) {
	ticker := time.NewTicker(CleanupInterval)
	defer ticker.Stop()

	log.Printf("🔄 Room Lifecycle Manager started (cleanup every %v)", CleanupInterval)

	// Run immediately on start
	lm.runCleanupCycle(ctx)

	for {
		select {
		case <-ctx.Done():
			log.Printf("⏹️  Room Lifecycle Manager stopped")
			return
		case <-ticker.C:
			lm.runCleanupCycle(ctx)
		}
	}
}

// runCleanupCycle performs all cleanup tasks
func (lm *LifecycleManager) runCleanupCycle(ctx context.Context) {
	log.Printf("🧹 Running room cleanup cycle...")

	// Step 1: Send warnings for rooms about to timeout
	lm.sendTimeoutWarnings(ctx)

	// Step 2: Close inactive waiting rooms
	lm.closeInactiveRooms(ctx)

	// Step 3: Close rooms that hit absolute timeout
	lm.closeExpiredRooms(ctx)

	// Step 4: Delete old abandoned/completed rooms
	lm.deleteOldRooms(ctx)

	log.Printf("✅ Cleanup cycle complete")
}

// sendTimeoutWarnings sends 5-minute warning to rooms about to timeout
func (lm *LifecycleManager) sendTimeoutWarnings(ctx context.Context) {
	warningThreshold := time.Now().Add(-InactivityTimeout + WarningBeforeTimeout)

	rows, err := lm.db.PG.Query(ctx, `
		SELECT id, room_code, name, host_user_id, current_players
		FROM rooms
		WHERE status = 'waiting'
		  AND timeout_warning_sent = false
		  AND last_activity_at < $1
	`, warningThreshold)

	if err != nil {
		log.Printf("❌ Failed to query rooms for warnings: %v", err)
		return
	}
	defer rows.Close()

	warnCount := 0
	for rows.Next() {
		var roomID uuid.UUID
		var roomCode, name string
		var hostUserID uuid.UUID
		var currentPlayers int

		if err := rows.Scan(&roomID, &roomCode, &name, &hostUserID, &currentPlayers); err != nil {
			log.Printf("❌ Failed to scan room: %v", err)
			continue
		}

		// Send warning via WebSocket
		lm.wsHub.BroadcastToRoom(roomID, models.WSTypeRoomUpdate, map[string]interface{}{
			"action":       "timeout_warning",
			"room_id":      roomID,
			"room_code":    roomCode,
			"minutes_left": int(WarningBeforeTimeout.Minutes()),
			"message":      "This room will close in 5 minutes due to inactivity. Host can extend the timeout.",
		})

		// Mark warning as sent
		_, err = lm.db.PG.Exec(ctx, `
			UPDATE rooms SET timeout_warning_sent = true WHERE id = $1
		`, roomID)

		if err != nil {
			log.Printf("❌ Failed to mark warning sent for room %s: %v", roomCode, err)
		} else {
			warnCount++
			log.Printf("⚠️  Sent timeout warning to room %s (%s) - %d players", roomCode, name, currentPlayers)
		}
	}

	if warnCount > 0 {
		log.Printf("⚠️  Sent %d timeout warnings", warnCount)
	}
}

// closeInactiveRooms closes rooms with no recent activity
func (lm *LifecycleManager) closeInactiveRooms(ctx context.Context) {
	inactivityThreshold := time.Now().Add(-InactivityTimeout)

	rows, err := lm.db.PG.Query(ctx, `
		SELECT id, room_code, name, current_players
		FROM rooms
		WHERE status = 'waiting'
		  AND last_activity_at < $1
		  AND (current_players = 1 OR last_activity_at < $2)
	`, inactivityThreshold, time.Now().Add(-InactivityTimeout))

	if err != nil {
		log.Printf("❌ Failed to query inactive rooms: %v", err)
		return
	}
	defer rows.Close()

	closedCount := 0
	for rows.Next() {
		var roomID uuid.UUID
		var roomCode, name string
		var currentPlayers int

		if err := rows.Scan(&roomID, &roomCode, &name, &currentPlayers); err != nil {
			log.Printf("❌ Failed to scan room: %v", err)
			continue
		}

		// Close the room
		if lm.closeRoom(ctx, roomID, "inactivity") {
			closedCount++
			log.Printf("🚪 Closed inactive room %s (%s) - %d players, no activity for %v",
				roomCode, name, currentPlayers, InactivityTimeout)
		}
	}

	if closedCount > 0 {
		log.Printf("🚪 Closed %d inactive rooms", closedCount)
	}
}

// closeExpiredRooms closes rooms that exceeded absolute timeout
func (lm *LifecycleManager) closeExpiredRooms(ctx context.Context) {
	absoluteThreshold := time.Now().Add(-AbsoluteTimeout)

	rows, err := lm.db.PG.Query(ctx, `
		SELECT id, room_code, name, current_players
		FROM rooms
		WHERE status = 'waiting'
		  AND created_at < $1
	`, absoluteThreshold)

	if err != nil {
		log.Printf("❌ Failed to query expired rooms: %v", err)
		return
	}
	defer rows.Close()

	closedCount := 0
	for rows.Next() {
		var roomID uuid.UUID
		var roomCode, name string
		var currentPlayers int

		if err := rows.Scan(&roomID, &roomCode, &name, &currentPlayers); err != nil {
			log.Printf("❌ Failed to scan room: %v", err)
			continue
		}

		// Close the room
		if lm.closeRoom(ctx, roomID, "timeout") {
			closedCount++
			log.Printf("⏱️  Closed expired room %s (%s) - %d players, exceeded %v",
				roomCode, name, currentPlayers, AbsoluteTimeout)
		}
	}

	if closedCount > 0 {
		log.Printf("⏱️  Closed %d expired rooms", closedCount)
	}
}

// closeRoom marks a room as abandoned and notifies players
func (lm *LifecycleManager) closeRoom(ctx context.Context, roomID uuid.UUID, reason string) bool {
	// Update room status
	_, err := lm.db.PG.Exec(ctx, `
		UPDATE rooms 
		SET status = 'abandoned', finished_at = NOW(), updated_at = NOW()
		WHERE id = $1
	`, roomID)

	if err != nil {
		log.Printf("❌ Failed to close room %s: %v", roomID, err)
		return false
	}

	// Notify all players
	lm.wsHub.BroadcastToRoom(roomID, models.WSTypeRoomUpdate, map[string]interface{}{
		"action":  "room_closed",
		"room_id": roomID,
		"reason":  reason,
		"message": "This room has been closed due to " + reason,
	})

	return true
}

// deleteOldRooms removes old abandoned and completed rooms
func (lm *LifecycleManager) deleteOldRooms(ctx context.Context) {
	abandonedThreshold := time.Now().Add(-AbandonedRetention)
	completedThreshold := time.Now().Add(-CompletedRetention)

	// Delete old abandoned rooms
	abandonedResult, err := lm.db.PG.Exec(ctx, `
		DELETE FROM rooms
		WHERE status = 'abandoned'
		  AND finished_at < $1
	`, abandonedThreshold)

	if err != nil {
		log.Printf("❌ Failed to delete old abandoned rooms: %v", err)
	} else if abandonedResult.RowsAffected() > 0 {
		log.Printf("🗑️  Deleted %d old abandoned rooms (>24h)", abandonedResult.RowsAffected())
	}

	// Delete old completed rooms
	completedResult, err := lm.db.PG.Exec(ctx, `
		DELETE FROM rooms
		WHERE status IN ('finished', 'completed')
		  AND finished_at < $1
	`, completedThreshold)

	if err != nil {
		log.Printf("❌ Failed to delete old completed rooms: %v", err)
	} else if completedResult.RowsAffected() > 0 {
		log.Printf("🗑️  Deleted %d old completed rooms (>7d)", completedResult.RowsAffected())
	}
}

// UpdateActivity updates the last_activity_at timestamp for a room
func (lm *LifecycleManager) UpdateActivity(ctx context.Context, roomID uuid.UUID) error {
	_, err := lm.db.PG.Exec(ctx, `
		UPDATE rooms 
		SET last_activity_at = NOW(), 
		    timeout_warning_sent = false,
		    updated_at = NOW()
		WHERE id = $1
	`, roomID)

	if err != nil {
		log.Printf("❌ Failed to update room activity for %s: %v", roomID, err)
		return err
	}

	return nil
}

// ExtendTimeout allows host to extend the room timeout
func (lm *LifecycleManager) ExtendTimeout(ctx context.Context, roomID uuid.UUID, hostUserID uuid.UUID) error {
	// Verify the user is the host
	var currentHostID uuid.UUID
	var currentStatus string
	err := lm.db.PG.QueryRow(ctx, `
		SELECT host_user_id, status FROM rooms WHERE id = $1
	`, roomID).Scan(&currentHostID, &currentStatus)

	if err != nil {
		return err
	}

	if currentHostID != hostUserID {
		return ErrNotHost
	}

	if currentStatus != string(models.RoomStatusWaiting) {
		return ErrRoomNotWaiting
	}

	// Update activity and increment extend count
	_, err = lm.db.PG.Exec(ctx, `
		UPDATE rooms 
		SET last_activity_at = NOW(),
		    timeout_warning_sent = false,
		    timeout_extended_count = timeout_extended_count + 1,
		    updated_at = NOW()
		WHERE id = $1
	`, roomID)

	if err != nil {
		log.Printf("❌ Failed to extend timeout for room %s: %v", roomID, err)
		return err
	}

	// Notify players
	lm.wsHub.BroadcastToRoom(roomID, models.WSTypeRoomUpdate, map[string]interface{}{
		"action":  "timeout_extended",
		"room_id": roomID,
		"message": "Host extended the room timeout",
	})

	log.Printf("⏰ Room %s timeout extended by host", roomID)
	return nil
}

// Custom errors
var (
	ErrNotHost        = &RoomError{"user is not the room host"}
	ErrRoomNotWaiting = &RoomError{"room is not in waiting status"}
)

type RoomError struct {
	Message string
}

func (e *RoomError) Error() string {
	return e.Message
}
