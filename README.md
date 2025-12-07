# Werewolf Voice - Real-Time Voice Room Social Gaming

A production-ready mobile game combining the classic Werewolf (Mafia) party game with real-time voice chat using Agora.io. Players join voice rooms, are assigned secret roles, and must work together (or deceive) to win.

## 🎮 Features

- **Real-Time Voice Chat** - Powered by Agora.io with dynamic channel switching
- **Multiple Game Roles** - Werewolf, Villager, Seer, Witch, Hunter, Cupid, Bodyguard, etc.
- **WebSocket Integration** - Real-time game state synchronization
- **Production-Ready Backend** - Go + PostgreSQL + Redis
- **Cross-Platform Mobile** - Flutter app for iOS & Android
- **Scalable Architecture** - Handles thousands of concurrent games
- **Complete Game Logic** - All roles, phases, win conditions implemented

## 📋 Table of Contents

1. [Tech Stack](#tech-stack)
2. [Prerequisites](#prerequisites)
3. [Getting Agora Credentials](#getting-agora-credentials)
4. [Backend Setup](#backend-setup)
5. [Mobile App Setup](#mobile-app-setup)
6. [Running the Application](#running-the-application)
7. [API Documentation](#api-documentation)
8. [Deployment](#deployment)
9. [Troubleshooting](#troubleshooting)

## 🛠 Tech Stack

### Backend
- **Language:** Go 1.21+
- **Framework:** Gin (HTTP), Gorilla WebSocket
- **Database:** PostgreSQL 15+
- **Cache:** Redis 7+
- **Voice:** Agora RTC SDK
- **Auth:** JWT tokens

### Mobile
- **Framework:** Flutter 3.0+
- **State Management:** GetX
- **Voice SDK:** Agora Flutter SDK
- **HTTP Client:** Dio
- **WebSocket:** web_socket_channel

## 📦 Prerequisites

Before you begin, ensure you have the following installed:

### For Backend:
- [Go 1.21+](https://golang.org/dl/)
- [PostgreSQL 15+](https://www.postgresql.org/download/)
- [Redis 7+](https://redis.io/download/)
- [Docker & Docker Compose](https://docs.docker.com/get-docker/) (optional but recommended)

### For Mobile:
- [Flutter 3.0+](https://flutter.dev/docs/get-started/install)
- [Xcode](https://developer.apple.com/xcode/) (for iOS development)
- [Android Studio](https://developer.android.com/studio) (for Android development)

## 🔑 Getting Agora Credentials

Agora provides the voice infrastructure for this application. You need to create a free account and get your credentials:

### Step 1: Create Agora Account

1. Go to [Agora Console](https://console.agora.io/)
2. Click **Sign Up** and create an account
3. Verify your email address

### Step 2: Create a Project

1. In the Agora Console, click **Project Management**
2. Click **Create New Project**
3. Enter project name: `Werewolf Voice`
4. Select **Secured mode: APP ID + Token** (recommended)
5. Click **Submit**

### Step 3: Get Your Credentials

After creating the project, you'll see:

- **App ID** - A unique identifier for your project (e.g., `a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6`)
- **App Certificate** - A secret key for token generation (e.g., `z9y8x7w6v5u4t3s2r1q0p9o8n7m6l5k4`)

**Important:** Keep these credentials secret! Never commit them to version control.

### Step 4: Free Tier Limits

Agora offers a generous free tier:
- **10,000 minutes/month** of voice/video for free
- No credit card required
- Perfect for development and testing

## 🚀 Backend Setup

### Option 1: Using Docker (Recommended)

1. **Clone the repository:**
```bash
cd werewolf-voice/backend
```

2. **Create environment file:**
```bash
cp .env.example .env
```

3. **Edit `.env` with your credentials:**
```bash
# Required: Add your Agora credentials
AGORA_APP_ID=your_agora_app_id_here
AGORA_APP_CERTIFICATE=your_agora_certificate_here

# Required: Set a secure JWT secret
JWT_SECRET=your_very_secure_random_string_at_least_32_characters

# Database credentials (defaults are fine for Docker)
DB_PASSWORD=werewolf_password
```

4. **Start all services:**
```bash
cd .. # Back to root directory
docker-compose up -d
```

This will start:
- PostgreSQL on port 5432
- Redis on port 6379
- Backend API on port 8080

5. **Run database migrations:**
```bash
docker-compose exec backend psql -h postgres -U werewolf_user -d werewolf_db -f /app/migrations/001_initial_schema.up.sql
```

6. **Verify backend is running:**
```bash
curl http://localhost:8080/health
```

Should return: `{"status":"healthy"}`

### Option 2: Manual Setup

1. **Install PostgreSQL and Redis:**
```bash
# macOS
brew install postgresql@15 redis

# Ubuntu/Debian
sudo apt-get install postgresql-15 redis-server

# Start services
brew services start postgresql@15
brew services start redis
```

2. **Create database:**
```bash
psql postgres
CREATE DATABASE werewolf_db;
CREATE USER werewolf_user WITH PASSWORD 'your_password';
GRANT ALL PRIVILEGES ON DATABASE werewolf_db TO werewolf_user;
\q
```

3. **Run migrations:**
```bash
cd backend
psql -U werewolf_user -d werewolf_db -f migrations/001_initial_schema.up.sql
```

4. **Set up environment:**
```bash
cp .env.example .env
# Edit .env with your credentials
```

5. **Install Go dependencies:**
```bash
go mod download
go mod tidy
```

6. **Run the backend:**
```bash
go run cmd/server/main.go
```

Backend should now be running on `http://localhost:8080`

## 📱 Mobile App Setup

### 1. Navigate to mobile directory:
```bash
cd mobile
```

### 2. Install Flutter dependencies:
```bash
flutter pub get
```

### 3. Configure Agora in the app:

Edit `lib/services/agora_service.dart` - the App ID will be fetched from your backend via API, so no hardcoding needed!

### 4. Configure API endpoint:

Edit `lib/services/api_service.dart`:

```dart
static const String baseUrl = 'http://YOUR_IP:8080/api/v1';
```

**For iOS Simulator:** Use `http://localhost:8080/api/v1`  
**For Android Emulator:** Use `http://10.0.2.2:8080/api/v1`  
**For Physical Device:** Use your computer's IP (e.g., `http://192.168.1.10:8080/api/v1`)

### 5. Platform-specific setup:

#### iOS:
```bash
cd ios
pod install
cd ..
```

Add to `ios/Runner/Info.plist`:
```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access for voice chat during games</string>
```

#### Android:

Add to `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
```

### 6. Run the app:

```bash
# iOS
flutter run -d ios

# Android
flutter run -d android

# Or select device
flutter devices
flutter run -d <device-id>
```

## 🎯 Running the Application

### Complete Workflow:

1. **Start Backend Services:**
```bash
docker-compose up -d
# OR manually start PostgreSQL, Redis, and Go server
```

2. **Start Mobile App:**
```bash
cd mobile
flutter run
```

3. **Test the Flow:**

   a. **Register/Login:**
   - Open app → Register with username/email/password
   - Or login with existing credentials

   b. **Create/Join Room:**
   - Create a new room or browse public rooms
   - Share room code with friends
   - Wait for players to join (minimum 6)

   c. **Start Game:**
   - Host clicks "Start Game"
   - Roles are secretly assigned
   - Voice channels are automatically configured

   d. **Play Game:**
   - **Night Phase:** Werewolves discuss in private channel
   - **Day Phase:** Everyone discusses in main channel
   - **Voting:** Vote to lynch suspected werewolves
   - Game continues until one team wins!

## 📚 API Documentation

### Authentication

**Register:**
```bash
curl -X POST http://localhost:8080/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "player1",
    "email": "player1@example.com",
    "password": "secure_password"
  }'
```

**Login:**
```bash
curl -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "player1",
    "password": "secure_password"
  }'
```

### Room Management

**Create Room:**
```bash
curl -X POST http://localhost:8080/api/v1/rooms \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Epic Werewolf Game",
    "max_players": 12,
    "config": {
      "enabled_roles": ["seer", "witch", "hunter"],
      "day_phase_seconds": 300,
      "night_phase_seconds": 120
    }
  }'
```

**Get Available Rooms:**
```bash
curl http://localhost:8080/api/v1/rooms
```

**Join Room:**
```bash
curl -X POST http://localhost:8080/api/v1/rooms/join \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "room_code": "ABC123"
  }'
```

### Game Actions

**Get Agora Token:**
```bash
curl -X POST http://localhost:8080/api/v1/agora/token \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "channel_name": "room_abc123",
    "uid": 12345
  }'
```

**Perform Game Action:**
```bash
curl -X POST http://localhost:8080/api/v1/games/{sessionId}/action \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "action_type": "werewolf_vote",
    "target_id": "player-uuid"
  }'
```

### WebSocket Connection

```javascript
ws://localhost:8080/api/v1/ws?room_id=ROOM_UUID
Headers: {
  "Authorization": "Bearer YOUR_TOKEN"
}
```

## 🚢 Deployment

### Backend Deployment (Railway.app / AWS / GCP)

1. **Build Docker image:**
```bash
docker build -t werewolf-backend:latest ./backend
```

2. **Push to registry:**
```bash
docker tag werewolf-backend:latest your-registry.com/werewolf-backend:latest
docker push your-registry.com/werewolf-backend:latest
```

3. **Set environment variables on your platform:**
```
AGORA_APP_ID=xxx
AGORA_APP_CERTIFICATE=xxx
JWT_SECRET=xxx
DB_HOST=your-db-host
DB_PASSWORD=xxx
ENVIRONMENT=production
```

4. **Run migrations on production database**

### Mobile App Deployment

**iOS (App Store):**
```bash
cd ios
# Configure signing in Xcode
# Build → Archive → Upload to App Store Connect
```

**Android (Play Store):**
```bash
flutter build apk --release
flutter build appbundle --release
# Upload to Google Play Console
```

## 🔧 Troubleshooting

### Backend Issues

**PostgreSQL Connection Failed:**
```bash
# Check if PostgreSQL is running
pg_isready
# Check connection
psql -U werewolf_user -d werewolf_db -h localhost
```

**Redis Connection Failed:**
```bash
# Check if Redis is running
redis-cli ping
# Should return: PONG
```

**Agora Token Generation Failed:**
- Verify AGORA_APP_ID and AGORA_APP_CERTIFICATE in .env
- Check they match your Agora Console project
- Ensure no extra spaces or quotes

### Mobile Issues

**Agora Voice Not Working:**
- Check microphone permissions are granted
- Verify network connectivity
- Check Agora App ID is correct
- Test on real device (simulators have limited audio)

**WebSocket Connection Failed:**
- Verify backend is running: `curl http://localhost:8080/health`
- Check API base URL in api_service.dart
- For physical device, use computer's IP, not localhost

**Build Failures:**
```bash
# Clean and rebuild
flutter clean
flutter pub get
cd ios && pod install && cd ..
flutter run
```

## 📖 Architecture Overview

```
┌─────────────────┐
│  Flutter App    │
│  (Mobile UI)    │
└────────┬────────┘
         │
         ├──HTTP──→ Go Backend API
         │          ├── Room Management
         │          ├── Game Engine
         │          └── Auth & Users
         │
         ├──WS───→ WebSocket Hub
         │          └── Real-time Updates
         │
         └──Voice→ Agora RTC
                    └── Voice Channels

Backend Services:
├── PostgreSQL (Game State, Users)
├── Redis (Presence, Cache)
└── Agora (Voice Infrastructure)
```

## 🎮 Game Roles

- **Werewolf:** Kill villagers at night
- **Villager:** Find and eliminate werewolves
- **Seer:** Divine one player's role each night
- **Witch:** Heal (once) or poison (once)
- **Hunter:** Shoot someone when killed
- **Cupid:** Choose two lovers (first night)
- **Bodyguard:** Protect one player each night

## 📄 License

This project is for educational purposes. Modify as needed.

## 🙋 Support

For issues or questions:
1. Check the troubleshooting section
2. Review Agora documentation: https://docs.agora.io
3. Check Flutter documentation: https://docs.flutter.dev

---

**Ready to play? Start the backend, launch the app, and gather your friends for an epic game of Werewolf! 🐺**
