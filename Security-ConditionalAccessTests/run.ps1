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
$token 
$monitorHeaders = @{
    'Content-Type' = 'application/json'
    'Authorization'  = "Bearer {0}" -f $token
}
$Request.Body | ConvertTo-Json -Depth 99

# The alert schema does not provide the content to look in to. Instead of that, I grab the linkToSearchResultsAPI value that allows me to get the content from Log Analytics.
$laUri = $Request.Body.data.alertContext.condition.allOf[0].linkToFilteredSearchResultsUI

$laApiFilter = $Request.Body.data.alertContext.condition.allOf[0].linkToFilteredSearchResultsAPI

$results = Invoke-RestMethod -uri $laApiFilter -Method get -Headers $monitorHeaders
$jsonResult = $($results.tables.rows[-2]) | ConvertFrom-Json -Depth 5
$policyName = $($results.tables.rows[-1])

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
                                        "text": "Conditional Access Test Failed!",
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
                                                "text": "Name",
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
                                                "text": "$($policyName)",
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
                                                "text": "Result",
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
                                                "text": "$($jsonResult.TestResults.TestResult)",
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
                                                "text": "TestDescription",
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
                                                "text": "$($jsonResult.TestResults.TestDescription)",
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
                "msteams": {
                     "width": "Full"
                },
                "version": "1.5"
            }
        }
    ]
}
"@
Invoke-RestMethod -Method post -uri $env:teamsUrl -body $cardBody -ContentType "application/json"
