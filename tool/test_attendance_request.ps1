param(
  [string]$HostBase = "http://localhost:5000",
  [string]$EmployeeId = "EMP_MAADI"
)

function PostJson($url, $obj) {
  $body = $obj | ConvertTo-Json -Depth 5
  return Invoke-RestMethod -Method Post -Uri $url -ContentType 'application/json' -Body $body
}

function Test-Health($base) {
  try {
    $h = Invoke-RestMethod -Method Get -Uri ("$base/health") -TimeoutSec 3
    return $true
  } catch { return $false }
}

# Auto-detect host
if (-not (Test-Health $HostBase)) {
  if ($env:API_HOSTBASE) {
    Write-Warning "Local API not reachable, trying API_HOSTBASE=$($env:API_HOSTBASE)"
    $HostBase = $env:API_HOSTBASE
  }
}
if (-not (Test-Health $HostBase)) {
  $fallback = "http://16.171.208.249:5000"
  Write-Warning "API not reachable at $HostBase, trying fallback $fallback"
  $HostBase = $fallback
}
if (-not (Test-Health $HostBase)) {
  Write-Error "API not reachable. Please pass -HostBase http://<host>:5000"
  exit 1
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "   Test Attendance Request Flow" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 1. Request Check-in
Write-Host "1) Requesting check-in for $EmployeeId..." -ForegroundColor Yellow
try {
  $checkinReq = PostJson "$HostBase/api/attendance/request-checkin" @{
    employee_id = $EmployeeId
    requested_time = (Get-Date).ToString("o")
    reason = "Forgot to check in this morning"
  }
  Write-Host "   Success: Check-in request created: ID=$($checkinReq.request.id)" -ForegroundColor Green
  Write-Host "      Status: $($checkinReq.request.status)" -ForegroundColor White
  Write-Host "      Type: $($checkinReq.request.requestType)" -ForegroundColor White
  Write-Host "      Reason: $($checkinReq.request.reason)" -ForegroundColor White
  $checkinId = $checkinReq.request.id
} catch {
  Write-Error "Failed to create check-in request: $_"
  exit 1
}

Write-Host ""

# 2. Check Manager Dashboard
Write-Host "2) Checking Manager Dashboard..." -ForegroundColor Yellow
try {
  $dashboard = Invoke-RestMethod -Method Get -Uri "$HostBase/api/manager/dashboard"
  Write-Host "   Success: Dashboard loaded" -ForegroundColor Green
  Write-Host "      Total Pending Requests: $($dashboard.dashboard.summary.totalPendingRequests)" -ForegroundColor White
  Write-Host "      Attendance Requests: $($dashboard.dashboard.summary.attendanceRequestsCount)" -ForegroundColor White
  Write-Host "      Leave Requests: $($dashboard.dashboard.summary.leaveRequestsCount)" -ForegroundColor White
  Write-Host "      Advances: $($dashboard.dashboard.summary.advancesCount)" -ForegroundColor White
  Write-Host "      Absences: $($dashboard.dashboard.summary.absencesCount)" -ForegroundColor White
  Write-Host "      Break Requests: $($dashboard.dashboard.summary.breakRequestsCount)" -ForegroundColor White
  
  Write-Host ""
  Write-Host "   Attendance Requests Details:" -ForegroundColor Cyan
  if ($dashboard.dashboard.attendanceRequests.Count -eq 0) {
    Write-Host "      WARNING: NO ATTENDANCE REQUESTS FOUND!" -ForegroundColor Red
  } else {
    foreach ($req in $dashboard.dashboard.attendanceRequests) {
      Write-Host "      - ID: $($req.id)" -ForegroundColor White
      Write-Host "        Employee: $($req.employeeName)" -ForegroundColor White
      Write-Host "        Type: $($req.requestType)" -ForegroundColor White
      Write-Host "        Status: $($req.status)" -ForegroundColor White
      Write-Host "        Reason: $($req.reason)" -ForegroundColor White
    }
  }
} catch {
  Write-Error "Failed to load dashboard: $_"
  exit 1
}

Write-Host ""

# 3. Approve the request
Write-Host "3) Approving check-in request..." -ForegroundColor Yellow
try {
  $approve = PostJson "$HostBase/api/attendance/requests/$checkinId/review" @{
    action = "approve"
    reviewer_id = "MGR_MAADI"
    notes = "Approved - reason confirmed"
  }
  Write-Host "   Success: Request approved!" -ForegroundColor Green
  Write-Host "      $($approve.message)" -ForegroundColor White
} catch {
  Write-Error "Failed to approve request: $_"
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "   Test Completed Successfully!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
