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
    'Authorization'  = "Bearer {0}" -f $token
}
$Request.Body | ConvertTo-Json -Depth 99


$graphToken = Get-AzAccessToken
$graphToken | ConvertFrom-Json
# The alert schema does not provide the content to look in to. Instead of that, I grab the linkToSearchResultsAPI value that allows me to get the content from Log Analytics.
$laUri = $Request.Body.data.alertContext.condition.allOf[0].linkToFilteredSearchResultsUI

$laApiFilter = $Request.Body.data.alertContext.condition.allOf[0].linkToFilteredSearchResultsAPI

$results = Invoke-RestMethod -uri $laApiFilter -Method get -Headers $monitorHeaders

$policies = Get-ChildItem .\CAPolicies
$policyObjects = [system.Collections.ArrayList]@()
$caPolicyUrl = "https://graph.microsoft.com/beta/identity/conditionalAccess/policies"
foreach ($policy in $policies) {
  $policyObjects.Add((Get-content $policy  | Convertfrom-json -Depth 99)) >> $null
}

# Check if the results are in an array or just one row that returns.. If more rows then, select last one. 
if (($results.tables.rows[-1]) -is [System.Object[]]){
    $jsonResult = $($results.tables.rows[-1])[-2] | ConvertFrom-Json
    $initiator = $($results.tables.rows[-1])[-3] | ConvertFrom-Json
} else {
    $jsonResult = $($results.tables.rows[-2]) | ConvertFrom-Json
    $initiator = $($results.tables.rows[-3]) | ConvertFrom-Json
}

try {
    $policyToRemediate = $policyObjects | Where-Object {$_.id -eq $jsonResult.id}
    $policyToRemediate.PSObject.Properties.Remove('id')
    $policyToRemediate.PSObject.Properties.Remove('createdDateTime')
    $policyToRemediate.PSObject.Properties.Remove('modifiedDateTime')
    $policyToRemediate.PSObject.Properties.Remove('templateId')
    if ($policyToRemediate.grantControls.authenticationStrength) {
    $strenghId = $policyToRemediate.grantControls.authenticationStrength.id
    $policyToRemediate.grantControls.PSObject.Properties.Remove('authenticationStrength')
    $policyToRemediate.grantControls | Add-Member -MemberType NoteProperty -Name "authenticationStrength" -Value @{ id = $strenghId } -Force
    }
    $remediationState = Invoke-RestMethod -Method POST -Uri $caPolicyUrl -body $($policyToRemediate | ConvertTo-Json -Depth 99)

}
catch {
    Write-Error $_
}
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
                "speak": "Conditional Access Policy Deleted!",
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
                                        "text": "Conditional Access has DELETED!",
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
                                                "text": "$($jsonResult.displayName)",
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