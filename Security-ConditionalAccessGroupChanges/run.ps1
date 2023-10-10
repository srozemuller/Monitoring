# Input bindings are passed in via param block.
param($Timer)

# The 'IsPastDue' property is 'true' when the current function invocation is later than scheduled.
if ($Timer.IsPastDue) {
    Write-Host "PowerShell timer is running late!"
}

function Get-DeltaResults {
    param(
        [Parameter(Mandatory = $true)]
        [string]$deltaUrl
    )
    Write-Information "Getting delta results from $deltaUrl"
    $deltaResults = Invoke-RestMethod -uri $deltaUrl -Headers $graphHeaders -Method Get
    Write-Information "Delta results: $($deltaResults.'@odata.deltaLink')"
    $deltaResults.'@odata.deltaLink' | Out-File .\deltaurl.txt
    return $deltaResults.value
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
                "content": "Explain based on the json content the delta status. Give me the user name and explain the user's role in detail. Surround the user name, roles and the status with ** $($($content).Replace('"','\"')) **"
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
$deltaFile = '.\deltaurl.txt'
$token = (Get-AzAccessToken -ResourceUrl "https://graph.microsoft.com/")
$graphHeaders = @{
    'Content-Type' = 'application/json'
    Authorization  = "Bearer {0}" -f $token.token
}


if (Test-Path $deltaFile) {
    $deltaUrl = Get-Content $deltaFile
    $deltas = Get-DeltaResults -deltaUrl $deltaUrl
}
else {
    Write-Warning "No delta file found yet"
    $graphGroupDeltaUrl = "{0}/beta/groups/delta?`$filter=id eq '{1}'&`$select=displayName,description,members" -f $graphUrl, $env:groupId
    $deltaCheckResult = Invoke-RestMethod -uri $graphGroupDeltaUrl -Headers $graphHeaders -Method Get
    do {
        $deltaCheckResult = Invoke-RestMethod -uri $deltaCheckResult.'@odata.nextLink' -Headers $graphHeaders -Method Get
    }
    while ($null -eq $deltaCheckResult.'@odata.deltaLink')
    $deltas = Get-DeltaResults -deltaUrl $deltaCheckResult.'@odata.deltaLink'
}

if ($deltas) {
    Write-Warning "Found deltas, $($deltas)"
    $deltas | ForEach-Object {
        $members = $_.'members@delta'
        $members | ForEach-Object {
            $roles = [System.Collections.ArrayList]::new()
            $member = $_
            if ($_.'@odata.type' -eq '#microsoft.graph.user') {
                $userInfoUrl = "{0}/beta/users/{1}" -f $graphUrl, $_.id
                $userInfo = Invoke-RestMethod -uri $userInfoUrl -Headers $graphHeaders -Method Get
                $inActiveRoleUrl = "{0}/beta/roleManagement/directory/roleEligibilitySchedules?`$filter=principalId eq '{1}'" -f $graphUrl, $_.id
                $inActiveRoles = Invoke-WebRequest -Uri $inActiveRoleUrl -Headers $graphHeaders -Method Get
                $inActiveResults = ($inActiveRoles.Content | Convertfrom-json).value
                $inActiveResults | ForEach-Object {
                    $roleDefinitionUrl = "{0}/beta/directoryRoles(roleTemplateId='{1}')" -f $graphUrl, $_.roleDefinitionId
                    $roleDefinition = ((Invoke-WebRequest -Uri $roleDefinitionUrl -Headers $graphHeaders -Method Get).Content | Convertfrom-json)
                    $roles.Add($roleDefinition.displayName) >> $null
                }
                $activeRoleUrl = "{0}/beta/roleManagement/directory/roleAssignmentSchedules?`$filter=principalId eq '{1}'" -f $graphUrl, $_.id
                $activeRoles = Invoke-WebRequest -Uri $activeRoleUrl -Headers $graphHeaders -Method Get
                $activeResults = ($activeRoles.Content | Convertfrom-json).value
                $activeResults | ForEach-Object {
                    $roleDefinitionUrl = "{0}/beta/directoryRoles(roleTemplateId='{1}')" -f $graphUrl, $_.roleDefinitionId
                    $roleDefinition = ((Invoke-WebRequest -Uri $roleDefinitionUrl -Headers $graphHeaders -Method Get).Content | Convertfrom-json)
                    $roles.Add($roleDefinition.displayName) >> $null
                }
            }
            # Based on the results, I ask OpenAI to find out what is changed.
            $memberObject = [PSCustomObject]@{
                'userDisplayName' = $userInfo.displayName
                'groupName'       = $delta.displayName
                'delta status'    = $member
                'roles'           = $roles
            }
            $aiInfo = Get-InfoFromAI -content $memberObject
            $aiInfo.choices[0].message
        }
    }


    $aiInfo = Get-InfoFromAI -content $($memberObject | ConvertTo-Json -Depth 10 -Compress)
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