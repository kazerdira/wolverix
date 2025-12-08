package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

const baseURL = "http://localhost:8080/api/v1"

type Player struct {
	Username string
	Email    string
	Token    string
	UserID   string
	Role     string
	IsAlive  bool
}

type GameStateResponse struct {
	ID           string `json:"id"`
	Status       string `json:"status"`
	CurrentPhase string `json:"current_phase"`
	DayNumber    int    `json:"day_number"`
	PhaseNumber  int    `json:"phase_number"`
	Winner       string `json:"winner,omitempty"`
	Players      []struct {
		UserID   string `json:"user_id"`
		Username string `json:"username"`
		Role     string `json:"role"`
		Team     string `json:"team"`
		IsAlive  bool   `json:"is_alive"`
	} `json:"players"`
}

func main() {
	fmt.Println("🎮 Starting Werewolf Game Logic Test")
	fmt.Println("=====================================\n")

	// Step 1: Create 8 players and start a game
	fmt.Println("📝 Step 1: Setting up game with 8 players...")
	players, sessionID, roomID := setupGame()
	if sessionID == "" {
		fmt.Println("❌ Failed to setup game")
		return
	}
	fmt.Printf("✅ Game started - Session: %s\n\n", sessionID)

	// Step 2: Get initial game state and identify roles
	fmt.Println("🎭 Step 2: Identifying player roles...")
	// Each player needs to check their own game state to see their role
	for i := range players {
		state := getGameState(players[i].Token, sessionID)
		assignRolesToPlayers(players, state)
		// Debug: print what this player sees
		for _, p := range state.Players {
			if p.UserID == players[i].UserID && p.Role != "" {
				fmt.Printf("  %s sees their role as: %s\n", players[i].Username, p.Role)
			}
		}
	}
	printPlayerRoles(players)

	// Step 3: Wait for night phase to start
	fmt.Println("\n🌙 Step 3: Waiting for first night phase...")
	waitForPhase(players[0].Token, sessionID, "night")
	gameState := getGameState(players[0].Token, sessionID)
	fmt.Printf("✅ Current phase: %s (Day %d)\n\n", gameState.CurrentPhase, gameState.DayNumber)

	// Step 4: Perform night actions
	fmt.Println("🔮 Step 4: Performing night actions...")
	performNightActions(players, sessionID, gameState)

	// Step 5: Wait for day phase
	fmt.Println("\n☀️  Step 5: Waiting for day discussion...")
	waitForPhase(players[0].Token, sessionID, "day_discussion")
	gameState = getGameState(players[0].Token, sessionID)
	fmt.Printf("✅ Current phase: %s\n", gameState.CurrentPhase)

	// Check if anyone died during night
	checkDeaths(gameState)

	// Step 6: Day voting
	fmt.Println("\n🗳️  Step 6: Waiting for voting phase...")
	waitForPhase(players[0].Token, sessionID, "day_voting")
	performDayVoting(players, sessionID, gameState)

	// Step 7: Check final state
	fmt.Println("\n🏁 Step 7: Final game state...")
	gameState = getGameState(players[0].Token, sessionID)
	fmt.Printf("Phase: %s (Day %d)\n", gameState.CurrentPhase, gameState.DayNumber)
	fmt.Printf("Status: %s\n", gameState.Status)
	if gameState.Winner != "" {
		fmt.Printf("🏆 Winner: %s\n", gameState.Winner)
	}

	fmt.Println("\n✨ Game logic test completed!")
	fmt.Printf("💡 Session ID: %s\n", sessionID)
	fmt.Printf("💡 Room ID: %s\n", roomID)
}

func setupGame() ([]Player, string, string) {
	players := make([]Player, 8)

	// Register and login all players
	for i := 0; i < 8; i++ {
		username := fmt.Sprintf("gametest%d_%d", i+1, time.Now().Unix())
		email := fmt.Sprintf("gametest%d_%d@example.com", i+1, time.Now().Unix())

		player := Player{
			Username: username,
			Email:    email,
		}

		// Register
		registerData := map[string]string{
			"username": username,
			"email":    email,
			"password": "password123",
		}
		resp := makeRequest("POST", "/auth/register", "", registerData)
		player.Token = resp["access_token"].(string)
		player.UserID = resp["user"].(map[string]interface{})["id"].(string)
		players[i] = player
	}

	// Create room with first player
	roomData := map[string]interface{}{
		"name":        "Game Logic Test",
		"max_players": 10,
		"is_private":  false,
	}
	roomResp := makeRequest("POST", "/rooms", players[0].Token, roomData)
	roomID := roomResp["id"].(string)
	roomCode := roomResp["room_code"].(string)

	// Other players join
	for i := 1; i < 8; i++ {
		joinData := map[string]string{"room_code": roomCode}
		makeRequest("POST", "/rooms/join", players[i].Token, joinData)
	}

	// All players set ready
	for i := 0; i < 8; i++ {
		readyData := map[string]bool{"ready": true}
		makeRequest("POST", fmt.Sprintf("/rooms/%s/ready", roomID), players[i].Token, readyData)
	}

	// Start game
	startResp := makeRequest("POST", fmt.Sprintf("/rooms/%s/start", roomID), players[0].Token, nil)
	sessionID := startResp["session_id"].(string)

	return players, sessionID, roomID
}

func assignRolesToPlayers(players []Player, gameState *GameStateResponse) {
	for i := range players {
		for _, p := range gameState.Players {
			if p.UserID == players[i].UserID {
				// Only update if role is not empty (means this player can see it)
				if p.Role != "" {
					players[i].Role = p.Role
				}
				players[i].IsAlive = p.IsAlive
				break
			}
		}
	}
}

func printPlayerRoles(players []Player) {
	werewolves := []string{}
	villagers := []string{}

	for _, p := range players {
		if p.Role == "werewolf" {
			werewolves = append(werewolves, p.Username)
		} else {
			villagers = append(villagers, fmt.Sprintf("%s (%s)", p.Username, p.Role))
		}
	}

	fmt.Printf("🐺 Werewolves: %v\n", werewolves)
	fmt.Printf("👥 Villagers: %v\n", villagers)
}

func performNightActions(players []Player, sessionID string, gameState *GameStateResponse) {
	// Find werewolves and their target (first villager)
	var werewolf *Player
	var target *Player

	for i := range players {
		if players[i].Role == "werewolf" && werewolf == nil {
			werewolf = &players[i]
		} else if players[i].Role != "werewolf" && target == nil {
			target = &players[i]
		}
		if werewolf != nil && target != nil {
			break
		}
	}

	if werewolf != nil && target != nil {
		fmt.Printf("🐺 Werewolf %s targeting %s (%s)\n", werewolf.Username, target.Username, target.Role)

		actionData := map[string]interface{}{
			"action_type": "werewolf_vote",
			"target_id":   target.UserID,
		}

		resp := makeRequest("POST", fmt.Sprintf("/games/%s/action", sessionID), werewolf.Token, actionData)
		if resp != nil {
			fmt.Println("✅ Werewolf action submitted")
		}
	}

	// Find seer and check someone
	for i := range players {
		if players[i].Role == "seer" {
			// Check a random player (not themselves)
			var checkTarget *Player
			for j := range players {
				if players[j].UserID != players[i].UserID {
					checkTarget = &players[j]
					break
				}
			}

			if checkTarget != nil {
				fmt.Printf("🔮 Seer %s checking %s\n", players[i].Username, checkTarget.Username)

				actionData := map[string]interface{}{
					"action_type": "seer_divine",
					"target_id":   checkTarget.UserID,
				}

				resp := makeRequest("POST", fmt.Sprintf("/games/%s/action", sessionID), players[i].Token, actionData)
				if resp != nil {
					fmt.Println("✅ Seer action submitted")
				}
			}
			break
		}
	}

	// Other special roles can be added here (witch, bodyguard, etc.)
}

func performDayVoting(players []Player, sessionID string, gameState *GameStateResponse) {
	// Find someone to vote for (first alive player that's not us)
	var voteTarget *Player
	for i := range players {
		if players[i].IsAlive {
			voteTarget = &players[i]
			break
		}
	}

	if voteTarget == nil {
		fmt.Println("⚠️  No valid vote targets")
		return
	}

	// All alive players vote for the same target (just for testing)
	votesSubmitted := 0
	for i := range players {
		if players[i].IsAlive {
			actionData := map[string]interface{}{
				"action_type": "vote_lynch",
				"target_id":   voteTarget.UserID,
			}

			resp := makeRequest("POST", fmt.Sprintf("/games/%s/action", sessionID), players[i].Token, actionData)
			if resp != nil {
				votesSubmitted++
			}
		}
	}

	fmt.Printf("✅ %d votes submitted for %s\n", votesSubmitted, voteTarget.Username)
}

func checkDeaths(gameState *GameStateResponse) {
	deadPlayers := []string{}
	for _, p := range gameState.Players {
		if !p.IsAlive {
			deadPlayers = append(deadPlayers, fmt.Sprintf("%s (%s)", p.Username, p.Role))
		}
	}

	if len(deadPlayers) > 0 {
		fmt.Printf("💀 Dead players: %v\n", deadPlayers)
	} else {
		fmt.Println("✅ No deaths yet")
	}
}

func getGameState(token, sessionID string) *GameStateResponse {
	resp := makeRequest("GET", fmt.Sprintf("/games/%s", sessionID), token, nil)
	if resp == nil {
		return nil
	}

	jsonData, _ := json.Marshal(resp)
	var gameState GameStateResponse
	json.Unmarshal(jsonData, &gameState)
	return &gameState
}

func waitForPhase(token, sessionID, phaseKeyword string) {
	maxAttempts := 60 // 5 minutes max
	for i := 0; i < maxAttempts; i++ {
		gameState := getGameState(token, sessionID)
		if gameState != nil {
			// Check if phase contains the keyword (e.g., "night" matches "night_0", "werewolf_phase")
			if contains(gameState.CurrentPhase, phaseKeyword) {
				return
			}
		}
		time.Sleep(5 * time.Second)
		if i%6 == 0 { // Print every 30 seconds
			fmt.Printf("  ⏳ Waiting for %s phase... (attempt %d/%d)\n", phaseKeyword, i+1, maxAttempts)
		}
	}
	fmt.Printf("⚠️  Timeout waiting for %s phase\n", phaseKeyword)
}

func contains(s, substr string) bool {
	return len(s) >= len(substr) && (s == substr ||
		(len(s) > len(substr) && (s[:len(substr)] == substr || s[len(s)-len(substr):] == substr)))
}

func makeRequest(method, path, token string, data interface{}) map[string]interface{} {
	var body io.Reader
	if data != nil {
		jsonData, _ := json.Marshal(data)
		body = bytes.NewBuffer(jsonData)
	}

	req, _ := http.NewRequest(method, baseURL+path, body)
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		fmt.Printf("❌ Request error: %v\n", err)
		return nil
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		bodyBytes, _ := io.ReadAll(resp.Body)
		fmt.Printf("⚠️  %s %s returned %d: %s\n", method, path, resp.StatusCode, string(bodyBytes))
		return nil
	}

	var result map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil
	}

	return result
}
