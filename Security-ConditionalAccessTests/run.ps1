# Input bindings are passed in via param block.
param($Request)

# The 'IsPastDue' property is 'true' when the current function invocation is later than scheduled.
if ($Timer.IsPastDue) {
    Write-Host "PowerShell timer is running late!"
}


$Request.Body | ConvertTo-Json -Depth 99
# The alert schema does not provide the content to look in to. Instead of that, I grab the linkToSearchResultsAPI value that allows me to get the content from Log Analytics.

# Based on the results, I ask OpenAI to find out what is changed.
$openAIHeader = @{
    'api-key'      = $env:openAIKey
    'Content-Type' = "application/json"
}
$body = @"
{
        "prompt": "Please give me explanation what is happening is this alert. $($Request.Body.data),
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