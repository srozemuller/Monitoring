# Input bindings are passed in via param block.
param($Timer)

# Get the current West Europe time in the default string format.
$currentTime = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId( (Get-Date), 'W. Europe Standard Time').ToString('yyyy-MM-dd HH:mm:ss')
$informationPreference = 'Continue'
$checkHours = (Get-Date).AddHours($env:backInHours)

# The 'IsPastDue' property is 'true' when the current function invocation is later than scheduled.
if ($Timer.IsPastDue) {
    Write-Host "PowerShell timer is running late!"
}

# Write an information log with the current time.
Write-Host "PowerShell timer trigger function ran! TIME: $currentTime"

try {
    if ($env:MSI_SECRET) {
        $azureAccount = Connect-AzAccount -Identity
        Write-Host "Is Managed Identity"
    }
    else {
        Write-Host "Function app is not a managed identity. Using app registration"
        $passwd = ConvertTo-SecureString $env:AppSecret -AsPlainText -Force
        $pscredential = New-Object System.Management.Automation.PSCredential($env:AppId, $passwd)
        $azureAccount = Connect-AzAccount -ServicePrincipal -Credential $pscredential
    }
    $accessToken = Get-AzAccessToken -ResourceUrl $env:graphApiUrl -DefaultProfile $azureAccount
}
catch {
    Write-error "Azure login failed with error: $($_.Exception.Message)"
} 

$authHeader = @{
    'Content-Type' = 'application/json'
    Authorization  = 'Bearer {0}' -f $accessToken.Token
}
$getUrl = "https://graph.microsoft.com/beta/deviceManagement/autopilotEvents?`$filter=((microsoft.graph.DeviceManagementAutopilotEvent/deploymentEndDateTime%20ge%20{0}) and deploymentState ne 'InProgress')" -f $checkHours
try {
    Write-Information "Searching for security baselines"
    $results = Invoke-RestMethod -URI $getUrl -Method GET -Headers $authHeader
}
catch {
    Write-Error "Unable to request for security baselines, $_"
}
if ($results.value.length -gt 0) {
    try {
        $results.value | ForEach-Object {
            Write-Information "Searching for device with serialnumber $($_.deviceSerialNumber)"
            $deviceStatusUrl = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities?`$filter=((contains(serialnumber,'{0}')))" -f $_.deviceSerialNumber
            $deviceResults = Invoke-RestMethod -URI $deviceStatusUrl -Method GET -Headers $authHeader
            if ($_.deploymentState -ne "success") {
                Write-Warning "Device with serialnumber $($_.deviceSerialNumber) is not enrolled succesfully, status is $($_.deploymentState) "
            }
            else {
                Write-Warning "Device with serialnumber $($_.deviceSerialNumber) is enrolled succesfully, duration is $($_.deploymentDuration) "
            }
        }
    }
    catch {
        Write-Error "Got results, but not able to check autopilot events. $_"
    }
}
else {
    Write-Warning "No autopilot events!"
}