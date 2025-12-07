# 📁 PROJECT STRUCTURE

## Overview

```
werewolf-voice/
├── backend/              # Go backend server
├── mobile/              # Flutter mobile app
├── docker-compose.yml   # Docker orchestration
├── README.md           # Full documentation
└── QUICKSTART.md       # Quick setup guide
```

## 🔧 Backend Structure

```
backend/
├── cmd/
│   └── server/
│       └── main.go              # Entry point, server setup
│
├── internal/
│   ├── api/
│   │   ├── handlers.go          # Room & game HTTP handlers
│   │   └── auth.go              # Auth endpoints (login/register)
│   │
│   ├── config/
│   │   └── config.go            # Configuration management
│   │
│   ├── database/
│   │   └── database.go          # PostgreSQL & Redis connections
│   │
│   ├── game/
│   │   ├── engine.go            # Core game logic (start game, role assignment)
│   │   └── actions.go           # Player actions (vote, divine, etc.)
│   │
│   ├── websocket/
│   │   └── hub.go               # Real-time WebSocket hub
│   │
│   ├── agora/
│   │   └── service.go           # Agora token generation
│   │
│   ├── middleware/
│   │   └── auth.go              # JWT authentication
│   │
│   └── models/
│       └── models.go            # Data structures & types
│
├── migrations/
│   ├── 001_initial_schema.up.sql    # Database setup
│   └── 001_initial_schema.down.sql  # Database teardown
│
├── go.mod                       # Go dependencies
├── go.sum                       # Dependency checksums
├── .env.example                 # Environment template
└── Dockerfile                   # Container definition
```

### Key Backend Files

**`cmd/server/main.go`**
- Application entry point
- Initializes services (DB, Redis, Agora, WebSocket)
- Sets up HTTP routes
- Handles graceful shutdown

**`internal/game/engine.go`**
- Core game engine
- Role assignment algorithm
- Game initialization
- Win condition checking

**`internal/game/actions.go`**
- Processes player actions (votes, abilities)
- Validates action permissions
- Updates game state
- Triggers events

**`internal/websocket/hub.go`**
- Manages WebSocket connections
- Broadcasts updates to rooms
- Handles client connect/disconnect
- Room-based message routing

**`internal/agora/service.go`**
- Generates Agora RTC tokens
- Validates channel names
- Manages token expiry
- Supports multiple roles (publisher/subscriber)

**`migrations/001_initial_schema.up.sql`**
- Complete database schema
- All tables, indexes, constraints
- Views for common queries
- Sample achievement data

## 📱 Mobile Structure

```
mobile/
├── lib/
│   ├── main.dart                # App entry point
│   │
│   ├── models/
│   │   └── models.dart          # Data models (User, Room, Game, etc.)
│   │
│   ├── services/
│   │   ├── api_service.dart     # HTTP API client
│   │   ├── agora_service.dart   # Voice chat integration
│   │   └── websocket_service.dart  # Real-time updates
│   │
│   ├── screens/                 # UI screens (add your designs here)
│   │   ├── login_screen.dart
│   │   ├── home_screen.dart
│   │   ├── room_screen.dart
│   │   └── game_screen.dart
│   │
│   ├── widgets/                 # Reusable UI components
│   │   ├── player_card.dart
│   │   ├── role_card.dart
│   │   └── voice_indicator.dart
│   │
│   ├── providers/               # State management (GetX controllers)
│   │   ├── auth_provider.dart
│   │   ├── room_provider.dart
│   │   └── game_provider.dart
│   │
│   └── utils/                   # Helper functions
│       ├── constants.dart
│       └── validators.dart
│
├── assets/
│   ├── images/                  # App images
│   ├── icons/                   # Custom icons
│   └── animations/              # Lottie animations
│
├── android/                     # Android config
├── ios/                         # iOS config
└── pubspec.yaml                 # Flutter dependencies
```

### Key Mobile Files

**`lib/services/agora_service.dart`**
- **CORE FEATURE:** Voice chat implementation
- Initializes Agora RTC engine
- Joins/leaves voice channels
- Handles mute/unmute
- Switches channels (main/werewolf/dead)
- Speaker volume control
- Audio event callbacks

**`lib/services/api_service.dart`**
- All HTTP requests to backend
- Auth (login/register)
- Room management (create/join/leave)
- Game actions (vote/divine/poison)
- Agora token fetching
- Automatic JWT token injection

**`lib/services/websocket_service.dart`**
- Real-time game updates
- Room state changes
- Player join/leave events
- Phase transitions
- Death notifications
- Heartbeat (ping/pong)

**`lib/models/models.dart`**
- Dart classes matching backend models
- JSON serialization/deserialization
- Type-safe data structures

**`lib/main.dart`**
- App initialization
- Theme configuration
- Navigation setup
- Service injection (GetX)
- Splash screen

## 🎮 Game Flow Architecture

```
User Opens App
    ↓
Login/Register → JWT Token → Stored Securely
    ↓
Browse/Create Room
    ↓
Join Room → Connect WebSocket → Subscribe to room updates
    ↓
Get Agora Token → Join Voice Channel (main)
    ↓
Host Starts Game
    ↓
Backend: Assign Roles → Create Game Session
    ↓
WS: Broadcast game_started
    ↓
Mobile: Show Role Card (private)
    ↓
--- NIGHT PHASE ---
    ↓
Werewolves → Switch to werewolf channel → Vote for kill
Seer → Divine action → Get result (private)
Witch → Heal/poison decision
Bodyguard → Protect someone
    ↓
WS: Broadcast phase_change → DAY
    ↓
--- DAY PHASE ---
    ↓
Everyone → Main voice channel → Discuss
    ↓
WS: Announce deaths
    ↓
--- VOTING PHASE ---
    ↓
Everyone votes → Backend counts
    ↓
WS: Broadcast lynch result
    ↓
Check Win Condition
    ↓
Game Continues OR Game Ends
```

## 🔐 Security Architecture

### Authentication Flow
```
1. User submits credentials
2. Backend validates & hashes password
3. Backend generates JWT with user_id
4. Mobile stores token securely
5. All requests include: Authorization: Bearer <token>
6. Middleware validates token on each request
```

### Agora Token Flow
```
1. Mobile requests token from backend
2. Backend generates token with:
   - App Certificate (secret)
   - Channel name
   - User UID
   - Expiry time
3. Mobile receives token
4. Mobile joins Agora channel with token
5. Agora validates token server-side
```

## 🗄️ Database Schema Highlights

**Users Table:**
- Authentication credentials
- Profile information
- Reputation score
- Ban status

**Rooms Table:**
- Room configuration
- Player count tracking
- Agora channel mapping
- Status (waiting/playing/finished)

**Game Sessions:**
- Current phase & day number
- Alive counts (werewolves/villagers)
- Game state JSON (flexible)
- Win condition tracking

**Game Players:**
- Role assignment (secret)
- Alive status
- Role-specific state (potions used, etc.)
- Voice channel assignment
- Lover pairing

**Game Actions:**
- Every action recorded
- Audit trail
- Used for replay/analysis

## 🚀 Deployment Architecture

### Development
```
localhost:5432  → PostgreSQL
localhost:6379  → Redis
localhost:8080  → Go Backend
Device/Simulator → Flutter App
```

### Production
```
Cloud PostgreSQL (RDS/Cloud SQL)
Cloud Redis (ElastiCache/MemoryStore)
Cloud Run/ECS/K8s → Go Backend (scaled)
App Store/Play Store → Flutter App
Agora.io → Voice Infrastructure
```

## 📊 Performance Considerations

**Backend:**
- Connection pooling (PostgreSQL: 25 max, Redis: 10)
- WebSocket hub runs in goroutine
- Each room has isolated state
- Indexes on all query paths

**Mobile:**
- Dio HTTP client with connection pooling
- Agora SDK optimized for mobile networks
- WebSocket auto-reconnect
- Cached images

**Agora:**
- High-quality voice codec
- Adaptive bitrate
- Low latency (<400ms)
- Supports 1000s concurrent channels

## 🧪 Testing Strategy

**Backend Testing:**
```bash
cd backend
go test ./... -v
```

**Mobile Testing:**
```bash
cd mobile
flutter test
flutter integration_test
```

**Load Testing:**
- Use k6 or Artillery for API load testing
- Test concurrent games
- Measure WebSocket throughput

## 🔄 Update & Extend

### Adding a New Role:

1. **Backend:** Add role to `models.go` Role enum
2. **Backend:** Implement role logic in `actions.go`
3. **Backend:** Update role assignment in `engine.go`
4. **Mobile:** Add role to `models.dart`
5. **Mobile:** Create role UI card
6. **Mobile:** Add action buttons for role

### Adding a New Feature:

1. **Database:** Add migration if DB changes needed
2. **Backend:** Add model, handler, service logic
3. **Mobile:** Add service method, UI screen
4. **Test:** Both backend and mobile
5. **Document:** Update README

## 📚 External Dependencies

**Backend:**
- Gin (HTTP framework)
- Gorilla WebSocket
- pgx (PostgreSQL driver)
- go-redis
- Agora Go tokenbuilder
- JWT library

**Mobile:**
- GetX (state management)
- Dio (HTTP client)
- Agora Flutter SDK
- web_socket_channel
- flutter_secure_storage

---

**This structure is designed for scalability and maintainability. Start small, test often, scale when needed!**
