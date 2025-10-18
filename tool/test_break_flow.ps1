param(
  [string]$HostBase = "http://localhost:5000",
  [string]$EmployeeId = "EMP_MAADI",
  [int]$Minutes = 15,
  [string]$ReviewerId = "MGR_MAADI"
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

# Auto-detect host: try provided, then env var, then AWS fallback
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

Write-Host "1) Create break request..."
try {
  $br = PostJson "$HostBase/api/breaks/request" @{ employee_id=$EmployeeId; duration_minutes=$Minutes }
  $breakId = $br.break.id
  Write-Host "   -> Break Id: $breakId Status: $($br.break.status)"
} catch {
  Write-Error "Failed to create break request at $HostBase. $_"; exit 1
}

Write-Host "2) Approve break..."
$approve = PostJson "$HostBase/api/breaks/$breakId/review" @{ action="approve"; manager_id=$ReviewerId }
Write-Host "   -> Status: $($approve.break.status) ApprovedBy: $($approve.break.approvedBy)"

Write-Host "3) Start break..."
$start = PostJson "$HostBase/api/breaks/$breakId/start" @{}
Write-Host "   -> Status: $($start.break.status) Start: $($start.break.startTime) End: $($start.break.endTime)"

Write-Host "4) End break..."
$end = PostJson "$HostBase/api/breaks/$breakId/end" @{}
Write-Host "   -> Status: $($end.break.status)"

