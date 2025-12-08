# Room Lifecycle Management System

## Overview
Professional-grade room timeout and cleanup system implementing multi-tier activity tracking with automated lifecycle management.

## Architecture Components

### 1. Database Layer
**Migration:** `002_add_room_activity_tracking.up.sql`
- `last_activity_at`: Tracks last meaningful activity (join, ready, settings)
- `timeout_warning_sent`: Prevents duplicate warnings
- `timeout_extended_count`: Tracks host extensions
- Indexes for efficient cleanup queries

### 2. Domain Model
**File:** `internal/models/models.go`
- Extended `Room` struct with activity tracking fields
- Added `RoomStatusAbandoned` status for auto-closed rooms

### 3. Lifecycle Manager Service
**File:** `internal/room/lifecycle.go`

**Core Features:**
- Background process running every 2 minutes
- Multi-tier timeout system with grace periods
- WebSocket notifications before closure
- Automatic cleanup of old rooms

**Timeout Tiers:**
1. **15-min warning** - Notification sent
2. **20-min inactivity** - Auto-close if only host or no activity
3. **1-hour absolute** - Max time for waiting rooms
4. **In-progress games** - Never timeout

**Retention Policies:**
- Abandoned rooms: 24 hours
- Completed games: 7 days

**Public Methods:**
- `Start(ctx)` - Begin background cleanup
- `UpdateActivity(ctx, roomID)` - Track room activity
- `ExtendTimeout(ctx, roomID, hostUserID)` - Host extends timeout

### 4. API Integration
**File:** `internal/api/handlers.go`

**Activity Tracking Points:**
- Player joins room → `UpdateActivity()`
- Player ready status → `UpdateActivity()`
- Settings changed → `UpdateActivity()`

**New Endpoint:**
```
POST /api/v1/rooms/:roomId/extend-timeout
Auth: Required (Host only)
Response: { message, extended_minutes }
```

### 5. Main Application
**File:** `cmd/server/main.go`
- Lifecycle manager started with context
- Graceful shutdown on SIGINT/SIGTERM
- Integrated with handler via interface

## Configuration Constants

```go
InactivityTimeout     = 20 * time.Minute  // Close if no activity
AbsoluteTimeout       = 1 * time.Hour     // Max time for waiting
WarningBeforeTimeout  = 5 * time.Minute   // Warning sent before close
CleanupInterval       = 2 * time.Minute   // Cleanup frequency
AbandonedRetention    = 24 * time.Hour    // Keep abandoned 24h
CompletedRetention    = 7 * 24 * time.Hour // Keep completed 7d
```

## WebSocket Events

**Timeout Warning:**
```json
{
  "type": "room_update",
  "data": {
    "action": "timeout_warning",
    "room_id": "uuid",
    "room_code": "ABC123",
    "minutes_left": 5,
    "message": "Room will close in 5 minutes..."
  }
}
```

**Room Closed:**
```json
{
  "type": "room_update",
  "data": {
    "action": "room_closed",
    "room_id": "uuid",
    "reason": "inactivity|timeout",
    "message": "Room has been closed..."
  }
}
```

**Timeout Extended:**
```json
{
  "type": "room_update",
  "data": {
    "action": "timeout_extended",
    "room_id": "uuid",
    "message": "Host extended the room timeout"
  }
}
```

## Cleanup Cycle Flow

```
Every 2 minutes:
1. Query rooms near timeout (15min inactive)
   → Send warnings via WebSocket
   → Mark warning_sent = true

2. Query rooms past inactivity (20min)
   → Set status = 'abandoned'
   → Notify players
   → Log closure

3. Query rooms past absolute (1h created)
   → Set status = 'abandoned'
   → Notify players
   → Log closure

4. Delete old abandoned rooms (>24h)
   → Hard delete from database

5. Delete old completed games (>7d)
   → Hard delete from database
```

## Benefits

### User Experience
✅ No abandoned rooms cluttering the list
✅ Clear warnings before closure
✅ Host can extend if needed
✅ Fair timeout policies

### System Health
✅ Automatic cleanup prevents bloat
✅ Efficient indexed queries
✅ Minimal performance impact
✅ Graceful shutdown handling

### Operational
✅ Detailed logging for debugging
✅ Configurable timeout periods
✅ WebSocket real-time notifications
✅ No manual intervention needed

## Testing

**Manual Test:**
1. Create room
2. Wait 15 minutes → Should receive warning
3. Wait 5 more minutes → Room auto-closed
4. Check `status = 'abandoned'`

**Host Extension Test:**
1. Create room
2. Receive warning
3. Call `/extend-timeout`
4. Wait another 20 minutes before timeout

**Cleanup Test:**
1. Create abandoned room with old `finished_at`
2. Wait for cleanup cycle (2min)
3. Verify room deleted

## Monitoring

**Log Patterns:**
```
🔄 Room Lifecycle Manager started
🧹 Running room cleanup cycle...
⚠️  Sent timeout warning to room ABC123
🚪 Closed inactive room ABC123 - 1 players
⏱️  Closed expired room XYZ789 - 3 players
🗑️  Deleted 5 old abandoned rooms
✅ Cleanup cycle complete
```

## Future Enhancements

1. **Configurable timeouts per room** - Premium rooms get longer timeout
2. **Activity heuristics** - Voice activity counts as engagement
3. **Metrics dashboard** - Track closure reasons, avg room lifetime
4. **Smart warnings** - Warn at 50% timeout, not fixed 5min
5. **Room pausing** - Host can pause/resume timeout clock

## Migration Rollback

If needed to rollback:
```sql
-- Run 002_add_room_activity_tracking.down.sql
DROP INDEX IF EXISTS idx_rooms_cleanup;
DROP INDEX IF EXISTS idx_rooms_status_activity;
ALTER TABLE rooms DROP COLUMN timeout_extended_count;
ALTER TABLE rooms DROP COLUMN timeout_warning_sent;
ALTER TABLE rooms DROP COLUMN last_activity_at;
```

Then remove lifecycle manager from main.go and rebuild.
