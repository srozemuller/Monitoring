# Input bindings are passed in via param block.
param($Timer)

# Get the current West Europe time in the default string format.
$currentTime = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId( (Get-Date), 'W. Europe Standard Time').ToString('yyyy-MM-dd HH:mm:ss')
$informationPreference = 'Continue'


# The 'IsPastDue' property is 'true' when the current function invocation is later than scheduled.
if ($Timer.IsPastDue) {
    Write-Host "PowerShell timer is running late!"
}

# Write an information log with the current time.
Write-Host "PowerShell timer trigger function ran! TIME: $currentTime"

try {
    import-module .\Modules\mem-monitor-functions.psm1
}
catch {
    Write-Error "Functions module not found!"
    exit;
}
try {
    $authHeader = Get-AuthApiToken -resource $env:graphApiUrl
}
catch {
    Throw "No token received, $_"
}

try {
    Write-Information "Searching for security baselines"
    $getUrl = "https://graph.microsoft.com/beta/deviceManagement/intents?`$filter=contains(displayName,'baseline')%20or%20contains(displayName,'Baseline')"
    $results = Invoke-RestMethod -URI $getUrl -Method GET -Headers $authHeader
}
catch {
    Write-Error "Unable to request for security baselines, $_"
}
if ($results.value -gt 0) {
    try {
        $results.value | ForEach-Object {
            if ($_.IsAssigned) {
                Write-Information "$($_.DisplayName) is assigned"
            }
            else {
                Send-AlertToAdmin -Title "Security Baseline" -SubTitle "Profile not in use" -Description $($_.DisplayName)
            }
        }
    }
    catch {
        Write-Error "Got results, but not able to check security baselines. $_"
    }
}
else {
    Write-Warning "No baselines found, nothting to check. You should consider using one!"
}