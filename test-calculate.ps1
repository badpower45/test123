# Test calculate-daily-salary function
Write-Host "Calling calculate-daily-salary for empp..." -ForegroundColor Cyan

$uri = "https://bbxuyuaemigrqsvsnxkj.supabase.co/functions/v1/calculate-daily-salary"
$apiKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJieHV5dWFlbWlncnFzdnNueGtqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzA5NzY2NzEsImV4cCI6MjA0NjU1MjY3MX0.shsuWES_CYcluj77ao5P_MK0Br5vHBxKpeSVqmfPI"
$headers = @{
    "Authorization" = "Bearer $apiKey"
    "Content-Type" = "application/json"
}
$body = @{
    employee_id = "empp"
    recalculate_period = $true
} | ConvertTo-Json

try {
    $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body
    Write-Host "Success!" -ForegroundColor Green
    $response | ConvertTo-Json -Depth 10
} catch {
    Write-Host "Error: $_" -ForegroundColor Red
    $_.Exception.Response
}
