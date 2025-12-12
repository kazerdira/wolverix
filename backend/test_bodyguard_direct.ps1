# Simple test: Login as Omega, join game, and try bodyguard action
$baseUrl = "http://localhost:8080/api/v1"

# Login as a player
$login = Invoke-RestMethod -Uri "$baseUrl/auth/login" -Method POST -Headers @{"Content-Type"="application/json"} -Body (@{username="Omega";password="secure123"}|ConvertTo-Json)

Write-Host "✓ Logged in as Omega" -ForegroundColor Green
Write-Host "  Token: $($login.access_token.Substring(0,50))..." -ForegroundColor Gray

# Get existing game sessions to find one in progress
$headers = @{
    "Content-Type" = "application/json"
    "Authorization" = "Bearer $($login.access_token)"
}

# Try to perform a bodyguard action (this will probably fail because no active game, but we'll see the error)
try {
    $fakeSession = "4d96c306-8973-42da-94e8-8b89aab3be47"  # From last test run
    $fakeTarget = "00000000-0000-0000-0000-000000000001"
    
    $body = @{
        action_type = "bodyguard_protect"
        target_id = $fakeTarget
    } | ConvertTo-Json
    
    Write-Host "`nAttempting bodyguard action..." -ForegroundColor Cyan
    Write-Host "  URL: POST $baseUrl/games/$fakeSession/action" -ForegroundColor Gray
    Write-Host "  Body: $body" -ForegroundColor Gray
    
    $result = Invoke-RestMethod -Uri "$baseUrl/games/$fakeSession/action" -Method POST -Headers $headers -Body $body
    Write-Host "✓ Action accepted!" -ForegroundColor Green
    Write-Host "Result: $result"
} catch {
    Write-Host "✗ Action failed" -ForegroundColor Red
    Write-Host "  Status: $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Yellow
    Write-Host "  Message: $($_.Exception.Message)" -ForegroundColor Yellow  
    Write-Host "  Response: $($_.ErrorDetails.Message)" -ForegroundColor Yellow
}
