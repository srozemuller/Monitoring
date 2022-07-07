$token = Get-AzAccessToken
$graphAuthHeader = @{
    'Content-Type' = 'application/json'
    Authorization  = 'Bearer ' + $token.token
}

$azureApiUrl = "https://management.azure.com"
$location = "WestEurope"
$resourceGroupName = 'rg-roz-avd-mon'
$subscriptionId = (Get-azcontext).Subscription.Id
$hostpoolName = 'Rozemuller-Hostpool'
$hpResourceGroupName = 'rg-roz-avd-01'
$logicAppWorkflowName = "la-sessionhost-alert"
$laWorkspace = "log-analytics-avd-" + (Get-Random -Maximum 99999)
$teamsConnector = "teams"


$lawsBody = @{
    location   = $location
    properties = @{
        retentionInDays = "30"
        sku             = @{
            name = "PerGB2018"
        }
    }
}
$lawsUrl = "{0}/subscriptions/{1}/resourcegroups/{2}/providers/Microsoft.OperationalInsights/workspaces/{3}?api-version=2020-08-01" -f $azureApiUrl, $subscriptionId, $resourceGroupName, $laWorkspace
$loganalyticsParameters = @{
    URI     = $lawsUrl 
    Method  = "PUT"
    Body    = $lawsBody | ConvertTo-Json
    Headers = $graphAuthHeader
}
$laws = Invoke-RestMethod @loganalyticsParameters
$laws


$hostpoolId = Get-AvdHostPool -HostPoolName $hostpoolName -ResourceGroupName $hpResourceGroupName
$diagnosticsBody = @{
    Properties = @{
        workspaceId = $laws.id
        logs        = @(
            @{
                Category = 'AgentHealthStatus'
                Enabled  = $true
            }
        )
    }
}  
$diagnosticsUrl = "{0}{1}/providers/microsoft.insights/diagnosticSettings/{2}?api-version=2017-05-01-preview" -f $azureApiUrl, $hostpoolId.id, $laws.name
$diagnosticsParameters = @{
    uri     = $diagnosticsUrl
    Method  = "PUT"
    Headers = $graphAuthHeader
    Body    = $diagnosticsBody | ConvertTo-Json -Depth 4
}
$diagnostics = Invoke-RestMethod @diagnosticsParameters
$diagnostics



$apiConnectionWebBody = @{
    location   = $location
    type       = "Microsoft.Web/connections"
    properties = @{ 
        api = @{
            brandColor  = "#4B53BC"
            category    = "Standard"
            description = "Microsoft Teams enables you to get all your content, tools and conversations in the Team workspace with Office 365."
            displayName = "Microsoft Teams"
            iconUri     = "https://connectoricons-prod.azureedge.net/releases/v1.0.1585/1.0.1585.2895/teams/icon.png"
            id          = "/subscriptions/{0}/providers/Microsoft.Web/locations/westeurope/managedApis/teams" -f $subscriptionId
            name        = "teams"
            type        = "Microsoft.Web/locations/managedApis"
        }
        authenticatedUser = @{
            name = "srozemuller@rozemuller.onmicrosoft.com"
            accessToken = $token.Token
        }
    }
}
$apiConnectionWebUrl = "{0}/subscriptions/{1}/resourceGroups/{2}/providers/Microsoft.Web/connections/tstsr?api-version=2018-07-01-preview" -f $azureApiUrl, $subscriptionId, $resourceGroupName, $teamsConnector
$apiConnectionWebParameters = @{
    uri     = $apiConnectionWebUrl
    Method  = "PUT"
    Headers = $graphAuthHeader
    Body    = $apiConnectionWebBody | ConvertTo-Json -Depth 99
}
$logiapiConnectioncApp = Invoke-RestMethod @apiConnectionWebParameters
$logiapiConnectioncApp




$logicAppBody = @{
    location   = $location
    properties = @{
        definition = Get-Content ./send-toteams-if-unhealty.json | ConvertFrom-Json  
        parameters = @{
            "`$connections" = @{
                value = @{
                    "teams_1" = @{
                        "connectionId"   = "/subscriptions/{0}/resourceGroups/rg-mem-monitoring/providers/Microsoft.Web/connections/teams-1" -f $subscriptionId
                        "connectionName" = "teams-1"
                        "id"             = "/subscriptions/{0}/providers/Microsoft.Web/locations/westeurope/managedApis/{1}" -f $subscriptionId, $teamsConnector
                    }
                }
            }
        }
    }
}
$logicAppUrl = "{0}/subscriptions/{1}/resourceGroups/{2}/providers/Microsoft.Logic/workflows/{3}?api-version=2016-06-01" -f $azureApiUrl, $subscriptionId, $resourceGroupName, $logicAppWorkflowName
$logicAppParameters = @{
    uri     = $logicAppUrl
    Method  = "PUT"
    Headers = $graphAuthHeader
    Body    = $logicAppBody | ConvertTo-Json -Depth 99
}
$logicApp = Invoke-RestMethod @logicAppParameters
$logicApp

