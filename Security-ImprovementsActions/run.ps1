# Input bindings are passed in via param block.
param($Request)

# Get the current universal time in the default string format.
$currentUTCtime = (Get-Date).ToUniversalTime()

# The 'IsPastDue' property is 'true' when the current function invocation is later than scheduled.
if ($Timer.IsPastDue) {
    Write-Host "PowerShell timer is running late!"
}
$graphUrl = "https://graph.microsoft.com"
$monitorResource = "https://monitor.azure.com//.default"
Connect-AzAccount -Identity

$allobjects = [System.Collections.ArrayList]@()


$token = (Get-AzAccessToken -ResourceTypeName MSGraph ).token

$headers = @{"X-IDENTITY-HEADER" = $env:IDENTITY_HEADER }
$ProgressPreference = "SilentlyContinue"
$response = Invoke-WebRequest -UseBasicParsing -Uri "$($env:IDENTITY_ENDPOINT)?resource=https://monitor.azure.com&api-version=2019-08-01" -Headers $headers
#$response.RawContent

($response.Content | Convertfrom-json).access_token
$graphHeader = @{
    'Content-Type' = 'application/json'
    Authorization  = "Bearer {0}" -f $token
}
$monitorHeaders = @{
    'Content-Type' = 'application/json'
    Authorization  = "Bearer {0}" -f ($response.Content | Convertfrom-json).access_token
}

$improvementsParams = @{
    method  = "GET"
    uri     = "{0}/beta/security/secureScoreControlProfiles?`$filter=controlCategory eq 'Identity'" -f $graphUrl
    headers = $graphHeader
}
$improvements = Invoke-RestMethod @improvementsParams

ForEach ($pol in $improvements.value) {
    $pol.controlStateUpdates | ForEach-Object {
        $object = [PSCustomObject]@{
            Time            = $currentUTCtime
            PolicyId        = $pol.Id
            PolicyTitle     = $pol.Title
            Service         = $pol.Service
            State           = $_.State
            UpdatedBy       = $_.UpdatedBy
            UpdatedDateTime = $_.UpdatedDateTime
        }
        $allobjects.Add($object) | Out-Null 
    }
}

$uploadBody = $allobjects | ConvertTo-Json
$uri = "{0}/dataCollectionRules/{1}/streams/{2}?api-version=2021-11-01-preview" -f $env:ingestionUrl, $env:dcrId, $env:streamName
Write-Information "Send data to monitor" -InformationAction Continue
$uri

Invoke-RestMethod -Uri $uri -Method POST -Body $uploadBody -Headers $monitorHeaders