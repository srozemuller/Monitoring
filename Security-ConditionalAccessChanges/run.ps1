# Input bindings are passed in via param block.
param($Request)

# The 'IsPastDue' property is 'true' when the current function invocation is later than scheduled.
if ($Timer.IsPastDue) {
    Write-Host "PowerShell timer is running late!"
}
function Format-PolicyChangeQuestion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$OldJson,
        [Parameter(Mandatory)][string]$NewJson
    )

    # Use a double-quoted here-string so that your JSON variables expand unescaped
    $question = @"
Consider you are an IT administrator and you’ve received a trigger from Azure Monitor indicating a Conditional Access policy has changed.  
You need a clear overview of exactly what changed, and you also want to understand the impact of that change. I want simple text output that explains clear what is changed and the impact.

Old JSON:
$OldJson

New JSON:
$NewJson
"@

    return $question
}

# Connect to Azure using the system assigned identity
Connect-AzAccount -Identity
$headers = @{"X-IDENTITY-HEADER" = $env:IDENTITY_HEADER }

$ProgressPreference = "SilentlyContinue"
$response = Invoke-WebRequest -UseBasicParsing -Uri "$($env:IDENTITY_ENDPOINT)?resource=https://api.loganalytics.io&api-version=2019-08-01" -Headers $headers
$token = ($response.Content | Convertfrom-json).access_token

$monitorHeaders = @{
    'Content-Type' = 'application/json'
    'Authorization'  = "Bearer {0}" -f $token
}
$Request.Body | ConvertTo-Json -Depth 99

$token
# The alert schema does not provide the content to look in to. Instead of that, I grab the linkToSearchResultsAPI value that allows me to get the content from Log Analytics.
$laUri = $Request.Body.data.alertContext.condition.allOf[0].linkToFilteredSearchResultsUI

$laApiFilter = $Request.Body.data.alertContext.condition.allOf[0].linkToFilteredSearchResultsAPI

$results = Invoke-RestMethod -uri $laApiFilter -Method get -Headers $monitorHeaders

$openAIheaders = @{
    "api-key"       = $env:AZURE_OPENAI_API_KEY
    "Content-Type"  = "application/json"
}
$apiVersion = "2025-04-01-preview"
$endpoint   = "$env:AZURE_OPENAI_ENDPOINT/openai"

$assistantId = "asst_WJYWT2zmaqwNhQUldcjzt2se"

$oldJson = $($results.tables.rows[-2])
$newJson = $($results.tables.rows[-1])
$initiator = $($results.tables.rows[-3]) | ConvertFrom-Json
$userQuestion = Format-PolicyChangeQuestion -OldJson $oldJson -NewJson $newJson

$threadRunBody = @{
    assistant_id = $assistantId
    thread       = @{
        messages = @(
            @{
                role    = "user"
                content = $userQuestion
            }
        )
    }
} | ConvertTo-Json -Depth 6

$runResp = Invoke-RestMethod -Method Post `
    -Uri "$endpoint/threads/runs?api-version=$apiVersion" `
    -Headers $openAIheaders `
    -Body $threadRunBody

$threadId = $runResp.thread_id
$runId    = $runResp.id
Write-Host "Run created: thread=$threadId  run=$runId  (status: $($runResp.status))"

do {
    Start-Sleep -Seconds 1
    $statusResp = Invoke-RestMethod -Method Get `
        -Uri "$endpoint/threads/$threadId/runs/$runId`?api-version=$apiVersion" `
        -Headers $openAIheaders
    $status = $statusResp.status
    Write-Host "Run status: $status"
} until ($status -in @("completed","failed","cancelled")) 

if ($status -ne "completed") {
    throw "Run did not complete successfully: $status"
}

$msgsResp = Invoke-RestMethod -Method Get `
    -Uri "$endpoint/threads/$threadId/messages?api-version=$apiVersion" `
    -Headers $openAIheaders

# Extract the last assistant message
$assistantMsg = $msgsResp.data |
    Where-Object { $_.role -eq "assistant" } |
    Select-Object -Last 1

# The content is an array; for plain text it's in content[0].text.value
$reply = $assistantMsg.content[0].text.value
Write-Output "Assistant replied: `n$reply"

$cardBody = @"
{
    "type": "message",
    "attachments": [
        {
            "contentType": "application/vnd.microsoft.card.adaptive",
            "contentUrl": null,
            "content": {
                "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
                "type": "AdaptiveCard",
                "speak": "Conditional Access Test results",
                "body": [
                    {
                        "inlines": [
                            {
                                "type": "TextRun",
                                "size": "Small",
                                "text": "Android Scrum Project / SSP-98",
                                "selectAction": {
                                    "url": "https://adaptivecards.io",
                                    "type": "Action.OpenUrl"
                                }
                            }
                        ],
                        "type": "RichTextBlock"
                    },
                    {
                        "columns": [
                            {
                                "width": "auto",
                                "items": [
                                    {
                                        "type": "Icon",
                                        "name": "Branch",
                                        "color": "Accent"
                                    }
                                ],
                                "type": "Column"
                            },
                            {
                                "width": "stretch",
                                "items": [
                                    {
                                        "size": "Large",
                                        "text": "Conditional Access has changed!",
                                        "weight": "Bolder",
                                        "wrap": true,
                                        "type": "TextBlock"
                                    }
                                ],
                                "verticalContentAlignment": "Center",
                                "spacing": "Small",
                                "type": "Column"
                            }
                        ],
                        "spacing": "Small",
                        "type": "ColumnSet"
                    },
                    {
                        "type": "Table",
                        "targetWidth": "AtLeast:Narrow",
                        "columns": [
                            {
                                "width": 1
                            },
                            {
                                "width": 2
                            }
                        ],
                        "rows": [
                            {
                                "type": "TableRow",
                                "cells": [
                                    {
                                        "type": "TableCell",
                                        "items": [
                                            {
                                                "type": "TextBlock",
                                                "text": "Initiator",
                                                "wrap": true,
                                                "weight": "Bolder"
                                            }
                                        ],
                                        "verticalContentAlignment": "Center"
                                    },
                                    {
                                        "type": "TableCell",
                                        "items": [
                                            {
                                                "type": "TextBlock",
                                                "text": "$($initiator.user.displayName) ($($initiator.user.id))",
                                                "wrap": true
                                            }
                                        ],
                                        "verticalContentAlignment": "Center"
                                    }
                                ]
                            },
                            {
                                "type": "TableRow",
                                "cells": [
                                    {
                                        "type": "TableCell",
                                        "items": [
                                            {
                                                "type": "TextBlock",
                                                "text": "IpAdress",
                                                "wrap": true,
                                                "weight": "Bolder"
                                            }
                                        ],
                                        "verticalContentAlignment": "Center"
                                    },
                                    {
                                        "type": "TableCell",
                                        "items": [
                                            {
                                                "type": "TextBlock",
                                                "text": "$($initiator.user.ipAddress)",
                                                "wrap": true
                                            }
                                        ],
                                        "verticalContentAlignment": "Center"
                                    }
                                ]
                            },
                            {
                                "type": "TableRow",
                                "cells": [
                                    {
                                        "type": "TableCell",
                                        "items": [
                                            {
                                                "type": "TextBlock",
                                                "text": "Policy Name",
                                                "wrap": true,
                                                "weight": "Bolder"
                                            }
                                        ],
                                        "verticalContentAlignment": "Center"
                                    },
                                    {
                                        "type": "TableCell",
                                        "items": [
                                            {
                                                "type": "TextBlock",
                                                "text": "Name",
                                                "wrap": true
                                            }
                                        ],
                                        "verticalContentAlignment": "Center"
                                    }
                                ]
                            },
                            {
                                "type": "TableRow",
                                "cells": [
                                    {
                                        "type": "TableCell",
                                        "items": [
                                            {
                                                "type": "TextBlock",
                                                "text": "Explanation",
                                                "wrap": true,
                                                "weight": "Bolder"
                                            }
                                        ]
                                    },
                                    {
                                        "type": "TableCell",
                                        "items": [
                                            {
                                                "type": "TextBlock",
                                                "text": "$($reply.Replace('"',"'"))",
  
                                                "wrap": true
                                            }
                                        ]
                                    }
                                ]
                            },
                            {
                                "type": "TableRow",
                                "cells": [
                                    {
                                        "type": "TableCell",
                                        "items": [
                                            {
                                                "type": "TextBlock",
                                                "text": "Priority",
                                                "wrap": true,
                                                "weight": "Bolder"
                                            }
                                        ],
                                        "verticalContentAlignment": "Center"
                                    },
                                    {
                                        "type": "TableCell",
                                        "items": [
                                            {
                                                "type": "ColumnSet",
                                                "columns": [
                                                    {
                                                        "type": "Column",
                                                        "width": "auto",
                                                        "items": [
                                                            {
                                                                "type": "Icon",
                                                                "name": "Flag",
                                                                "color": "Attention",
                                                                "size": "xSmall",
                                                                "horizontalAlignment": "Center"
                                                            }
                                                        ]
                                                    },
                                                    {
                                                        "type": "Column",
                                                        "width": "stretch",
                                                        "items": [
                                                            {
                                                                "color": "Attention",
                                                                "text": "Critical",
                                                                "wrap": true,
                                                                "spacing": "Small",
                                                                "type": "TextBlock"
                                                            }
                                                        ],
                                                        "spacing": "Small"
                                                    }
                                                ],
                                                "spacing": "Small"
                                            }
                                        ],
                                        "verticalContentAlignment": "Center"
                                    }
                                ]
                            }
                        ],
                        "firstRowAsHeaders": false,
                        "showGridLines": false
                    },
                    {
                        "type": "Container",
                        "targetWidth": "VeryNarrow",
                        "items": [
                            {
                                "text": "Status",
                                "weight": "Bolder",
                                "wrap": true,
                                "type": "TextBlock"
                            },
                            {
                                "text": "Waiting for Review",
                                "wrap": true,
                                "type": "TextBlock",
                                "spacing": "None"
                            },
                            {
                                "text": "Due Date",
                                "weight": "Bolder",
                                "wrap": true,
                                "spacing": "Small",
                                "type": "TextBlock"
                            },
                            {
                                "text": "May 21, 2023",
                                "wrap": true,
                                "spacing": "None",
                                "type": "TextBlock"
                            },
                            {
                                "text": "Priority",
                                "weight": "Bolder",
                                "wrap": true,
                                "spacing": "Small",
                                "type": "TextBlock"
                            },
                            {
                                "type": "ColumnSet",
                                "columns": [
                                    {
                                        "type": "Column",
                                        "width": "auto",
                                        "items": [
                                            {
                                                "type": "Icon",
                                                "name": "Flag",
                                                "color": "Attention",
                                                "size": "xSmall",
                                                "horizontalAlignment": "Center"
                                            }
                                        ],
                                        "verticalContentAlignment": "Center"
                                    },
                                    {
                                        "type": "Column",
                                        "width": "stretch",
                                        "items": [
                                            {
                                                "color": "Attention",
                                                "text": "Critical",
                                                "wrap": true,
                                                "spacing": "Small",
                                                "type": "TextBlock"
                                            }
                                        ],
                                        "spacing": "Small"
                                    }
                                ],
                                "spacing": "None"
                            },
                            {
                                "text": "Assigned To",
                                "weight": "Bolder",
                                "wrap": true,
                                "spacing": "Small",
                                "type": "TextBlock"
                            },
                            {
                                "type": "ColumnSet",
                                "columns": [
                                    {
                                        "type": "Column",
                                        "width": "auto",
                                        "items": [
                                            {
                                                "type": "Image",
                                                "url": "https://raw.githubusercontent.com/OfficeDev/Microsoft-Teams-Card-Samples/main/samples/issue/assets/avatar.png",
                                                "width": "16px"
                                            }
                                        ],
                                        "verticalContentAlignment": "Center",
                                        "horizontalAlignment": "Center"
                                    },
                                    {
                                        "type": "Column",
                                        "width": "stretch",
                                        "items": [
                                            {
                                                "type": "TextBlock",
                                                "text": "Charlotte Waltson",
                                                "wrap": true
                                            }
                                        ],
                                        "spacing": "Small"
                                    }
                                ],
                                "spacing": "None"
                            }
                        ]
                    },
                    {
                        "actions": [
                            {
                                "title": "Go to Alert",
                                "type": "Action.OpenUrl",
                                "url": "https://portal.azure.com/#view/Microsoft_Azure_Monitoring_Alerts/AlertDetails.ReactView/alertId~/%2Fsubscriptions%2F6d3c408e-b617-44ed-bc24-280249636525%2Fresourcegroups%2Fconditionalaccesstester%2Fproviders%2Fmicrosoft.operationalinsights%2Fworkspaces%2Fcatestlogs24%2Fproviders%2FMicrosoft.AlertsManagement%2Falerts%2Fc9958b43-665d-991e-707d-0bd5961d000e/invokedFrom/CopyLinkFeature"
                            },
                            {
                                "title": "Go to Log row",
                                "type": "Action.OpenUrl",
                                "url": "$laUri"
                            }
                        ],
                        "type": "ActionSet",
                        "targetWidth": "AtLeast:Narrow",
                        "spacing": "ExtraLarge"
                    }
                ],
                "version": "1.5"
            }
        }
    ]
}
"@
Invoke-RestMethod -Method post -uri $env:teamsUrl -body $cardBody -ContentType "application/json"