$ErrorActionPreference = "Stop"
$baseUrl = "http://localhost:8080/api/v1"

# --- Helper Functions ---
function Invoke-Api {
    param(
        [string]$Method,
        [string]$Path,
        [hashtable]$Body = @{},
        [string]$Token = $null,
        [bool]$IgnoreError = $false
    )
    $headers = @{ "Content-Type" = "application/json" }
    if ($Token) { $headers["Authorization"] = "Bearer $Token" }
    
    $params = @{
        Uri = "$baseUrl$Path"
        Method = $Method
        Headers = $headers
    }
    if ($Method -ne "GET" -and $Body.Count -gt 0) {
        $params.Body = ($Body | ConvertTo-Json -Depth 10)
    }

    try {
        return Invoke-RestMethod @params
    } catch {
        if ($IgnoreError) {
            Write-Host "Expected Error on $Path : $($_.Exception.Message)" -ForegroundColor DarkGray
            return $null
        }
        Write-Host "Error calling $Path : $($_.Exception.Message)" -ForegroundColor Red
        if ($_.Exception.Response) {
            try {
                if ($_.Exception.Response.Content) {
                    $body = $_.Exception.Response.Content.ReadAsStringAsync().Result
                    Write-Host "Response Body: $body" -ForegroundColor Red
                } elseif ($_.Exception.Response.GetResponseStream) {
                    $reader = New-Object System.IO.StreamReader $_.Exception.Response.GetResponseStream()
                    Write-Host "Response Body: $($reader.ReadToEnd())" -ForegroundColor Red
                }
            } catch {}
        }
        throw
    }
}

function Wait-ForPhase {
    param([string]$SessionId, [string]$TargetPhase, [string]$Token)
    Write-Host "Waiting for phase: $TargetPhase..." -NoNewline
    $retries = 0
    do {
        Start-Sleep -Seconds 2
        $game = Invoke-Api -Method GET -Path "/games/$SessionId" -Token $Token
        Write-Host "." -NoNewline
        $retries++
        if ($retries -gt 30) { throw "Timeout waiting for phase $TargetPhase" }
    } until ($game.current_phase -eq $TargetPhase)
    Write-Host " OK!" -ForegroundColor Green
    return $game
}

# --- 1. Setup & Registration ---
Write-Host "=== 1. Setup & Registration ===" -ForegroundColor Cyan
$players = @()
$names = @("tester1", "tester2", "tester3", "tester4", "tester5", "tester6")

foreach ($name in $names) {
    try {
        $res = Invoke-Api -Method POST -Path "/auth/register" -Body @{
            username = $name
            email = "$name@scenario.com"
            password = "password123"
        } -IgnoreError $true
        
        if (-not $res) {
             # Login if register fails (user exists)
             $res = Invoke-Api -Method POST -Path "/auth/login" -Body @{
                username = $name
                password = "password123"
            }
        }
        
        $players += @{
            Name = $name
            Id = $res.user.id
            Token = $res.access_token
        }
        Write-Host "Player $name ready" -ForegroundColor Green
    } catch {
        Write-Host "Failed to setup $name" -ForegroundColor Red
    }
}

$hostPlayer = $players[0]

# --- 2. Create Room with Short Timers ---
Write-Host "`n=== 2. Creating Fast-Paced Room ===" -ForegroundColor Cyan
$roomConfig = @{
    name = "Scenario Test Room"
    max_players = 6
    is_private = $false
    config = @{
        night_phase_seconds = 10
        day_phase_seconds = 10
        voting_seconds = 10
        werewolf_count = 2
    }
}

$room = Invoke-Api -Method POST -Path "/rooms" -Token $hostPlayer.Token -Body $roomConfig
$roomId = $room.id
$roomCode = $room.room_code
Write-Host "Room Created: $roomId (Code: $roomCode)" -ForegroundColor Yellow

# --- 3. Join & Start ---
Write-Host "`n=== 3. Joining & Starting ===" -ForegroundColor Cyan
for ($i = 1; $i -lt $players.Count; $i++) {
    $p = $players[$i]
    $null = Invoke-Api -Method POST -Path "/rooms/join" -Token $p.Token -Body @{ room_code = $roomCode }
}

foreach ($p in $players) {
    $null = Invoke-Api -Method POST -Path "/rooms/$roomId/ready" -Token $p.Token -Body @{ ready = $true }
}

$gameStart = Invoke-Api -Method POST -Path "/rooms/$roomId/start" -Token $hostPlayer.Token
$sessionId = $gameStart.session_id
Write-Host "Game Started! Session: $sessionId" -ForegroundColor Magenta

# --- 4. Role Discovery ---
Write-Host "`n=== 4. Role Discovery ===" -ForegroundColor Cyan
$roleMap = @{} # Role -> List of Player Objects (with Token)
$playerMap = @{} # GamePlayerID -> Player Object

foreach ($p in $players) {
    # Fetch game state AS THIS PLAYER to see their own role
    $myState = Invoke-Api -Method GET -Path "/games/$sessionId" -Token $p.Token
    
    # Find myself in the players list
    $myPlayerStruct = $myState.players | Where-Object { $_.user_id -eq $p.Id }
    
    if (-not $myPlayerStruct) {
        Write-Host "Error: Could not find player $($p.Name) in game state" -ForegroundColor Red
        continue
    }

    $pObj = @{
        GamePlayerId = $myPlayerStruct.id
        UserId = $p.Id
        Name = $p.Name
        Token = $p.Token
        Role = $myPlayerStruct.role
        Team = $myPlayerStruct.team
    }
    
    if (-not $roleMap[$myPlayerStruct.role]) { $roleMap[$myPlayerStruct.role] = @() }
    $roleMap[$myPlayerStruct.role] += $pObj
    $playerMap[$myPlayerStruct.id] = $pObj
    
    Write-Host "$($p.Name) is a $($myPlayerStruct.role)" -ForegroundColor Gray
}

# --- 5. Night Phase Actions ---
Write-Host "`n=== 5. Night Phase Actions ===" -ForegroundColor Cyan
# Wait for night (should be immediate or very quick)
$gameState = Wait-ForPhase -SessionId $sessionId -TargetPhase "night_0" -Token $hostPlayer.Token

# 5a. Werewolf Vote
$wolves = $roleMap["werewolf"]

# Find a valid target (anyone who is not a werewolf)
$potentialTargets = @()
foreach ($key in $roleMap.Keys) {
    if ($key -ne "werewolf") { $potentialTargets += $roleMap[$key] }
}
$target = $potentialTargets[0]

Write-Host "Werewolves ($($wolves.Name)) voting for $($target.Name)..."
foreach ($wolf in $wolves) {
    Invoke-Api -Method POST -Path "/games/$sessionId/action" -Token $wolf.Token -Body @{
        action_type = "werewolf_vote"
        target_id = $target.GamePlayerId
    }
    Write-Host "  $($wolf.Name) voted." -ForegroundColor Green
}

# 5b. Abuse Test: Non-Werewolf tries to vote as werewolf
$innocent = $target # The target is definitely not a werewolf
if ($innocent) {
    Write-Host "Abuse Test: Innocent $($innocent.Name) ($($innocent.Role)) trying to vote as werewolf..."
    try {
        Invoke-Api -Method POST -Path "/games/$sessionId/action" -Token $innocent.Token -Body @{
            action_type = "werewolf_vote"
            target_id = $target.GamePlayerId
        }
        Write-Host "  FAILED: Innocent was allowed to vote!" -ForegroundColor Red
    } catch {
        Write-Host "  SUCCESS: Innocent blocked." -ForegroundColor Green
    }
}

# 5c. Seer Action
$seer = $roleMap["seer"][0]
if ($seer) {
    Write-Host "Seer $($seer.Name) divining $($wolves[0].Name)..."
    Invoke-Api -Method POST -Path "/games/$sessionId/action" -Token $seer.Token -Body @{
        action_type = "seer_divine"
        target_id = $wolves[0].GamePlayerId
    }
    Write-Host "  Seer acted." -ForegroundColor Green
}

# --- 6. Day Phase ---
Write-Host "`n=== 6. Day Phase ===" -ForegroundColor Cyan
$gameState = Wait-ForPhase -SessionId $sessionId -TargetPhase "day_discussion" -Token $hostPlayer.Token

# Check deaths
if ($gameState.state.night_kills.Count -gt 0) {
    Write-Host "Night Kills: $($gameState.state.night_kills)" -ForegroundColor Red
} else {
    Write-Host "No one died (Night 0 usually has no kills or protected)." -ForegroundColor Yellow
}

# Abuse Test: Voting during discussion
Write-Host "Abuse Test: Voting during discussion..."
try {
    Invoke-Api -Method POST -Path "/games/$sessionId/action" -Token $hostPlayer.Token -Body @{
        action_type = "vote_lynch"
        target_id = $wolves[0].GamePlayerId
    }
    Write-Host "  FAILED: Allowed to vote early!" -ForegroundColor Red
} catch {
    Write-Host "  SUCCESS: Early vote blocked." -ForegroundColor Green
}

# --- 7. Voting Phase ---
Write-Host "`n=== 7. Voting Phase ===" -ForegroundColor Cyan
$gameState = Wait-ForPhase -SessionId $sessionId -TargetPhase "day_voting" -Token $hostPlayer.Token

# Everyone votes for the first Werewolf
$lynchTarget = $wolves[0]
Write-Host "Everyone voting to lynch $($lynchTarget.Name)..."

foreach ($p in $players) {
    # Skip if dead (check game state)
    # For simplicity assuming all alive or just try/catch
    try {
        Invoke-Api -Method POST -Path "/games/$sessionId/action" -Token $p.Token -Body @{
            action_type = "vote_lynch"
            target_id = $lynchTarget.GamePlayerId
        } -IgnoreError $true
    } catch {}
}
Write-Host "Votes cast." -ForegroundColor Green

# --- 8. Result Verification ---
Write-Host "`n=== 8. Result Verification ===" -ForegroundColor Cyan
# Wait for next phase (Night) - after Day 1, it cycles back to night_0
$gameState = Wait-ForPhase -SessionId $sessionId -TargetPhase "night_0" -Token $hostPlayer.Token

# Check if target is dead
$updatedTarget = $gameState.players | Where-Object { $_.id -eq $lynchTarget.GamePlayerId }
if ($updatedTarget.is_alive -eq $false) {
    Write-Host "SUCCESS: $($lynchTarget.Name) was lynched!" -ForegroundColor Green
} else {
    Write-Host "FAILURE: $($lynchTarget.Name) is still alive!" -ForegroundColor Red
}

# Abuse Test: Dead player trying to act
Write-Host "Abuse Test: Dead player trying to act..."
# We need to find the player object for the lynched target to get their token
$deadPlayer = $players | Where-Object { $_.Id -eq $lynchTarget.UserId }

try {
    Invoke-Api -Method POST -Path "/games/$sessionId/action" -Token $deadPlayer.Token -Body @{
        action_type = "werewolf_vote"
        target_id = $target.GamePlayerId
    }
    Write-Host "  FAILED: Dead player allowed to act!" -ForegroundColor Red
} catch {
    Write-Host "  SUCCESS: Dead player blocked." -ForegroundColor Green
}

Write-Host "`n=== SCENARIO COMPLETE ===" -ForegroundColor Magenta
