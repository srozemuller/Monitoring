# Input bindings are passed in via param block.
param($Timer)

# The 'IsPastDue' property is 'true' when the current function invocation is later than scheduled.
if ($Timer.IsPastDue) {
    Write-Host "PowerShell timer is running late!"
}


function Get-InfoFromAI {
    param(
        [Parameter(Mandatory = $true)]
        [string]$content
    )
    $openAIHeader = @{
        'api-key'      = $env:openAIKey
        'Content-Type' = "application/json"
    }
    $body = @"
{
        "temperature": 0.7,
        "top_p": 0.95,
        "frequency_penalty": 0,
        "presence_penalty": 0,
        "max_tokens": 1000,
        "stop": null,
        "messages":  [
            {
                "role": "user",
                "content": "Based on the json content give me the second highest os version under the devices object and the current defined Os version. Then tell me if the current defined Os version matches the second highest os version. If not, then tell me what the defined Os version should be. surround the defined OS version with <>. Give me the policy name that is updated $($($content).Replace('"','\"'))"
            }
        ]
        }
"@
    $openAIResponse = Invoke-RestMethod -Method post -uri $env:openAIUrl -Headers $openAIHeader -Body $body
    return $openAIResponse
}


# Connect to Azure using the system assigned identity
Connect-AzAccount -Identity
$headers = @{"X-IDENTITY-HEADER" = $env:IDENTITY_HEADER }
$ProgressPreference = "SilentlyContinue"
$graphUrl = "https://graph.microsoft.com"
$token = Get-AzAccessToken -ResourceUrl $graphUrl
$graphHeaders = @{
    'Content-Type' = 'application/json'
    Authorization  = "Bearer {0}" -f $token.token
}

function Get-ActiveAssignedFilters {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$IntuneDeviceId,

        [Parameter()]
        [string]$FilterId
    )
    $activeFiltersPerDevice = [System.Collections.ArrayList]::new()
    # Get the assigned user ID from the device
    $usersUrl = "{0}/beta//deviceManagement/managedDevices/{1}/users" -f $graphUrl, $device.id
    $user = (Invoke-WebRequest -Uri $usersUrl -Method Get -Headers $graphHeaders | ConvertFrom-Json).value
    $requestParams = @{
        uri     = "{0}/beta/deviceManagement/assignmentFilters('{1}')/payloads" -f $graphUrl, $FilterId
        method  = "GET"
        headers = $graphHeaders
    }
    $assignedFilters = (Invoke-WebRequest @requestParams | ConvertFrom-Json).value
    $assignedFilters | Where-Object { $_.payloadType -eq 'deviceConfigurationAndCompliance' } | ForEach-Object {
        $payLoadId = $_.payloadId
        $payLoadId
        $filterCheckBody = @{
            "managedDeviceId" = $IntuneDeviceId
            "payloadId"       = $payLoadId # Based on the returned JSON, this is the PolicyId
            "userId"          = $user.id
        }
        $activeFilterParam = @{
            uri     = "https://graph.microsoft.com/beta/deviceManagement/getAssignmentFiltersStatusDetails"
            method  = "POST"
            body    = $filterCheckBody | ConvertTo-Json
            headers = $graphHeaders
        }
        $activeFiltersReq = Invoke-WebRequest @activeFilterParam | ConvertFrom-Json
        $activeFiltersReq
        if (($activeFiltersReq.evalutionSummaries) -and ($activeFiltersReq.evalutionSummaries.assignmentFilterType -eq "include") -and ($activeFiltersReq.evalutionSummaries.evaluationResult -eq "match")) {
            $activeFilters = [PSCustomObject]@{
                deviceId          = $activeFiltersReq.managedDeviceId
                activeFilters     = $activeFiltersReq.evalutionSummaries.assignmentFilterId
                activeFiltersName = $activeFiltersReq.evalutionSummaries.assignmentFilterDisplayName
            }
            $activeFiltersPerDevice.Add($activeFilters) >> $null
        }
    }
    return $activeFiltersPerDevice
}

try {
    $compliancePoliciesUrl = "{0}/beta//deviceManagement/deviceCompliancePolicies?`$filter=isof('microsoft.graph.windows10CompliancePolicy')&`$expand=assignments" -f $graphUrl
    $compliancePolicies = (Invoke-WebRequest -Uri $compliancePoliciesUrl -Method Get -Headers $graphHeaders | ConvertFrom-Json).value
    $compliancePolicies = $compliancePolicies | Where-Object { ($_.osMinimumVersion) -and $_.assignments }
}
catch {
    Throw "Unable to get compliance policies from Intune"
}

if ($null -ne $compliancePolicies) {
    $compliancePolicies | ForEach-Object {
        $compliancePolicy = $_
        $compliancePolicyAndDevices = [System.Collections.ArrayList]::new()
        # Search for the assigned filters for each compliance policy and return the devices that match the filter that is assigned to the compliance policy.
        Write-Information -InformationAction Continue -Message "Found $($compliancePolicies.count) compliance policies, checking for assigned filters"
        try {
            $devicesUrl = "{0}/beta//deviceManagement/managedDevices" -f $graphUrl
            $devices = (Invoke-WebRequest -Uri $devicesUrl -Method Get -Headers $graphHeaders | ConvertFrom-Json).value
            $devicesAndMatchingFilters = [System.Collections.ArrayList]::new()
            $devices | ForEach-Object {
                $device = $_
                $filterInfo = Get-ActiveAssignedFilters -IntuneDeviceId $device.id -FilterId $compliancePolicies.assignments.target.deviceAndAppManagementAssignmentFilterId
                $deviceFilter = [PSCustomObject]@{
                    device    = $device.id
                    filter    = $filterInfo
                    osVersion = $device.osVersion
                }
                $devicesAndMatchingFilters.Add($deviceFilter) >> $null
            }
        }
        catch {
            Throw "Unable to get devices from Intune"
        }
        try {
            $compliancePolicy.osMinimumVersion = (Select-String -Pattern '(?<=\<)(.*?)(?=\>)' -InputObject $aiInfo.choices[0].message.content).Matches.Value
            $compliancePolicy.PSObject.Properties.Remove('assignments')
            $compliancePoliciesUrl = "{0}/beta/deviceManagement/deviceCompliancePolicies/{1}" -f $graphUrl, $compliancePolicyAndDevices.policy
            Invoke-WebRequest -Uri $compliancePoliciesUrl -Method PATCH -Headers $graphHeaders -Body ($compliancePolicy | ConvertTo-Json -Depth 10)

            $policyInfo = [PSCustomObject]@{
                policy           = $_.id
                name             = $_.displayName
                definedOsVersion = $_.osMinimumVersion
                devices          = $devicesAndMatchingFilters
            }
        }
        catch {
            Throw "Unable to update compliance policy $($compliancePolicy.displayName) in Intune"
        }
        $compliancePolicyAndDevices.Add($policyInfo) >> $null
        $aiInfo = Get-InfoFromAI -content $($compliancePolicyAndDevices | ConvertTo-Json -Depth 10 -Compress)
    }
    $cardBody = @"
{
    "type":"message",
    "attachments":[
       {
          "contentType":"application/vnd.microsoft.card.adaptive",
          "contentUrl":null,
          "content":{
             "`$schema":"http://adaptivecards.io/schemas/adaptive-card.json",
             "type":"AdaptiveCard",
             "version":"1.4",
             "body":[
                 {
                 "type": "TextBlock",
                 "text": "$($($aiInfo.choices[0].message.content).Replace('"','**').Replace("`n"," "))",
                 "wrap": true
                 }
             ],
          "msteams": {
            "width": "Full"
        }
          }
       }
    ]
}
"@
    Invoke-RestMethod -Method post -uri $env:teamsUrl -body $cardBody -ContentType 'application/json'
}
else {
    Throw "No compliance policies found in Intune, so nothing that can be compared"
}

