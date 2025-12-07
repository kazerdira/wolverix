package api

import (
	"context"
	"log"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/kazerdira/wolverix/backend/internal/config"
	"github.com/kazerdira/wolverix/backend/internal/middleware"
	"github.com/kazerdira/wolverix/backend/internal/models"
	"golang.org/x/crypto/bcrypt"
)

// Register handles user registration
func (h *Handler) Register(c *gin.Context) {
	var req models.RegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		log.Printf("❌ Register - JSON bind error: %v", err)
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	log.Printf("✓ Register request - Username: %s, Email: %s", req.Username, req.Email)

	// Hash password
	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to hash password"})
		return
	}

	userID := uuid.New()
	now := time.Now()
	language := req.Language
	if language == "" {
		language = "en"
	}

	ctx := context.Background()

	// Check if username or email already exists
	var existingCount int
	err = h.db.PG.QueryRow(ctx, `
		SELECT COUNT(*) FROM users WHERE username = $1 OR email = $2
	`, req.Username, req.Email).Scan(&existingCount)
	if err != nil {
		log.Printf("❌ Register - Error checking existing user: %v", err)
	}
	if err == nil && existingCount > 0 {
		log.Printf("⚠️ Register - User already exists: %s / %s", req.Username, req.Email)
		c.JSON(http.StatusConflict, gin.H{"error": "username or email already exists"})
		return
	}

	// Create user
	_, err = h.db.PG.Exec(ctx, `
		INSERT INTO users (id, username, email, password_hash, language, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
	`, userID, req.Username, req.Email, string(hashedPassword), language, now, now)

	if err != nil {
		log.Printf("❌ Register - Error creating user: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create user"})
		return
	}

	// Create user stats
	_, err = h.db.PG.Exec(ctx, `
		INSERT INTO user_stats (user_id, created_at, updated_at) VALUES ($1, $2, $3)
	`, userID, now, now)
	if err != nil {
		log.Printf("❌ Register - Error creating user stats: %v", err)
	}

	// Load config for JWT
	cfg, err := config.Load()
	if err != nil {
		log.Printf("❌ Register - Error loading config: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load configuration"})
		return
	}

	// Generate tokens
	token, err := middleware.GenerateToken(userID, req.Username, cfg.JWT.Secret, cfg.JWT.ExpiryHours)
	if err != nil {
		log.Printf("❌ Register - Error generating token: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate token"})
		return
	}

	refreshToken, err := middleware.GenerateRefreshToken(userID, req.Username, cfg.JWT.Secret, cfg.JWT.RefreshExpiryDays)
	if err != nil {
		log.Printf("❌ Register - Error generating refresh token: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate refresh token"})
		return
	}

	user := models.User{
		ID:              userID,
		Username:        req.Username,
		Email:           req.Email,
		Language:        language,
		ReputationScore: 0,
		IsBanned:        false,
		CreatedAt:       now,
		UpdatedAt:       now,
	}

	c.JSON(http.StatusCreated, models.AuthResponse{
		Token:        token,
		RefreshToken: refreshToken,
		User:         user,
	})
}

// Login handles user authentication
func (h *Handler) Login(c *gin.Context) {
	var req models.LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		log.Printf("❌ Login - JSON bind error: %v", err)
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	// Require either username or email
	if req.Username == "" && req.Email == "" {
		log.Printf("❌ Login - Missing username or email")
		c.JSON(http.StatusBadRequest, gin.H{"error": "username or email is required"})
		return
	}

	loginIdentifier := req.Username
	if loginIdentifier == "" {
		loginIdentifier = req.Email
	}
	log.Printf("✓ Login request - Identifier: %s", loginIdentifier)

	ctx := context.Background()

	// Get user by username or email - only select columns that exist in the database
	var user models.User
	var passwordHash string
	var lastSeenAt *time.Time
	err := h.db.PG.QueryRow(ctx, `
		SELECT id, username, email, password_hash, avatar_url, language, created_at, updated_at, last_seen_at
		FROM users WHERE username = $1 OR email = $1
	`, loginIdentifier).Scan(
		&user.ID, &user.Username, &user.Email, &passwordHash,
		&user.AvatarURL, &user.Language, &user.CreatedAt, &user.UpdatedAt, &lastSeenAt,
	)

	if err != nil {
		log.Printf("❌ Login - User not found or error: %v", err)
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid username or password"})
		return
	}

	user.LastSeenAt = lastSeenAt
	// Set fields that don't exist in database but are in the model
	user.ReputationScore = 0
	user.IsBanned = false

	// Verify password
	if err := bcrypt.CompareHashAndPassword([]byte(passwordHash), []byte(req.Password)); err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid username or password"})
		return
	}

	// Update last seen
	now := time.Now()
	h.db.PG.Exec(ctx, `UPDATE users SET last_seen_at = $1 WHERE id = $2`, now, user.ID)

	// Load config for JWT
	cfg, _ := config.Load()

	// Generate tokens
	token, err := middleware.GenerateToken(user.ID, user.Username, cfg.JWT.Secret, cfg.JWT.ExpiryHours)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate token"})
		return
	}

	refreshToken, err := middleware.GenerateRefreshToken(user.ID, user.Username, cfg.JWT.Secret, cfg.JWT.RefreshExpiryDays)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate refresh token"})
		return
	}

	c.JSON(http.StatusOK, models.AuthResponse{
		Token:        token,
		RefreshToken: refreshToken,
		User:         user,
	})
}

// RefreshToken handles token refresh
func (h *Handler) RefreshToken(c *gin.Context) {
	var req models.RefreshTokenRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	cfg, _ := config.Load()

	// Validate refresh token
	claims, err := middleware.ValidateRefreshToken(req.RefreshToken, cfg.JWT.Secret)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid refresh token"})
		return
	}

	ctx := context.Background()

	// Get user to ensure they still exist and aren't banned
	var isBanned bool
	err = h.db.PG.QueryRow(ctx, `SELECT is_banned FROM users WHERE id = $1`, claims.UserID).Scan(&isBanned)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user not found"})
		return
	}

	if isBanned {
		c.JSON(http.StatusForbidden, gin.H{"error": "user is banned"})
		return
	}

	// Generate new tokens
	token, err := middleware.GenerateToken(claims.UserID, claims.Username, cfg.JWT.Secret, cfg.JWT.ExpiryHours)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate token"})
		return
	}

	refreshToken, err := middleware.GenerateRefreshToken(claims.UserID, claims.Username, cfg.JWT.Secret, cfg.JWT.RefreshExpiryDays)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate refresh token"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"token":         token,
		"refresh_token": refreshToken,
	})
}

// GetCurrentUser returns the current authenticated user
func (h *Handler) GetCurrentUser(c *gin.Context) {
	log.Printf("✓ GetCurrentUser - Starting, user_id from context: %v", c.GetString("user_id"))
	userID, exists := c.Get("user_id")
	if !exists {
		log.Printf("❌ GetCurrentUser - No user_id in context")
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	log.Printf("✓ GetCurrentUser - User ID: %v", userID)

	ctx := context.Background()

	var user models.User
	err := h.db.PG.QueryRow(ctx, `
		SELECT id, username, email, avatar_url, language, is_online,
			created_at, updated_at, last_seen_at
		FROM users WHERE id = $1
	`, userID).Scan(
		&user.ID, &user.Username, &user.Email, &user.AvatarURL,
		&user.Language, &user.IsOnline,
		&user.CreatedAt, &user.UpdatedAt, &user.LastSeenAt,
	)

	if err != nil {
		log.Printf("❌ GetCurrentUser - Database error: %v", err)
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		return
	}

	// Set default values for non-existent fields
	displayName := user.Username
	user.DisplayName = &displayName // Use username as display name
	user.ReputationScore = 0
	user.IsBanned = false

	log.Printf("✓ GetCurrentUser - Success, returning user: %s", user.Username)
	c.JSON(http.StatusOK, user)
}

// UpdateUser updates user profile
func (h *Handler) UpdateUser(c *gin.Context) {
	userID, _ := c.Get("user_id")

	var req struct {
		DisplayName *string `json:"display_name"`
		AvatarURL   *string `json:"avatar_url"`
		Language    *string `json:"language"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	ctx := context.Background()

	_, err := h.db.PG.Exec(ctx, `
		UPDATE users SET 
			display_name = COALESCE($1, display_name),
			avatar_url = COALESCE($2, avatar_url),
			language = COALESCE($3, language),
			updated_at = $4
		WHERE id = $5
	`, req.DisplayName, req.AvatarURL, req.Language, time.Now(), userID)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update user"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "user updated"})
}

// GetUserStats returns user statistics
func (h *Handler) GetUserStats(c *gin.Context) {
	userIDStr := c.Param("userId")
	log.Printf("✓ GetUserStats - Fetching stats for user: %s", userIDStr)

	userID, err := uuid.Parse(userIDStr)
	if err != nil {
		log.Printf("❌ GetUserStats - Invalid user ID format: %s", userIDStr)
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid user ID"})
		return
	}

	ctx := context.Background()

	var stats models.UserStats
	err = h.db.PG.QueryRow(ctx, `
		SELECT user_id, games_played, games_won, games_lost, games_as_villager,
			games_as_werewolf, games_as_seer, games_as_witch, games_as_hunter,
			games_won_as_villager, games_won_as_werewolf, total_kills,
			created_at, updated_at
		FROM user_stats WHERE user_id = $1
	`, userID).Scan(
		&stats.UserID, &stats.TotalGames, &stats.TotalWins, &stats.TotalLosses,
		&stats.GamesAsVillager, &stats.GamesAsWerewolf, &stats.GamesAsSeer,
		&stats.GamesAsWitch, &stats.GamesAsHunter, &stats.VillagerWins,
		&stats.WerewolfWins, &stats.TotalKills,
		&stats.CreatedAt, &stats.UpdatedAt,
	)

	if err != nil {
		log.Printf("❌ GetUserStats - Database error: %v", err)
		// If no stats exist, create default stats
		if err.Error() == "no rows in result set" {
			log.Printf("✓ GetUserStats - Creating default stats for user: %s", userID)
			now := time.Now()
			stats = models.UserStats{
				UserID:          userID,
				TotalGames:      0,
				TotalWins:       0,
				TotalLosses:     0,
				GamesAsVillager: 0,
				GamesAsWerewolf: 0,
				GamesAsSeer:     0,
				GamesAsWitch:    0,
				GamesAsHunter:   0,
				VillagerWins:    0,
				WerewolfWins:    0,
				CurrentStreak:   0,
				BestStreak:      0,
				TotalKills:      0,
				TotalDeaths:     0,
				MVPCount:        0,
				CreatedAt:       now,
				UpdatedAt:       now,
			}
			// Insert default stats into database
			_, insertErr := h.db.PG.Exec(ctx, `
				INSERT INTO user_stats (user_id) VALUES ($1)
			`, userID)
			if insertErr != nil {
				log.Printf("❌ GetUserStats - Failed to create default stats: %v", insertErr)
			}
		} else {
			c.JSON(http.StatusNotFound, gin.H{"error": "stats not found"})
			return
		}
	}

	// Set default values for fields not in database
	stats.CurrentStreak = 0
	stats.BestStreak = 0
	stats.TotalDeaths = 0
	stats.MVPCount = 0

	log.Printf("✓ GetUserStats - Success, returning stats for user: %s", userID)
	c.JSON(http.StatusOK, stats)
}
