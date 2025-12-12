$ErrorActionPreference = "Stop"
$baseUrl = "http://localhost:8080/api/v1"

function Invoke-Api {
    param(
        [string]$Method,
        [string]$Path,
        [hashtable]$Body = @{},
        [string]$Token = $null
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
        Write-Host "Error calling $Path : $($_.Exception.Message)" -ForegroundColor Red
        
        if ($_.Exception.Response) {
            try {
                # Try to read content from HttpResponseMessage (PowerShell Core)
                if ($_.Exception.Response.Content) {
                    $body = $_.Exception.Response.Content.ReadAsStringAsync().Result
                    Write-Host "Response Body: $body" -ForegroundColor Red
                }
                # Fallback for WebException (Windows PowerShell)
                elseif ($_.Exception.Response.GetResponseStream) {
                    $reader = New-Object System.IO.StreamReader $_.Exception.Response.GetResponseStream()
                    Write-Host "Response Body: $($reader.ReadToEnd())" -ForegroundColor Red
                }
            } catch {
                Write-Host "Could not read response body: $($_.Exception.Message)" -ForegroundColor DarkRed
            }
        }
        throw
    }
}

Write-Host "=== 1. Registering 6 Players ===" -ForegroundColor Cyan
$players = @()
$names = @("alice", "bob", "charlie", "diana", "eve", "frank")

foreach ($name in $names) {
    $res = Invoke-Api -Method POST -Path "/auth/register" -Body @{
        username = $name
        email = "$name@test.com"
        password = "password123"
    }
    $players += @{
        Name = $name
        Id = $res.user.id
        Token = $res.access_token
    }
    Write-Host "Registered $name (ID: $($res.user.id))" -ForegroundColor Green
}

$hostPlayer = $players[0]

Write-Host "`n=== 2. Creating Room ===" -ForegroundColor Cyan
$room = Invoke-Api -Method POST -Path "/rooms" -Token $hostPlayer.Token -Body @{
    name = "Test Scenario Room"
    max_players = 6
    is_private = $false
}
$roomId = $room.id
$roomCode = $room.room_code
Write-Host "Room Created: $roomId (Code: $roomCode)" -ForegroundColor Yellow

Write-Host "`n=== 3. Joining Room ===" -ForegroundColor Cyan
for ($i = 1; $i -lt $players.Count; $i++) {
    $p = $players[$i]
    $null = Invoke-Api -Method POST -Path "/rooms/join" -Token $p.Token -Body @{ room_code = $roomCode }
    Write-Host "$($p.Name) joined room" -ForegroundColor Green
}

Write-Host "`n=== 4. Setting Ready Status ===" -ForegroundColor Cyan
foreach ($p in $players) {
    $null = Invoke-Api -Method POST -Path "/rooms/$roomId/ready" -Token $p.Token -Body @{ ready = $true }
    Write-Host "$($p.Name) is ready" -ForegroundColor Green
}

Write-Host "`n=== 5. Starting Game ===" -ForegroundColor Cyan
$gameStart = Invoke-Api -Method POST -Path "/rooms/$roomId/start" -Token $hostPlayer.Token
$sessionId = $gameStart.session_id
Write-Host "Game Started! Session ID: $sessionId" -ForegroundColor Magenta

Write-Host "`n=== GAME SETUP COMPLETE ===" -ForegroundColor Cyan
Write-Host "Session ID: $sessionId"
Write-Host "Room ID:    $roomId"
Write-Host "`nPlayer Tokens:"
foreach ($p in $players) {
    Write-Host "$($p.Name): $($p.Token)"
}
