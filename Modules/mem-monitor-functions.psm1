function Get-AuthApiToken ($resource) {
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
    }
    catch {
        Write-error "Azure login failed with error: $($_.Exception.Message)"
    } 
    $accessToken = Get-AzAccessToken -ResourceUrl $resource -DefaultProfile $azureAccount
    $authHeader = @{
        'Content-Type' = 'application/json'
        Authorization  = 'Bearer {0}' -f $accessToken.Token
    }
    $authHeader
}

function Send-AlertToAdmin {
    [CmdletBinding()]
    param (
        [Parameter()][string]$Title,
        [Parameter()][string]$SubTitle,
        [Parameter()][string]$Description
    )
    $body = 
    @"
    {
        "type": "message",
        "attachments": [
            {
                "contentType": "application/vnd.microsoft.card.adaptive",
                "contentUrl": null,
                "content": {
                    "`$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
                    "type": "AdaptiveCard",
                    "version": "1.4",
                    "body": [
                        {
                            "type": "TextBlock",
                            "text": "$Title",
                            "size": "Large",
                            "weight": "Bolder",
                            "wrap": true
                        },
                        {
                            "type": "TextBlock",
                            "text": "$SubTitle",
                            "isSubtle": true,
                            "color": "Accent",
                            "weight": "Bolder",
                            "size": "Small",
                            "spacing": "None"
                        },
                        {
                            "type": "TextBlock",
                            "text": "$Description",
                            "isSubtle": true,
                            "wrap": true
                        }
                    ],
                    "actions": [
                        {
                            "type": "Action.OpenUrl",
                            "title": "View Details",
                            "url": "https://google.com"
                        }
                    ]
                }
            }
        ]
    }
"@
    try {    
        Invoke-RestMethod -Uri $env:teamsUrl -Method POST -Body $body -ContentType 'application/json'
    }
    catch {
        Throw "Message to MS Teams not send succesful, $_"
    }
}