$ErrorActionPreference = "Stop"
$baseUrl = "http://localhost:8080/api/v1"

function Invoke-Api {
    param([string]$Method, [string]$Path, [hashtable]$Body = @{}, [string]$Token = $null, [bool]$IgnoreError = $false)
    $headers = @{ "Content-Type" = "application/json" }
    if ($Token) { $headers["Authorization"] = "Bearer $Token" }
    $params = @{ Uri = "$baseUrl$Path"; Method = $Method; Headers = $headers }
    if ($Method -ne "GET" -and $Body.Count -gt 0) { $params.Body = ($Body | ConvertTo-Json -Depth 10) }
    try { return Invoke-RestMethod @params }
    catch {
        if ($IgnoreError) { Write-Host "Expected Error: $($_.Exception.Message)" -ForegroundColor DarkGray; return $null }
        throw
    }
}

function Wait-ForPhase {
    param([string]$SessionId, [string]$TargetPhase, [string]$Token)
    Write-Host "Waiting for $TargetPhase..." -NoNewline
    $retries = 0
    do {
        Start-Sleep -Seconds 2
        $game = Invoke-Api -Method GET -Path "/games/$SessionId" -Token $Token
        Write-Host "." -NoNewline
        $retries++
        if ($retries -gt 30) { throw "Timeout" }
    } until ($game.current_phase -eq $TargetPhase)
    Write-Host " OK!" -ForegroundColor Green
    return $game
}

Write-Host "╔═════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
Write-Host "║   WEREWOLF SPLIT VOTE TEST - What happens on tie?      ║" -ForegroundColor Yellow
Write-Host "╚═════════════════════════════════════════════════════════╝" -ForegroundColor Yellow

# Setup players
$players = @()
foreach ($name in @("SplitWolf1", "SplitWolf2", "SplitVictim1", "SplitVictim2", "SplitObs1", "SplitObs2")) {
    $res = Invoke-Api -Method POST -Path "/auth/register" -Body @{
        username = $name; email = "$($name.ToLower())@splitvote.com"; password = "splitpass123"
    } -IgnoreError $true
    if (-not $res) {
        $res = Invoke-Api -Method POST -Path "/auth/login" -Body @{ username = $name; password = "splitpass123" }
    }
    $players += @{ Name = $name; UserId = $res.user.id; Token = $res.access_token }
    Write-Host "  ✓ $name ready" -ForegroundColor Green
}

# Create room
$room = Invoke-Api -Method POST -Path "/rooms" -Token $players[0].Token -Body @{
    name = "Split Vote Test"
    max_players = 6
    is_private = $false
    config = @{ night_phase_seconds = 15; day_phase_seconds = 15; voting_seconds = 15; werewolf_count = 2 }
}
$roomId = $room.id
$roomCode = $room.room_code
Write-Host "`nRoom: $roomCode" -ForegroundColor Yellow

# Join and start
for ($i = 1; $i -lt $players.Count; $i++) {
    Invoke-Api -Method POST -Path "/rooms/join" -Token $players[$i].Token -Body @{ room_code = $roomCode } | Out-Null
}
foreach ($p in $players) {
    Invoke-Api -Method POST -Path "/rooms/$roomId/ready" -Token $p.Token -Body @{ ready = $true } | Out-Null
}
$gameStart = Invoke-Api -Method POST -Path "/rooms/$roomId/start" -Token $players[0].Token
$sessionId = $gameStart.session_id
Write-Host "Game Started: $sessionId" -ForegroundColor Magenta

# Discover roles
$allPlayerObjs = @()
$wolves = @()
$victims = @()

foreach ($p in $players) {
    $myState = Invoke-Api -Method GET -Path "/games/$sessionId" -Token $p.Token
    $myPlayerStruct = $myState.players | Where-Object { $_.user_id -eq $p.UserId }
    
    $pObj = @{
        GamePlayerId = $myPlayerStruct.id
        Name = $p.Name
        Token = $p.Token
        Role = $myPlayerStruct.role
        Team = $myPlayerStruct.team
    }
    $allPlayerObjs += $pObj
    
    if ($myPlayerStruct.role -eq "werewolf") { $wolves += $pObj }
    elseif ($myPlayerStruct.role -in @("villager", "bodyguard", "witch", "seer", "cupid")) { $victims += $pObj }
    
    Write-Host "  $($p.Name) is $($myPlayerStruct.role)" -ForegroundColor Gray
}

if ($wolves.Count -ne 2) {
    Write-Host "`n✗ ERROR: Need exactly 2 werewolves, got $($wolves.Count)" -ForegroundColor Red
    exit 1
}

if ($victims.Count -lt 2) {
    Write-Host "`n✗ ERROR: Need at least 2 non-werewolves, got $($victims.Count)" -ForegroundColor Red
    exit 1
}

# Wait for night
$gameState = Wait-ForPhase -SessionId $sessionId -TargetPhase "night_0" -Token $players[0].Token

Write-Host "`n╔═════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║              SPLIT VOTE SCENARIO                        ║" -ForegroundColor Cyan
Write-Host "╚═════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

Write-Host "`nWerewolf Pack:" -ForegroundColor Red
Write-Host "  • $($wolves[0].Name)" -ForegroundColor Red
Write-Host "  • $($wolves[1].Name)" -ForegroundColor Red

Write-Host "`nVictim Options:" -ForegroundColor Yellow
Write-Host "  • Option A: $($victims[0].Name)" -ForegroundColor Yellow
Write-Host "  • Option B: $($victims[1].Name)" -ForegroundColor Yellow

Write-Host "`n[SCENARIO] Werewolves disagree on target:" -ForegroundColor Magenta
Write-Host "  $($wolves[0].Name) votes to kill $($victims[0].Name)" -ForegroundColor DarkRed
Invoke-Api -Method POST -Path "/games/$sessionId/action" -Token $wolves[0].Token -Body @{
    action_type = "werewolf_vote"
    target_id = $victims[0].GamePlayerId
} | Out-Null
Write-Host "    ✓ Vote cast" -ForegroundColor Green

Write-Host "  $($wolves[1].Name) votes to kill $($victims[1].Name)" -ForegroundColor DarkRed
Invoke-Api -Method POST -Path "/games/$sessionId/action" -Token $wolves[1].Token -Body @{
    action_type = "werewolf_vote"
    target_id = $victims[1].GamePlayerId
} | Out-Null
Write-Host "    ✓ Vote cast" -ForegroundColor Green

Write-Host "`n[RESULT] Checking what the backend decides..." -ForegroundColor Cyan

# Wait for day phase to see the result
$gameState = Wait-ForPhase -SessionId $sessionId -TargetPhase "day_discussion" -Token $players[0].Token

# Check deaths
$deadPlayers = @()
foreach ($p in $allPlayerObjs) {
    $updated = $gameState.players | Where-Object { $_.id -eq $p.GamePlayerId }
    if ($updated -and -not $updated.is_alive) {
        $deadPlayers += $p
    }
}

Write-Host "`n╔═════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
Write-Host "║                 VERDICT                                 ║" -ForegroundColor Yellow
Write-Host "╚═════════════════════════════════════════════════════════╝" -ForegroundColor Yellow

if ($deadPlayers.Count -eq 0) {
    Write-Host "`nNO ONE DIED!" -ForegroundColor Green
    Write-Host "When werewolves split their votes (1-1 tie), the backend:" -ForegroundColor Yellow
    Write-Host "  • Picks ONE target (likely first in database order)" -ForegroundColor Yellow
    Write-Host "  • OR requires MAJORITY to kill (2 wolves need to agree)" -ForegroundColor Yellow
    Write-Host "`nIn this case: TIE = NO KILL (might be protected or Night 0 rule)" -ForegroundColor Cyan
} elseif ($deadPlayers.Count -eq 1) {
    $victim = $deadPlayers[0]
    Write-Host "`nVICTIM: $($victim.Name) died!" -ForegroundColor Red
    
    if ($victim.GamePlayerId -eq $victims[0].GamePlayerId) {
        Write-Host "Backend chose: $($wolves[0].Name)'s target ($($victims[0].Name))" -ForegroundColor Yellow
    } elseif ($victim.GamePlayerId -eq $victims[1].GamePlayerId) {
        Write-Host "Backend chose: $($wolves[1].Name)'s target ($($victims[1].Name))" -ForegroundColor Yellow
    } else {
        Write-Host "Unexpected victim!" -ForegroundColor Red
    }
    
    Write-Host "`nCONCLUSION:" -ForegroundColor Cyan
    Write-Host "  When werewolves vote for DIFFERENT targets (1-1 tie)," -ForegroundColor White
    Write-Host "  the backend uses the SQL 'ORDER BY vote_count DESC LIMIT 1'" -ForegroundColor White
    Write-Host "  which picks ONE target (likely based on database order)." -ForegroundColor White
} else {
    Write-Host "`nMULTIPLE DEATHS: $($deadPlayers.Name -join ', ')" -ForegroundColor Red
    Write-Host "Unexpected: Both targets died (shouldn't happen on split vote)" -ForegroundColor Red
}

Write-Host "`n✓ Test complete!" -ForegroundColor Green
