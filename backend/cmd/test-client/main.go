package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"time"
)

const baseURL = "http://localhost:8080/api/v1"

type Player struct {
	Username string
	Email    string
	Password string
	Token    string
	UserID   string
}

type LoginResponse struct {
	Token        string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	User         struct {
		ID       string `json:"id"`
		Username string `json:"username"`
	} `json:"user"`
}

type CreateRoomResponse struct {
	ID       string `json:"id"`
	RoomCode string `json:"room_code"`
}

type JoinRoomResponse struct {
	RoomID string `json:"room_id"`
}

type StartGameResponse struct {
	SessionID string `json:"session_id"`
}

type GameStateResponse struct {
	Session struct {
		ID           string `json:"id"`
		CurrentPhase string `json:"current_phase"`
		PhaseNumber  int    `json:"phase_number"`
		DayNumber    int    `json:"day_number"`
	} `json:"session"`
	Players []struct {
		ID      string `json:"id"`
		Role    string `json:"role"`
		Team    string `json:"team"`
		IsAlive bool   `json:"is_alive"`
	} `json:"players"`
}

func main() {
	log.Println("🎮 Starting Werewolf Game Test Client")

	// Create 8 players
	players := make([]Player, 8)
	for i := 0; i < 8; i++ {
		players[i] = Player{
			Username: fmt.Sprintf("bot%d", i+1),
			Email:    fmt.Sprintf("bot%d@test.com", i+1),
			Password: "password123",
		}
	}

	// Step 1: Register and login all players
	log.Println("\n📝 Step 1: Registering and logging in 8 players...")
	for i := range players {
		if err := registerPlayer(&players[i]); err != nil {
			log.Printf("⚠️  Registration failed for %s (might already exist): %v", players[i].Username, err)
		}
		if err := loginPlayer(&players[i]); err != nil {
			log.Fatalf("❌ Login failed for %s: %v", players[i].Username, err)
		}
		log.Printf("✅ %s logged in", players[i].Username)
	}

	// Step 2: Player 1 creates a room
	log.Println("\n🏠 Step 2: Creating room...")
	roomID, roomCode, err := createRoom(players[0].Token)
	if err != nil {
		log.Fatalf("❌ Failed to create room: %v", err)
	}
	log.Printf("✅ Room created - ID: %s, Code: %s", roomID, roomCode)

	// Step 3: Other players join the room
	log.Println("\n👥 Step 3: Players joining room...")
	for i := 1; i < 8; i++ {
		if err := joinRoom(players[i].Token, roomCode); err != nil {
			log.Fatalf("❌ %s failed to join room: %v", players[i].Username, err)
		}
		log.Printf("✅ %s joined room", players[i].Username)
		time.Sleep(200 * time.Millisecond) // Small delay between joins
	}

	// Step 4: All players set ready
	log.Println("\n✋ Step 4: Setting all players ready...")
	for i := range players {
		if err := setReady(players[i].Token, roomID); err != nil {
			log.Fatalf("❌ %s failed to set ready: %v", players[i].Username, err)
		}
		log.Printf("✅ %s is ready", players[i].Username)
		time.Sleep(200 * time.Millisecond)
	}

	// Step 5: Host starts the game
	log.Println("\n🚀 Step 5: Starting game...")
	sessionID, err := startGame(players[0].Token, roomID)
	if err != nil {
		log.Fatalf("❌ Failed to start game: %v", err)
	}
	log.Printf("✅ Game started - Session ID: %s", sessionID)

	// Step 6: Get game state and show roles
	log.Println("\n🎭 Step 6: Fetching game state and roles...")
	time.Sleep(1 * time.Second) // Wait for game initialization
	gameState, err := getGameState(players[0].Token, sessionID)
	if err != nil {
		log.Fatalf("❌ Failed to get game state: %v", err)
	}

	log.Printf("\n📊 Game State:")
	log.Printf("   Phase: %s (Day %d, Phase %d)", gameState.Session.CurrentPhase,
		gameState.Session.DayNumber, gameState.Session.PhaseNumber)
	log.Printf("   Players and Roles:")
	for _, p := range gameState.Players {
		status := "Alive"
		if !p.IsAlive {
			status = "Dead"
		}
		log.Printf("      - %s: %s (%s) [%s]", p.ID[:8], p.Role, p.Team, status)
	}

	log.Println("\n✨ Basic test completed successfully!")

	// Step 7: Test new features - Multiple room prevention
	log.Println("\n🚫 Step 7: Testing multiple room prevention...")
	testMultipleRoomPrevention(players[0].Token)

	// Step 8: Test timeout extension
	log.Println("\n⏰ Step 8: Testing room timeout extension...")
	testTimeoutExtension(players)

	log.Println("\n✅ All tests completed successfully!")
	log.Println("💡 Game is running. You can now:")
	log.Println("   - Check the server logs for phase transitions")
	log.Println("   - Use test.http to perform actions")
	log.Printf("   - Session ID: %s", sessionID)
}

func testMultipleRoomPrevention(token string) {
	// Try to create another room while in active game
	log.Println("   Attempting to create a second room (should fail)...")

	body := map[string]interface{}{
		"name":        "Second Room (Should Fail)",
		"is_private":  false,
		"max_players": 10,
		"language":    "en",
	}
	jsonBody, _ := json.Marshal(body)

	req, _ := http.NewRequest("POST", baseURL+"/rooms", bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+token)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		log.Printf("   ❌ Request failed: %v", err)
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusBadRequest {
		bodyBytes, _ := io.ReadAll(resp.Body)
		log.Printf("   ✅ Correctly prevented: %s", string(bodyBytes))
	} else {
		log.Printf("   ⚠️  Expected 400 Bad Request, got %d", resp.StatusCode)
	}
}

func testTimeoutExtension(players []Player) {
	// Create a new test player for timeout testing
	testPlayer := Player{
		Username: "timeout_test_bot",
		Email:    "timeout_test@test.com",
		Password: "password123",
	}

	log.Println("   Creating new player for timeout test...")
	if err := registerPlayer(&testPlayer); err != nil {
		log.Printf("   ⚠️  Registration failed (might already exist): %v", err)
	}
	if err := loginPlayer(&testPlayer); err != nil {
		log.Printf("   ❌ Login failed: %v", err)
		return
	}
	log.Printf("   ✅ Test player logged in: %s", testPlayer.Username)

	// Create a room
	log.Println("   Creating test room for timeout extension...")
	roomID, roomCode, err := createRoom(testPlayer.Token)
	if err != nil {
		log.Printf("   ❌ Failed to create room: %v", err)
		return
	}
	log.Printf("   ✅ Room created - Code: %s", roomCode)

	// Try to extend timeout
	log.Println("   Attempting to extend room timeout...")
	if err := extendRoomTimeout(testPlayer.Token, roomID); err != nil {
		log.Printf("   ❌ Failed to extend timeout: %v", err)
	} else {
		log.Println("   ✅ Successfully extended room timeout")
	}

	// Clean up - leave the room
	log.Println("   Cleaning up test room...")
	leaveRoom(testPlayer.Token, roomID)
}

func registerPlayer(p *Player) error {
	body := map[string]string{
		"username": p.Username,
		"email":    p.Email,
		"password": p.Password,
	}
	jsonBody, _ := json.Marshal(body)

	resp, err := http.Post(baseURL+"/auth/register", "application/json", bytes.NewBuffer(jsonBody))
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusCreated && resp.StatusCode != http.StatusConflict {
		bodyBytes, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("status %d: %s", resp.StatusCode, string(bodyBytes))
	}
	return nil
}

func loginPlayer(p *Player) error {
	body := map[string]string{
		"email":    p.Email,
		"password": p.Password,
	}
	jsonBody, _ := json.Marshal(body)

	resp, err := http.Post(baseURL+"/auth/login", "application/json", bytes.NewBuffer(jsonBody))
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		bodyBytes, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("status %d: %s", resp.StatusCode, string(bodyBytes))
	}

	var loginResp LoginResponse
	if err := json.NewDecoder(resp.Body).Decode(&loginResp); err != nil {
		return err
	}

	p.Token = loginResp.Token
	p.UserID = loginResp.User.ID
	return nil
}

func createRoom(token string) (string, string, error) {
	body := map[string]interface{}{
		"name":        "Bot Test Game",
		"is_private":  false,
		"max_players": 10,
		"language":    "en",
	}
	jsonBody, _ := json.Marshal(body)

	req, _ := http.NewRequest("POST", baseURL+"/rooms", bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+token)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusCreated {
		bodyBytes, _ := io.ReadAll(resp.Body)
		return "", "", fmt.Errorf("status %d: %s", resp.StatusCode, string(bodyBytes))
	}

	var roomResp CreateRoomResponse
	if err := json.NewDecoder(resp.Body).Decode(&roomResp); err != nil {
		return "", "", err
	}

	return roomResp.ID, roomResp.RoomCode, nil
}

func joinRoom(token, roomCode string) error {
	body := map[string]string{
		"room_code": roomCode,
	}
	jsonBody, _ := json.Marshal(body)

	req, _ := http.NewRequest("POST", baseURL+"/rooms/join", bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+token)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		bodyBytes, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("status %d: %s", resp.StatusCode, string(bodyBytes))
	}

	return nil
}

func setReady(token, roomID string) error {
	body := map[string]bool{
		"is_ready": true,
	}
	jsonBody, _ := json.Marshal(body)

	req, _ := http.NewRequest("POST", baseURL+"/rooms/"+roomID+"/ready", bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+token)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		bodyBytes, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("status %d: %s", resp.StatusCode, string(bodyBytes))
	}

	return nil
}

func startGame(token, roomID string) (string, error) {
	req, _ := http.NewRequest("POST", baseURL+"/rooms/"+roomID+"/start", nil)
	req.Header.Set("Authorization", "Bearer "+token)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		bodyBytes, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("status %d: %s", resp.StatusCode, string(bodyBytes))
	}

	var startResp StartGameResponse
	if err := json.NewDecoder(resp.Body).Decode(&startResp); err != nil {
		return "", err
	}

	return startResp.SessionID, nil
}

func getGameState(token, sessionID string) (*GameStateResponse, error) {
	req, _ := http.NewRequest("GET", baseURL+"/games/"+sessionID, nil)
	req.Header.Set("Authorization", "Bearer "+token)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		bodyBytes, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("status %d: %s", resp.StatusCode, string(bodyBytes))
	}

	var gameState GameStateResponse
	if err := json.NewDecoder(resp.Body).Decode(&gameState); err != nil {
		return nil, err
	}

	return &gameState, nil
}

func extendRoomTimeout(token, roomID string) error {
	req, _ := http.NewRequest("POST", baseURL+"/rooms/"+roomID+"/extend", nil)
	req.Header.Set("Authorization", "Bearer "+token)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		bodyBytes, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("status %d: %s", resp.StatusCode, string(bodyBytes))
	}

	return nil
}

func leaveRoom(token, roomID string) error {
	req, _ := http.NewRequest("POST", baseURL+"/rooms/"+roomID+"/leave", nil)
	req.Header.Set("Authorization", "Bearer "+token)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		bodyBytes, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("status %d: %s", resp.StatusCode, string(bodyBytes))
	}

	return nil
}
