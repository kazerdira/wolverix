package websocket

import (
	"context"
	"encoding/json"
	"log"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/gorilla/websocket"
	"github.com/kazerdira/wolverix/backend/internal/models"
)

const (
	writeWait      = 10 * time.Second
	pongWait       = 60 * time.Second
	pingPeriod     = (pongWait * 9) / 10
	maxMessageSize = 8192
)

// Hub maintains active websocket connections and broadcasts messages
type Hub struct {
	clients    map[*Client]bool
	rooms      map[uuid.UUID]map[*Client]bool
	broadcast  chan *BroadcastMessage
	register   chan *Client
	unregister chan *Client
	mu         sync.RWMutex
}

// BroadcastMessage represents a message to be broadcast
type BroadcastMessage struct {
	RoomID    uuid.UUID
	Message   models.WSMessage
	ToPlayers []uuid.UUID // If set, only send to these players
	Exclude   *uuid.UUID  // Optional: exclude this user from broadcast
}

// NewHub creates a new WebSocket hub
func NewHub() *Hub {
	return &Hub{
		clients:    make(map[*Client]bool),
		rooms:      make(map[uuid.UUID]map[*Client]bool),
		broadcast:  make(chan *BroadcastMessage, 256),
		register:   make(chan *Client),
		unregister: make(chan *Client),
	}
}

// Run starts the hub's main loop
func (h *Hub) Run(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			log.Println("Hub shutting down")
			return
		case client := <-h.register:
			h.registerClient(client)
		case client := <-h.unregister:
			h.unregisterClient(client)
		case message := <-h.broadcast:
			h.broadcastToRoom(message)
		}
	}
}

func (h *Hub) registerClient(client *Client) {
	h.mu.Lock()
	defer h.mu.Unlock()

	h.clients[client] = true

	// Add to room
	if client.RoomID != uuid.Nil {
		if h.rooms[client.RoomID] == nil {
			h.rooms[client.RoomID] = make(map[*Client]bool)
		}
		h.rooms[client.RoomID][client] = true
		log.Printf("Client %s joined room %s", client.UserID, client.RoomID)
	}
}

func (h *Hub) unregisterClient(client *Client) {
	h.mu.Lock()
	defer h.mu.Unlock()

	if _, ok := h.clients[client]; ok {
		delete(h.clients, client)
		close(client.send)

		// Remove from room
		if client.RoomID != uuid.Nil {
			if clients, ok := h.rooms[client.RoomID]; ok {
				delete(clients, client)
				if len(clients) == 0 {
					delete(h.rooms, client.RoomID)
				}
			}
		}
		log.Printf("Client %s disconnected from room %s", client.UserID, client.RoomID)
	}
}

func (h *Hub) broadcastToRoom(message *BroadcastMessage) {
	h.mu.RLock()
	defer h.mu.RUnlock()

	clients, ok := h.rooms[message.RoomID]
	if !ok {
		log.Printf("Room %s has no connected clients", message.RoomID)
		return
	}

	messageJSON, err := json.Marshal(message.Message)
	if err != nil {
		log.Printf("Error marshaling message: %v", err)
		return
	}

	// Create a set of target players if specified
	targetSet := make(map[uuid.UUID]bool)
	if len(message.ToPlayers) > 0 {
		for _, id := range message.ToPlayers {
			targetSet[id] = true
		}
	}

	sentCount := 0
	for client := range clients {
		// Skip excluded user if specified
		if message.Exclude != nil && client.UserID == *message.Exclude {
			continue
		}

		// If specific players are targeted, only send to them
		if len(targetSet) > 0 && !targetSet[client.UserID] {
			continue
		}

		select {
		case client.send <- messageJSON:
			sentCount++
		default:
			// Client send buffer is full, disconnect
			close(client.send)
			delete(h.clients, client)
			delete(clients, client)
		}
	}

	log.Printf("Sent %s message to %d clients in room %s", message.Message.Type, sentCount, message.RoomID)
}

// BroadcastToRoom sends a message to all clients in a room
func (h *Hub) BroadcastToRoom(roomID uuid.UUID, msgType models.WSMessageType, payload interface{}) {
	message := models.WSMessage{
		Type:      msgType,
		Payload:   payload,
		Timestamp: time.Now(),
	}

	log.Printf("Broadcasting to room %s: type=%s payload=%+v", roomID, msgType, payload)

	h.broadcast <- &BroadcastMessage{
		RoomID:  roomID,
		Message: message,
	}
}

// BroadcastToPlayers sends a message to specific players in a room
func (h *Hub) BroadcastToPlayers(roomID uuid.UUID, playerIDs []uuid.UUID, msgType models.WSMessageType, payload interface{}) {
	message := models.WSMessage{
		Type:      msgType,
		Payload:   payload,
		Timestamp: time.Now(),
	}

	h.broadcast <- &BroadcastMessage{
		RoomID:    roomID,
		Message:   message,
		ToPlayers: playerIDs,
	}
}

// BroadcastToRoomExcept sends a message to all clients in a room except one user
func (h *Hub) BroadcastToRoomExcept(roomID, excludeUserID uuid.UUID, msgType models.WSMessageType, payload interface{}) {
	message := models.WSMessage{
		Type:      msgType,
		Payload:   payload,
		Timestamp: time.Now(),
	}

	h.broadcast <- &BroadcastMessage{
		RoomID:  roomID,
		Message: message,
		Exclude: &excludeUserID,
	}
}

// SendToUser sends a message to a specific user
func (h *Hub) SendToUser(roomID, userID uuid.UUID, msgType models.WSMessageType, payload interface{}) {
	h.BroadcastToPlayers(roomID, []uuid.UUID{userID}, msgType, payload)
}

// GetRoomClientCount returns the number of clients in a room
func (h *Hub) GetRoomClientCount(roomID uuid.UUID) int {
	h.mu.RLock()
	defer h.mu.RUnlock()

	if clients, ok := h.rooms[roomID]; ok {
		return len(clients)
	}
	return 0
}

// GetRoomUserIDs returns all user IDs in a room
func (h *Hub) GetRoomUserIDs(roomID uuid.UUID) []uuid.UUID {
	h.mu.RLock()
	defer h.mu.RUnlock()

	var userIDs []uuid.UUID
	if clients, ok := h.rooms[roomID]; ok {
		for client := range clients {
			userIDs = append(userIDs, client.UserID)
		}
	}
	return userIDs
}

// Client represents a websocket client connection
type Client struct {
	hub    *Hub
	conn   *websocket.Conn
	send   chan []byte
	UserID uuid.UUID
	RoomID uuid.UUID
}

// NewClient creates a new websocket client
func NewClient(hub *Hub, conn *websocket.Conn, userID, roomID uuid.UUID) *Client {
	return &Client{
		hub:    hub,
		conn:   conn,
		send:   make(chan []byte, 256),
		UserID: userID,
		RoomID: roomID,
	}
}

// Register registers the client with the hub
func (c *Client) Register() {
	c.hub.register <- c
}

// ReadPump pumps messages from the websocket connection to the hub
func (c *Client) ReadPump() {
	defer func() {
		c.hub.unregister <- c
		c.conn.Close()
	}()

	c.conn.SetReadLimit(maxMessageSize)
	c.conn.SetReadDeadline(time.Now().Add(pongWait))
	c.conn.SetPongHandler(func(string) error {
		c.conn.SetReadDeadline(time.Now().Add(pongWait))
		return nil
	})

	for {
		_, message, err := c.conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("WebSocket error: %v", err)
			}
			break
		}

		// Parse incoming message
		var wsMsg models.WSMessage
		if err := json.Unmarshal(message, &wsMsg); err != nil {
			log.Printf("Error parsing message: %v", err)
			continue
		}

		// Handle ping/pong
		if wsMsg.Type == models.WSTypePing {
			pongMsg := models.WSMessage{
				Type:      models.WSTypePong,
				Timestamp: time.Now(),
			}
			if data, err := json.Marshal(pongMsg); err == nil {
				c.send <- data
			}
			continue
		}

		// Client-to-server messages are handled in the API layer
		// This is just for connection maintenance
	}
}

// WritePump pumps messages from the hub to the websocket connection
func (c *Client) WritePump() {
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		c.conn.Close()
	}()

	for {
		select {
		case message, ok := <-c.send:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok {
				// Hub closed the channel
				c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}

			w, err := c.conn.NextWriter(websocket.TextMessage)
			if err != nil {
				return
			}
			w.Write(message)

			// Add queued messages to current websocket message
			n := len(c.send)
			for i := 0; i < n; i++ {
				w.Write([]byte{'\n'})
				w.Write(<-c.send)
			}

			if err := w.Close(); err != nil {
				return
			}
		case <-ticker.C:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}
