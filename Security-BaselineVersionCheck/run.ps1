# Input bindings are passed in via param block.
param($Timer)

# Get the current West Europe time in the default string format.
$currentTime = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId( (Get-Date), 'W. Europe Standard Time').ToString('yyyy-MM-dd HH:mm:ss')
$informationPreference = 'Continue'
$checkDate = (Get-Date).AddDays($env:backInDays)
$env:graphApiUrl = "https://graph.microsoft.com"

# Write an information log with the current time.
Write-Output "PowerShell timer trigger function ran! TIME: $currentTime"
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
    $getUrl = "{0}/beta/deviceManagement/templates?$filter=(templateType%20eq%20'securityBaseline')%20or%20(templateType%20eq%20'advancedThreatProtectionSecurityBaseline')%20or%20(templateType%20eq%20'microsoftEdgeSecurityBaseline')%20or%20(templateType%20eq%20'cloudPC')" -f $env:graphApiUrl
    $results = Invoke-RestMethod -URI $getUrl -Method GET -Headers $authHeader
}
catch {
    Write-Error "Unable to request for security baselines, $_"
}

if ($results.value.length -gt 0) {
    try {
        $results.value | ForEach-Object {
            if (($_.IntentCount -gt 0) -and ($_.PublishedDateTime -gt $checkDate) ) {
                Write-Warning "Security Baseline $($_.DisplayName) has a new version published at $($_.PublishedDateTime)"
                Send-AlertToAdmin -Title "Security Baseline" -SubTitle "New version available" -Description "New version with date $(Get-Date)"
            }
            else {
                Write-Information "Security Baseline $($_.DisplayName) is most recent version"
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