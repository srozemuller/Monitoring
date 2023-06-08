# Input bindings are passed in via param block.
param($Request)

# Get the current universal time in the default string format.
$currentUTCtime = (Get-Date).ToUniversalTime()

# The 'IsPastDue' property is 'true' when the current function invocation is later than scheduled.
if ($Timer.IsPastDue) {
    Write-Host "PowerShell timer is running late!"
}
Connect-AzAccount -Identity
$headers = @{"X-IDENTITY-HEADER" = $env:IDENTITY_HEADER }
$ProgressPreference = "SilentlyContinue"
$response = Invoke-WebRequest -UseBasicParsing -Uri "$($env:IDENTITY_ENDPOINT)?resource=https://api.loganalytics.io&api-version=2019-08-01" -Headers $headers
$token = ($response.Content | Convertfrom-json).access_token
$monitorHeaders = @{
    'Content-Type' = 'application/json'
    Authorization  = "Bearer {0}" -f $token
}

$laUri = "https://api.loganalytics.io/v1/workspaces/3c053b59-ac34-4c93-9781-641890890189/query?query=AuditLogs%0A%7C%20where%20OperationName%20%3D%3D%20%27Update%20conditional%20access%20policy%27%0A%7C%20project%20TimeGenerated%2C%20OperationName%2C%20TargetResources%2C%20InitiatedBy%7C%20where%20tostring%28OperationName%29%20%3D%3D%20%40%27Update%20conditional%20access%20policy%27&timespan=2023-06-07T20%3a33%3a42.0000000Z%2f2023-06-07T20%3a48%3a42.0000000Z"
$results = Invoke-RestMethod -uri $laUri -Method get -Headers $monitorHeaders

"Rows"
$Request