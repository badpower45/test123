param(
  [string]$HostBase = "http://localhost:5000",
  [string]$EmployeeId = "EMP_MAADI",
  [string]$Type = "check-in",
  [string]$Reason = "نسيت اسجل",
  [string]$ReviewerId = "MGR_MAADI"
)

function PostJson($url, $obj) {
  $body = $obj | ConvertTo-Json -Depth 5
  return Invoke-RestMethod -Method Post -Uri $url -ContentType 'application/json' -Body $body
}

$nowIso = (Get-Date).ToString('s') + 'Z'

if ($Type -eq 'check-in') {
  Write-Host "1) Send attendance check-in request..."
  $req = PostJson "$HostBase/api/attendance/request-checkin" @{ employee_id=$EmployeeId; requested_time=$nowIso; reason=$Reason }
  $reqId = $req.request.id
} else {
  Write-Host "1) Send attendance check-out request..."
  $req = PostJson "$HostBase/api/attendance/request-checkout" @{ employee_id=$EmployeeId; requested_time=$nowIso; reason=$Reason }
  $reqId = $req.request.id
}

Write-Host "2) Manager approves..."
$rev = PostJson "$HostBase/api/attendance/requests/$reqId/review" @{ action='approve'; reviewer_id=$ReviewerId; notes='ok' }
$rev | ConvertTo-Json -Depth 5
