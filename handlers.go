package api

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/gorilla/websocket"
	"github.com/yourusername/werewolf-voice/internal/agora"
	"github.com/yourusername/werewolf-voice/internal/database"
	"github.com/yourusername/werewolf-voice/internal/game"
	"github.com/yourusername/werewolf-voice/internal/models"
	ws "github.com/yourusername/werewolf-voice/internal/websocket"
	rtctokenbuilder "github.com/AgoraIO-Community/go-tokenbuilder/rtctokenbuilder"
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		return true // Configure properly in production
	},
}

type Handler struct {
	db          *database.Database
	gameEngine  *game.Engine
	agoraService *agora.Service
	wsHub       *ws.Hub
}

func NewHandler(db *database.Database, gameEngine *game.Engine, agoraService *agora.Service, wsHub *ws.Hub) *Handler {
	return &Handler{
		db:          db,
		gameEngine:  gameEngine,
		agoraService: agoraService,
		wsHub:       wsHub,
	}
}

// ============================================================================
// ROOM HANDLERS
// ============================================================================

// CreateRoom creates a new game room
func (h *Handler) CreateRoom(c *gin.Context) {
	userID, _ := c.Get("user_id")
	
	var req models.CreateRoomRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
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
	ctx := context.Background()
	_, err := h.db.PG.Exec(ctx, `
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
	_, err = h.db.PG.Exec(ctx, `
		INSERT INTO room_players (id, room_id, user_id, is_ready, is_host, seat_position)
		VALUES ($1, $2, $3, $4, $5, $6)
	`, uuid.New(), roomID, userID, false, true, 0)
	
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to add host to room"})
		return
	}

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
		CreatedAt:        time.Now(),
	}

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
		room.Host = &host
		rooms = append(rooms, room)
	}

	c.JSON(http.StatusOK, rooms)
}

// JoinRoom allows a player to join a room
func (h *Handler) JoinRoom(c *gin.Context) {
	userID, _ := c.Get("user_id")
	
	var req models.JoinRoomRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

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

	// Add player to room
	_, err = h.db.PG.Exec(ctx, `
		INSERT INTO room_players (id, room_id, user_id, is_ready, is_host, seat_position)
		VALUES ($1, $2, $3, $4, $5, $6)
		ON CONFLICT (room_id, user_id) DO NOTHING
	`, uuid.New(), roomID, userID, false, false, currentPlayers)
	
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to join room"})
		return
	}

	// Update current players count
	_, err = h.db.PG.Exec(ctx, `
		UPDATE rooms SET current_players = current_players + 1 WHERE id = $1
	`, roomID)

	// Broadcast room update
	h.wsHub.BroadcastToRoom(roomID, models.WSTypeRoomUpdate, gin.H{
		"action": "player_joined",
		"user_id": userID,
	})

	c.JSON(http.StatusOK, gin.H{"room_id": roomID})
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

	// Broadcast game start
	h.wsHub.BroadcastToRoom(roomID, models.WSTypeGameUpdate, gin.H{
		"action": "game_started",
		"session": session,
	})

	c.JSON(http.StatusOK, session)
}

// ============================================================================
// GAME HANDLERS
// ============================================================================

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
	if err := h.gameEngine.ProcessAction(ctx, sessionID, userID.(uuid.UUID), req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Get room ID for broadcast
	var roomID uuid.UUID
	h.db.PG.QueryRow(ctx, `
		SELECT room_id FROM game_sessions WHERE id = $1
	`, sessionID).Scan(&roomID)

	// Broadcast action (without revealing private info)
	h.wsHub.BroadcastToRoomExcept(roomID, userID.(uuid.UUID), models.WSTypePlayerAction, gin.H{
		"action_type": req.ActionType,
		"player_id": userID,
	})

	c.JSON(http.StatusOK, gin.H{"success": true})
}

// ============================================================================
// AGORA TOKEN HANDLERS
// ============================================================================

// GetAgoraToken generates an Agora RTC token
func (h *Handler) GetAgoraToken(c *gin.Context) {
	userID, _ := c.Get("user_id")
	
	var req models.AgoraTokenRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Generate token
	token, err := h.agoraService.GenerateRTCToken(req.ChannelName, req.UID, rtctokenbuilder.RolePublisher)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate token"})
		return
	}

	response := models.AgoraTokenResponse{
		Token:       token,
		ChannelName: req.ChannelName,
		UID:         req.UID,
		ExpiresAt:   time.Now().Unix() + int64(h.agoraService.GetAppID()),
	}

	c.JSON(http.StatusOK, response)
}

// ============================================================================
// WEBSOCKET HANDLER
// ============================================================================

// HandleWebSocket upgrades HTTP to WebSocket
func (h *Handler) HandleWebSocket(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
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
	h.wsHub.register <- client

	go client.WritePump()
	go client.ReadPump()
}

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

func generateRoomCode() string {
	const charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	code := make([]byte, 6)
	for i := range code {
		code[i] = charset[time.Now().UnixNano()%int64(len(charset))]
		time.Sleep(1 * time.Nanosecond)
	}
	return string(code)
}
