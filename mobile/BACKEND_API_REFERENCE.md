# Wolverix Backend API Reference

**Version:** 1.0.0  
**Base URL:** `http://localhost:8080/api/v1`  
**Last Updated:** December 10, 2025

This document provides the complete API reference for the Wolverix Werewolf game backend, including all endpoints, WebSocket events, authentication, and error handling patterns that have been **tested and verified to work**.

---

## 📋 Table of Contents

1. [Authentication](#authentication)
2. [Room Management](#room-management)
3. [Game Flow](#game-flow)
4. [Game Actions](#game-actions)
5. [WebSocket Connection](#websocket-connection)
6. [Error Handling](#error-handling)
7. [Data Models](#data-models)

---

## 🔐 Authentication

### Register User

```http
POST /auth/register
Content-Type: application/json

{
  "username": "string",
  "password": "string",
  "email": "string"
}
```

**Response (201):**
```json
{
  "user_id": "uuid",
  "username": "string",
  "email": "string"
}
```

**Errors:**
- `409 Conflict` - Username or email already exists
- `400 Bad Request` - Invalid input

---

### Login

```http
POST /auth/login
Content-Type: application/json

{
  "username": "string",
  "password": "string"
}
```

**Response (200):**
```json
{
  "token": "jwt_token_string",
  "user_id": "uuid",
  "username": "string"
}
```

**Errors:**
- `401 Unauthorized` - Invalid credentials
- `400 Bad Request` - Missing fields

---

### Using JWT Token

All authenticated endpoints require the JWT token in the Authorization header:

```http
Authorization: Bearer <jwt_token>
```

**Example (PowerShell):**
```powershell
$headers = @{ Authorization = "Bearer $token" }
Invoke-RestMethod -Uri "$baseUrl/rooms" -Headers $headers
```

**Example (JavaScript):**
```javascript
fetch('http://localhost:8080/api/v1/rooms', {
  headers: {
    'Authorization': `Bearer ${token}`,
    'Content-Type': 'application/json'
  }
})
```

---

## 🏠 Room Management

### Create Room

```http
POST /rooms
Authorization: Bearer <token>
Content-Type: application/json

{
  "name": "string",
  "max_players": 8,
  "is_private": false,
  "config": {
    "werewolf_count": 2,
    "day_phase_seconds": 300,
    "night_phase_seconds": 120,
    "voting_seconds": 180,
    "enabled_roles": ["werewolf", "villager", "seer", "witch", "cupid", "bodyguard", "hunter"]
  }
}
```

**Response (201):**
```json
{
  "id": "uuid",
  "room_code": "ABC123",
  "name": "string",
  "host_user_id": "uuid",
  "status": "waiting",
  "max_players": 8,
  "current_players": 1,
  "config": { ... }
}
```

**Notes:**
- `room_code` is auto-generated (6 characters)
- Creator becomes host automatically
- Minimum players: 4
- Maximum players: 20

---

### Join Room

```http
POST /rooms/{room_id}/join
Authorization: Bearer <token>
Content-Type: application/json

{
  "room_code": "ABC123"
}
```

**Response (200):**
```json
{
  "room": { ... },
  "player": {
    "id": "uuid",
    "user_id": "uuid",
    "username": "string",
    "is_ready": false
  }
}
```

**Errors:**
- `404 Not Found` - Room doesn't exist
- `400 Bad Request` - Room is full or game already started
- `409 Conflict` - Already in room

---

### Mark Ready

```http
POST /rooms/{room_id}/ready
Authorization: Bearer <token>
```

**Response (200):**
```json
{
  "is_ready": true
}
```

**Notes:**
- Must be called before host can start game
- Can be toggled on/off

---

### Start Game

```http
POST /rooms/{room_id}/start
Authorization: Bearer <token>
```

**Response (200):**
```json
{
  "session_id": "uuid",
  "status": "active",
  "current_phase": "night_0",
  "phase_number": 1
}
```

**Requirements:**
- Must be room host
- All players must be ready
- Minimum 4 players

**Errors:**
- `403 Forbidden` - Not host
- `400 Bad Request` - Not all players ready or insufficient players

---

## 🎮 Game Flow

### Get Game State

```http
GET /games/{session_id}
Authorization: Bearer <token>
```

**Response (200):**
```json
{
  "id": "uuid",
  "room_id": "uuid",
  "status": "active",
  "current_phase": "night_0",
  "phase_number": 1,
  "day_number": 0,
  "phase_started_at": "2025-12-10T00:00:00Z",
  "phase_ends_at": "2025-12-10T00:02:00Z",
  "werewolves_alive": 2,
  "villagers_alive": 6,
  "winner": null,
  "players": [
    {
      "id": "uuid",
      "user_id": "uuid",
      "username": "string",
      "role": "seer",
      "team": "villagers",
      "is_alive": true,
      "died_at_phase": null,
      "death_reason": null,
      "seat_position": 1,
      "current_voice_channel": "main",
      "allowed_chat_channels": ["main"]
    }
  ]
}
```

**Notes:**
- Each player only sees their own `role`
- Other players' roles are hidden until death
- Werewolves can see other werewolves' roles
- Poll this endpoint to track game state changes
- Phase transitions happen automatically after `phase_ends_at`

**Voice Channel Fields (Critical for Agora Integration):**
- `current_voice_channel`: Current channel player should be in (`"werewolf"`, `"main"`, `"dead"`, or `""`)
- `allowed_chat_channels`: Array of channels player can access (e.g., `["werewolf"]`, `["main"]`, `["dead"]`, or `[]`)
- Empty `allowed_chat_channels` means player is **silenced** (cannot talk or listen)

---

### Game Phases

The game follows this cycle:

1. **`night_0`** - First night (Cupid chooses lovers, werewolves vote, seer divines, bodyguard protects, witch acts)
2. **`day_discussion`** - Players discuss who might be werewolf (no voting yet)
3. **`day_voting`** - Players vote to lynch someone
4. **`night_0`** - Regular night (werewolves kill, special roles act)
5. Repeat steps 2-4 until game ends

**Phase Durations (configurable in room config):**
- Night: `night_phase_seconds` (default: 120s)
- Discussion: `day_phase_seconds` (default: 300s)
- Voting: `voting_seconds` (default: 180s)

---

## ⚔️ Game Actions

### Submit Action

```http
POST /games/{session_id}/action
Authorization: Bearer <token>
Content-Type: application/json

{
  "action_type": "string",
  "target_id": "uuid",        // optional
  "data": { ... }             // optional, depends on action type
}
```

**Response (200):**
```json
{
  "success": true,
  "message": "Action recorded"
}
```

---

### Action Types

#### 1. Cupid Choose Lovers (First Night Only)

```json
{
  "action_type": "cupid_choose",
  "target_id": "player1_id",
  "data": {
    "second_lover": "player2_id"
  }
}
```

**Rules:**
- Can only be used on phase 1 (night_0)
- Targets must be different players
- Both lovers die if one dies
- Lovers can win if they're the last 2 alive

---

#### 2. Werewolf Vote

```json
{
  "action_type": "werewolf_vote",
  "target_id": "victim_player_id"
}
```

**Rules:**
- Only during night phases
- Must be a werewolf
- All werewolves must vote
- Majority target dies (unless protected/healed)

---

#### 3. Seer Divine

```json
{
  "action_type": "seer_divine",
  "target_id": "player_id"
}
```

**Rules:**
- Only during night phases
- Must be seer and alive
- Reveals if target is werewolf or villager
- One divine per night

---

#### 4. Bodyguard Protect

```json
{
  "action_type": "bodyguard_protect",
  "target_id": "player_id"
}
```

**Rules:**
- Only during night phases
- Must be bodyguard and alive
- Cannot protect same player twice in a row
- Protects target from werewolf kill only (not witch poison)

---

#### 5. Witch Heal

```json
{
  "action_type": "witch_heal"
}
```

**Rules:**
- Only during night phases
- Must be witch and alive
- Can only use once per game
- Saves the werewolf victim
- Witch knows who was attacked

---

#### 6. Witch Poison

```json
{
  "action_type": "witch_poison",
  "target_id": "player_id"
}
```

**Rules:**
- Only during night phases
- Must be witch and alive
- Can only use once per game
- Kills target (cannot be protected/healed)

---

#### 7. Lynch Vote

```json
{
  "action_type": "vote_lynch",
  "target_id": "player_id"
}
```

**Rules:**
- Only during `day_voting` phase
- All alive players can vote
- Player with most votes is lynched
- Ties: no one is lynched

---

#### 8. Hunter Shoot (Automatic on Death)

```json
{
  "action_type": "hunter_shoot",
  "target_id": "player_id"
}
```

**Rules:**
- Only hunter can use
- Automatically triggered when hunter dies
- Hunter can choose to shoot someone or skip
- Happens immediately after hunter's death

---

### Action Validation Errors

**Common errors (400 Bad Request):**
```json
{
  "error": "invalid action type"
}
```

```json
{
  "error": "not your turn / wrong phase"
}
```

```json
{
  "error": "dead players cannot act"
}
```

```json
{
  "error": "target not found or invalid"
}
```

```json
{
  "error": "action already submitted this phase"
}
```

**Example handling in PowerShell:**
```powershell
try {
    $response = Invoke-RestMethod -Method Post -Uri "$baseUrl/games/$sessionId/action" `
        -Headers @{ Authorization = "Bearer $token" } `
        -Body ($action | ConvertTo-Json) `
        -ContentType "application/json"
    Write-Host "✓ Action successful"
} catch {
    Write-Host "✗ Action failed: $($_.ErrorDetails.Message)" -ForegroundColor Red
}
```

---

## 🔌 WebSocket Connection

### Connect to Game Room

```
ws://localhost:8080/api/v1/ws?room_id={room_id}&token={jwt_token}
```

**Example (JavaScript):**
```javascript
const ws = new WebSocket(`ws://localhost:8080/api/v1/ws?room_id=${roomId}&token=${token}`);

ws.onopen = () => {
  console.log('Connected to game room');
};

ws.onmessage = (event) => {
  const message = JSON.parse(event.data);
  handleMessage(message);
};

ws.onerror = (error) => {
  console.error('WebSocket error:', error);
};

ws.onclose = () => {
  console.log('Disconnected from game room');
};
```

**Connection Notes:**
- Token must be passed as query parameter
- Will receive 401 if token is invalid or expired
- Automatically joins the room on connection
- Receives all game events in real-time

---

### WebSocket Message Types

All messages follow this structure:
```json
{
  "type": "string",
  "payload": { ... }
}
```

---

#### 1. Game Started

```json
{
  "type": "game_update",
  "payload": {
    "action": "game_started",
    "session_id": "uuid",
    "phase": "night_0"
  }
}
```

---

#### 2. Phase Change

```json
{
  "type": "phase_change",
  "payload": {
    "session_id": "uuid",
    "from_phase": "night_0",
    "to_phase": "day_discussion",
    "phase": "day_discussion",
    "phase_number": 2,
    "day_number": 1,
    "phase_end_time": "2025-12-10T00:05:00Z",
    "message": "Day 1 begins. No one died during the night.",
    "deaths": [
      {
        "player_id": "uuid",
        "username": "string",
        "role": "villager",
        "death_reason": "werewolf_kill"
      }
    ]
  }
}
```

---

#### 3. Player Action

```json
{
  "type": "game_update",
  "payload": {
    "action": "werewolf_vote",
    "phase": "night_0",
    "session_id": "uuid"
  }
}
```

**Note:** Specific action details are hidden for game integrity

---

#### 4. Player Joined/Left

```json
{
  "type": "player_update",
  "payload": {
    "action": "joined",
    "room_id": "uuid",
    "player": {
      "user_id": "uuid",
      "username": "string"
    }
  }
}
```

---

#### 5. Player Ready Status

```json
{
  "type": "player_update",
  "payload": {
    "action": "ready_status",
    "room_id": "uuid",
    "player_id": "uuid",
    "is_ready": true
  }
}
```

---

#### 6. Game Over

```json
{
  "type": "game_over",
  "payload": {
    "session_id": "uuid",
    "winner": "villagers",
    "final_state": {
      "werewolves_alive": 0,
      "villagers_alive": 4,
      "days_survived": 3
    }
  }
}
```

---

### WebSocket Error Handling

**Connection Errors:**
- Invalid token → 401 response, connection refused
- Room not found → Connection closes immediately
- Player not in room → Connection closes immediately

**Reconnection Strategy:**
```javascript
let ws;
let reconnectAttempts = 0;
const maxReconnectAttempts = 5;

function connect() {
  ws = new WebSocket(wsUrl);
  
  ws.onclose = () => {
    if (reconnectAttempts < maxReconnectAttempts) {
      reconnectAttempts++;
      setTimeout(() => connect(), 2000 * reconnectAttempts);
    }
  };
  
  ws.onopen = () => {
    reconnectAttempts = 0; // Reset on successful connection
  };
}
```

---

## 🎤 Voice Channel Security (Critical for Agora Integration)

### Overview

The backend manages voice channel access to ensure game integrity. **Werewolves must be able to talk privately at night without villagers hearing them.** This is enforced through the `allowed_chat_channels` field.

### Channel Types

| Channel | Who Can Access | When |
|---------|---------------|------|
| `werewolf` | Werewolves only | During night phases |
| `main` | All alive players | During day discussion & voting |
| `dead` | Dead players | After death (spectator chat) |
| Empty `[]` | No one | Player is silenced |

### Channel Assignment by Phase & Role

#### Night Phases (`night_0`, `night_2`, etc.)

```dart
// Werewolf perspective
{
  "current_voice_channel": "werewolf",
  "allowed_chat_channels": ["werewolf"]
}

// Non-werewolf perspective (Seer, Villager, Bodyguard, etc.)
{
  "current_voice_channel": "",
  "allowed_chat_channels": []  // SILENCED - cannot talk or hear
}

// Dead player
{
  "current_voice_channel": "dead",
  "allowed_chat_channels": ["dead"]
}
```

#### Day Phases (`day_discussion`, `day_voting`)

```dart
// All alive players
{
  "current_voice_channel": "main",
  "allowed_chat_channels": ["main"]
}

// Dead player
{
  "current_voice_channel": "dead",
  "allowed_chat_channels": ["dead"]
}
```

### Flutter/Dart Integration

#### 1. Poll Game State for Channel Updates

```dart
class GameService {
  Timer? _pollTimer;
  
  void startPolling(String sessionId) {
    _pollTimer = Timer.periodic(Duration(seconds: 2), (_) async {
      final gameState = await getGameState(sessionId);
      final myPlayer = gameState.players.firstWhere(
        (p) => p.userId == currentUserId
      );
      
      // Update voice channels based on allowed_chat_channels
      await updateVoiceChannels(
        myPlayer.allowedChatChannels,
        myPlayer.currentVoiceChannel
      );
    });
  }
  
  void stopPolling() {
    _pollTimer?.cancel();
  }
}
```

#### 2. Enforce Channel Access with Agora

```dart
class VoiceChannelManager {
  final AgoraRtcEngine agoraEngine;
  String? currentChannel;
  
  Future<void> updateVoiceChannels(
    List<String> allowedChannels,
    String currentVoiceChannel
  ) async {
    // Case 1: Player is silenced
    if (allowedChannels.isEmpty) {
      await muteAndLeaveChannel();
      return;
    }
    
    // Case 2: Player has channel access
    final targetChannel = allowedChannels.first;
    
    if (currentChannel != targetChannel) {
      // Leave old channel
      if (currentChannel != null) {
        await agoraEngine.leaveChannel();
      }
      
      // Join new channel
      final token = await getAgoraToken(targetChannel);
      await agoraEngine.joinChannel(
        token: token,
        channelId: targetChannel,
        uid: myUid,
        options: ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileCommunication,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
        ),
      );
      
      currentChannel = targetChannel;
      print('✓ Joined voice channel: $targetChannel');
    }
  }
  
  Future<void> muteAndLeaveChannel() async {
    await agoraEngine.muteLocalAudioStream(true);
    if (currentChannel != null) {
      await agoraEngine.leaveChannel();
      currentChannel = null;
    }
    print('✓ Silenced - left all voice channels');
  }
}
```

#### 3. UI State Management

```dart
class VoiceChannelState extends ChangeNotifier {
  List<String> allowedChannels = [];
  bool get isSilenced => allowedChannels.isEmpty;
  bool get canTalk => allowedChannels.isNotEmpty;
  String? get currentChannel => allowedChannels.isNotEmpty ? allowedChannels.first : null;
  
  void updateFromGameState(Player myPlayer) {
    allowedChannels = myPlayer.allowedChatChannels;
    notifyListeners();
  }
}

// In your widget
Widget build(BuildContext context) {
  return Consumer<VoiceChannelState>(
    builder: (context, voiceState, _) {
      if (voiceState.isSilenced) {
        return VoiceSilencedIndicator(); // Show muted icon
      }
      return VoiceActiveIndicator(
        channel: voiceState.currentChannel!
      );
    },
  );
}
```

### Security Requirements

⚠️ **CRITICAL: The frontend MUST enforce these restrictions**

1. **Always check `allowed_chat_channels` before enabling voice**
2. **Immediately leave channels when `allowed_chat_channels` becomes empty**
3. **Never allow manual channel switching** - backend controls access
4. **Poll game state every 2-3 seconds** during active game for channel updates
5. **Use WebSocket `phase_change` events** to trigger immediate channel updates

### Testing Checklist

- ✅ Night phase: Werewolves can hear each other, villagers are silenced
- ✅ Day phase: All alive players can hear each other
- ✅ Dead players: Isolated to dead channel
- ✅ Phase transitions: Channels update within 2-3 seconds
- ✅ No audio leakage between channels

**Verified with:** `backend/test_voice_channels.ps1`

---

## ⚠️ Error Handling

### HTTP Status Codes

| Code | Meaning | Example |
|------|---------|---------|
| 200 | Success | Action recorded |
| 201 | Created | Room or user created |
| 400 | Bad Request | Invalid action, wrong phase, missing fields |
| 401 | Unauthorized | Invalid or missing JWT token |
| 403 | Forbidden | Not host, not your turn |
| 404 | Not Found | Room or game not found |
| 409 | Conflict | Username taken, already in room |
| 500 | Server Error | Database error, unexpected error |

---

### Error Response Format

All errors return JSON:
```json
{
  "error": "human readable error message"
}
```

**Examples:**
```json
{ "error": "invalid username or password" }
{ "error": "room not found" }
{ "error": "dead players cannot act" }
{ "error": "not your turn" }
{ "error": "invalid action type" }
```

---

### Common Error Scenarios

#### 1. Token Expired
```
401 Unauthorized
{ "error": "token is expired" }
```

**Solution:** Re-login to get new token

---

#### 2. Wrong Phase
```
400 Bad Request
{ "error": "action not allowed in current phase" }
```

**Solution:** Check `current_phase` in game state before submitting action

---

#### 3. Already Acted
```
400 Bad Request
{ "error": "action already submitted this phase" }
```

**Solution:** Track which actions have been submitted locally

---

#### 4. Invalid Target
```
400 Bad Request
{ "error": "target player not found or dead" }
```

**Solution:** Verify target is alive before submitting action

---

## 📊 Data Models

### User
```typescript
interface User {
  id: string;              // UUID
  username: string;
  email: string;
  avatar_url?: string;
  display_name?: string;
  language: string;        // "en", "fr", etc.
  is_online: boolean;
  reputation_score: number;
  is_banned: boolean;
  banned_until?: string;   // ISO 8601 datetime
  created_at: string;      // ISO 8601 datetime
}
```

---

### Room
```typescript
interface Room {
  id: string;              // UUID
  room_code: string;       // 6 characters
  name: string;
  host_user_id: string;    // UUID
  status: "waiting" | "playing" | "finished" | "abandoned";
  is_private: boolean;
  max_players: number;
  current_players: number;
  language: string;
  config: RoomConfig;
  created_at: string;
  updated_at: string;
}
```

---

### RoomConfig
```typescript
interface RoomConfig {
  enabled_roles: string[];          // ["werewolf", "seer", "witch", ...]
  werewolf_count: number;           // Number of werewolves
  day_phase_seconds: number;        // Discussion duration
  night_phase_seconds: number;      // Night action duration
  voting_seconds: number;           // Lynch voting duration
  allow_spectators: boolean;
  require_ready: boolean;
}
```

---

### GameSession
```typescript
interface GameSession {
  id: string;                       // UUID
  room_id: string;                  // UUID
  status: "active" | "finished";
  current_phase: GamePhase;
  phase_number: number;             // Increments each phase
  day_number: number;               // Increments each day
  phase_started_at: string;         // ISO 8601
  phase_ends_at: string;            // ISO 8601
  werewolves_alive: number;
  villagers_alive: number;
  winner?: "werewolves" | "villagers" | "lovers" | "tanner";
  players: GamePlayer[];
  started_at: string;
  ended_at?: string;
}
```

---

### GamePlayer
```typescript
interface GamePlayer {
  id: string;                       // UUID (game_player_id)
  session_id: string;               // UUID
  user_id: string;                  // UUID
  username: string;
  role: Role;
  team: "werewolves" | "villagers" | "neutral";
  is_alive: boolean;
  died_at_phase?: number;
  death_reason?: string;
  seat_position: number;            // 1-based
  lover_id?: string;                // UUID if player is a lover
}
```

---

### Role Types
```typescript
type Role = 
  | "werewolf"
  | "villager"
  | "seer"
  | "witch"
  | "hunter"
  | "cupid"
  | "bodyguard"
  | "mayor"
  | "tanner"
  | "medium"
  | "little_girl";
```

---

### GamePhase Types
```typescript
type GamePhase =
  | "night_0"              // Night phase
  | "day_discussion"       // Day discussion
  | "day_voting"          // Lynch voting
  | "game_over";          // Game ended
```

---

## 🧪 Tested & Verified

This API reference is based on **actual working tests**. The following test files demonstrate correct usage:

1. **`test_comprehensive.ps1`** - Complete 8-player game with all mechanics
2. **`test_scenario_full.ps1`** - 6-player game with security tests
3. **`test_complete_game.ps1`** - Multiple scenarios to win conditions

### Key Verified Behaviors:

✅ **Authentication:**
- JWT tokens work correctly
- Token must be in `Authorization: Bearer <token>` header
- Expired tokens return 401

✅ **Room Management:**
- Room creation and joining works
- Ready system works
- Host can start game when all ready

✅ **Game Actions:**
- All role powers work (Cupid, Werewolf, Seer, Witch, Bodyguard)
- Phase restrictions enforced
- Dead players blocked from acting
- Action validation works

✅ **Phase Transitions:**
- Auto-transitions work after timer expires
- Deaths resolved correctly
- Lover death chains work (both die together)

✅ **WebSocket:**
- Real-time updates work
- Phase changes broadcast
- Death notifications sent

✅ **Error Handling:**
- All error codes verified
- Error messages are clear
- Invalid actions properly rejected

---

## 💡 Best Practices

### 1. **Always Check Phase Before Action**
```javascript
const gameState = await fetch(`/api/v1/games/${sessionId}`).then(r => r.json());
if (gameState.current_phase === 'night_0' && myRole === 'werewolf') {
  // Submit werewolf vote
}
```

### 2. **Handle Token Expiration**
```javascript
async function apiCall(url, options) {
  let response = await fetch(url, options);
  if (response.status === 401) {
    // Token expired, re-login
    await login();
    response = await fetch(url, options); // Retry
  }
  return response;
}
```

### 3. **Use WebSocket for Real-Time Updates**
Don't poll `/games/{session_id}` constantly. Use WebSocket to receive updates automatically.

### 4. **Track Game State Locally**
```javascript
let gameState = {
  myRole: null,
  currentPhase: null,
  alivePlayers: [],
  hasActedThisPhase: false
};

// Update on WebSocket messages
ws.onmessage = (event) => {
  const msg = JSON.parse(event.data);
  if (msg.type === 'phase_change') {
    gameState.currentPhase = msg.payload.phase;
    gameState.hasActedThisPhase = false;
  }
};
```

### 5. **Validate Before Submitting Actions**
```javascript
function canSubmitAction(actionType, targetId) {
  if (!myPlayer.is_alive) return false;
  if (gameState.hasActedThisPhase) return false;
  if (gameState.currentPhase !== getRequiredPhase(actionType)) return false;
  if (targetId && !isPlayerAlive(targetId)) return false;
  return true;
}
```

---

## 🚀 Quick Start Example

```javascript
// 1. Register/Login
const loginResponse = await fetch('http://localhost:8080/api/v1/auth/login', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ username: 'player1', password: 'pass123' })
});
const { token, user_id } = await loginResponse.json();

// 2. Create Room
const roomResponse = await fetch('http://localhost:8080/api/v1/rooms', {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${token}`,
    'Content-Type': 'application/json'
  },
  body: JSON.stringify({
    name: 'My Game',
    max_players: 8,
    config: {
      werewolf_count: 2,
      day_phase_seconds: 300,
      night_phase_seconds: 120,
      voting_seconds: 180,
      enabled_roles: ['werewolf', 'villager', 'seer', 'witch', 'cupid']
    }
  })
});
const { id: roomId, room_code } = await roomResponse.json();

// 3. Connect WebSocket
const ws = new WebSocket(`ws://localhost:8080/api/v1/ws?room_id=${roomId}&token=${token}`);
ws.onmessage = (event) => {
  const msg = JSON.parse(event.data);
  console.log('Received:', msg.type, msg.payload);
};

// 4. Mark Ready
await fetch(`http://localhost:8080/api/v1/rooms/${roomId}/ready`, {
  method: 'POST',
  headers: { 'Authorization': `Bearer ${token}` }
});

// 5. Start Game (when all ready)
const startResponse = await fetch(`http://localhost:8080/api/v1/rooms/${roomId}/start`, {
  method: 'POST',
  headers: { 'Authorization': `Bearer ${token}` }
});
const { session_id } = await startResponse.json();

// 6. Get My Role
const gameState = await fetch(`http://localhost:8080/api/v1/games/${session_id}`, {
  headers: { 'Authorization': `Bearer ${token}` }
}).then(r => r.json());

const myPlayer = gameState.players.find(p => p.user_id === user_id);
console.log('My role:', myPlayer.role);

// 7. Submit Action (example: werewolf vote)
if (myPlayer.role === 'werewolf' && gameState.current_phase === 'night_0') {
  const target = gameState.players.find(p => p.team === 'villagers');
  await fetch(`http://localhost:8080/api/v1/games/${session_id}/action`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      action_type: 'werewolf_vote',
      target_id: target.id
    })
  });
}
```

---

## 📞 Support

For issues or questions:
- Check error messages carefully - they're descriptive
- Verify JWT token format: `Authorization: Bearer <token>`
- Ensure actions match current phase
- Check WebSocket connection before expecting real-time updates

**Backend Status:** ✅ Production Ready  
**Test Coverage:** ✅ All core mechanics verified  
**Known Issues:** None blocking production use
