# Werewolf Game - Complete Test Scenario (6 Players)

## Prerequisites
- Server running via Docker: `docker-compose up -d`
- Server accessible at `http://localhost:8080`

## Base URL
```
http://localhost:8080/api/v1
```

---

## PHASE 1: Register 6 Players

### Player 1 (Host)
```bash
curl -X POST http://localhost:8080/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username": "player1", "email": "player1@test.com", "password": "password123"}'
```

### Player 2
```bash
curl -X POST http://localhost:8080/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username": "player2", "email": "player2@test.com", "password": "password123"}'
```

### Player 3
```bash
curl -X POST http://localhost:8080/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username": "player3", "email": "player3@test.com", "password": "password123"}'
```

### Player 4
```bash
curl -X POST http://localhost:8080/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username": "player4", "email": "player4@test.com", "password": "password123"}'
```

### Player 5
```bash
curl -X POST http://localhost:8080/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username": "player5", "email": "player5@test.com", "password": "password123"}'
```

### Player 6
```bash
curl -X POST http://localhost:8080/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username": "player6", "email": "player6@test.com", "password": "password123"}'
```

**Save the tokens from each response!**

---

## PHASE 2: Create Room (Player 1 as Host)

```bash
curl -X POST http://localhost:8080/api/v1/rooms \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer {PLAYER1_TOKEN}" \
  -d '{
    "name": "Test Game Room",
    "max_players": 6,
    "is_private": false
  }'
```

**Save the `room_id` from response!**

---

## PHASE 3: Other Players Join Room

### Player 2 joins
```bash
curl -X POST http://localhost:8080/api/v1/rooms/join \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer {PLAYER2_TOKEN}" \
  -d '{"room_id": "{ROOM_ID}"}'
```

### Player 3 joins
```bash
curl -X POST http://localhost:8080/api/v1/rooms/join \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer {PLAYER3_TOKEN}" \
  -d '{"room_id": "{ROOM_ID}"}'
```

### Player 4 joins
```bash
curl -X POST http://localhost:8080/api/v1/rooms/join \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer {PLAYER4_TOKEN}" \
  -d '{"room_id": "{ROOM_ID}"}'
```

### Player 5 joins
```bash
curl -X POST http://localhost:8080/api/v1/rooms/join \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer {PLAYER5_TOKEN}" \
  -d '{"room_id": "{ROOM_ID}"}'
```

### Player 6 joins
```bash
curl -X POST http://localhost:8080/api/v1/rooms/join \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer {PLAYER6_TOKEN}" \
  -d '{"room_id": "{ROOM_ID}"}'
```

---

## PHASE 4: Connect WebSockets (All Players)

Each player connects via WebSocket:
```
ws://localhost:8080/api/v1/ws?room_id={ROOM_ID}&token={PLAYER_TOKEN}
```

**WebSocket Message Format:**
```json
{
  "type": "message_type",
  "payload": { ... }
}
```

---

## PHASE 5: All Players Set Ready

### Player 1 ready
```bash
curl -X POST http://localhost:8080/api/v1/rooms/{ROOM_ID}/ready \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer {PLAYER1_TOKEN}" \
  -d '{"ready": true}'
```

*Repeat for all 6 players*

---

## PHASE 6: Host Starts Game

```bash
curl -X POST http://localhost:8080/api/v1/rooms/{ROOM_ID}/start \
  -H "Authorization: Bearer {PLAYER1_TOKEN}"
```

**Response includes:**
- `session_id` - The game session ID
- Each player receives their role via WebSocket

---

## PHASE 7: Get Game State

```bash
curl -X GET http://localhost:8080/api/v1/games/{SESSION_ID} \
  -H "Authorization: Bearer {PLAYER_TOKEN}"
```

**Expected Response:**
```json
{
  "session_id": "uuid",
  "room_id": "uuid",
  "current_phase": "night",
  "phase_number": 1,
  "phase_end_time": "timestamp",
  "players": [
    {
      "user_id": "uuid",
      "username": "player1",
      "is_alive": true,
      "role": "villager"  // Only shown for requesting player or if revealed
    }
  ],
  "your_role": "werewolf",  // Your role
  "your_status": "alive",
  "allowed_actions": ["vote_kill"],  // Actions you can perform
  "current_voice_channel": "werewolf",
  "allowed_chat_channels": ["werewolf", "main"]
}
```

---

## GAME PHASES & ACTIONS

### Role Distribution for 6 Players:
- 2 Werewolves
- 1 Seer
- 1 Doctor
- 2 Villagers

### Night Phase Actions:

#### Werewolf Vote (performed by werewolves)
```bash
curl -X POST http://localhost:8080/api/v1/games/{SESSION_ID}/action \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer {WEREWOLF_TOKEN}" \
  -d '{
    "action_type": "vote_kill",
    "target_user_id": "{VILLAGER_USER_ID}"
  }'
```

#### Seer Investigate
```bash
curl -X POST http://localhost:8080/api/v1/games/{SESSION_ID}/action \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer {SEER_TOKEN}" \
  -d '{
    "action_type": "investigate",
    "target_user_id": "{SUSPECT_USER_ID}"
  }'
```

**Response reveals if target is werewolf or not!**

#### Doctor Protect
```bash
curl -X POST http://localhost:8080/api/v1/games/{SESSION_ID}/action \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer {DOCTOR_TOKEN}" \
  -d '{
    "action_type": "protect",
    "target_user_id": "{PLAYER_TO_PROTECT_USER_ID}"
  }'
```

---

### Day Phase (Discussion)
- All alive players can talk
- Phase lasts for configured time
- No actions during discussion

---

### Voting Phase

#### Cast Vote
```bash
curl -X POST http://localhost:8080/api/v1/games/{SESSION_ID}/action \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer {PLAYER_TOKEN}" \
  -d '{
    "action_type": "vote_lynch",
    "target_user_id": "{SUSPECT_USER_ID}"
  }'
```

#### Skip Vote
```bash
curl -X POST http://localhost:8080/api/v1/games/{SESSION_ID}/action \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer {PLAYER_TOKEN}" \
  -d '{
    "action_type": "vote_lynch",
    "target_user_id": null
  }'
```

---

## WebSocket Events to Monitor

### Events you'll receive:
```json
// Game started, role assigned
{"type": "game_started", "payload": {"session_id": "...", "role": "werewolf"}}

// Phase changed
{"type": "phase_changed", "payload": {"phase": "night", "phase_number": 1, "end_time": "..."}}

// Player action result
{"type": "action_result", "payload": {"action_type": "investigate", "success": true, "result": "werewolf"}}

// Player eliminated
{"type": "player_eliminated", "payload": {"user_id": "...", "username": "...", "reason": "lynched"}}

// Vote update
{"type": "vote_update", "payload": {"votes": {"user_id": 3, "other_user_id": 2}}}

// Game ended
{"type": "game_ended", "payload": {"winner": "werewolves", "roles_revealed": [...]}}
```

---

## COMPLETE TEST FLOW

### Night 1:
1. Phase: `night`, Phase Number: `1`
2. Werewolves vote to kill a villager
3. Seer investigates someone
4. Doctor protects someone
5. Phase auto-advances after timeout or all actions done

### Day 1:
1. Phase: `day_discussion`
2. Announce who was killed (if any)
3. Players discuss (voice chat enabled for all alive)

### Voting 1:
1. Phase: `day_voting`
2. All alive players vote
3. Player with most votes is lynched

### Win Conditions:
- **Werewolves win**: When werewolves >= villagers
- **Villagers win**: When all werewolves are eliminated

---

## GET GAME HISTORY

```bash
curl -X GET http://localhost:8080/api/v1/games/{SESSION_ID}/history \
  -H "Authorization: Bearer {PLAYER_TOKEN}"
```

Returns all actions, votes, and eliminations.

---

## UTILITY ENDPOINTS

### Check Room Status
```bash
curl -X GET http://localhost:8080/api/v1/rooms/{ROOM_ID} \
  -H "Authorization: Bearer {PLAYER_TOKEN}"
```

### List All Rooms
```bash
curl -X GET http://localhost:8080/api/v1/rooms
```

### Health Check
```bash
curl http://localhost:8080/health
```

---

## TESTING TIPS

1. **Use Postman or Insomnia** for easier API testing
2. **Open 6 WebSocket connections** in separate tabs using a WebSocket client
3. **Track tokens in a notepad** - you'll need them throughout
4. **Watch server logs**: `docker logs -f backend-backend-1`
5. **Check database state**: 
   ```bash
   docker exec -it backend-postgres-1 psql -U wolverix -d wolverix -c "SELECT * FROM game_players;"
   ```
