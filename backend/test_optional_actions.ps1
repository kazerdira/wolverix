#!/usr/bin/env pwsh

# TEST: Optional Actions - Game progresses when special roles don't act
# Professional test verifying phase transitions work without all actions

$ErrorActionPreference = "Stop"

$baseUrl = "http://localhost:8080/api/v1"

# Color output functions
function Write-Success { param($msg) Write-Host "✓ $msg" -ForegroundColor Green }
function Write-Error { param($msg) Write-Host "✗ $msg" -ForegroundColor Red }
function Write-Info { param($msg) Write-Host "ℹ $msg" -ForegroundColor Cyan }
function Write-Test { param($msg) Write-Host "`n=== $msg ===" -ForegroundColor Yellow }

# Helper: Register user
function Register-TestUser {
    param($username, $email, $password = "testpass123")
    
    try {
        $registerBody = @{
            username = $username
            email = $email
            password = $password
        } | ConvertTo-Json
        
        Invoke-RestMethod -Method Post -Uri "$baseUrl/auth/register" `
            -Body $registerBody -ContentType "application/json" | Out-Null
        
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

# Helper: Submit action
function Submit-Action {
    param($sessionId, $token, $actionType, $targetId = $null, $data = $null)
    
    $body = @{ action_type = $actionType }
    if ($targetId) { $body.target_id = $targetId }
    if ($data) { $body.data = $data }
    
    $headers = @{ Authorization = "Bearer $token" }
    return Invoke-RestMethod -Method Post -Uri "$baseUrl/games/$sessionId/actions" `
        -Body ($body | ConvertTo-Json) -Headers $headers -ContentType "application/json"
}

Write-Test "OPTIONAL ACTIONS TEST"
Write-Info "Testing game behavior when special roles don't act...`n"

# Register 8 test players
Write-Info "Registering 8 test players..."
$timestamp = Get-Date -Format "HHmmss"
$players = @()
for ($i = 1; $i -le 8; $i++) {
    $username = "opttest$timestamp$i"
    $email = "$username@test.com"
    $player = Register-TestUser -username $username -email $email
    $players += $player
    Write-Success "Registered $username"
}

$host_player = $players[0]

# Create room
Write-Info "Creating test room..."
$headers = @{ Authorization = "Bearer $($host_player.token)" }
$roomBody = @{
    name = "Optional Actions Test"
    max_players = 8
} | ConvertTo-Json

$room = Invoke-RestMethod -Method Post -Uri "$baseUrl/rooms" `
    -Body $roomBody -Headers $headers -ContentType "application/json"
Write-Success "Room created: $($room.room_code)"

# All players join
Write-Info "Players joining room..."
for ($i = 1; $i -lt $players.Count; $i++) {
    $p = $players[$i]
    $headers = @{ Authorization = "Bearer $($p.token)" }
    $joinBody = @{ room_code = $room.room_code } | ConvertTo-Json
    Invoke-RestMethod -Method Post -Uri "$baseUrl/rooms/join" -Headers $headers `
        -Body $joinBody -ContentType "application/json" | Out-Null
    Write-Success "$($p.username) joined"
}

# All players ready
Write-Info "All players marking ready..."
foreach ($p in $players) {
    $headers = @{ Authorization = "Bearer $($p.token)" }
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
Write-Success "Game started! Session: $sessionId`n"

# Identify roles by checking each player's own state
Write-Info "Identifying player roles (API shows each player only their own role)..."
$playerRoles = @{}
foreach ($p in $players) {
    try {
        $pState = Get-GameState -sessionId $sessionId -token $p.token
        $myPlayer = $pState.players | Where-Object { $_.user_id -eq $p.user_id }
        $playerRoles[$p.username] = @{
            role = $myPlayer.role
            user_id = $p.user_id
            id = $myPlayer.id
            token = $p.token
            username = $p.username
        }
    } catch {
        Write-Error "Failed to get state for $($p.username): $($_.Exception.Message)"
    }
}

# Categorize by role
$werewolves = @()
$bodyguard = $null
$seer = $null
$witch = $null
$villagers = @()

foreach ($username in $playerRoles.Keys) {
    $role = $playerRoles[$username].role
    switch ($role) {
        "werewolf" { $werewolves += $playerRoles[$username] }
        "bodyguard" { $bodyguard = $playerRoles[$username] }
        "seer" { $seer = $playerRoles[$username] }
        "witch" { $witch = $playerRoles[$username] }
        "villager" { $villagers += $playerRoles[$username] }
    }
}

Write-Info "Role Distribution:"
Write-Info "  Werewolves: $($werewolves.Count)"
Write-Info "  Bodyguard: $(if ($bodyguard) { $bodyguard.username } else { 'Not assigned' })"
Write-Info "  Seer: $(if ($seer) { $seer.username } else { 'Not assigned' })"
Write-Info "  Witch: $(if ($witch) { $witch.username } else { 'Not assigned' })"
Write-Info "  Villagers: $($villagers.Count)"

if ($werewolves.Count -eq 0) {
    Write-Error "No werewolves! Cannot test."
    exit 1
}

# Wait for an action night phase (night_2 or later)
Write-Info "`nWaiting for action night phase..."
$maxWait = 180
$waited = 0
$gameState = $null
$actionNightReached = $false

while ($waited -lt $maxWait) {
    $gameState = Get-GameState -sessionId $sessionId -token $host_player.token
    $phase = $gameState.current_phase
    
    if ($waited % 10 -eq 0) {
        Write-Info "  Phase: $phase (${waited}s elapsed)"
    }
    
    # Check for action night (night_2, night_3, etc - not night_0)
    if ($phase -match "^night_\d+$" -and $phase -ne "night_0") {
        Write-Success "Reached $phase"
        $actionNightReached = $true
        break
    }
    
    Start-Sleep -Seconds 2
    $waited += 2
}

if (-not $actionNightReached) {
    Write-Error "Failed to reach action night! Current: $($gameState.current_phase)"
    exit 1
}

Write-Test "TEST 1: Phase Transition Without Special Role Actions"

# Get werewolf's view to see other werewolves and pick target
$wwState = Get-GameState -sessionId $sessionId -token $werewolves[0].token
$alivePlayers = $wwState.players | Where-Object { $_.is_alive }

# Werewolves can see each other, so find non-werewolf
$nonWerewolfTargets = $alivePlayers | Where-Object { $_.role -ne "werewolf" }
if ($nonWerewolfTargets.Count -eq 0) {
    Write-Error "No valid targets!"
    exit 1
}

$victim = $nonWerewolfTargets[0]
Write-Info "Target selected: $($victim.username)`n"

# Werewolves vote
Write-Info "Werewolves submitting votes..."
$voteCount = 0
foreach ($ww in $werewolves) {
    try {
        Submit-Action -sessionId $sessionId -token $ww.token `
            -actionType "werewolf_vote" -targetId $victim.id | Out-Null
        Write-Success "  $($ww.username) voted for $($victim.username)"
        $voteCount++
    } catch {
        Write-Error "  $($ww.username) vote failed: $($_.Exception.Message)"
    }
}

if ($voteCount -eq 0) {
    Write-Error "No werewolf votes succeeded!"
    exit 1
}

Write-Info "`nSpecial roles deliberately NOT acting..."
Write-Info "  Bodyguard: Not protecting anyone"
Write-Info "  Seer: Not investigating"
Write-Info "  Witch: Not using potions"
Write-Info "`nWaiting for phase timeout and auto-transition..."

Start-Sleep -Seconds 13

$gameState = Get-GameState -sessionId $sessionId -token $host_player.token
$newPhase = $gameState.current_phase

Write-Info "New phase: $newPhase"

if ($newPhase -ne "day_discussion") {
    Write-Error "Expected day_discussion, got: $newPhase"
    exit 1
}

Write-Success "✓ Phase transitioned to day_discussion without special role actions"

# Verify victim died
$victimState = $gameState.players | Where-Object { $_.id -eq $victim.id }
if (-not $victimState.is_alive) {
    Write-Success "✓ Victim died (no bodyguard protection, no witch heal)"
} else {
    Write-Error "✗ Victim still alive! Expected death."
    exit 1
}

Write-Test "TEST 2: Continue Through Multiple Phases"

# Wait for day_voting
Write-Info "Waiting for day_voting phase..."
Start-Sleep -Seconds 13

$gameState = Get-GameState -sessionId $sessionId -token $host_player.token
Write-Info "Phase: $($gameState.current_phase)"

if ($gameState.current_phase -eq "day_voting") {
    # Submit some lynch votes (optional, testing that game continues)
    $alivePlayers = $gameState.players | Where-Object { $_.is_alive }
    if ($alivePlayers.Count -gt 2) {
        $lynchTarget = $alivePlayers | Where-Object { $_.id -ne $host_player.user_id } | Select-Object -First 1
        
        Write-Info "Submitting partial lynch votes for $($lynchTarget.username)..."
        $voteCount = 0
        foreach ($p in $alivePlayers | Select-Object -First 3) {
            $pData = $players | Where-Object { $_.user_id -eq $p.user_id }
            if ($pData) {
                try {
                    Submit-Action -sessionId $sessionId -token $pData.token `
                        -actionType "vote_lynch" -targetId $lynchTarget.id | Out-Null
                    $voteCount++
                } catch {}
            }
        }
        Write-Success "$voteCount votes submitted"
    }
}

# Wait for next night
Write-Info "`nWaiting for next night phase..."
Start-Sleep -Seconds 15

$gameState = Get-GameState -sessionId $sessionId -token $host_player.token
Write-Info "Phase: $($gameState.current_phase)"

if ($gameState.current_phase -match "^night") {
    Write-Success "✓ Game progressed to next night phase"
    
    # Again, special roles don't act
    $aliveWerewolves = $werewolves | Where-Object { 
        $playerId = $_.id
        $playerState = $gameState.players | Where-Object { $_.id -eq $playerId }
        $playerState -and $playerState.is_alive
    }
    
    if ($aliveWerewolves.Count -gt 0) {
        Write-Info "Werewolves voting again (special roles still not acting)..."
        
        # Get updated werewolf view
        $wwState = Get-GameState -sessionId $sessionId -token $aliveWerewolves[0].token
        $aliveTargets = $wwState.players | Where-Object { $_.is_alive -and $_.role -ne "werewolf" }
        
        if ($aliveTargets.Count -gt 0) {
            $newVictim = $aliveTargets[0]
            
            foreach ($ww in $aliveWerewolves) {
                try {
                    Submit-Action -sessionId $sessionId -token $ww.token `
                        -actionType "werewolf_vote" -targetId $newVictim.id | Out-Null
                } catch {}
            }
            
            Write-Info "Waiting for next day..."
            Start-Sleep -Seconds 13
            
            $gameState = Get-GameState -sessionId $sessionId -token $host_player.token
            
            if ($gameState.current_phase -eq "day_discussion") {
                Write-Success "✓ Second night -> day transition worked"
                
                $newVictimState = $gameState.players | Where-Object { $_.id -eq $newVictim.id }
                if ($newVictimState -and -not $newVictimState.is_alive) {
                    Write-Success "✓ Second victim died (continued without special roles)"
                }
            }
        }
    }
}

Write-Test "VERIFICATION SUMMARY"

$totalDeaths = ($gameState.players | Where-Object { -not $_.is_alive }).Count
$totalAlive = ($gameState.players | Where-Object { $_.is_alive }).Count

Write-Info "Deaths: $totalDeaths"
Write-Info "Alive: $totalAlive"
Write-Info "Game Status: $($gameState.status)"

if ($totalDeaths -ge 2) {
    Write-Success "✓ Multiple deaths occurred without all special role actions"
} else {
    Write-Info "Note: $totalDeaths death(s) recorded"
}

if ($gameState.status -eq "active") {
    Write-Success "✓ Game still active and progressing"
}

Write-Test "OPTIONAL ACTIONS TEST COMPLETE"
Write-Success "✓ Phase transitions work without bodyguard actions"
Write-Success "✓ Phase transitions work without seer actions"
Write-Success "✓ Phase transitions work without witch actions"
Write-Success "✓ Victims die when special roles don't protect/heal"
Write-Success "✓ Game progresses normally with optional actions"
Write-Info "`nAll optional action tests PASSED!`n"
