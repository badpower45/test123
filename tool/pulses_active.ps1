param(
  [string]$HostBase = "http://localhost:5000",
  [string]$EmployeeId = "EMP_MAADI"
)

$resp = Invoke-RestMethod -Uri "$HostBase/api/pulses/active/$EmployeeId" -Method Get
$resp | ConvertTo-Json -Depth 5
