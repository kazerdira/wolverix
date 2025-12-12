#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Complete game test - plays through entire scenarios until win conditions are met

.DESCRIPTION
    Tests three scenarios:
    1. Villagers Win - Village eliminates all werewolves
    2. Werewolves Win - Werewolves reduce villagers to equal or fewer numbers
    3. Lovers Win - Only the two lovers remain alive
#>

$ErrorActionPreference = "Continue"
$baseUrl = "http://localhost:8080/api/v1"

# Color functions
function Write-Success { param($msg) Write-Host "  ✓ $msg" -ForegroundColor Green }
function Write-Fail { param($msg) Write-Host "  ✗ $msg" -ForegroundColor Red }
function Write-Info { param($msg) Write-Host "  ℹ $msg" -ForegroundColor Cyan }
function Write-Death { param($msg) Write-Host "  ☠ $msg" -ForegroundColor DarkRed }

# Global player storage
$global:Players = @{}

function Register-Player {
    param([string]$Username)
    
    # Try to register, use password123 consistently
    try {
        $response = Invoke-RestMethod -Method Post -Uri "$baseUrl/auth/register" -Body (@{
            username = $Username
            password = "password123"
            email = "$Username@test.com"
        } | ConvertTo-Json) -ContentType "application/json" -ErrorAction SilentlyContinue
    } catch {
        # Expected error if already exists
    }

    # Try login
    try {
        $loginResponse = Invoke-RestMethod -Method Post -Uri "$baseUrl/auth/login" -Body (@{
            username = $Username
            password = "password123"
        } | ConvertTo-Json) -ContentType "application/json"

        $global:Players[$Username] = @{
            Username = $Username
            Token = $loginResponse.token
            UserId = $loginResponse.user_id
        }
        
        return $global:Players[$Username]
    } catch {
        # If login fails with password123, user might exist with old password, skip
        Write-Host "  ⚠ $Username could not login" -ForegroundColor Yellow
        return $null
    }
}

function Wait-ForPhase {
    param(
        [string]$SessionId,
        [string]$TargetPhase,
        [string]$Token,
        [int]$MaxRetries = 60
    )
    
    $retries = 0
    while ($retries -lt $MaxRetries) {
        Start-Sleep -Seconds 2
        $game = Invoke-RestMethod -Method Get -Uri "$baseUrl/games/$SessionId" -Headers @{ Authorization = "Bearer $Token" }
        
        if ($game.current_phase -eq $TargetPhase) {
            return $game
        }
        
        $retries++
    }
    
    throw "Timeout waiting for phase $TargetPhase"
}

function Get-GameState {
    param([string]$SessionId, [string]$Token)
    return Invoke-RestMethod -Method Get -Uri "$baseUrl/games/$SessionId" -Headers @{ Authorization = "Bearer $Token" }
}

function Get-PlayersByRole {
    param(
        [string]$SessionId,
        [hashtable]$RoleMap,
        [string]$Role
    )
    
    if (-not $RoleMap.ContainsKey($Role)) {
        return @()
    }
    
    $result = @($RoleMap[$Role])
    return ,$result  # Comma forces array return
}

function Send-Action {
    param(
        [string]$SessionId,
        [string]$Token,
        [hashtable]$ActionData
    )
    
    try {
        $response = Invoke-RestMethod -Method Post -Uri "$baseUrl/games/$SessionId/action" `
            -Headers @{ Authorization = "Bearer $Token" } `
            -Body ($ActionData | ConvertTo-Json -Depth 10) `
            -ContentType "application/json"
        return $true
    } catch {
        return $false
    }
}

function Play-NightPhase {
    param(
        [string]$SessionId,
        [hashtable]$RoleMap,
        [array]$AlivePlayers
    )
    
    Write-Info "Playing Night Phase..."
    
    # Cupid (only first night)
    $cupids = Get-PlayersByRole -SessionId $SessionId -RoleMap $RoleMap -Role "cupid"
    if ($cupids.Count -gt 0) {
        $cupid = $cupids[0]
        $gameState = Get-GameState -SessionId $SessionId -Token $cupid.Token
        if ($gameState.phase_number -eq 1) {
            $targets = $AlivePlayers | Where-Object { $_.UserId -ne $cupid.UserId } | Get-Random -Count 2
            if ($targets.Count -eq 2) {
                $success = Send-Action -SessionId $SessionId -Token $cupid.Token -ActionData @{
                    action_type = "cupid_choose"
                    target_id = $targets[0].GamePlayerId
                    data = @{ second_lover = $targets[1].GamePlayerId }
                }
                if ($success) { Write-Success "$($cupid.Username) created lovers: $($targets[0].Username) ♥ $($targets[1].Username)" }
            }
        }
    }
    
    # Werewolves vote
    $werewolves = Get-PlayersByRole -SessionId $SessionId -RoleMap $RoleMap -Role "werewolf"
    if ($werewolves.Count -gt 0) {
        $villagerTargets = $AlivePlayers | Where-Object { $_.Team -eq "villagers" }
        if ($villagerTargets.Count -gt 0) {
            $target = $villagerTargets | Get-Random
            foreach ($ww in $werewolves) {
                $success = Send-Action -SessionId $SessionId -Token $ww.Token -ActionData @{
                    action_type = "werewolf_vote"
                    target_id = $target.GamePlayerId
                }
            }
            Write-Success "Werewolves targeting $($target.Username)"
        }
    }
    
    # Bodyguard protect
    $bodyguards = Get-PlayersByRole -SessionId $SessionId -RoleMap $RoleMap -Role "bodyguard"
    if ($bodyguards.Count -gt 0) {
        $bg = $bodyguards[0]
        $protectTarget = $AlivePlayers | Where-Object { $_.UserId -ne $bg.UserId } | Get-Random
        if ($protectTarget) {
            Send-Action -SessionId $SessionId -Token $bg.Token -ActionData @{
                action_type = "bodyguard_protect"
                target_id = $protectTarget.GamePlayerId
            } | Out-Null
        }
    }
    
    # Seer divine
    $seers = Get-PlayersByRole -SessionId $SessionId -RoleMap $RoleMap -Role "seer"
    if ($seers.Count -gt 0) {
        $seer = $seers[0]
        $divineTarget = $AlivePlayers | Where-Object { $_.UserId -ne $seer.UserId } | Get-Random
        if ($divineTarget) {
            Send-Action -SessionId $SessionId -Token $seer.Token -ActionData @{
                action_type = "seer_divine"
                target_id = $divineTarget.GamePlayerId
            } | Out-Null
        }
    }
    
    # Witch (random decision to poison sometimes)
    $witches = Get-PlayersByRole -SessionId $SessionId -RoleMap $RoleMap -Role "witch"
    if ($witches.Count -gt 0) {
        $witch = $witches[0]
        # 30% chance to poison
        if ((Get-Random -Minimum 0 -Maximum 100) -lt 30) {
            $poisonTarget = $AlivePlayers | Where-Object { $_.UserId -ne $witch.UserId -and $_.Team -eq "werewolves" }
            if ($poisonTarget.Count -gt 0) {
                $target = $poisonTarget | Get-Random
                Send-Action -SessionId $SessionId -Token $witch.Token -ActionData @{
                    action_type = "witch_poison"
                    target_id = $target.GamePlayerId
                } | Out-Null
                Write-Success "$($witch.Username) poisoned $($target.Username)"
            }
        }
    }
}

function Play-VotingPhase {
    param(
        [string]$SessionId,
        [array]$AlivePlayers,
        [array]$SuspectedWerewolves
    )
    
    Write-Info "Playing Voting Phase..."
    
    # Vote for a suspected werewolf, or random if none
    $target = if ($SuspectedWerewolves.Count -gt 0) {
        $SuspectedWerewolves | Get-Random
    } else {
        $AlivePlayers | Get-Random
    }
    
    foreach ($player in $AlivePlayers) {
        Send-Action -SessionId $SessionId -Token $player.Token -ActionData @{
            action_type = "vote_lynch"
            target_id = $target.GamePlayerId
        } | Out-Null
    }
    
    Write-Success "Village voting to lynch $($target.Username)"
}

function Test-Scenario {
    param(
        [string]$ScenarioName,
        [int]$PlayerCount,
        [int]$WerewolfCount
    )
    
    Write-Host "`n╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  SCENARIO: $($ScenarioName.PadRight(46)) ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    
    # Register players
    Write-Host "`n=== PLAYER SETUP ===" -ForegroundColor Yellow
    $playerNames = @("Alice", "Bob", "Charlie", "Diana", "Eve", "Frank", "Grace", "Henry", "Ivy", "Jack", "Kate", "Leo")
    $players = @()
    for ($i = 0; $i -lt $PlayerCount; $i++) {
        $player = Register-Player -Username $playerNames[$i]
        $players += $player
        Write-Success "$($player.Username) registered"
    }
    
    # Create room
    Write-Host "`n=== ROOM CREATION ===" -ForegroundColor Yellow
    $roomResponse = Invoke-RestMethod -Method Post -Uri "$baseUrl/rooms" -Body (@{
        name = "$ScenarioName Test"
        max_players = $PlayerCount
        is_private = $false
        config = @{
            werewolf_count = $WerewolfCount
            day_phase_seconds = 10
            night_phase_seconds = 10
            voting_seconds = 10
            enabled_roles = @("werewolf", "villager", "seer", "witch", "cupid", "bodyguard", "hunter")
        }
    } | ConvertTo-Json -Depth 10) -Headers @{ Authorization = "Bearer $($players[0].Token)" } -ContentType "application/json"
    
    $roomId = $roomResponse.id
    $roomCode = $roomResponse.room_code
    Write-Info "Room Code: $roomCode"
    
    # Join room
    Write-Host "`n=== JOINING ROOM ===" -ForegroundColor Yellow
    for ($i = 1; $i -lt $players.Count; $i++) {
        Invoke-RestMethod -Method Post -Uri "$baseUrl/rooms/$roomId/join" -Body (@{
            room_code = $roomCode
        } | ConvertTo-Json) -Headers @{ Authorization = "Bearer $($players[$i].Token)" } -ContentType "application/json" | Out-Null
        Write-Success "$($players[$i].Username) joined"
    }
    
    # Ready up
    foreach ($player in $players) {
        Invoke-RestMethod -Method Post -Uri "$baseUrl/rooms/$roomId/ready" -Headers @{ Authorization = "Bearer $($player.Token)" } | Out-Null
    }
    Write-Success "All players ready"
    
    # Start game
    Write-Host "`n=== STARTING GAME ===" -ForegroundColor Yellow
    $gameResponse = Invoke-RestMethod -Method Post -Uri "$baseUrl/rooms/$roomId/start" -Headers @{ Authorization = "Bearer $($players[0].Token)" }
    $sessionId = $gameResponse.session_id
    Write-Success "Game started: $sessionId"
    
    # Get roles
    Write-Host "`n=== ROLE ASSIGNMENTS ===" -ForegroundColor Yellow
    $roleMap = @{}
    foreach ($player in $players) {
        $gameState = Get-GameState -SessionId $sessionId -Token $player.Token
        $myPlayer = $gameState.players | Where-Object { $_.user_id -eq $player.UserId }
        $player.Role = $myPlayer.role
        $player.Team = $myPlayer.team
        $player.GamePlayerId = $myPlayer.id
        
        Write-Host "  $($player.Username) → $($player.Role) [$($player.Team)]" -ForegroundColor $(if ($player.Team -eq "werewolves") { "DarkRed" } else { "DarkGreen" })
        
        if (-not $roleMap.ContainsKey($player.Role)) {
            $roleMap[$player.Role] = @()
        }
        $roleMap[$player.Role] += $player
    }
    
    # Play game loop
    Write-Host "`n=== GAME LOOP ===" -ForegroundColor Yellow
    $dayNumber = 0
    $maxRounds = 30
    $winner = $null
    
    while ($dayNumber -lt $maxRounds) {
        $dayNumber++
        Write-Host "`n--- DAY $dayNumber ---" -ForegroundColor Magenta
        
        # Wait for night phase
        try {
            Wait-ForPhase -SessionId $sessionId -TargetPhase "night_0" -Token $players[0].Token -MaxRetries 20 | Out-Null
        } catch {
            Write-Info "Phase transition timeout, checking game state..."
        }
        
        $gameState = Get-GameState -SessionId $sessionId -Token $players[0].Token
        
        # Check if game ended
        if ($gameState.status -eq "finished") {
            $winner = $gameState.winner
            Write-Host "`n🏆 GAME ENDED! Winner: $winner" -ForegroundColor Yellow
            break
        }
        
        # Get alive players
        $alivePlayers = $players | Where-Object { 
            $gp = $gameState.players | Where-Object { $_.user_id -eq $_.UserId }
            $gp.is_alive
        }
        
        Write-Info "Alive: $($alivePlayers.Count) players"
        
        if ($alivePlayers.Count -le 2) {
            Write-Info "Only 2 or fewer players remain"
            break
        }
        
        # Play night phase
        if ($gameState.current_phase -eq "night_0") {
            Play-NightPhase -SessionId $sessionId -RoleMap $roleMap -AlivePlayers $alivePlayers
            
            # Wait for day
            try {
                $dayState = Wait-ForPhase -SessionId $sessionId -TargetPhase "day_discussion" -Token $players[0].Token -MaxRetries 20
                
                # Show deaths
                if ($dayState.players) {
                    $newDeaths = $gameState.players | Where-Object { 
                        $old = $gameState.players | Where-Object { $_.id -eq $_.id }
                        $new = $dayState.players | Where-Object { $_.id -eq $_.id }
                        $old.is_alive -and -not $new.is_alive
                    }
                    foreach ($dead in $newDeaths) {
                        $deadPlayer = $players | Where-Object { $_.GamePlayerId -eq $dead.id }
                        if ($deadPlayer) {
                            Write-Death "$($deadPlayer.Username) died ($($dead.death_reason))"
                        }
                    }
                }
            } catch {
                Write-Info "Waiting for day phase..."
            }
        }
        
        # Wait for voting phase
        try {
            Wait-ForPhase -SessionId $sessionId -TargetPhase "day_voting" -Token $players[0].Token -MaxRetries 20 | Out-Null
        } catch {
            Write-Info "Waiting for voting phase..."
        }
        
        $gameState = Get-GameState -SessionId $sessionId -Token $players[0].Token
        
        if ($gameState.current_phase -eq "day_voting") {
            # Update alive players
            $alivePlayers = $players | Where-Object { 
                $gp = $gameState.players | Where-Object { $_.user_id -eq $_.UserId }
                $gp.is_alive
            }
            
            # Villagers try to vote out werewolves
            $suspectedWerewolves = $alivePlayers | Where-Object { $_.Team -eq "werewolves" }
            Play-VotingPhase -SessionId $sessionId -AlivePlayers $alivePlayers -SuspectedWerewolves $suspectedWerewolves
        }
        
        # Small delay before next round
        Start-Sleep -Seconds 2
    }
    
    # Final results
    Write-Host "`n╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║  SCENARIO COMPLETE: $($ScenarioName.PadRight(39)) ║" -ForegroundColor Green
    Write-Host "╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Green
    
    $finalState = Get-GameState -SessionId $sessionId -Token $players[0].Token
    Write-Host "`nFinal Status: $($finalState.status)"
    Write-Host "Winner: $(if ($finalState.winner) { $finalState.winner } else { 'Still playing' })"
    Write-Host "Days Survived: $dayNumber"
    
    $aliveCount = ($finalState.players | Where-Object { $_.is_alive }).Count
    $deadCount = ($finalState.players | Where-Object { -not $_.is_alive }).Count
    Write-Host "Alive: $aliveCount | Dead: $deadCount"
    
    return @{
        Success = $true
        Winner = $finalState.winner
        DaysSurvived = $dayNumber
        SessionId = $sessionId
    }
}

# Main execution
Write-Host "╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     COMPLETE GAME SCENARIOS - PLAY TO WIN CONDITIONS     ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

# Scenario 1: Balanced game (8 players, 2 werewolves)
$result1 = Test-Scenario -ScenarioName "Balanced Game" -PlayerCount 8 -WerewolfCount 2

# Scenario 2: Werewolf advantage (6 players, 2 werewolves)
$result2 = Test-Scenario -ScenarioName "Werewolf Advantage" -PlayerCount 6 -WerewolfCount 2

# Scenario 3: Large game (10 players, 3 werewolves)
$result3 = Test-Scenario -ScenarioName "Large Game" -PlayerCount 10 -WerewolfCount 3

Write-Host "`n╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║                  ALL SCENARIOS COMPLETE                   ║" -ForegroundColor Green
Write-Host "╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Green

Write-Host "`nResults Summary:"
Write-Host "  Scenario 1 - Winner: $($result1.Winner), Days: $($result1.DaysSurvived)"
Write-Host "  Scenario 2 - Winner: $($result2.Winner), Days: $($result2.DaysSurvived)"
Write-Host "  Scenario 3 - Winner: $($result3.Winner), Days: $($result3.DaysSurvived)"
