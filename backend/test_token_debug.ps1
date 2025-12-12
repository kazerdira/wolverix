$baseUrl = "http://localhost:8080/api/v1"

# Register and login
$login = Invoke-RestMethod -Uri "$baseUrl/auth/login" -Method POST -Headers @{"Content-Type"="application/json"} -Body (@{username="Alpha";password="secure123"}|ConvertTo-Json)

Write-Host "User ID: $($login.user.id)"
Write-Host "Token Length: $($login.access_token.Length)"
Write-Host "Token: $($login.access_token.Substring(0, 50))..."

# Try to get game state with this token
$headers = @{
    "Content-Type" = "application/json"
    "Authorization" = "Bearer $($login.access_token)"
}

try {
    $result = Invoke-RestMethod -Uri "$baseUrl/games/00000000-0000-0000-0000-000000000000" -Method GET -Headers $headers
    Write-Host "✓ Token accepted by middleware" -ForegroundColor Green
} catch {
    Write-Host "✗ Token rejected: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Response: $($_.ErrorDetails.Message)"
}
