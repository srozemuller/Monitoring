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
        "temperature": 0.1,
        "top_p": 0,
        "frequency_penalty": 0,
        "presence_penalty": 0,
        "max_tokens": 1000,
        "stop": null,
        "messages":  [
            {
                "role": "user",
                "content": "Based on the json content give me the the currentVersions array, order it ascending and pick the second highest. Tell me if the current osMinimumVersion matches the second highest os version from the array. If not, then tell me what the defined Os version should be. Surround the defined OS version with <> and which policy should be updated. Always return the compliancePolicyName. $($($content).Replace('"','\"'))"
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

function Get-MachinesPerFilters {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$FilterId
    )
    $activeDevicesPerFilter = [System.Collections.ArrayList]::new()
    # Get the assigned user ID from the device
    $filterReqParams = @{
        uri     = "{0}/beta/deviceManagement/assignmentFilters('{1}')" -f $graphUrl, $FilterId
        method  = "GET"
        headers = $graphHeaders
    }
    $filterReq = Invoke-WebRequest @filterReqParams | ConvertFrom-Json
    $filterInfo = @{
        "data" = @{
            "platform" = $filterReq.platform
            "rule"     = $filterReq.rule
            "skip"     = 0
        }
    }
    $activeDevicesFilterParam = @{
        uri     = "{0}/beta/deviceManagement/evaluateAssignmentFilter" -f $graphUrl
        method  = "POST"
        body    = $filterInfo | ConvertTo-Json
        headers = $graphHeaders
    }
    $activeFiltersReq = Invoke-WebRequest @activeDevicesFilterParam | ConvertFrom-Json
    $activeFiltersReq.values | ForEach-Object {
        $activeDevice = [PSCustomObject]@{
            deviceId  = $_[1]
            osVersion = $_[-3]
        }
        $activeDevicesPerFilter.Add($activeDevice) >> $null
    }
    $fullReturn = @{
        "filter"  = $filterReq
        "devices" = $activeDevicesPerFilter
    }
    return $fullReturn
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
        # Search for the assigned filters for each compliance policy and return the devices that match the filter that is assigned to the compliance policy.
        Write-Information -InformationAction Continue -Message "Found $($compliancePolicies.count) compliance policies, checking for assigned filters"
        try {
            $compliancePolicy = $_
            $filterInfo = Get-MachinesPerFilters -FilterId $compliancePolicy.assignments.target.deviceAndAppManagementAssignmentFilterId
            $filterResults = [PSCustomObject]@{
                compliancePolicyName = $compliancePolicy.displayName
                currentVersions      = $filterInfo.devices.osVersion | Select-Object -Unique
                osMinimumVersion     = $compliancePolicy.osMinimumVersion
            }
            $aiInfo = Get-InfoFromAI -content $($filterResults | ConvertTo-Json -Depth 10 -Compress)
        }
        catch {
            Throw "Unable to get filter information from Intune"
        }
        try {
            # Check of the AI repsonse contains a new version by checking for a version betwee < >, if so, update the compliance policy
            $newVersion = (Select-String -Pattern '(?<=\<)(.*?)(?=\>)' -InputObject $aiInfo.choices[0].message.content).Matches.Value
            if ($newVersion) {
                $compliancePolicy.osMinimumVersion = $newVersion
                $compliancePolicy.PSObject.Properties.Remove('assignments')
                $compliancePoliciesUrl = "{0}/beta/deviceManagement/deviceCompliancePolicies/{1}" -f $graphUrl, $compliancePolicy.policy
                Invoke-WebRequest -Uri $compliancePoliciesUrl -Method PATCH -Headers $graphHeaders -Body ($compliancePolicy | ConvertTo-Json -Depth 10)
            }
        }
        catch {
            Throw "Unable to update compliance policy $($compliancePolicy.displayName) in Intune"
        }

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

