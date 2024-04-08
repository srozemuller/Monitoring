# Input bindings are passed in via param block.
param($Timer)

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
                "content": "Please summerize this content into a nice message. $($($content).Replace('"','\"'))"
            }
        ]
        }
"@
    $openAIResponse = Invoke-RestMethod -Method post -uri $env:openAIUrl -Headers $openAIHeader -Body $body
    return $openAIResponse
}

# Get the current West Europe time in the default string format.
$currentTime = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId( (Get-Date), 'W. Europe Standard Time').ToString('yyyy-MM-dd HH:mm:ss')
$informationPreference = 'Continue'
# Connect to Azure using the system assigned identity
Connect-AzAccount -Identity

$ProgressPreference = "SilentlyContinue"
$graphUrl = "https://graph.microsoft.com"
$token = Get-AzAccessToken -ResourceUrl $graphUrl
$graphHeaders = @{
    'Content-Type' = 'application/json'
    Authorization  = "Bearer {0}" -f $token.token
}

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
    # Search for all Edge security baselines
    $currentConfiguredBaselinesUrl = "https://graph.microsoft.com/beta//deviceManagement/configurationPolicies?`$filter=(templateReference/TemplateId%20eq%20%27c66347b7-8325-4954-a235-3bf2233dfbfd_1%27%20or%20templateReference/TemplateId%20eq%20%27c66347b7-8325-4954-a235-3bf2233dfbfd_2%27)%20and%20(templateReference/TemplateFamily%20eq%20%27Baseline%27)"
    $results = Invoke-RestMethod -Uri $currentConfiguredBaselinesUrl -Headers $graphHeaders -Method Get
}
catch {
    Write-Error "Unable to request for security baselines, $_"
}

if ($results.value.length -gt 0) {
    try {
        $results.value | ForEach-Object {
            # Code block here
            $baseline = $_

            # Get current baseline information
            $baselineSettingsUrl = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('{0}')/settings?`$expand=settingDefinitions&top=1000" -f $baseline.Id
            $getBaselineSettings = Invoke-RestMethod -Uri $baselineSettingsUrl -Headers $graphHeaders -Method Get

            # Get setting insights for the baseline
            $getSettingInsightsUrl = "https://graph.microsoft.com/beta/deviceManagement/templateInsights('{0}')/settingInsights" -f $baseline.templateReference.templateid
            $getSettingInsights = Invoke-RestMethod -Uri $getSettingInsightsUrl -Headers $graphHeaders -Method Get
            $alertResults = [System.Collections.ArrayList]::new()
            # When there are insights available, loop through them and compare the current setting with the recommended setting.
            if ($getSettingInsights.count -gt 0) {
                $getSettingInsights.value.ForEach({
                        $getSettingInsightsId = $_.settingDefinitionId
                        $recommendedSettingId = $_.settingInsight.value

                        $currentBaselineDefinition = $getBaselineSettings.value.settingDefinitions.Where({ $_.id -eq $getSettingInsightsId })
                        $currentBaselineSetting = ($getBaselineSettings.value.settingInstance.Where({ $_.settingDefinitionId -eq $getSettingInsightsId })).choiceSettingValue.value

                        $currentBaselineSettingReadable = $currentBaselineDefinition.options.Where({ $_.itemId -eq $currentBaselineSetting }).displayName
                        $shouldBeValue = $currentBaselineDefinition.options.Where({ $_.itemId -eq $recommendedSettingId }).displayName

                        if ($currentBaselineSettingReadable -ne $shouldBeValue) {
                            $alertResults.Add("Baseline: $($baseline.Name) has setting: $($currentBaselineDefinition.displayName) with value: $($currentBaselineSettingReadable) but should be: $shouldBeValue")
                        }
                        else {
                            $alertResults.Add("Baseline: $($baseline.Name) has setting: $($currentBaselineDefinition.displayName) with value: $($currentBaselineSettingReadable) and is correct.")
                        }

                    })
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
                Write-Host "Baseline: $($baseline.Name) has no insights."
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