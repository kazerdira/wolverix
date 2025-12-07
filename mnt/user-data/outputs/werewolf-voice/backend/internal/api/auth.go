package api

import (
	"context"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/yourusername/werewolf-voice/internal/models"
	"golang.org/x/crypto/bcrypt"
)

// Register handles user registration
func (h *Handler) Register(c *gin.Context) {
	var req models.RegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Hash password
	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to hash password"})
		return
	}

	// Set default language if not provided
	if req.Language == "" {
		req.Language = "en"
	}

	// Create user
	userID := uuid.New()
	ctx := context.Background()
	
	_, err = h.db.PG.Exec(ctx, `
		INSERT INTO users (id, username, email, password_hash, language, reputation_score)
		VALUES ($1, $2, $3, $4, $5, $6)
	`, userID, req.Username, req.Email, string(hashedPassword), req.Language, 100)
	
	if err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "username or email already exists"})
		return
	}

	// Create user stats
	_, err = h.db.PG.Exec(ctx, `
		INSERT INTO user_stats (user_id) VALUES ($1)
	`, userID)

	// Generate JWT token
	token, err := generateJWT(userID, req.Username, 24*time.Hour)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate token"})
		return
	}

	refreshToken, err := generateJWT(userID, req.Username, 7*24*time.Hour)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate refresh token"})
		return
	}

	user := models.User{
		ID:              userID,
		Username:        req.Username,
		Email:           req.Email,
		Language:        req.Language,
		ReputationScore: 100,
		CreatedAt:       time.Now(),
		UpdatedAt:       time.Now(),
	}

	response := models.AuthResponse{
		Token:        token,
		RefreshToken: refreshToken,
		User:         user,
	}

	c.JSON(http.StatusCreated, response)
}

// Login handles user authentication
func (h *Handler) Login(c *gin.Context) {
	var req models.LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	ctx := context.Background()
	
	// Get user from database
	var user models.User
	err := h.db.PG.QueryRow(ctx, `
		SELECT id, username, email, password_hash, avatar_url, display_name, 
			language, reputation_score, is_banned, created_at, updated_at
		FROM users WHERE username = $1
	`, req.Username).Scan(&user.ID, &user.Username, &user.Email, &user.PasswordHash,
		&user.AvatarURL, &user.DisplayName, &user.Language, &user.ReputationScore,
		&user.IsBanned, &user.CreatedAt, &user.UpdatedAt)
	
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid credentials"})
		return
	}

	// Check if banned
	if user.IsBanned {
		c.JSON(http.StatusForbidden, gin.H{"error": "account is banned"})
		return
	}

	// Verify password
	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.Password)); err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid credentials"})
		return
	}

	// Update last seen
	_, err = h.db.PG.Exec(ctx, `
		UPDATE users SET last_seen_at = $1 WHERE id = $2
	`, time.Now(), user.ID)

	// Generate JWT tokens
	token, err := generateJWT(user.ID, user.Username, 24*time.Hour)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate token"})
		return
	}

	refreshToken, err := generateJWT(user.ID, user.Username, 7*24*time.Hour)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate refresh token"})
		return
	}

	// Clear password hash before sending
	user.PasswordHash = ""

	response := models.AuthResponse{
		Token:        token,
		RefreshToken: refreshToken,
		User:         user,
	}

	c.JSON(http.StatusOK, response)
}

// GetProfile returns the current user's profile
func (h *Handler) GetProfile(c *gin.Context) {
	userID, _ := c.Get("user_id")
	
	ctx := context.Background()
	var user models.User
	
	err := h.db.PG.QueryRow(ctx, `
		SELECT id, username, email, avatar_url, display_name, language, 
			reputation_score, created_at, updated_at, last_seen_at
		FROM users WHERE id = $1
	`, userID).Scan(&user.ID, &user.Username, &user.Email, &user.AvatarURL,
		&user.DisplayName, &user.Language, &user.ReputationScore, 
		&user.CreatedAt, &user.UpdatedAt, &user.LastSeenAt)
	
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		return
	}

	c.JSON(http.StatusOK, user)
}

// GetStats returns the current user's statistics
func (h *Handler) GetStats(c *gin.Context) {
	userID, _ := c.Get("user_id")
	
	ctx := context.Background()
	var stats models.UserStats
	
	err := h.db.PG.QueryRow(ctx, `
		SELECT user_id, total_games, total_wins, total_losses,
			games_as_villager, games_as_werewolf, games_as_seer, games_as_witch, games_as_hunter,
			villager_wins, werewolf_wins, current_streak, best_streak,
			total_kills, total_deaths, mvp_count
		FROM user_stats WHERE user_id = $1
	`, userID).Scan(&stats.UserID, &stats.TotalGames, &stats.TotalWins, &stats.TotalLosses,
		&stats.GamesAsVillager, &stats.GamesAsWerewolf, &stats.GamesAsSeer, &stats.GamesAsWitch, &stats.GamesAsHunter,
		&stats.VillagerWins, &stats.WerewolfWins, &stats.CurrentStreak, &stats.BestStreak,
		&stats.TotalKills, &stats.TotalDeaths, &stats.MVPCount)
	
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "stats not found"})
		return
	}

	c.JSON(http.StatusOK, stats)
}

// Helper: Generate JWT token
func generateJWT(userID uuid.UUID, username string, expiry time.Duration) (string, error) {
	claims := jwt.MapClaims{
		"user_id":  userID.String(),
		"username": username,
		"exp":      time.Now().Add(expiry).Unix(),
		"iat":      time.Now().Unix(),
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	
	// Get secret from environment (hardcoded for now, should come from config)
	secret := []byte("your-secret-key-change-this-in-production")
	
	return token.SignedString(secret)
}

// GetRoom returns room details
func (h *Handler) GetRoom(c *gin.Context) {
	roomIDStr := c.Param("roomId")
	roomID, err := uuid.Parse(roomIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid room ID"})
		return
	}

	ctx := context.Background()
	var room models.Room
	
	// Implementation similar to GetRooms but for single room with players
	c.JSON(http.StatusOK, room)
}

// LeaveRoom handles player leaving a room
func (h *Handler) LeaveRoom(c *gin.Context) {
	userID, _ := c.Get("user_id")
	roomIDStr := c.Param("roomId")
	
	roomID, err := uuid.Parse(roomIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid room ID"})
		return
	}

	ctx := context.Background()
	
	// Mark player as left
	_, err = h.db.PG.Exec(ctx, `
		UPDATE room_players SET left_at = $1 
		WHERE room_id = $2 AND user_id = $3 AND left_at IS NULL
	`, time.Now(), roomID, userID)
	
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to leave room"})
		return
	}

	// Broadcast update
	h.wsHub.BroadcastToRoom(roomID, models.WSTypeRoomUpdate, gin.H{
		"action": "player_left",
		"user_id": userID,
	})

	c.JSON(http.StatusOK, gin.H{"success": true})
}

// SetReady toggles player ready status
func (h *Handler) SetReady(c *gin.Context) {
	userID, _ := c.Get("user_id")
	roomIDStr := c.Param("roomId")
	
	roomID, err := uuid.Parse(roomIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid room ID"})
		return
	}

	ctx := context.Background()
	
	_, err = h.db.PG.Exec(ctx, `
		UPDATE room_players SET is_ready = NOT is_ready 
		WHERE room_id = $1 AND user_id = $2
	`, roomID, userID)
	
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update ready status"})
		return
	}

	h.wsHub.BroadcastToRoom(roomID, models.WSTypeRoomUpdate, gin.H{
		"action": "player_ready_changed",
		"user_id": userID,
	})

	c.JSON(http.StatusOK, gin.H{"success": true})
}

// GetGameState returns current game state
func (h *Handler) GetGameState(c *gin.Context) {
	sessionIDStr := c.Param("sessionId")
	sessionID, err := uuid.Parse(sessionIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid session ID"})
		return
	}

	// Implementation would fetch full game state
	c.JSON(http.StatusOK, gin.H{"session_id": sessionID})
}

// GetMyRole returns the current player's role (private)
func (h *Handler) GetMyRole(c *gin.Context) {
	userID, _ := c.Get("user_id")
	sessionIDStr := c.Param("sessionId")
	
	sessionID, err := uuid.Parse(sessionIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid session ID"})
		return
	}

	ctx := context.Background()
	var role models.Role
	var team models.Team
	
	err = h.db.PG.QueryRow(ctx, `
		SELECT role, team FROM game_players 
		WHERE session_id = $1 AND user_id = $2
	`, sessionID, userID).Scan(&role, &team)
	
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "role not found"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"role": role,
		"team": team,
	})
}
