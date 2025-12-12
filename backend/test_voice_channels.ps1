# Test Voice Channel Isolation
# Verifies that voice channels are properly isolated during different game phases
# - Night: Werewolves get "werewolf" channel, others get no channel
# - Day: All alive players get "main" channel
# - Dead: Dead players get "dead" channel

$ErrorActionPreference = "Stop"
$baseUrl = "http://localhost:8080/api/v1"

# Color output functions
function Write-Success($message) { Write-Host "✓ $message" -ForegroundColor Green }
function Write-Error($message) { Write-Host "✗ $message" -ForegroundColor Red }
function Write-Info($message) { Write-Host "ℹ $message" -ForegroundColor Cyan }
function Write-Test($message) { Write-Host "`n=== $message ===" -ForegroundColor Yellow }

# Helper: Register and login user
function Register-TestUser {
    param($username, $email, $password)
    
    try {
        $registerBody = @{
            username = $username
            email = $email
            password = $password
        } | ConvertTo-Json
        
        $response = Invoke-RestMethod -Method Post -Uri "$baseUrl/auth/register" `
            -Body $registerBody -ContentType "application/json"
        
        # Login to get token
        $loginBody = @{
            username = $username
            password = $password
        } | ConvertTo-Json
        
        $loginResponse = Invoke-RestMethod -Method Post -Uri "$baseUrl/auth/login" `
            -Body $loginBody -ContentType "application/json"
        
        return @{
            token = $loginResponse.access_token
            user_id = $loginResponse.user.id
            username = $username
        }
    } catch {
        Write-Error "Failed to register $username : $($_.Exception.Message)"
        throw
    }
}

# Helper: Get game state
function Get-GameState {
    param($sessionId, $token)
    
    $headers = @{ Authorization = "Bearer $token" }
    return Invoke-RestMethod -Uri "$baseUrl/games/$sessionId" -Headers $headers
}

# Helper: Get player by username
function Get-PlayerByUsername {
    param($players, $username)
    return $players | Where-Object { $_.username -eq $username }
}

# Helper: Submit action
function Submit-Action {
    param($sessionId, $token, $actionType, $targetId = $null, $data = $null)
    
    $headers = @{ Authorization = "Bearer $token" }
    $body = @{ action_type = $actionType }
    
    if ($targetId) { $body.target_id = $targetId }
    if ($data) { $body.data = $data }
    
    try {
        $response = Invoke-RestMethod -Method Post -Uri "$baseUrl/games/$sessionId/action" `
            -Headers $headers -Body ($body | ConvertTo-Json) -ContentType "application/json"
        return $response
    } catch {
        Write-Error "Action $actionType failed: $($_.ErrorDetails.Message)"
        return $null
    }
}

# Helper: Wait for phase change
function Wait-ForPhase {
    param($sessionId, $token, $expectedPhase, $maxWaitSeconds = 30)
    
    $startTime = Get-Date
    while (((Get-Date) - $startTime).TotalSeconds -lt $maxWaitSeconds) {
        $gameState = Get-GameState -sessionId $sessionId -token $token
        if ($gameState.current_phase -eq $expectedPhase) {
            return $gameState
        }
        Start-Sleep -Milliseconds 500
    }
    throw "Timeout waiting for phase $expectedPhase"
}

Write-Test "VOICE CHANNEL ISOLATION TEST"
Write-Info "Testing channel assignments during different game phases..."

# Register 8 players with timestamp to avoid conflicts
$timestamp = Get-Date -Format "HHmmss"
Write-Info "Registering 8 test players..."
$players = @()
for ($i = 1; $i -le 8; $i++) {
    $username = "vctest$timestamp$i"
    $email = "vctest$timestamp$i@test.com"
    $password = "password123"
    
    $player = Register-TestUser -username $username -email $email -password $password
    $players += $player
    Write-Success "Registered $username"
}

$host_player = $players[0]

# Create room
Write-Info "Creating test room..."
$roomConfig = @{
    name = "Voice Channel Test Room"
    max_players = 8
    config = @{
        werewolf_count = 2
        day_phase_seconds = 15
        night_phase_seconds = 15
        voting_seconds = 15
        enabled_roles = @("werewolf", "villager", "seer", "bodyguard")
    }
} | ConvertTo-Json

$headers = @{ Authorization = "Bearer $($host_player.token)" }
$room = Invoke-RestMethod -Method Post -Uri "$baseUrl/rooms" `
    -Headers $headers -Body $roomConfig -ContentType "application/json"

Write-Success "Room created: $($room.room_code)"

# All players join
Write-Info "Players joining room..."
foreach ($player in $players[1..7]) {
    $joinBody = @{ room_code = $room.room_code } | ConvertTo-Json
    $headers = @{ Authorization = "Bearer $($player.token)" }
    Invoke-RestMethod -Method Post -Uri "$baseUrl/rooms/join" `
        -Headers $headers -Body $joinBody -ContentType "application/json" | Out-Null
    Write-Success "$($player.username) joined"
}

# All players ready
Write-Info "All players marking ready..."
foreach ($player in $players) {
    $headers = @{ Authorization = "Bearer $($player.token)" }
    $readyBody = @{ ready = $true } | ConvertTo-Json
    Invoke-RestMethod -Method Post -Uri "$baseUrl/rooms/$($room.id)/ready" `
        -Headers $headers -Body $readyBody -ContentType "application/json" | Out-Null
}
Write-Success "All players ready"

# Start game
Write-Info "Starting game..."
$headers = @{ Authorization = "Bearer $($host_player.token)" }
$gameStart = Invoke-RestMethod -Method Post -Uri "$baseUrl/rooms/$($room.id)/start" -Headers $headers
$sessionId = $gameStart.session_id
Write-Success "Game started! Session: $sessionId"

Start-Sleep -Seconds 2

# Get initial game state
Write-Test "PHASE 1: NIGHT_0 - First Night"
$gameState = Get-GameState -sessionId $sessionId -token $host_player.token

# DEBUG: Print raw game state
Write-Host "`nDEBUG: Players array:" -ForegroundColor Magenta
$gameState.players | ForEach-Object {
    Write-Host "  Player: $($_ | ConvertTo-Json -Compress)" -ForegroundColor Yellow
}

Write-Info "Current Phase: $($gameState.current_phase)"
Write-Info "Verifying channel assignments..."

$werewolves = @()
$nonWerewolves = @()
$errors = @()

foreach ($player in $gameState.players) {
    $username = $player.username
    $role = $player.role
    $channels = $player.allowed_chat_channels
    
    Write-Info "Player: $username | Role: $role | Channels: $($channels -join ', ')"
    
    if ($role -eq "werewolf") {
        $werewolves += $player
        
        # Werewolf should have ["werewolf"] channel
        if ($channels.Count -ne 1 -or $channels[0] -ne "werewolf") {
            $errors += "❌ Werewolf $username has wrong channels: $($channels -join ', ') (expected: werewolf)"
        } else {
            Write-Success "Werewolf $username correctly assigned to werewolf channel"
        }
    } else {
        $nonWerewolves += $player
        
        # Non-werewolves should have NO channels (empty array) during night
        if ($channels.Count -ne 0) {
            $errors += "❌ Non-werewolf $username ($role) has channels during night: $($channels -join ', ') (expected: none)"
        } else {
            Write-Success "Non-werewolf $username ($role) correctly silenced"
        }
    }
}

if ($errors.Count -gt 0) {
    Write-Error "Night channel assignment errors:"
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Success "✓ Night phase channel isolation: PASSED"

# Werewolves vote
Write-Info "`nWerewolves voting to kill a villager..."
$victim = $nonWerewolves[0]
foreach ($ww in $werewolves) {
    $wwToken = ($players | Where-Object { $_.username -eq $ww.username }).token
    Submit-Action -sessionId $sessionId -token $wwToken `
        -actionType "werewolf_vote" -targetId $victim.id | Out-Null
    Write-Success "$($ww.username) voted to kill $($victim.username)"
}

# Wait for day phase
Write-Info "Waiting for day phase..."
Start-Sleep -Seconds 16

$gameState = Get-GameState -sessionId $sessionId -token $host_player.token

Write-Test "PHASE 2: DAY_DISCUSSION - Day Phase"
Write-Info "Current Phase: $($gameState.current_phase)"
Write-Info "Verifying channel assignments..."

$errors = @()
$deadPlayers = @()

foreach ($player in $gameState.players) {
    $username = $player.username
    $isAlive = $player.is_alive
    $channels = $player.allowed_chat_channels
    
    Write-Info "Player: $username | Alive: $isAlive | Channels: $($channels -join ', ')"
    
    if (-not $isAlive) {
        $deadPlayers += $player
        
        # Dead players should have ["dead"] channel
        if ($channels.Count -ne 1 -or $channels[0] -ne "dead") {
            $errors += "❌ Dead player $username has wrong channels: $($channels -join ', ') (expected: dead)"
        } else {
            Write-Success "Dead player $username correctly assigned to dead channel"
        }
    } else {
        # Alive players should have ["main"] channel during day
        if ($channels.Count -ne 1 -or $channels[0] -ne "main") {
            $errors += "❌ Alive player $username has wrong channels: $($channels -join ', ') (expected: main)"
        } else {
            Write-Success "Alive player $username correctly assigned to main channel"
        }
    }
}

if ($errors.Count -gt 0) {
    Write-Error "Day channel assignment errors:"
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Success "✓ Day phase channel isolation: PASSED"

# Check that at least one player died
if ($deadPlayers.Count -eq 0) {
    Write-Error "Expected at least one death, but no players died"
    exit 1
}

Write-Success "✓ Death detected: $($deadPlayers[0].username) died"

# Wait for voting phase
Write-Info "`nWaiting for voting phase..."
Start-Sleep -Seconds 16

$gameState = Get-GameState -sessionId $sessionId -token $host_player.token
Write-Test "PHASE 3: DAY_VOTING - Voting Phase"
Write-Info "Current Phase: $($gameState.current_phase)"

# Verify channels still correct during voting
$errors = @()
foreach ($player in $gameState.players) {
    $username = $player.username
    $isAlive = $player.is_alive
    $channels = $player.allowed_chat_channels
    
    if (-not $isAlive) {
        if ($channels.Count -ne 1 -or $channels[0] -ne "dead") {
            $errors += "❌ Dead player $username has wrong channels during voting: $($channels -join ', ')"
        }
    } else {
        if ($channels.Count -ne 1 -or $channels[0] -ne "main") {
            $errors += "❌ Alive player $username has wrong channels during voting: $($channels -join ', ')"
        }
    }
}

if ($errors.Count -gt 0) {
    Write-Error "Voting phase channel assignment errors:"
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Success "✓ Voting phase channel isolation: PASSED"

# Lynch someone
Write-Info "`nPlayers voting to lynch..."
$alivePlayers = $gameState.players | Where-Object { $_.is_alive }
$lynchTarget = $alivePlayers[0]

foreach ($player in $alivePlayers[1..($alivePlayers.Count - 1)]) {
    $pToken = ($players | Where-Object { $_.username -eq $player.username }).token
    Submit-Action -sessionId $sessionId -token $pToken `
        -actionType "vote_lynch" -targetId $lynchTarget.id | Out-Null
}

Write-Success "Players voted to lynch $($lynchTarget.username)"

# Wait for next night
Write-Info "`nWaiting for next night phase..."
Start-Sleep -Seconds 16

$gameState = Get-GameState -sessionId $sessionId -token $host_player.token

Write-Test "PHASE 4: NIGHT_1 - Second Night"
Write-Info "Current Phase: $($gameState.current_phase)"
Write-Info "Verifying channel assignments after lynch..."

$errors = @()
$currentDeadCount = ($gameState.players | Where-Object { -not $_.is_alive }).Count

Write-Info "Total dead players: $currentDeadCount"

foreach ($player in $gameState.players) {
    $username = $player.username
    $role = $player.role
    $isAlive = $player.is_alive
    $channels = $player.allowed_chat_channels
    
    Write-Info "Player: $username | Role: $role | Alive: $isAlive | Channels: $($channels -join ', ')"
    
    if (-not $isAlive) {
        # Dead players should have ["dead"] channel
        if ($channels.Count -ne 1 -or $channels[0] -ne "dead") {
            $errors += "❌ Dead player $username has wrong channels: $($channels -join ', ') (expected: dead)"
        }
    } elseif ($role -eq "werewolf") {
        # Alive werewolves should have ["werewolf"] channel
        if ($channels.Count -ne 1 -or $channels[0] -ne "werewolf") {
            $errors += "❌ Werewolf $username has wrong channels: $($channels -join ', ') (expected: werewolf)"
        }
    } else {
        # Alive non-werewolves should have NO channels
        if ($channels.Count -ne 0) {
            $errors += "❌ Non-werewolf $username has channels during night: $($channels -join ', ') (expected: none)"
        }
    }
}

if ($errors.Count -gt 0) {
    Write-Error "Second night channel assignment errors:"
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Success "✓ Second night phase channel isolation: PASSED"

# Final summary
Write-Test "TEST SUMMARY"
Write-Success "✓ All voice channel isolation tests PASSED!"
Write-Info ""
Write-Info "Verified Behaviors:"
Write-Success "  ✓ Werewolves get 'werewolf' channel during night"
Write-Success "  ✓ Non-werewolves are silenced (no channels) during night"
Write-Success "  ✓ All alive players get 'main' channel during day"
Write-Success "  ✓ Dead players get 'dead' channel at all times"
Write-Success "  ✓ Channel assignments persist across phase transitions"
Write-Success "  ✓ Channel assignments update correctly after deaths"

Write-Info "`n=== VOICE CHANNEL TEST COMPLETE ==="
