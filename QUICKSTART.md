# ⚡ QUICK START GUIDE

Get up and running in 5 minutes!

## 🎯 Prerequisites

1. [Docker Desktop](https://www.docker.com/products/docker-desktop/) installed
2. [Flutter 3.0+](https://flutter.dev/docs/get-started/install) installed
3. [Agora Account](https://console.agora.io/) (free - see below)

## 🔑 Step 1: Get Agora Credentials (2 minutes)

1. Go to https://console.agora.io/
2. Sign up (free, no credit card needed)
3. Create a project called "Werewolf Voice"
4. Select **"Secured mode: APP ID + Token"**
5. Copy your **App ID** and **App Certificate**

## 🚀 Step 2: Start Backend (1 minute)

```bash
cd werewolf-voice/backend

# Create .env file
cp .env.example .env

# Edit .env - ONLY these 3 lines are required:
AGORA_APP_ID=paste_your_app_id_here
AGORA_APP_CERTIFICATE=paste_your_certificate_here
JWT_SECRET=any_random_string_at_least_32_chars_long

# Start everything with Docker
cd ..
docker-compose up -d

# Run migrations
docker-compose exec backend sh -c "cd /root && psql postgresql://werewolf_user:werewolf_password@postgres:5432/werewolf_db -f migrations/001_initial_schema.up.sql"
```

Wait ~30 seconds for services to start, then verify:
```bash
curl http://localhost:8080/health
# Should return: {"status":"healthy"}
```

## 📱 Step 3: Run Mobile App (2 minutes)

```bash
cd mobile

# Install dependencies
flutter pub get

# Run on your device/simulator
flutter run
```

**IMPORTANT:** Edit `lib/services/api_service.dart` first:
- **iOS Simulator:** Use `http://localhost:8080/api/v1`
- **Android Emulator:** Use `http://10.0.2.2:8080/api/v1`  
- **Physical Device:** Use `http://YOUR_IP:8080/api/v1` (find your IP with `ipconfig` or `ifconfig`)

## 🎮 Step 4: Test It Out!

1. Open the app
2. Register a new account
3. Create a room
4. Open another device/simulator and join with the room code
5. Start the game!

## ❓ Troubleshooting

**Backend not starting?**
```bash
docker-compose logs backend
```

**Can't connect from mobile?**
- Check firewall allows port 8080
- Use your computer's IP address, not "localhost" on physical devices
- Verify backend health: `curl http://localhost:8080/health`

**Agora voice not working?**
- Grant microphone permissions in phone settings
- Test on real device (simulators have limited audio)
- Verify Agora credentials in backend .env file

## 📚 Next Steps

- Read full [README.md](README.md) for detailed documentation
- Customize game rules in `RoomConfig`
- Add more UI screens in Flutter
- Deploy to production (Railway.app, AWS, etc.)

## 🆘 Need Help?

1. Check [README.md](README.md) Troubleshooting section
2. Review Agora docs: https://docs.agora.io
3. Check logs: `docker-compose logs -f`

---

**That's it! You now have a production-ready voice chat gaming platform running locally! 🎉**
