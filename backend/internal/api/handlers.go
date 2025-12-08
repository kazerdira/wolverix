package api

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"math/rand"
	"net/http"
	"time"

	rtctokenbuilder "github.com/AgoraIO-Community/go-tokenbuilder/rtctokenbuilder"
	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/gorilla/websocket"
	"github.com/kazerdira/wolverix/backend/internal/agora"
	"github.com/kazerdira/wolverix/backend/internal/config"
	"github.com/kazerdira/wolverix/backend/internal/database"
	"github.com/kazerdira/wolverix/backend/internal/game"
	"github.com/kazerdira/wolverix/backend/internal/models"
	ws "github.com/kazerdira/wolverix/backend/internal/websocket"
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		return true // Configure properly in production
	},
}

type Handler struct {
	db               *database.Database
	gameEngine       *game.Engine
	agoraService     *agora.Service
	wsHub            *ws.Hub
	lifecycleManager RoomLifecycleManager
}

// RoomLifecycleManager interface for activity tracking
type RoomLifecycleManager interface {
	UpdateActivity(ctx context.Context, roomID uuid.UUID) error
	ExtendTimeout(ctx context.Context, roomID uuid.UUID, hostUserID uuid.UUID) error
}

func NewHandler(db *database.Database, gameEngine *game.Engine, agoraService *agora.Service, wsHub *ws.Hub, lifecycleManager RoomLifecycleManager) *Handler {
	return &Handler{
		db:               db,
		gameEngine:       gameEngine,
		agoraService:     agoraService,
		wsHub:            wsHub,
		lifecycleManager: lifecycleManager,
	}
}

// ============================================================================
// ROOM HANDLERS
// ============================================================================

// CreateRoom creates a new game room
func (h *Handler) CreateRoom(c *gin.Context) {
	userID, _ := c.Get("user_id")
	log.Printf("✓ CreateRoom - User %v attempting to create room", userID)

	var req models.CreateRoomRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		log.Printf("❌ CreateRoom - Invalid request body: %v", err)
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	log.Printf("✓ CreateRoom - Request parsed: name=%s, maxPlayers=%d, isPrivate=%v", req.Name, req.MaxPlayers, req.IsPrivate)

	// Set defaults
	if req.MaxPlayers == 0 {
		req.MaxPlayers = 12
	}

	// Validate MaxPlayers after setting default
	if req.MaxPlayers < 6 || req.MaxPlayers > 24 {
		log.Printf("❌ CreateRoom - Invalid MaxPlayers: %d (must be between 6 and 24)", req.MaxPlayers)
		c.JSON(http.StatusBadRequest, gin.H{"error": "max_players must be between 6 and 24"})
		return
	}

	if req.Language == "" {
		req.Language = "en"
	}
	if req.Config.DayPhaseSeconds == 0 {
		req.Config.DayPhaseSeconds = 120
	}
	if req.Config.NightPhaseSeconds == 0 {
		req.Config.NightPhaseSeconds = 60
	}
	if req.Config.VotingSeconds == 0 {
		req.Config.VotingSeconds = 60
	}

	log.Printf("✓ CreateRoom - After defaults: maxPlayers=%d, language=%s", req.MaxPlayers, req.Language)

	ctx := context.Background()

	// Check if user is already in an active room
	var existingRoomCount int
	err := h.db.PG.QueryRow(ctx, `
		SELECT COUNT(*) FROM room_players rp
		JOIN rooms r ON rp.room_id = r.id
		WHERE rp.user_id = $1 
		  AND rp.left_at IS NULL 
		  AND r.status IN ('waiting', 'in_progress')
	`, userID).Scan(&existingRoomCount)

	if err != nil && err != sql.ErrNoRows {
		log.Printf("❌ CreateRoom - Failed to check existing rooms: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to verify room status"})
		return
	}

	if existingRoomCount > 0 {
		log.Printf("❌ CreateRoom - User %v already in an active room", userID)
		c.JSON(http.StatusBadRequest, gin.H{"error": "you are already in an active room. Please leave it before creating a new one"})
		return
	}

	// Generate unique room code
	roomCode := generateRoomCode()
	roomID := uuid.New()
	agoraChannelName := fmt.Sprintf("room_%s", roomID.String()[:8])

	// Validate channel name
	if err := h.agoraService.ValidateChannelName(agoraChannelName); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create voice channel"})
		return
	}

	configJSON, _ := json.Marshal(req.Config)

	// Create room in database
	_, err = h.db.PG.Exec(ctx, `
		INSERT INTO rooms (id, room_code, name, host_user_id, is_private, max_players, 
			current_players, language, config, agora_channel_name, agora_app_id, status)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
	`, roomID, roomCode, req.Name, userID, req.IsPrivate, req.MaxPlayers,
		1, req.Language, configJSON, agoraChannelName, h.agoraService.GetAppID(), "waiting")

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create room"})
		return
	}

	// Add host as player
	playerID := uuid.New()
	_, err = h.db.PG.Exec(ctx, `
		INSERT INTO room_players (id, room_id, user_id, is_ready, is_host, seat_position)
		VALUES ($1, $2, $3, $4, $5, $6)
	`, playerID, roomID, userID, false, true, 0)

	if err != nil {
		log.Printf("❌ CreateRoom - Failed to add host to room: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to add host to room"})
		return
	}

	// Fetch the host user details to include in response
	var hostUser models.User
	err = h.db.PG.QueryRow(ctx, `
		SELECT id, username, email, avatar_url, language, is_online
		FROM users WHERE id = $1
	`, userID).Scan(
		&hostUser.ID, &hostUser.Username, &hostUser.Email, &hostUser.AvatarURL,
		&hostUser.Language, &hostUser.IsOnline,
	)
	if err != nil {
		log.Printf("❌ CreateRoom - Failed to fetch host user: %v", err)
	}

	// Create room player object for host
	seatPos := 0
	hostPlayer := models.RoomPlayer{
		ID:           playerID,
		RoomID:       roomID,
		UserID:       userID.(uuid.UUID),
		IsReady:      false,
		IsHost:       true,
		SeatPosition: &seatPos,
		JoinedAt:     time.Now(),
		User:         &hostUser,
	}

	appID := h.agoraService.GetAppID()
	room := models.Room{
		ID:               roomID,
		RoomCode:         roomCode,
		Name:             req.Name,
		HostUserID:       userID.(uuid.UUID),
		Status:           models.RoomStatusWaiting,
		IsPrivate:        req.IsPrivate,
		MaxPlayers:       req.MaxPlayers,
		CurrentPlayers:   1,
		Language:         req.Language,
		Config:           req.Config,
		AgoraChannelName: agoraChannelName,
		AgoraAppID:       &appID,
		CreatedAt:        time.Now(),
		Players:          []models.RoomPlayer{hostPlayer},
	}

	log.Printf("✓ CreateRoom - Room created successfully: %s (code: %s) with %d players", room.Name, roomCode, len(room.Players))
	c.JSON(http.StatusCreated, room)
}

// GetRooms returns list of available rooms
func (h *Handler) GetRooms(c *gin.Context) {
	ctx := context.Background()

	rows, err := h.db.PG.Query(ctx, `
		SELECT r.id, r.room_code, r.name, r.host_user_id, r.status, r.is_private,
			r.max_players, r.current_players, r.language, r.created_at,
			u.username, u.avatar_url
		FROM rooms r
		JOIN users u ON r.host_user_id = u.id
		WHERE r.status = 'waiting' AND NOT r.is_private
		ORDER BY r.created_at DESC
		LIMIT 50
	`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch rooms"})
		return
	}
	defer rows.Close()

	var rooms []models.Room
	for rows.Next() {
		var room models.Room
		var host models.User
		var avatarURL sql.NullString

		err := rows.Scan(&room.ID, &room.RoomCode, &room.Name, &room.HostUserID, &room.Status,
			&room.IsPrivate, &room.MaxPlayers, &room.CurrentPlayers, &room.Language, &room.CreatedAt,
			&host.Username, &avatarURL)
		if err != nil {
			continue
		}

		if avatarURL.Valid {
			host.AvatarURL = &avatarURL.String
		}
		host.ID = room.HostUserID
		room.Host = &host
		rooms = append(rooms, room)
	}

	c.JSON(http.StatusOK, rooms)
}

// GetRoom returns details of a specific room
func (h *Handler) GetRoom(c *gin.Context) {
	roomIDStr := c.Param("roomId")
	roomID, err := uuid.Parse(roomIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid room ID"})
		return
	}

	ctx := context.Background()

	var room models.Room
	var configJSON json.RawMessage
	err = h.db.PG.QueryRow(ctx, `
		SELECT id, room_code, name, host_user_id, status, is_private,
			max_players, current_players, language, config, agora_channel_name,
			agora_app_id, created_at, started_at
		FROM rooms WHERE id = $1
	`, roomID).Scan(
		&room.ID, &room.RoomCode, &room.Name, &room.HostUserID, &room.Status,
		&room.IsPrivate, &room.MaxPlayers, &room.CurrentPlayers, &room.Language,
		&configJSON, &room.AgoraChannelName, &room.AgoraAppID, &room.CreatedAt, &room.StartedAt,
	)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "room not found"})
		return
	}

	json.Unmarshal(configJSON, &room.Config)

	// Get players
	rows, err := h.db.PG.Query(ctx, `
		SELECT rp.id, rp.user_id, rp.is_ready, rp.is_host, rp.seat_position, rp.joined_at,
			u.username, u.avatar_url
		FROM room_players rp
		JOIN users u ON rp.user_id = u.id
		WHERE rp.room_id = $1 AND rp.left_at IS NULL
		ORDER BY rp.seat_position
	`, roomID)
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var player models.RoomPlayer
			var user models.User
			var avatarURL sql.NullString
			rows.Scan(&player.ID, &player.UserID, &player.IsReady, &player.IsHost,
				&player.SeatPosition, &player.JoinedAt, &user.Username, &avatarURL)
			if avatarURL.Valid {
				user.AvatarURL = &avatarURL.String
			}
			user.ID = player.UserID
			player.User = &user
			room.Players = append(room.Players, player)
		}
	}

	c.JSON(http.StatusOK, room)
}

// JoinRoom allows a player to join a room
func (h *Handler) JoinRoom(c *gin.Context) {
	userID, _ := c.Get("user_id")

	var req models.JoinRoomRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		log.Printf("❌ JoinRoom - JSON bind error: %v", err)
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	log.Printf("✓ JoinRoom request - UserID: %v, RoomCode: %s", userID, req.RoomCode)

	ctx := context.Background()

	// Get room info
	var roomID uuid.UUID
	var currentPlayers, maxPlayers int
	var status string

	err := h.db.PG.QueryRow(ctx, `
		SELECT id, current_players, max_players, status
		FROM rooms WHERE room_code = $1
	`, req.RoomCode).Scan(&roomID, &currentPlayers, &maxPlayers, &status)

	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "room not found"})
		return
	}

	if status != "waiting" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "room is not accepting players"})
		return
	}

	if currentPlayers >= maxPlayers {
		c.JSON(http.StatusBadRequest, gin.H{"error": "room is full"})
		return
	}

	// Check if user is already in ANY active room
	var existingRoomCount int
	err = h.db.PG.QueryRow(ctx, `
		SELECT COUNT(*) FROM room_players rp
		JOIN rooms r ON rp.room_id = r.id
		WHERE rp.user_id = $1 
		  AND rp.left_at IS NULL 
		  AND r.status IN ('waiting', 'in_progress')
	`, userID).Scan(&existingRoomCount)

	if err != nil && err != sql.ErrNoRows {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to verify room status"})
		return
	}

	if existingRoomCount > 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "you are already in an active room. Please leave it before joining another"})
		return
	}

	// Add player to room
	_, err = h.db.PG.Exec(ctx, `
		INSERT INTO room_players (id, room_id, user_id, is_ready, is_host, seat_position)
		VALUES ($1, $2, $3, $4, $5, $6)
	`, uuid.New(), roomID, userID, false, false, currentPlayers)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to join room"})
		return
	}

	// Update current players count
	h.db.PG.Exec(ctx, `
		UPDATE rooms SET current_players = current_players + 1 WHERE id = $1
	`, roomID)

	// Track room activity (player joined)
	if h.lifecycleManager != nil {
		h.lifecycleManager.UpdateActivity(ctx, roomID)
	}

	// Broadcast room update
	h.wsHub.BroadcastToRoom(roomID, models.WSTypeRoomUpdate, gin.H{
		"action":  "player_joined",
		"user_id": userID,
	})

	c.JSON(http.StatusOK, gin.H{"room_id": roomID})
}

// LeaveRoom removes a player from a room
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
		UPDATE room_players SET left_at = $1 WHERE room_id = $2 AND user_id = $3 AND left_at IS NULL
	`, time.Now(), roomID, userID)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to leave room"})
		return
	}

	// Update current players count
	h.db.PG.Exec(ctx, `
		UPDATE rooms SET current_players = current_players - 1 WHERE id = $1
	`, roomID)

	// Broadcast room update
	h.wsHub.BroadcastToRoom(roomID, models.WSTypeRoomUpdate, gin.H{
		"action":  "player_left",
		"user_id": userID,
	})

	c.JSON(http.StatusOK, gin.H{"message": "left room"})
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

	var req struct {
		Ready bool `json:"ready"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	ctx := context.Background()

	_, err = h.db.PG.Exec(ctx, `
		UPDATE room_players SET is_ready = $1 WHERE room_id = $2 AND user_id = $3 AND left_at IS NULL
	`, req.Ready, roomID, userID)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update ready status"})
		return
	}

	// Track room activity (ready status changed)
	if h.lifecycleManager != nil {
		h.lifecycleManager.UpdateActivity(ctx, roomID)
	}

	// Broadcast room update
	h.wsHub.BroadcastToRoom(roomID, models.WSTypeRoomUpdate, gin.H{
		"action":  "player_ready",
		"user_id": userID,
		"ready":   req.Ready,
	})

	c.JSON(http.StatusOK, gin.H{"ready": req.Ready})
}

// KickPlayer removes a player from the room (host only)
func (h *Handler) KickPlayer(c *gin.Context) {
	userID, _ := c.Get("user_id")
	roomIDStr := c.Param("roomId")

	roomID, err := uuid.Parse(roomIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid room ID"})
		return
	}

	var req struct {
		PlayerID uuid.UUID `json:"player_id"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	ctx := context.Background()

	// Verify user is host
	var hostUserID uuid.UUID
	err = h.db.PG.QueryRow(ctx, `
		SELECT host_user_id FROM rooms WHERE id = $1
	`, roomID).Scan(&hostUserID)

	if err != nil || hostUserID != userID.(uuid.UUID) {
		c.JSON(http.StatusForbidden, gin.H{"error": "only host can kick players"})
		return
	}

	// Cannot kick yourself
	if req.PlayerID == userID.(uuid.UUID) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "cannot kick yourself"})
		return
	}

	// Remove player
	_, err = h.db.PG.Exec(ctx, `
		UPDATE room_players SET left_at = $1 WHERE room_id = $2 AND user_id = $3 AND left_at IS NULL
	`, time.Now(), roomID, req.PlayerID)

	h.db.PG.Exec(ctx, `
		UPDATE rooms SET current_players = current_players - 1 WHERE id = $1
	`, roomID)

	// Broadcast kick
	h.wsHub.BroadcastToRoom(roomID, models.WSTypeRoomUpdate, gin.H{
		"action":  "player_kicked",
		"user_id": req.PlayerID,
	})

	c.JSON(http.StatusOK, gin.H{"message": "player kicked"})
}

// ExtendRoomTimeout allows host to extend the room timeout
func (h *Handler) ExtendRoomTimeout(c *gin.Context) {
	userID, _ := c.Get("user_id")
	roomIDStr := c.Param("roomId")

	roomID, err := uuid.Parse(roomIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid room ID"})
		return
	}

	ctx := context.Background()

	if h.lifecycleManager == nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "lifecycle manager not available"})
		return
	}

	// Extend the timeout
	err = h.lifecycleManager.ExtendTimeout(ctx, roomID, userID.(uuid.UUID))
	if err != nil {
		if err.Error() == "user is not the room host" {
			c.JSON(http.StatusForbidden, gin.H{"error": "only the host can extend room timeout"})
		} else if err.Error() == "room is not in waiting status" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "can only extend timeout for waiting rooms"})
		} else {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to extend timeout"})
		}
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message":          "room timeout extended successfully",
		"extended_minutes": 20,
	})
}

// StartGame starts the game in a room
func (h *Handler) StartGame(c *gin.Context) {
	userID, _ := c.Get("user_id")
	roomIDStr := c.Param("roomId")

	roomID, err := uuid.Parse(roomIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid room ID"})
		return
	}

	// Verify user is host
	ctx := context.Background()
	var hostUserID uuid.UUID
	err = h.db.PG.QueryRow(ctx, `
		SELECT host_user_id FROM rooms WHERE id = $1
	`, roomID).Scan(&hostUserID)

	if err != nil || hostUserID != userID.(uuid.UUID) {
		c.JSON(http.StatusForbidden, gin.H{"error": "only host can start game"})
		return
	}

	// Start the game
	session, err := h.gameEngine.StartGame(ctx, roomID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Get players with their roles to send private role info
	fullSession, err := h.gameEngine.GetGameState(ctx, session.ID)
	if err != nil {
		log.Printf("⚠️  Failed to get game state after start: %v", err)
		// Still return success since game was created
		c.JSON(http.StatusOK, gin.H{"session_id": session.ID})
		return
	}

	// Broadcast game start to all players
	h.wsHub.BroadcastToRoom(roomID, models.WSTypeGameUpdate, gin.H{
		"action":     "game_started",
		"session_id": session.ID,
		"phase":      session.CurrentPhase,
	})

	// Send each player their role privately
	if fullSession.Players != nil {
		for _, player := range fullSession.Players {
			h.wsHub.SendToUser(roomID, player.UserID, models.WSTypeRoleReveal, gin.H{
				"your_role": player.Role,
				"your_team": player.Team,
			})
		}
	}

	c.JSON(http.StatusOK, gin.H{"session_id": session.ID})
}

// ============================================================================
// GAME HANDLERS
// ============================================================================

// GetGameState returns the current game state
func (h *Handler) GetGameState(c *gin.Context) {
	userID, _ := c.Get("user_id")
	sessionIDStr := c.Param("sessionId")

	sessionID, err := uuid.Parse(sessionIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid session ID"})
		return
	}

	ctx := context.Background()
	session, err := h.gameEngine.GetGameState(ctx, sessionID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "game not found"})
		return
	}

	// Filter sensitive information based on requesting player
	filteredSession := filterSessionForPlayer(session, userID.(uuid.UUID))

	c.JSON(http.StatusOK, filteredSession)
}

// PerformAction handles player actions during the game
func (h *Handler) PerformAction(c *gin.Context) {
	userID, _ := c.Get("user_id")
	sessionIDStr := c.Param("sessionId")

	sessionID, err := uuid.Parse(sessionIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid session ID"})
		return
	}

	var req models.GameActionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	ctx := context.Background()
	err = h.gameEngine.ProcessAction(ctx, sessionID, userID.(uuid.UUID), req)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Get room ID for broadcast
	session, _ := h.gameEngine.GetGameState(ctx, sessionID)
	roomID := session.RoomID

	// Broadcast action performed
	h.wsHub.BroadcastToRoom(roomID, models.WSTypeGameUpdate, gin.H{
		"action":     req.ActionType,
		"session_id": sessionID,
		"phase":      session.CurrentPhase,
	})

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "Action performed successfully",
	})
}

// GetGameHistory returns the history of events for a game
func (h *Handler) GetGameHistory(c *gin.Context) {
	sessionIDStr := c.Param("sessionId")

	sessionID, err := uuid.Parse(sessionIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid session ID"})
		return
	}

	ctx := context.Background()

	rows, err := h.db.PG.Query(ctx, `
		SELECT id, phase_number, event_type, event_data, is_public, created_at
		FROM game_events
		WHERE session_id = $1 AND is_public = true
		ORDER BY created_at ASC
	`, sessionID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get history"})
		return
	}
	defer rows.Close()

	var events []models.GameEvent
	for rows.Next() {
		var event models.GameEvent
		var eventDataJSON json.RawMessage
		rows.Scan(&event.ID, &event.PhaseNumber, &event.EventType, &eventDataJSON, &event.IsPublic, &event.CreatedAt)
		json.Unmarshal(eventDataJSON, &event.EventData)
		event.SessionID = sessionID
		events = append(events, event)
	}

	c.JSON(http.StatusOK, events)
}

// ============================================================================
// AGORA TOKEN HANDLERS
// ============================================================================

// GetAgoraToken generates an Agora RTC token
func (h *Handler) GetAgoraToken(c *gin.Context) {
	var req models.AgoraTokenRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		log.Printf("❌ GetAgoraToken - JSON bind error: %v", err)
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// If UID is 0, Agora will auto-assign one
	if req.UID == 0 {
		log.Printf("✓ GetAgoraToken request - Channel: %s, UID: 0 (auto-assign)", req.ChannelName)
	} else {
		log.Printf("✓ GetAgoraToken request - Channel: %s, UID: %d", req.ChannelName, req.UID)
	}

	// Generate token
	token, err := h.agoraService.GenerateRTCToken(req.ChannelName, req.UID, rtctokenbuilder.RolePublisher)
	if err != nil {
		log.Printf("❌ GetAgoraToken - Token generation error: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate token"})
		return
	}

	response := models.AgoraTokenResponse{
		Token:       token,
		ChannelName: req.ChannelName,
		UID:         req.UID,
		ExpiresAt:   time.Now().Unix() + int64(h.agoraService.GetTokenExpiry()),
	}

	log.Printf("✓ GetAgoraToken - Token generated successfully for channel: %s", req.ChannelName)
	c.JSON(http.StatusOK, response)
}

// ============================================================================
// WEBSOCKET HANDLER
// ============================================================================

// HandleWebSocket upgrades HTTP to WebSocket
func (h *Handler) HandleWebSocket(c *gin.Context) {
	log.Printf("✓ WebSocket - Connection attempt from %s", c.ClientIP())

	// For WebSocket, try to get user_id from middleware first, then from token query param
	userID, exists := c.Get("user_id")
	if !exists {
		// Try to authenticate from query parameter token (for WebSocket compatibility)
		tokenString := c.Query("token")
		log.Printf("✓ WebSocket - Token from query: %s...", tokenString[:20])
		if tokenString == "" {
			log.Printf("❌ WebSocket - No token provided")
			c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
			return
		}

		// Validate token inline (WebSocket can't use Authorization header easily)
		cfg, _ := config.Load()
		token, err := jwt.Parse(tokenString, func(token *jwt.Token) (interface{}, error) {
			if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
				return nil, jwt.ErrSignatureInvalid
			}
			return []byte(cfg.JWT.Secret), nil
		})

		if err != nil || !token.Valid {
			log.Printf("❌ WebSocket - Invalid token: %v, valid: %v", err, token.Valid)
			c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
			return
		}

		claims, ok := token.Claims.(jwt.MapClaims)
		if !ok {
			log.Printf("❌ WebSocket - Failed to cast claims to MapClaims")
			c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid token claims"})
			return
		}

		log.Printf("✓ WebSocket - Token claims: %+v", claims)

		userIDStr, ok := claims["user_id"].(string)
		if !ok {
			log.Printf("❌ WebSocket - user_id not found or not string in claims: %+v", claims)
			c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid user ID in token"})
			return
		}

		userID, err = uuid.Parse(userIDStr)
		if err != nil {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid user ID format"})
			return
		}
	}

	roomIDStr := c.Query("room_id")
	roomID, err := uuid.Parse(roomIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid room ID"})
		return
	}

	conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		return
	}

	client := ws.NewClient(h.wsHub, conn, userID.(uuid.UUID), roomID)
	client.Register()

	go client.WritePump()
	go client.ReadPump()
}

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

func generateRoomCode() string {
	const charset = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // Removed confusing chars
	rng := rand.New(rand.NewSource(time.Now().UnixNano()))
	code := make([]byte, 6)
	for i := range code {
		code[i] = charset[rng.Intn(len(charset))]
	}
	return string(code)
}

// filterSessionForPlayer removes sensitive information based on player perspective
func filterSessionForPlayer(session *models.GameSession, userID uuid.UUID) *models.GameSession {
	// Create a copy of the session
	filtered := *session

	// Clear sensitive state info
	filtered.State.WerewolfVotes = nil
	filtered.State.PoisonedPlayer = nil
	filtered.State.HealedPlayer = nil
	filtered.State.ProtectedPlayer = nil

	// Find requesting player
	var requestingPlayer *models.GamePlayer
	for i := range session.Players {
		if session.Players[i].UserID == userID {
			requestingPlayer = &session.Players[i]
			break
		}
	}

	// Filter player info based on what requesting player should see
	filteredPlayers := make([]models.GamePlayer, len(session.Players))
	for i, p := range session.Players {
		filteredPlayers[i] = models.GamePlayer{
			ID:                  p.ID,
			SessionID:           p.SessionID,
			UserID:              p.UserID,
			IsAlive:             p.IsAlive,
			DiedAtPhase:         p.DiedAtPhase,
			DeathReason:         p.DeathReason,
			CurrentVoiceChannel: p.CurrentVoiceChannel,
			SeatPosition:        p.SeatPosition,
			User:                p.User,
		}

		// Show role if:
		// - It's the requesting player's own role
		// - The player is dead (role revealed)
		// - Requesting player is werewolf and target is werewolf
		// - The player is a lover of requesting player
		showRole := p.UserID == userID ||
			!p.IsAlive ||
			(requestingPlayer != nil && requestingPlayer.Role == models.RoleWerewolf && p.Role == models.RoleWerewolf) ||
			(requestingPlayer != nil && requestingPlayer.LoverID != nil && *requestingPlayer.LoverID == p.ID)

		if showRole {
			filteredPlayers[i].Role = p.Role
			filteredPlayers[i].Team = p.Team
		}

		// Show lover if requesting player is the lover
		if requestingPlayer != nil && requestingPlayer.LoverID != nil && *requestingPlayer.LoverID == p.ID {
			filteredPlayers[i].LoverID = p.LoverID
		}
	}
	filtered.Players = filteredPlayers

	return &filtered
}
