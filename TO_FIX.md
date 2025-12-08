# Wolverix Game Engine - Critical Fixes Required

**Status**: 🔴 Multiple Critical Issues Identified  
**Last Updated**: December 8, 2025  
**Reviewers**: GitHub Copilot + External Expert

---

## 🔴 PRIORITY 0 - CRITICAL (Must Fix Before Any Testing)

### 1. ❌ Lovers Team Assignment is BROKEN
**Location**: `backend/internal/game/engine.go:370` - `getTeam(role)`  
**Problem**: Lovers are assigned to original team (Werewolves/Villagers), NOT `TeamLovers`  
**Impact**: Lovers win condition will NEVER trigger. Even if 2 lovers are last alive, they're counted as werewolf/villager  
**Root Cause**:
```go
// Current: getTeam() only checks role, not lover_id
func getTeam(role models.Role) models.Team {
    switch role {
    case models.RoleWerewolf:
        return models.TeamWerewolves
    case models.RoleTanner:
        return models.TeamNeutral
    default:
        return models.TeamVillagers
    }
}
```
**Fix Required**:
- When Cupid assigns lovers, UPDATE both players' `team` column to `TeamLovers`
- OR modify `getTeam()` to check `lover_id` field dynamically
- Update `game_players` table: `UPDATE game_players SET team = 'lovers' WHERE lover_id IS NOT NULL`

**Expert Review**: ⚠️ Not mentioned by expert (missed critical bug)

---

### 2. ❌ Cupid Lovers Assignment Never Executes
**Location**: `backend/internal/game/action_processor.go` - `processCupidChoose()`  
**Problem**: Function exists but never actually sets `lover_id` in database  
**Impact**: Lover mechanics completely non-functional  
**Evidence**: No SQL UPDATE statement for `lover_id` field in entire codebase  
**Fix Required**:
```go
func (e *Engine) processCupidChoose(ctx context.Context, sessionID, userID uuid.UUID, target1ID, target2ID *uuid.UUID) error {
    // Add:
    _, err = e.db.Exec(ctx, `
        UPDATE game_players 
        SET lover_id = $1, team = 'lovers'
        WHERE session_id = $2 AND user_id = $3
    `, target2ID, sessionID, target1ID)
    
    _, err = e.db.Exec(ctx, `
        UPDATE game_players 
        SET lover_id = $1, team = 'lovers'
        WHERE session_id = $2 AND user_id = $3
    `, target1ID, sessionID, target2ID)
}
```

**Expert Review**: ⚠️ Not mentioned by expert

---

### 3. ❌ Night Action Order is WRONG (Expert Review)
**Location**: `backend/internal/game/night_coordinator.go:24` - `ProcessNightActions()`  
**Problem**: Actions processed as they arrive, not in canonical order  
**Impact**: Wrong game outcomes (bodyguard protecting after witch poison, etc.)  
**Expert Scenario**:
```
23:01:00 - Witch poisons Player A
23:01:05 - Werewolves vote Player A  
23:01:10 - Bodyguard protects Player A
Result: Player A's fate depends on processing order, NOT game rules
```
**Current Code Issue**:
```go
// night_coordinator.go - queries actions immediately from DB
werewolfTarget, err := nc.getWerewolfTarget(ctx, sessionID, phaseNumber)
// This reads from game_actions table as they arrive
```

**Fix Required**: Implement **Collect-Then-Resolve Pattern**
```go
// 1. Collect phase - wait for all actions or timeout
func (nc *NightCoordinator) CollectNightActions(ctx context.Context, sessionID uuid.UUID) (*NightActions, error) {
    // Get all actions submitted during night phase
    actions := &NightActions{
        WerewolfVotes: make(map[uuid.UUID]uuid.UUID),
    }
    
    rows, _ := nc.db.Query(ctx, `
        SELECT player_id, action_type, target_player_id 
        FROM game_actions 
        WHERE session_id = $1 AND phase_number = $2
    `, sessionID, phaseNumber)
    
    // Collect all actions into struct
    return actions, nil
}

// 2. Resolve phase - process in CANONICAL order
func (nc *NightCoordinator) ResolveNightActions(ctx context.Context, sessionID uuid.UUID, actions *NightActions) (*NightResult, error) {
    result := &NightResult{}
    
    // Step 1: Cupid (first night only) - already processed
    // Step 2: Werewolf target selection (majority vote)
    werewolfTarget := nc.tallyWerewolfVotes(actions.WerewolfVotes)
    
    // Step 3: Seer divination (doesn't affect deaths)
    // Step 4: Bodyguard protection (prevents werewolf kill)
    isProtected := actions.BodyguardTarget != nil && 
                   werewolfTarget != nil && 
                   *actions.BodyguardTarget == *werewolfTarget
    
    // Step 5: Witch actions (heal cancels werewolf, poison adds death)
    isHealed := actions.WitchHealUsed && !isProtected
    
    // Final death calculation
    if werewolfTarget != nil && !isProtected && !isHealed {
        result.Deaths = append(result.Deaths, *werewolfTarget)
    }
    if actions.WitchPoisonTarget != nil {
        result.Deaths = append(result.Deaths, *actions.WitchPoisonTarget)
    }
    
    return result, nil
}
```

**Expert Review**: ✅ 🟠 P1 Priority - "Wrong game outcomes"

---

### 4. ❌ Phase Timeout Scheduler MISSING (Expert Review)
**Location**: NOWHERE - doesn't exist  
**Problem**: You have `phase_ends_at` timestamp but NO automatic phase transitions  
**Current Behavior**: Game waits for client to call `/api/v1/games/{id}/transition` endpoint  
**Attack Vector**: Malicious client can stall game indefinitely by never calling transition  
**Impact**: Games hang forever, terrible UX  

**Fix Required**: Add background scheduler
```go
// cmd/server/main.go
type GameScheduler struct {
    engine  *game.Engine
    timers  map[uuid.UUID]*time.Timer
    mu      sync.Mutex
}

func NewGameScheduler(engine *game.Engine) *GameScheduler {
    return &GameScheduler{
        engine: engine,
        timers: make(map[uuid.UUID]*time.Timer),
    }
}

func (gs *GameScheduler) SchedulePhaseEnd(sessionID uuid.UUID, duration time.Duration) {
    gs.mu.Lock()
    defer gs.mu.Unlock()
    
    // Cancel existing timer
    if timer, exists := gs.timers[sessionID]; exists {
        timer.Stop()
    }
    
    // Schedule automatic transition
    gs.timers[sessionID] = time.AfterFunc(duration, func() {
        ctx := context.Background()
        _, err := gs.engine.TransitionPhase(ctx, sessionID)
        if err != nil {
            log.Printf("Auto-transition failed for session %s: %v", sessionID, err)
        }
        
        gs.mu.Lock()
        delete(gs.timers, sessionID)
        gs.mu.Unlock()
    })
}

// Start background checker for stuck games
func (gs *GameScheduler) StartPhaseTimeoutChecker(ctx context.Context) {
    ticker := time.NewTicker(10 * time.Second)
    go func() {
        for {
            select {
            case <-ticker.C:
                gs.checkAndTransitionExpiredPhases(ctx)
            case <-ctx.Done():
                ticker.Stop()
                return
            }
        }
    }()
}
```

**Usage in phase_manager.go**:
```go
func (pm *PhaseManager) TransitionToDay(ctx context.Context, sessionID uuid.UUID) (*PhaseTransition, error) {
    // ... existing logic ...
    
    phaseEndsAt := time.Now().Add(5 * time.Minute)
    
    // Schedule automatic transition
    pm.scheduler.SchedulePhaseEnd(sessionID, 5*time.Minute)
    
    return transition, nil
}
```

**Expert Review**: ✅ 🔴 P0 - "Games will hang forever"

---

### 5. ❌ Hunter Revenge is INCOMPLETE
**Location**: `backend/internal/game/death_resolver.go:96-105` - `handleHunterDeath()`  
**Problem**: Returns `TargetID: nil` with comment "Hunter must choose target via action"  
**Issue**: NO mechanism to pause death resolution and wait for hunter input  
**Impact**: Hunter ability doesn't work at all  
**Current Code**:
```go
func (dr *DeathResolver) handleHunterDeath(...) (*HunterShotResult, error) {
    // ... marks hunter shot as used ...
    
    return &HunterShotResult{
        HunterID: hunterID,
        TargetID: nil,  // ❌ Hunter must choose target via action
    }, nil
}

// In ProcessDeath line 99:
if hunterShot.TargetID != nil {  // ❌ This NEVER executes!
    // Recursively process hunter's target death
}
```

**Fix Options**:
1. **Option A**: Implement HUNTER_REVENGE phase (complex, proper solution)
2. **Option B**: Remove Hunter role entirely (quick MVP fix)
3. **Option C**: Auto-random hunter target (playable but not ideal)

**Recommended**: Option B for now, implement Option A post-MVP

**Expert Review**: ⚠️ Not mentioned by expert

---

### 6. ❌ Information Leakage in Error Messages (Expert Review)
**Location**: Multiple places in `backend/internal/game/action_processor.go`  
**Problem**: Error messages reveal secret information  
**Examples**:
```go
// Line 26 - LEAK: Confirms target is werewolf
if player.Role != models.RoleWerewolf {
    return fmt.Errorf("only werewolves can vote for kills")
}

// Line 48 - LEAK: Confirms target is werewolf
if target.Team == models.TeamWerewolves {
    return fmt.Errorf("werewolves cannot target each other")
}

// handlers.go - LEAK: Timing reveals role
// If action takes longer for certain roles, clients can measure
```

**Fix Required**:
```go
// Generic errors only
if !e.canPerformAction(player, action, target) {
    return fmt.Errorf("invalid action")  // ❌ Don't say WHY
}

// Add constant-time responses
func (e *Engine) processSeerDivine(...) error {
    defer func() {
        time.Sleep(time.Duration(500+rand.Intn(1000)) * time.Millisecond)
    }()
    // ... process ...
}
```

**Expert Review**: ✅ 🟡 P2 - "Cheating becomes possible"

---

## 🟠 PRIORITY 1 - HIGH (Breaks Core Gameplay)

### 7. ⚠️ Mayor Role is INCOMPLETE
**Location**: `backend/internal/game/vote_manager.go:27`  
**Problem**: Mayor mentioned in comments but has NO implementation  
**Current**: `TieBreaker *uuid.UUID // Who broke the tie (e.g., Mayor)`  
**Reality**: Mayor has no double vote or tie-breaking power  
**Decision Required**: Implement or remove from `models.Role`

**Expert Review**: ⚠️ Not mentioned

---

### 8. ⚠️ Medium Role is UNDEFINED
**Location**: `backend/internal/models/models.go` - `RoleMedium` constant  
**Problem**: ZERO implementation anywhere  
**Impact**: If assigned, player has no actions (dead weight)  
**Typical Ability**: Can communicate with dead players  
**Decision Required**: Remove or implement post-MVP

**Expert Review**: ⚠️ Not mentioned

---

### 9. ⚠️ Little Girl Role is UNDEFINED
**Location**: `backend/internal/models/models.go` - `RoleLittleGirl` constant  
**Problem**: No implementation  
**Typical Ability**: Can peek during werewolf voting  
**Decision Required**: Remove or implement post-MVP

**Expert Review**: ⚠️ Not mentioned

---

### 10. ⚠️ Night Phase Can Deadlock
**Location**: `backend/internal/game/night_coordinator.go:119` - `IsNightPhaseComplete()`  
**Problem**: Checks if `actions_remaining` array is empty  
**Deadlock Scenario**: 
  - Player with required role dies mid-night
  - Player disconnects permanently
  - Their action stays in `actions_remaining` forever
  - Night phase never completes
**Fix Required**: 
  - Add timeout mechanism (30 seconds per action)
  - Auto-skip if player dead/disconnected
  - Remove dead player roles from `actions_remaining`

**Expert Review**: ⚠️ Not directly mentioned, but related to reconnection handling

---

### 11. ⚠️ WebSocket Reconnection Missing (Expert Review)
**Location**: `backend/internal/websocket/hub.go`  
**Problem**: Client disconnect = permanent removal, no state recovery  
**Impact**: Network hiccup = forced game loss  
**Current Behavior**:
```go
// hub.go - client removed on disconnect
client.conn.Close()
delete(h.clients, client)  // Gone forever
```

**Fix Required**:
```sql
-- Add to game_players table
ALTER TABLE game_players 
ADD COLUMN connection_state VARCHAR(20) DEFAULT 'connected' 
    CHECK (connection_state IN ('connected', 'disconnected', 'afk', 'kicked')),
ADD COLUMN disconnected_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN auto_action_enabled BOOLEAN DEFAULT true;
```

```go
// hub.go
func (h *Hub) HandleReconnect(client *Client, userID uuid.UUID) {
    // Find active game session
    activeSession := h.getActiveSessionForUser(userID)
    if activeSession != nil {
        // Restore full game state
        h.sendGameStateRecovery(client, activeSession)
        // Update connection_state
        h.updateConnectionState(userID, "connected")
    }
}

// Auto-actions for disconnected players
func (h *Hub) handleDisconnectedPlayer(sessionID, playerID uuid.UUID) {
    player := h.getPlayer(sessionID, playerID)
    
    switch player.Role {
    case RoleWerewolf:
        // Auto-abstain from vote
    case RoleSeer:
        // Skip divine
    case RoleWitch:
        // Skip potions
    case RoleBodyguard:
        // Skip protection
    default:
        // Auto-skip lynch vote
    }
}
```

**Expert Review**: ✅ 🟠 P1 - "Players will rage-quit"

---

### 12. ⚠️ Witch Heal Logic Unclear
**Location**: `backend/internal/game/night_coordinator.go:57`  
**Problem**: Witch only sees attack if bodyguard didn't protect  
**Current Code**:
```go
if werewolfTarget != nil && !results.IsProtected {
    healed, err := nc.isHealed(ctx, sessionID, phaseNumber, *werewolfTarget)
}
```
**Question**: Should witch know who was attacked even if bodyguard protected?  
**Typical Rules**: Witch should see attack regardless, but heal is wasted if already protected  
**Fix Required**: Clarify game rules, adjust logic accordingly

**Expert Review**: ⚠️ Not mentioned

---

### 13. ⚠️ Vote Tie Resolution Missing
**Location**: `backend/internal/game/vote_manager.go:178`  
**Problem**: Function signature exists: `determineLynchFromTie()` but implementation unclear  
**Impact**: Tied votes may cause crash or incorrect behavior  
**Options**:
  - Random selection
  - Mayor decides (if Mayor implemented)
  - Revote phase
  - No lynch
**Fix Required**: Implement clear tie-breaking logic

**Expert Review**: ⚠️ Not mentioned

---

## 🟡 PRIORITY 2 - MEDIUM (Improve Quality)

### 14. 📊 Werewolf Count Scaling is HARSH
**Location**: `backend/internal/game/engine.go:357` - `calculateWerewolfCount()`  
**Current Formula**:
```go
func calculateWerewolfCount(playerCount int) int {
    if playerCount <= 8 { return 2 }      // 25%
    else if playerCount <= 12 { return 3 } // 25-33%
    else if playerCount <= 18 { return 4 } // 22-33%
    return 5                               // 21-26%
}
```
**Issue**: Jump from 8→9 players goes from 2→3 wolves (25%→33% sudden spike)  
**Balance Concern**: 9-player games heavily favor werewolves  
**Suggestion**: Consider 3 wolves starting at 10-11 players  
**Decision**: Playtest and adjust

**Expert Review**: ⚠️ Not mentioned

---

### 15. 🔒 Concurrency Protection Missing (Expert Review)
**Location**: Multiple places (vote_manager.go, action_processor.go)  
**Problem**: ZERO locks on read-modify-write operations  
**Test to Prove Bug**:
```bash
# Have 2 players vote simultaneously
curl -X POST /api/v1/games/{id}/action & 
curl -X POST /api/v1/games/{id}/action &
# Result: Corrupted vote counts
```

**Current Vulnerable Code**:
```go
// vote_manager.go - CastVote
// 1. Read current votes
// 2. Modify count
// 3. Write back
// ❌ No locking = race condition
```

**Fix Options** (Expert's 3 solutions):

**Option 1: Database-level atomicity** (Easiest)
```go
_, err = tx.Exec(ctx, `
    INSERT INTO game_actions (...)
    ON CONFLICT (session_id, player_id, phase_number, action_type)
    DO UPDATE SET target_player_id = EXCLUDED.target_player_id
`)
```

**Option 2: Redis distributed locks** (Best for scaling)
```go
func (e *Engine) ProcessAction(ctx context.Context, sessionID uuid.UUID, ...) error {
    lockKey := fmt.Sprintf("game:%s:action", sessionID)
    lock, err := e.redis.Lock(ctx, lockKey, 5*time.Second)
    if err != nil {
        return ErrGameBusy
    }
    defer lock.Release(ctx)
    
    // Now safe to process
}
```

**Option 3: Actor model** (Most elegant, biggest refactor)
```go
type GameActor struct {
    sessionID uuid.UUID
    actions   chan ActionRequest
    state     *GameSession
}

func (ga *GameActor) Run() {
    for action := range ga.actions {
        result := ga.processAction(action)
        action.Response <- result
    }
}
```

**Recommended for MVP**: Option 1 (DB constraints) + `FOR UPDATE` locks in queries

**Expert Review**: ✅ 🔴 P0 - "Games will corrupt without it" (I downgraded to P1 for single-server MVP)

---

### 16. 🔍 WebSocket Information Leaks (Expert Review)
**Location**: `backend/internal/websocket/hub.go` (not reviewed but likely exists)  
**Problem**: Broadcast messages probably reveal roles  
**Example Leak**:
```go
// ❌ Broadcasting to everyone
h.BroadcastToRoom(roomID, "player_action", gin.H{
    "action": "werewolf_vote",  // Reveals who's a werewolf!
    "player_id": player.ID,
})
```

**Fix Required**: Separate broadcast channels
```go
// ✅ Only werewolves see this
h.BroadcastToPlayers(roomID, werewolfPlayerIDs, "werewolf_vote", data)

// ✅ Everyone else sees generic message
h.BroadcastToOthers(roomID, werewolfPlayerIDs, "night_action", gin.H{
    "message": "A night action occurred",
})
```

**Expert Review**: ✅ 🟡 P2 - "Cheating becomes possible"

---

## 🟢 PRIORITY 3 - NICE TO HAVE (Post-MVP)

### 17. 📝 Event Sourcing Refactor (Expert Review)
**Location**: Entire codebase  
**Problem**: Current approach mixes state mutation + event logging  
**Current Pattern**:
```go
func (e *Engine) ProcessAction(...) {
    session.State.WerewolfVotes[player.ID] = targetID  // Mutate state
    e.UpdateSessionState(ctx, session)  // Save state
    e.RecordEvent(ctx, event)           // Also log event (afterthought)
}
```

**Better Pattern**: Event-first
```go
func (e *Engine) ProcessAction(...) {
    // 1. Validate
    if !e.isValidAction(action) {
        return ErrInvalidAction
    }
    
    // 2. Create and persist event
    event := &GameEvent{Type: "werewolf_voted", Data: ...}
    e.persistEvent(ctx, event)
    
    // 3. Rebuild state from events (or apply to cached state)
    e.applyEvent(session, event)
}
```

**Benefits**:
- Game state derivable from events (debugging, replays)
- Built-in audit trail
- Natural "undo" for moderators
- Dispute resolution

**Downside**: Major architectural refactor

**Expert Review**: ✅ 🟡 P2 - "Debugging/support will be painful" (I suggest P3 post-MVP)

---

### 18. 🧪 Testing Infrastructure (Expert Review)
**Location**: MISSING - probably zero tests  
**Current State**: No game logic tests evident  

**Needed - Scenario-based tests**:
```go
func TestWerewolfKillProtectedPlayer(t *testing.T) {
    game := NewTestGame(t).
        WithPlayers(8).
        WithRoles(Werewolf, Werewolf, Bodyguard, Seer, Villager, Villager, Villager, Villager)
    
    game.Night(1).
        WerewolfVote(0, 2).  // Vote for Bodyguard
        WerewolfVote(1, 2).
        BodyguardProtect(2, 2).  // Self-protect
        EndNight()
    
    game.AssertAlive(2, "Bodyguard should survive self-protection")
    game.AssertPhase(PhaseDay)
}

func TestTannerWinCondition(t *testing.T) {
    game := NewTestGame(t).WithPlayers(6).WithRoles(Werewolf, Werewolf, Tanner, Villager, Villager, Villager)
    
    game.Night(1).EndNight()
    game.Day(1).EndDay()
    game.Voting(1).LynchPlayer(2)  // Lynch Tanner
    
    game.AssertGameEnded()
    game.AssertWinner(TeamNeutral)
}
```

**Property-based testing**:
```go
func TestWinConditionInvariants(t *testing.T) {
    rapid.Check(t, func(t *rapid.T) {
        players := rapid.SliceOfN(rapid.Custom(randomPlayer), 6, 20).Draw(t, "players")
        game := setupGameWithPlayers(players)
        
        for !game.IsFinished() {
            game.SimulateRandomPhase()
        }
        
        // Invariant: exactly one team wins
        assert.NotNil(t, game.WinningTeam())
        assertWinConditionMet(t, game)
    })
}
```

**Expert Review**: ✅ 🟢 P3 - "Regressions will happen"

---

### 19. 📊 Observability: Health & Metrics (Expert Review)
**Location**: MISSING  
**Current State**: No `/health` endpoint, no metrics  

**Required for Production**:

**Health Endpoint**:
```go
// handlers.go
func (h *Handler) HealthCheck(c *gin.Context) {
    // Check DB
    if err := h.db.Ping(c.Request.Context()); err != nil {
        c.JSON(503, gin.H{"status": "unhealthy", "db": "down"})
        return
    }
    
    // Check Redis
    if err := h.redis.Ping(c.Request.Context()).Err(); err != nil {
        c.JSON(503, gin.H{"status": "unhealthy", "redis": "down"})
        return
    }
    
    c.JSON(200, gin.H{"status": "healthy"})
}
```

**Prometheus Metrics**:
```go
var (
    gamesActive = prometheus.NewGauge(prometheus.GaugeOpts{
        Name: "wolverix_games_active",
        Help: "Number of currently active games",
    })
    
    actionLatency = prometheus.NewHistogramVec(prometheus.HistogramOpts{
        Name: "wolverix_action_latency_seconds",
        Help: "Latency of game actions",
    }, []string{"action_type"})
    
    websocketConnections = prometheus.NewGauge(prometheus.GaugeOpts{
        Name: "wolverix_websocket_connections",
        Help: "Number of active WebSocket connections",
    })
    
    phaseTransitions = prometheus.NewCounterVec(prometheus.CounterOpts{
        Name: "wolverix_phase_transitions_total",
        Help: "Number of phase transitions",
    }, []string{"from_phase", "to_phase"})
)
```

**Docker Compose Updates**:
```yaml
services:
  backend:
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:8080/health"]
      interval: 10s
      timeout: 5s
      retries: 3
    deploy:
      resources:
        limits:
          memory: 512M
        reservations:
          memory: 256M
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
```

**Expert Review**: ✅ 🟢 P3 - "Production issues invisible"

---

### 20. 📱 Flutter Client Patterns (Expert Review)
**Location**: `mobile/lib/` (not deeply reviewed)  
**Suggested Improvements**:

**Optimistic UI with rollback**:
```dart
class GameState extends ChangeNotifier {
  void castVote(String targetId) {
    final previousVote = _myVote;
    _myVote = targetId;  // Optimistic update
    notifyListeners();
    
    _api.castVote(targetId).catchError((e) {
      _myVote = previousVote;  // Rollback on failure
      notifyListeners();
      showError(e);
    });
  }
}
```

**WebSocket reconnection with exponential backoff**:
```dart
class GameWebSocket {
  int _reconnectAttempts = 0;
  
  void _onDisconnect() {
    final delay = Duration(seconds: min(pow(2, _reconnectAttempts), 30));
    Future.delayed(delay, _connect);
    _reconnectAttempts++;
  }
  
  void _onConnect() {
    _reconnectAttempts = 0;
    _requestGameStateSync();  // Critical: resync after reconnect
  }
}
```

**Offline action queue**:
```dart
class OfflineActionQueue {
  final List<GameAction> _pendingActions = [];
  
  void queueAction(GameAction action) {
    _pendingActions.add(action);
    _trySend();
  }
  
  void _trySend() {
    if (!_isConnected) return;
    while (_pendingActions.isNotEmpty) {
      final action = _pendingActions.removeAt(0);
      _websocket.send(action);
    }
  }
}
```

**Expert Review**: ✅ 🟢 P3 - Good practices for mobile

---

### 21. 🗄️ Database Optimization (Expert Review)
**Location**: Database schema  
**Suggested Improvements**:

**Add indexes for hot queries**:
```sql
-- Actions by session and phase (hot query in night coordinator)
CREATE INDEX idx_game_actions_session_phase_type 
    ON game_actions(session_id, phase_number, action_type);

-- Players by session and alive status (hot query in win checker)
CREATE INDEX idx_game_players_session_alive 
    ON game_players(session_id, is_alive);

-- Events by session ordered by time (hot query for event log)
CREATE INDEX idx_game_events_session_time 
    ON game_events(session_id, created_at DESC);
```

**Add unique constraint** (prevents double-actions):
```sql
ALTER TABLE game_actions 
ADD CONSTRAINT unique_action_per_phase
    UNIQUE (session_id, player_id, phase_number, action_type);
```

**Optimistic locking** (concurrency protection):
```sql
ALTER TABLE game_sessions 
ADD COLUMN version INTEGER DEFAULT 0;

-- In application code:
UPDATE game_sessions 
SET state = $1, version = version + 1
WHERE id = $2 AND version = $3;  -- Fails if someone else updated
```

**Typed columns vs JSONB** (debatable):
```sql
-- Instead of role_state JSONB, could use:
ALTER TABLE game_players 
    ADD COLUMN heal_potion_used BOOLEAN DEFAULT false,
    ADD COLUMN poison_potion_used BOOLEAN DEFAULT false,
    ADD COLUMN last_protected_id UUID REFERENCES game_players(id),
    ADD COLUMN hunter_shot_used BOOLEAN DEFAULT false,
    ADD COLUMN divined_players UUID[] DEFAULT '{}';
```
**Note**: Current JSONB approach is fine for flexibility. Only refactor if performance issues arise.

**Expert Review**: ✅ 🟡 P2 - Database improvements

---

## 📋 IMPLEMENTATION CHECKLIST

### Week 1: Critical Fixes (P0)
- [ ] **Day 1-2**: Fix lovers team assignment + Cupid lover_id setting (Issues #1, #2)
- [ ] **Day 2-3**: Implement night action collect-then-resolve pattern (Issue #3)
- [ ] **Day 3-4**: Add phase timeout scheduler with background goroutine (Issue #4)
- [ ] **Day 4-5**: Fix information leakage (generic errors, constant-time responses) (Issue #6)
- [ ] **Day 5**: Remove Hunter role OR implement revenge phase (Issue #5)

### Week 2: High Priority (P1)
- [ ] **Day 1**: Fix night phase deadlock (auto-skip dead/disconnected players) (Issue #10)
- [ ] **Day 2-3**: Implement WebSocket reconnection + state recovery (Issue #11)
- [ ] **Day 3**: Implement vote tie resolution logic (Issue #13)
- [ ] **Day 4**: Decision: Remove or implement Mayor, Medium, Little Girl roles (Issues #7, #8, #9)
- [ ] **Day 5**: Clarify and fix witch heal logic (Issue #12)

### Week 3: Concurrency & Testing (P1/P2)
- [ ] **Day 1-2**: Add database constraints + FOR UPDATE locks (Issue #15)
- [ ] **Day 2-3**: Fix WebSocket broadcast information leaks (Issue #16)
- [ ] **Day 3-4**: Write scenario-based tests for all win conditions (Issue #18)
- [ ] **Day 4-5**: Write tests for the 13 bugs fixed in Week 1-2
- [ ] **Day 5**: Add health endpoint and basic metrics (Issue #19)

### Post-MVP (P3)
- [ ] Event sourcing refactor (Issue #17)
- [ ] Property-based testing (Issue #18)
- [ ] Full Prometheus observability (Issue #19)
- [ ] Mobile client improvements (Issue #20)
- [ ] Database optimization (Issue #21)

---

## 🎯 EXPERT PRIORITY COMPARISON

| Expert Priority | My Priority | Item | Reasoning |
|-----------------|-------------|------|-----------|
| 🔴 P0 | 🔴 P0 | **Phase timeout scheduling** | Agree - games will hang |
| 🔴 P0 | 🟠 P1 | Concurrency/locking | You're single-server MVP, not multi-instance yet |
| 🟠 P1 | 🔴 P0 | **Night action ordering** | This breaks core gameplay RIGHT NOW |
| 🟠 P1 | 🟠 P1 | Reconnection handling | Agree - UX killer |
| 🟡 P2 | 🟠 P1 | **Information leakage** | Easier to fix than expert thinks, ruins games |
| 🟡 P2 | 🟡 P2 | Event sourcing | Big refactor, defer to v2 |
| 🟢 P3 | 🔴 P0 | **Lovers/Cupid/Hunter bugs** | Expert missed these CRITICAL bugs |
| 🟢 P3 | 🟡 P2 | Testing infrastructure | Do while fixing bugs |
| 🟢 P3 | 🟢 P3 | Metrics/observability | Nice-to-have |

---

## 📝 NOTES

### What Expert Got Right
✅ Night action order bug (spot on)  
✅ Phase timeout missing (critical catch)  
✅ Information leakage (detailed examples)  
✅ Concurrency issues (race conditions exist)  
✅ Reconnection needed (UX critical)  
✅ Testing patterns (excellent examples)  
✅ Operational concerns (production-ready thinking)  
✅ Flutter best practices (solid mobile advice)  

### What Expert Missed
❌ Lovers team assignment completely broken  
❌ Cupid never sets lover_id  
❌ Hunter revenge incomplete  
❌ Mayor/Medium/Little Girl undefined  
❌ Vote tie resolution missing  
❌ Night phase can deadlock on dead/disconnected players  

### Architecture Decisions
- **Event Sourcing**: Great for v2, too big for MVP
- **Actor Model**: Most elegant but biggest refactor - defer
- **Redis Locks**: Only needed if scaling to multiple backend instances
- **Typed Columns**: Current JSONB is fine, only change if performance issues

---

## 🚀 READY TO START?

**Estimated total fix time**: ~15-20 days of focused work

**Suggested approach**: 
1. Start with Week 1 checklist (P0 critical bugs)
2. Test each fix thoroughly before moving to next
3. Write tests as you fix bugs
4. Deploy MVP after Week 2
5. Monitor and fix concurrency issues in production
6. Plan v2 with event sourcing

**Questions before starting?**
- Which issues to tackle first?
- Need clarification on any fix approach?
- Want to discuss architectural decisions?

---

**Document Version**: 1.0  
**Next Review**: After Week 1 fixes completed
