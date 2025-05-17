# Input bindings are passed in via param block.
param($Request)

# The 'IsPastDue' property is 'true' when the current function invocation is later than scheduled.
if ($Timer.IsPastDue) {
    Write-Host "PowerShell timer is running late!"
}

# Connect to Azure using the system assigned identity
Connect-AzAccount -Identity
$headers = @{"X-IDENTITY-HEADER" = $env:IDENTITY_HEADER }

$ProgressPreference = "SilentlyContinue"
$response = Invoke-WebRequest -UseBasicParsing -Uri "$($env:IDENTITY_ENDPOINT)?resource=https://api.loganalytics.io&api-version=2019-08-01" -Headers $headers
$token = ($response.Content | Convertfrom-json).access_token
$monitorHeaders = @{
    'Content-Type' = 'application/json'
    Authorization  = "Bearer {0}" -f $token.token
}
$Request.Body | ConvertTo-Json -Depth 99
# The alert schema does not provide the content to look in to. Instead of that, I grab the linkToSearchResultsAPI value that allows me to get the content from Log Analytics.
$laUri = $Request.Body.data.alertContext.condition.allOf[0].linkToSearchResultsAPI
$results = Invoke-RestMethod -uri $laUri -Method get -Headers $monitorHeaders

# Based on the results, I ask OpenAI to find out what is changed.
$openAIHeader = @{
    'api-key'      = $env:openAIKey
    'Content-Type' = "application/json"
}
$body = @"
{
        "prompt": "Please compare the two JSON object below and give me a list of differences. Start the salutation with 'Hi, here's a message from OpenAI! I have been asked to compare settings\n for a conditional access policy that has been changed. The following changes are found in policy: ' and attach the display name value from the old value object only first. Surround the display name with **. End the line with \n. Then, show me a list on what exactly differs between the old value object and new value and show the outcome in a list? Surround the object name with **. End every line with \n. If there is a change in a nested array, please also tell me what is different in that array and return the values. At the end, please give a summarize about the impact. Old value object \" $($($results.tables.rows[-2]).Replace('"',"'"))  \" New value object: \"$($($results.tables.rows[-1]).Replace('"',"'"))\"",
        "temperature": 0.2,
        "top_p": 1,
        "frequency_penalty": 0,
        "presence_penalty": 0,
        "max_tokens": 2000,
        "best_of": 1,
        "stop": null
}
"@
$openAIResponse = Invoke-RestMethod -Method post -uri $env:openAIUrl -Headers $openAIHeader -Body $body

$cardBody = @"
{
    "type":"message",
    "attachments":[
       {
          "contentType":"application/vnd.microsoft.card.adaptive",
          "contentUrl":null,
          "content":{
             "$schema":"http://adaptivecards.io/schemas/adaptive-card.json",
             "type":"AdaptiveCard",
             "version":"1.4",
             "body":[
                 {
                 "type": "TextBlock",
                 "text": "$($openAIResponse.choices.text)",
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
Invoke-RestMethod -Method post -uri $env:teamsUrl -body $cardBody