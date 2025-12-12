# Wolverix Backend API Documentation

## Overview
Comprehensive REST API and WebSocket service for a real-time multiplayer Werewolf game with voice chat integration, automated game management, and professional room lifecycle handling.

**Base URL:** `http://localhost:8080/api/v1`  
**WebSocket URL:** `ws://localhost:8080/api/v1/ws`

---

## Table of Contents
1. [Authentication](#authentication)
2. [User Management](#user-management)
3. [Room Management](#room-management)
4. [Game Management](#game-management)
5. [Voice Chat (Agora)](#voice-chat-agora)
6. [WebSocket Events](#websocket-events)
7. [Business Rules & Restrictions](#business-rules--restrictions)
8. [Error Handling](#error-handling)
9. [Database Schema](#database-schema)

---

## Authentication

### Register
```http
POST /auth/register
Content-Type: application/json

{
  "username": "string (3-20 chars, alphanumeric)",
  "email": "string (valid email)",
  "password": "string (min 8 chars)"
}
```

**Response 201:**
```json
{
  "user": {
    "id": "uuid",
    "username": "string",
    "email": "string",
    "language": "en",
    "is_online": false,
    "created_at": "2025-12-08T10:00:00Z"
  }
}
```

**Errors:**
- `400`: Invalid input, username/email already exists
- `500`: Server error

### Login
```http
POST /auth/login
Content-Type: application/json

{
  "email": "string",
  "password": "string"
}
```

**Response 200:**
```json
{
  "access_token": "jwt_token",
  "refresh_token": "jwt_token",
  "user": {
    "id": "uuid",
    "username": "string",
    "email": "string",
    "avatar_url": "string|null",
    "language": "en",
    "is_online": true
  }
}
```

**Errors:**
- `401`: Invalid credentials
- `500`: Server error

### Refresh Token
```http
POST /auth/refresh
Content-Type: application/json

{
  "refresh_token": "string"
}
```

**Response 200:**
```json
{
  "access_token": "jwt_token",
  "refresh_token": "jwt_token"
}
```

**Token Expiry:**
- Access Token: 24 hours
- Refresh Token: 7 days

---

## User Management

All endpoints require `Authorization: Bearer <token>` header.

### Get Current User
```http
GET /users/me
Authorization: Bearer <token>
```

**Response 200:**
```json
{
  "id": "uuid",
  "username": "string",
  "email": "string",
  "avatar_url": "string|null",
  "display_name": "string|null",
  "language": "en",
  "is_online": true,
  "reputation_score": 0,
  "created_at": "2025-12-08T10:00:00Z",
  "last_seen_at": "2025-12-08T12:00:00Z"
}
```

### Update User Profile
```http
PUT /users/me
Authorization: Bearer <token>
Content-Type: application/json

{
  "display_name": "string (optional)",
  "avatar_url": "string (optional)",
  "language": "en|fr|es|de (optional)"
}
```

**Response 200:** Updated user object

### Get User Stats
```http
GET /users/:userId/stats
Authorization: Bearer <token>
```

**Response 200:**
```json
{
  "user_id": "uuid",
  "total_games": 42,
  "total_wins": 18,
  "total_losses": 24,
  "games_as_villager": 30,
  "games_as_werewolf": 12,
  "games_as_seer": 5,
  "games_as_witch": 3,
  "games_as_hunter": 2,
  "villager_wins": 12,
  "werewolf_wins": 6,
  "current_streak": 3,
  "best_streak": 7,
  "total_kills": 15,
  "total_deaths": 24,
  "mvp_count": 5
}
```

---

## Room Management

### List Available Rooms
```http
GET /rooms
```

**Response 200:**
```json
[
  {
    "id": "uuid",
    "room_code": "ABC123",
    "name": "Evening Game",
    "host_user_id": "uuid",
    "status": "waiting|playing|finished|abandoned",
    "is_private": false,
    "max_players": 12,
    "current_players": 3,
    "language": "en",
    "config": {
      "enabled_roles": ["werewolf", "seer", "witch", "hunter"],
      "werewolf_count": 2,
      "day_phase_seconds": 120,
      "night_phase_seconds": 60,
      "voting_seconds": 60,
      "allow_spectators": false,
      "require_ready": true
    },
    "agora_channel_name": "room_abc123",
    "created_at": "2025-12-08T10:00:00Z",
    "last_activity_at": "2025-12-08T10:05:00Z",
    "timeout_warning_sent": false,
    "timeout_extended_count": 0,
    "host": {
      "id": "uuid",
      "username": "player1",
      "avatar_url": null
    },
    "players": [...]
  }
]
```

### Create Room
```http
POST /rooms
Authorization: Bearer <token>
Content-Type: application/json

{
  "name": "string (required, 3-50 chars)",
  "is_private": false,
  "max_players": 12,
  "language": "en",
  "config": {
    "day_phase_seconds": 120,
    "night_phase_seconds": 60,
    "voting_seconds": 60
  }
}
```

**Response 201:** Room object with host added as first player

**Restrictions:**
- User can only be in ONE active room at a time
- Max players: 6-24 (minimum 6 for game balance)
- Room code is auto-generated (6 alphanumeric chars)

**Errors:**
- `400`: Already in an active room, invalid parameters
- `401`: Unauthorized
- `500`: Server error

### Get Room Details
```http
GET /rooms/:roomId
Authorization: Bearer <token>
```

**Response 200:** Full room object including all players

### Join Room
```http
POST /rooms/join
Authorization: Bearer <token>
Content-Type: application/json

{
  "room_code": "ABC123"
}
```

**Response 200:**
```json
{
  "room_id": "uuid"
}
```

**Restrictions:**
- Room must be in `waiting` status
- Room must not be full
- User cannot already be in another active room
- User cannot join same room twice

**Errors:**
- `400`: Already in room, room full, already in another room
- `404`: Room not found
- `500`: Server error

### Leave Room
```http
POST /rooms/:roomId/leave
Authorization: Bearer <token>
```

**Response 200:**
```json
{
  "message": "left room successfully"
}
```

**Behavior:**
- Marks player as `left_at = NOW()`
- Decrements `current_players` count
- If host leaves: game abandoned or host transferred
- Broadcasts `player_left` event via WebSocket

### Set Ready Status
```http
POST /rooms/:roomId/ready
Authorization: Bearer <token>
Content-Type: application/json

{
  "ready": true
}
```

**Response 200:**
```json
{
  "ready": true
}
```

**Behavior:**
- Updates player's `is_ready` status
- Updates room `last_activity_at` timestamp
- Broadcasts `player_ready` event

### Kick Player (Host Only)
```http
POST /rooms/:roomId/kick
Authorization: Bearer <token>
Content-Type: application/json

{
  "player_id": "uuid"
}
```

**Response 200:**
```json
{
  "message": "player kicked"
}
```

**Restrictions:**
- Only host can kick
- Cannot kick yourself
- Cannot kick during active game

### Extend Room Timeout (Host Only)
```http
POST /rooms/:roomId/extend-timeout
POST /rooms/:roomId/extend  (alternative)
Authorization: Bearer <token>
```

**Response 200:**
```json
{
  "message": "room timeout extended successfully",
  "extended_minutes": 20
}
```

**Behavior:**
- Resets `last_activity_at` to NOW()
- Clears `timeout_warning_sent` flag
- Increments `timeout_extended_count`
- Adds 20 minutes to room lifetime
- Broadcasts `timeout_extended` event

**Restrictions:**
- Only host can extend
- Room must be in `waiting` status

**Errors:**
- `403`: Not the host
- `400`: Room not in waiting status

### Start Game (Host Only)
```http
POST /rooms/:roomId/start
Authorization: Bearer <token>
```

**Response 200:**
```json
{
  "session_id": "uuid",
  "room_id": "uuid",
  "status": "active",
  "current_phase": "night_0",
  "phase_number": 0,
  "day_number": 0,
  "started_at": "2025-12-08T10:30:00Z"
}
```

**Requirements:**
- Minimum 5 players (configurable, default 6)
- Maximum 24 players
- All non-host players must be ready
- Room status must be `waiting`
- Only host can start

**Game Start Process:**
1. Creates `game_sessions` entry
2. Assigns random roles to players
3. Creates `game_players` entries with roles
4. Schedules first phase timeout
5. Updates room status to `playing`
6. Broadcasts `game_started` event

**Role Assignment Logic:**
- 2 Werewolves (minimum)
- 1 Seer (if enabled)
- 1 Witch (if enabled)
- 1 Hunter (if enabled)
- 1 Bodyguard (if enabled)
- 1 Cupid (if enabled)
- Rest as Villagers

**Errors:**
- `403`: Not the host
- `400`: Not enough players, not all ready, invalid room status

---

## Game Management

### Get Game State
```http
GET /games/:sessionId
Authorization: Bearer <token>
```

**Response 200:**
```json
{
  "session": {
    "id": "uuid",
    "room_id": "uuid",
    "status": "active|completed",
    "winner": null|"werewolves"|"villagers",
    "current_phase": "night_0|day_discussion|day_voting|night_1|...",
    "phase_number": 0,
    "day_number": 0,
    "started_at": "2025-12-08T10:30:00Z",
    "ended_at": null
  },
  "players": [
    {
      "id": "uuid",
      "user_id": "uuid",
      "role": "werewolf|villager|seer|witch|hunter|bodyguard|cupid",
      "team": "werewolves|villagers",
      "is_alive": true,
      "died_at_phase": null,
      "death_reason": null,
      "lover_id": null,
      "current_voice_channel": "werewolf|main|dead|",
      "allowed_chat_channels": ["werewolf"]|["main"]|["dead"]|[],
      "seat_position": 0,
      "user": {
        "id": "uuid",
        "username": "player1",
        "avatar_url": null
      }
    }
  ],
  "actions_remaining": ["werewolf_vote", "seer_divine", ...],
  "phase_ends_at": "2025-12-08T10:35:00Z"
}
```

**Role Visibility:**
- Player sees only their own role
- Dead players see all roles
- Werewolves see other werewolves
- Lovers see each other's roles
- Game completed: all roles visible

**Voice Channel Security:**

The `current_voice_channel` and `allowed_chat_channels` fields control voice chat access:

| Phase | Role | current_voice_channel | allowed_chat_channels | Description |
|-------|------|----------------------|----------------------|-------------|
| night_0, night_X | Werewolf | `"werewolf"` | `["werewolf"]` | Werewolves discuss privately |
| night_0, night_X | Non-werewolf | `""` (empty) | `[]` (empty) | Silenced during night |
| day_discussion, day_voting | All alive | `"main"` | `["main"]` | Public discussion |
| any | Dead player | `"dead"` | `["dead"]` | Dead players' channel |

**Channel Isolation Rules:**
- Empty `allowed_chat_channels` means player cannot send/receive voice
- Frontend MUST enforce these restrictions
- Channels updated automatically on phase transitions
- Security-critical: prevents werewolves from being overheard

### Perform Action
```http
POST /games/:sessionId/action
Authorization: Bearer <token>
Content-Type: application/json

{
  "action_type": "werewolf_vote|seer_divine|witch_heal|witch_poison|bodyguard_protect|cupid_choose|vote_lynch|hunter_shoot",
  "target_player_id": "uuid",
  "data": {
    "additional": "data"
  }
}
```

**Response 200:**
```json
{
  "message": "action recorded",
  "action_id": "uuid"
}
```

**Action Types & Phases:**

| Action | Phase | Who | Target | Effect |
|--------|-------|-----|--------|--------|
| `werewolf_vote` | night_X | Werewolves | Any alive player | Vote to kill |
| `seer_divine` | night_X | Seer | Any alive player | Learn their team |
| `witch_heal` | night_X | Witch | Killed player | Save from death |
| `witch_poison` | night_X | Witch | Any alive player | Kill target |
| `bodyguard_protect` | night_X | Bodyguard | Any alive player | Protect from werewolves |
| `cupid_choose` | night_0 | Cupid | Two players | Make them lovers |
| `vote_lynch` | day_voting | Everyone alive | Any alive player | Vote to eliminate |
| `hunter_shoot` | death | Hunter | Any alive player | Kill on death |

**Restrictions:**
- Must be alive to perform actions
- Must be correct phase for action
- Must have the role for role-specific actions
- Cannot perform same action twice in same phase
- Cannot target dead players (except witch_heal)
- Cupid can only act on night_0

**Errors:**
- `400`: Invalid action, wrong phase, already acted
- `403`: Not authorized (not your turn, wrong role)
- `404`: Session or target not found

### Get Game History
```http
GET /games/:sessionId/history
Authorization: Bearer <token>
```

**Response 200:**
```json
{
  "events": [
    {
      "id": "uuid",
      "event_type": "game_started|phase_change|player_death|player_action|game_ended",
      "phase_number": 0,
      "day_number": 0,
      "data": {
        "phase": "night_0",
        "player_id": "uuid",
        "action": "werewolf_vote",
        "target": "uuid"
      },
      "created_at": "2025-12-08T10:30:00Z"
    }
  ]
}
```

---

## Voice Chat (Agora)

### Get Agora Token
```http
POST /agora/token
Authorization: Bearer <token>
Content-Type: application/json

{
  "channel_name": "room_abc123",
  "uid": "user_uuid_or_int"
}
```

**Response 200:**
```json
{
  "token": "agora_rtc_token",
  "channel_name": "room_abc123",
  "uid": "user_id",
  "app_id": "agora_app_id",
  "expires_at": "2025-12-08T11:30:00Z"
}
```

**Token Validity:** 1 hour (3600 seconds)

**Channel Naming:**
- Format: `room_{room_id_prefix}`
- Auto-generated on room creation
- Unique per room

### Voice Channel Isolation (Critical Security Feature)

The backend manages voice channel access through the `allowed_chat_channels` field in game state. This ensures game integrity by controlling who can hear whom.

**Implementation Requirements:**

1. **Frontend Integration:**
   ```dart
   // Check game state for voice permissions
   final gameState = await getGameState(sessionId);
   final myPlayer = gameState.players.firstWhere((p) => p.userId == myUserId);
   final allowedChannels = myPlayer.allowedChatChannels; // ["werewolf"], ["main"], ["dead"], or []
   
   // Enforce in Agora:
   if (allowedChannels.isEmpty) {
     // Mute microphone, disable voice UI
     await agoraEngine.muteLocalAudioStream(true);
   } else {
     // Join allowed channel(s)
     final channelName = allowedChannels.first;
     await agoraEngine.joinChannel(token, channelName, null, uid);
   }
   ```

2. **Channel Types:**
   - `werewolf`: Werewolves-only night discussion
   - `main`: All alive players during day phases
   - `dead`: Deceased players (spectator channel)

3. **Security Notes:**
   - Backend updates channels on every phase transition
   - Client must poll game state or use WebSocket for updates
   - Always check `allowed_chat_channels` before enabling voice
   - Empty array = player is silenced (cannot talk or listen)

**Testing:**
- Verified with `test_voice_channels.ps1`
- Night isolation: ✓ Werewolves private, others silenced
- Day open: ✓ All alive players share main channel
- Critical for preventing cheating

---

## WebSocket Events

### Connection
```javascript
const ws = new WebSocket('ws://localhost:8080/api/v1/ws?token=<jwt_token>');
```

**Authentication:**
- Token passed as query parameter
- Connection rejected if token invalid/expired

### Server → Client Events

#### Room Update
```json
{
  "type": "room_update",
  "payload": {
    "action": "player_joined|player_left|player_ready|settings_changed",
    "room_id": "uuid",
    "user_id": "uuid",
    "ready": true
  }
}
```

#### Timeout Warning
```json
{
  "type": "room_update",
  "payload": {
    "action": "timeout_warning",
    "room_id": "uuid",
    "room_code": "ABC123",
    "minutes_left": 5,
    "message": "This room will close in 5 minutes due to inactivity. Host can extend the timeout."
  }
}
```

#### Room Closed
```json
{
  "type": "room_update",
  "payload": {
    "action": "room_closed",
    "room_id": "uuid",
    "reason": "inactivity|timeout",
    "message": "Room has been closed due to inactivity"
  }
}
```

#### Timeout Extended
```json
{
  "type": "room_update",
  "payload": {
    "action": "timeout_extended",
    "room_id": "uuid",
    "message": "Host extended the room timeout"
  }
}
```

#### Player Kicked
```json
{
  "type": "player_kicked",
  "payload": {
    "room_id": "uuid",
    "user_id": "uuid",
    "kicked_by": "uuid"
  }
}
```

#### Game Started
```json
{
  "type": "game_started",
  "payload": {
    "session_id": "uuid",
    "room_id": "uuid",
    "started_at": "2025-12-08T10:30:00Z"
  }
}
```

#### Phase Change
```json
{
  "type": "phase_change",
  "payload": {
    "session_id": "uuid",
    "phase": "day_discussion|day_voting|night_1|...",
    "phase_number": 1,
    "day_number": 1,
    "phase_ends_at": "2025-12-08T10:35:00Z"
  }
}
```

#### Player Death
```json
{
  "type": "player_death",
  "payload": {
    "session_id": "uuid",
    "player_id": "uuid",
    "death_reason": "werewolf_attack|lynch|poison|hunter_shot",
    "phase": "night_1"
  }
}
```

#### Game Ended
```json
{
  "type": "game_ended",
  "payload": {
    "session_id": "uuid",
    "winner": "werewolves|villagers",
    "reason": "all_werewolves_dead|villagers_outnumbered",
    "ended_at": "2025-12-08T11:00:00Z"
  }
}
```

---

## Business Rules & Restrictions

### Room Lifecycle
**Automatic Timeout System:**
- **Inactivity Timeout:** 20 minutes with no joins/ready changes
- **Absolute Timeout:** 1 hour maximum for waiting rooms
- **Warning:** 5 minutes before timeout
- **Host Extension:** Can extend once per warning (adds 20 minutes)

**Cleanup Policy:**
- Abandoned rooms: Deleted after 24 hours
- Completed games: Deleted after 7 days
- Background job runs every 2 minutes

**Room Status Flow:**
```
waiting → playing → finished
   ↓
abandoned (auto-closed)
```

### One Room Per User
**Strict Enforcement:**
- User can only be in ONE active room at any time
- Checked on both `createRoom` and `joinRoom`
- Active = status IN ('waiting', 'in_progress')
- Must leave current room before joining/creating another

### Game Rules
**Player Requirements:**
- Minimum: 5-6 players (configurable)
- Maximum: 24 players
- Optimal: 8-12 players

**Role Distribution:**
- Always 2+ Werewolves
- Special roles assigned if enabled
- Remaining players are Villagers
- Roles randomly assigned

**Phase Timing:**
- night_0: 2 minutes (initial role reveal)
- night_X: 60 seconds (configurable)
- day_discussion: 5 minutes (configurable)
- day_voting: 60 seconds (configurable)

**Win Conditions:**
- Werewolves win: Werewolves ≥ Villagers
- Villagers win: All Werewolves dead

### Voice Chat
**Restrictions:**
- One voice channel per room
- Auto-disconnected when leaving room
- Token expires after 1 hour
- Must be in room to get token

---

## Error Handling

### HTTP Status Codes
- `200`: Success
- `201`: Created
- `400`: Bad Request (validation failed, business rule violated)
- `401`: Unauthorized (missing/invalid token)
- `403`: Forbidden (not allowed, not host, etc.)
- `404`: Not Found
- `409`: Conflict (duplicate username/email)
- `500`: Internal Server Error

### Error Response Format
```json
{
  "error": "Human-readable error message"
}
```

### Common Error Messages
| Message | Meaning |
|---------|---------|
| "you are already in an active room. Please leave it before creating a new one" | Multiple room restriction |
| "you are already in an active room. Please leave it before joining another" | Multiple room restriction |
| "room is full" | Cannot join, max players reached |
| "room is not accepting players" | Room not in waiting status |
| "only host can kick players" | Not authorized |
| "only host can start game" | Not authorized |
| "not enough players" | Minimum players not met |
| "all players must be ready" | Cannot start game |
| "only the host can extend room timeout" | Not authorized |
| "can only extend timeout for waiting rooms" | Wrong room status |
| "this role has already acted this phase" | Action already performed |
| "invalid action for current phase" | Wrong phase |
| "target player not found or dead" | Invalid target |

---

## Database Schema

### Core Tables

**users**
- `id` (uuid, PK)
- `username` (unique)
- `email` (unique)
- `password_hash`
- `avatar_url`
- `language`
- `is_online`
- `reputation_score`
- `created_at`, `updated_at`

**rooms**
- `id` (uuid, PK)
- `room_code` (unique, 6 chars)
- `name`
- `host_user_id` (FK → users)
- `status` (enum: waiting, playing, finished, abandoned)
- `is_private`
- `max_players`, `current_players`
- `language`
- `config` (jsonb)
- `agora_channel_name`
- `created_at`, `updated_at`
- `last_activity_at` ⭐ NEW
- `timeout_warning_sent` ⭐ NEW
- `timeout_extended_count` ⭐ NEW

**room_players**
- `id` (uuid, PK)
- `room_id` (FK → rooms)
- `user_id` (FK → users)
- `is_ready`, `is_host`
- `seat_position`
- `joined_at`, `left_at`

**game_sessions**
- `id` (uuid, PK)
- `room_id` (FK → rooms)
- `status` (active, completed)
- `winner` (werewolves, villagers, null)
- `current_phase`
- `phase_number`, `day_number`
- `started_at`, `ended_at`

**game_players**
- `id` (uuid, PK)
- `session_id` (FK → game_sessions)
- `user_id` (FK → users)
- `role` (werewolf, villager, seer, witch, hunter, bodyguard, cupid)
- `team` (werewolves, villagers)
- `is_alive`
- `died_at_phase`, `death_reason`
- `lover_id` (FK → game_players)
- `role_state` (jsonb)

**game_actions**
- `id` (uuid, PK)
- `session_id` (FK → game_sessions)
- `player_id` (FK → game_players)
- `action_type`
- `target_player_id`
- `phase_number`, `day_number`
- `data` (jsonb)
- `created_at`

**game_events**
- `id` (uuid, PK)
- `session_id` (FK → game_sessions)
- `event_type`
- `phase_number`, `day_number`
- `data` (jsonb)
- `created_at`

### Indexes
- `rooms`: (status, last_activity_at) for cleanup
- `rooms`: (status, created_at) WHERE status IN ('abandoned', 'completed')
- `game_actions`: (session_id, player_id, phase_number, action_type)
- `game_players`: (session_id, user_id)

---

## Rate Limiting
**Not Currently Implemented**

Recommended limits:
- Auth endpoints: 5 requests/minute
- Room creation: 10 requests/minute
- Game actions: 30 requests/minute
- WebSocket connections: 3 connections/minute

---

## Environment Variables

```env
# Server
SERVER_PORT=8080
SERVER_HOST=0.0.0.0
SERVER_ENV=development|production

# Database
DATABASE_HOST=localhost
DATABASE_PORT=5432
DATABASE_USER=wolverix
DATABASE_PASSWORD=wolverix_password
DATABASE_NAME=wolverix
DATABASE_SSL_MODE=disable

# Redis (Sessions/Cache)
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=
REDIS_DB=0

# JWT
JWT_SECRET=your_secret_key
JWT_EXPIRY=24h
JWT_REFRESH_EXPIRY=168h

# Agora (Voice Chat)
AGORA_APP_ID=your_agora_app_id
AGORA_APP_CERTIFICATE=your_agora_certificate
AGORA_TOKEN_EXPIRY=3600

# CORS
ALLOWED_ORIGINS=http://localhost:3000,http://localhost:8080
```

---

## Testing

### Test Client
Location: `backend/cmd/test-client/main.go`

Features:
- Registers 8 bot players
- Creates room
- All players join and ready
- Starts game
- Tests multiple room prevention
- Tests timeout extension

Run: `go run cmd/test-client/main.go`

### Integration Tests
Location: `mobile/test/api_integration_test.dart`

Coverage:
- Authentication flow
- Room creation and joining
- Game start and state
- Error handling
- Performance (6ms avg response)

Run: `flutter test test/api_integration_test.dart`

---

## Performance Metrics

**Response Times:**
- Auth endpoints: < 50ms
- Room operations: < 30ms
- Game state: < 20ms
- WebSocket latency: < 10ms

**Capacity:**
- Concurrent users: 1000+ (tested)
- Concurrent games: 100+ (estimated)
- WebSocket connections: 1000+ (tested)

**Database:**
- Connection pool: 25 max connections
- Query timeout: 5 seconds
- Health check: Every 30 seconds

---

## Security

### Authentication
- JWT-based stateless authentication
- Bcrypt password hashing (cost 12)
- Token rotation on refresh
- Secure password requirements

### Authorization
- Middleware validates all protected routes
- Role-based checks (host vs player)
- Action validation per role/phase
- WebSocket token validation

### Data Protection
- No sensitive data in logs
- Password hash never returned in API
- CORS configured for allowed origins
- SQL injection prevention (parameterized queries)

---

## Version History

**v1.0.0** (Current)
- Initial release
- Core game mechanics
- Voice chat integration
- Room lifecycle management ⭐
- One room per user restriction ⭐
- Automated cleanup system ⭐

---

## Support & Contact

**Repository:** github.com/kazerdira/wolverix  
**Documentation:** See ROOM_LIFECYCLE.md for lifecycle details  
**Issues:** GitHub Issues

---

*Last Updated: December 8, 2025*
