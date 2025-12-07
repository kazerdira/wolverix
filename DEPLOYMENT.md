# 🚀 DEPLOYMENT GUIDE

Production deployment guide for Werewolf Voice.

## 🎯 Pre-Deployment Checklist

- [ ] All features tested locally
- [ ] Agora account upgraded if needed (free tier: 10k minutes/month)
- [ ] Domain name purchased (optional but recommended)
- [ ] SSL certificates ready
- [ ] Monitoring tools selected
- [ ] Backup strategy defined

## ☁️ Backend Deployment Options

### Option 1: Railway.app (Easiest)

**Why Railway:**
- One-click PostgreSQL + Redis
- Auto-deploy from Git
- Built-in SSL
- $5/month starter plan

**Steps:**

1. **Push code to GitHub:**
```bash
git init
git add .
git commit -m "Initial commit"
git remote add origin https://github.com/your-username/werewolf-voice.git
git push -u origin main
```

2. **Deploy on Railway:**
   - Go to https://railway.app
   - Click "New Project"
   - Select "Deploy from GitHub repo"
   - Choose your repository
   - Add PostgreSQL service
   - Add Redis service

3. **Set Environment Variables:**
```
AGORA_APP_ID=your_agora_app_id
AGORA_APP_CERTIFICATE=your_agora_certificate
JWT_SECRET=generate_random_string_32_chars
DB_HOST=postgres.railway.internal
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=(automatically set by Railway)
DB_NAME=railway
REDIS_HOST=redis.railway.internal
REDIS_PORT=6379
ENVIRONMENT=production
```

4. **Run Migrations:**
```bash
# Connect to Railway database
railway run bash
psql $DATABASE_URL -f migrations/001_initial_schema.up.sql
```

5. **Get your URL:**
   - Railway provides: `https://your-app.up.railway.app`

### Option 2: AWS (Most Scalable)

**Services Needed:**
- ECS Fargate (containers)
- RDS PostgreSQL
- ElastiCache Redis
- Application Load Balancer
- Route 53 (DNS)

**Steps:**

1. **Create RDS PostgreSQL:**
```bash
aws rds create-db-instance \
  --db-instance-identifier werewolf-db \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --master-username admin \
  --master-user-password YourStrongPassword \
  --allocated-storage 20
```

2. **Create ElastiCache Redis:**
```bash
aws elasticache create-cache-cluster \
  --cache-cluster-id werewolf-redis \
  --cache-node-type cache.t3.micro \
  --engine redis \
  --num-cache-nodes 1
```

3. **Build & Push Docker Image:**
```bash
# Build image
docker build -t werewolf-backend:latest ./backend

# Tag for ECR
docker tag werewolf-backend:latest YOUR_ECR_URI/werewolf-backend:latest

# Push to ECR
aws ecr get-login-password | docker login --username AWS --password-stdin YOUR_ECR_URI
docker push YOUR_ECR_URI/werewolf-backend:latest
```

4. **Create ECS Task Definition:**
```json
{
  "family": "werewolf-backend",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "containerDefinitions": [{
    "name": "backend",
    "image": "YOUR_ECR_URI/werewolf-backend:latest",
    "portMappings": [{
      "containerPort": 8080,
      "protocol": "tcp"
    }],
    "environment": [
      {"name": "AGORA_APP_ID", "value": "your_app_id"},
      {"name": "DB_HOST", "value": "your-rds-endpoint"}
    ]
  }]
}
```

5. **Create ECS Service:**
```bash
aws ecs create-service \
  --cluster werewolf-cluster \
  --service-name werewolf-service \
  --task-definition werewolf-backend \
  --desired-count 2 \
  --launch-type FARGATE
```

### Option 3: Google Cloud Run (Serverless)

**Steps:**

1. **Enable APIs:**
```bash
gcloud services enable run.googleapis.com
gcloud services enable sql-component.googleapis.com
```

2. **Create Cloud SQL PostgreSQL:**
```bash
gcloud sql instances create werewolf-db \
  --database-version=POSTGRES_15 \
  --tier=db-f1-micro \
  --region=us-central1
```

3. **Deploy to Cloud Run:**
```bash
gcloud run deploy werewolf-backend \
  --source ./backend \
  --platform managed \
  --region us-central1 \
  --allow-unauthenticated \
  --set-env-vars AGORA_APP_ID=xxx,JWT_SECRET=xxx
```

## 📱 Mobile App Deployment

### iOS App Store

1. **Prepare App:**
```bash
cd mobile
flutter build ios --release
```

2. **Configure in Xcode:**
   - Open `ios/Runner.xcworkspace`
   - Set Team & Bundle Identifier
   - Configure signing certificates
   - Update version & build number

3. **Archive & Upload:**
   - Product → Archive
   - Window → Organizer
   - Distribute App → App Store Connect
   - Upload

4. **App Store Connect:**
   - Add screenshots
   - Write description
   - Set pricing
   - Submit for review

**Timeline:** 1-7 days for review

### Android Play Store

1. **Generate Signing Key:**
```bash
keytool -genkey -v -keystore ~/werewolf-key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias werewolf
```

2. **Configure Signing:**

Create `android/key.properties`:
```properties
storePassword=your_password
keyPassword=your_password
keyAlias=werewolf
storeFile=/path/to/werewolf-key.jks
```

Update `android/app/build.gradle`:
```gradle
signingConfigs {
    release {
        keyAlias keystoreProperties['keyAlias']
        keyPassword keystoreProperties['keyPassword']
        storeFile file(keystoreProperties['storeFile'])
        storePassword keystoreProperties['storePassword']
    }
}
buildTypes {
    release {
        signingConfig signingConfigs.release
    }
}
```

3. **Build Release:**
```bash
flutter build appbundle --release
```

4. **Upload to Play Console:**
   - Go to https://play.google.com/console
   - Create app
   - Upload AAB file
   - Add screenshots, description
   - Submit for review

**Timeline:** 1-3 days for review

## 🔒 SSL/TLS Configuration

### Let's Encrypt (Free SSL)

**For Railway/Cloud Run:** Automatic!

**For AWS/Custom Server:**

1. **Install Certbot:**
```bash
sudo snap install --classic certbot
```

2. **Get Certificate:**
```bash
sudo certbot --nginx -d api.yourapp.com
```

3. **Auto-Renewal:**
```bash
sudo certbot renew --dry-run
```

## 📊 Monitoring & Analytics

### Backend Monitoring

**Recommended Tools:**
- **Sentry** - Error tracking
- **DataDog** - APM & metrics
- **Prometheus + Grafana** - Open source monitoring

**Add to Go code:**
```go
import "github.com/getsentry/sentry-go"

sentry.Init(sentry.ClientOptions{
    Dsn: "your-sentry-dsn",
    Environment: "production",
})
```

### Mobile Analytics

**Firebase Analytics:**

```yaml
# pubspec.yaml
dependencies:
  firebase_core: ^2.24.2
  firebase_analytics: ^10.7.4
```

```dart
// Initialize
await Firebase.initializeApp();
FirebaseAnalytics analytics = FirebaseAnalytics.instance;

// Track events
analytics.logEvent(
  name: 'game_started',
  parameters: {'room_id': roomId},
);
```

### Agora Analytics

- Built-in analytics at https://console.agora.io
- Track call quality, duration, concurrent users

## 🔄 CI/CD Pipeline

### GitHub Actions Example

Create `.github/workflows/deploy.yml`:

```yaml
name: Deploy Backend

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Build Docker image
        run: docker build -t werewolf-backend ./backend
      
      - name: Push to Registry
        run: |
          echo ${{ secrets.REGISTRY_PASSWORD }} | docker login -u ${{ secrets.REGISTRY_USER }} --password-stdin
          docker push werewolf-backend
      
      - name: Deploy to Railway
        run: railway up
        env:
          RAILWAY_TOKEN: ${{ secrets.RAILWAY_TOKEN }}
```

## 💾 Backup Strategy

### Database Backups

**Automated (Railway):**
- Automatic daily backups included

**Manual (PostgreSQL):**
```bash
# Backup
pg_dump -U postgres werewolf_db > backup_$(date +%Y%m%d).sql

# Restore
psql -U postgres werewolf_db < backup_20240101.sql
```

**AWS RDS:**
- Enable automated backups (retention: 7-35 days)
- Take manual snapshots before major updates

### Redis Backups

```bash
# Save snapshot
redis-cli SAVE

# Backup file
cp /var/lib/redis/dump.rdb backup_$(date +%Y%m%d).rdb
```

## 🔍 Performance Optimization

### Backend

1. **Enable Caching:**
```go
// Cache frequently accessed data
func (h *Handler) GetRooms(c *gin.Context) {
    cached, _ := h.redis.Get("rooms:list").Result()
    if cached != "" {
        c.JSON(200, cached)
        return
    }
    // ... fetch from DB and cache
}
```

2. **Database Indexes:**
All critical indexes already in migrations!

3. **Connection Pooling:**
Already configured in `database.go`

4. **CDN for Assets:**
Use CloudFront or Cloudflare

### Mobile

1. **Optimize Images:**
```bash
# Compress images
pngquant assets/images/*.png
```

2. **Enable Code Obfuscation:**
```bash
flutter build apk --obfuscate --split-debug-info=build/app/outputs/symbols
```

3. **Tree Shaking:**
Automatically done by Flutter in release mode

## 💰 Cost Estimates

### Monthly Costs (USD)

**Small Scale (100 daily users):**
- Railway: $5-20
- Agora: Free (under 10k minutes)
- **Total: $5-20/month**

**Medium Scale (1000 daily users):**
- Railway/AWS: $50-100
- Agora: $50-100 (30k minutes)
- **Total: $100-200/month**

**Large Scale (10k daily users):**
- AWS/GCP: $200-500
- Agora: $500-1000
- CDN: $50-100
- **Total: $750-1600/month**

## 🚨 Security Checklist

- [ ] JWT secret is strong & secret
- [ ] Database credentials secured
- [ ] Agora certificate never exposed
- [ ] HTTPS/TLS enabled everywhere
- [ ] Rate limiting configured
- [ ] Input validation on all endpoints
- [ ] SQL injection prevention (using pgx parameterized queries ✓)
- [ ] XSS prevention
- [ ] CORS properly configured

## 📈 Scaling Strategy

**Phase 1 (0-1k users):**
- Single backend instance
- Managed PostgreSQL
- Managed Redis

**Phase 2 (1k-10k users):**
- 2-3 backend instances
- Load balancer
- Database read replicas
- Redis cluster

**Phase 3 (10k+ users):**
- Auto-scaling backend (5-20 instances)
- Database sharding
- Redis cluster with replication
- CDN for static assets
- Regional deployments

## 🔄 Post-Deployment

1. **Monitor Logs:**
```bash
# Railway
railway logs

# AWS
aws logs tail /aws/ecs/werewolf-backend --follow
```

2. **Set Up Alerts:**
- Error rate > 1%
- Response time > 1s
- Database connections > 80%
- Memory usage > 80%

3. **Gradual Rollout:**
- Deploy to staging first
- Test with beta users
- Monitor metrics closely
- Gradual traffic increase

## ✅ Launch Checklist

- [ ] Backend deployed & health check passing
- [ ] Database migrations run
- [ ] Agora tokens working
- [ ] WebSocket connections stable
- [ ] Mobile apps submitted to stores
- [ ] Monitoring & alerts configured
- [ ] Backups automated
- [ ] Documentation updated
- [ ] Support email/channel ready
- [ ] Marketing materials prepared

---

**You're ready to launch! Good luck with your Werewolf Voice game! 🎉🐺**
