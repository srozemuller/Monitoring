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

# Search in the send-toteams-if-unhealthy.json for <--connectorName--> and change that into the name below.
$connectorName = "teams-connector"

$actionGroupName = "ag-to-logicApp"
$monitorRuleName = "monrule-avd-sessionhosthealth"

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
        api               = @{
            brandColor  = "#4B53BC"
            category    = "Standard"
            description = "Microsoft Teams enables you to get all your content, tools and conversations in the Team workspace with Office 365."
            displayName = "Microsoft Teams"
            iconUri     = "https://connectoricons-prod.azureedge.net/releases/v1.0.1585/1.0.1585.2895/teams/icon.png"
            id          = "/subscriptions/{0}/providers/Microsoft.Web/locations/westeurope/managedApis/teams" -f $subscriptionId
            name        = "teams"
            type        = "Microsoft.Web/locations/managedApis"
        }
    }
}
$apiConnectionWebUrl = "{0}/subscriptions/{1}/resourceGroups/{2}/providers/Microsoft.Web/connections/{3}?api-version=2018-07-01-preview" -f $azureApiUrl, $subscriptionId, $resourceGroupName, $connectorName
$apiConnectionWebParameters = @{
    uri     = $apiConnectionWebUrl
    Method  = "PUT"
    Headers = $graphAuthHeader
    Body    = $apiConnectionWebBody | ConvertTo-Json -Depth 99
}
$logicApiConnectioncApp = Invoke-RestMethod @apiConnectionWebParameters
$logicApiConnectioncApp


$logicAppBody = @{
    location   = $location
    identity = @{
        type = "SystemAssigned"
     }
    properties = @{
        definition = Get-Content ./send-toteams-if-unhealty.json | ConvertFrom-Json  
        parameters = @{
            "`$connections" = @{
                value = @{
                    $connectorName = @{
                        "connectionId"   = "{0}" -f $logicApiConnectioncApp.id
                        "connectionName" = "{0}" -f $connectorName
                        "id"             = "{0}" -f $logicApiConnectioncApp.properties.api.id
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

# Virtual Machine Contributor : 9980e02c-c2be-4d73-94e8-173b1dc7cf3c
# Desktop Virtualization Reade : 49a72310-ab8d-41df-bbb0-79b649203868
$rolesIds = @("9980e02c-c2be-4d73-94e8-173b1dc7cf3c","49a72310-ab8d-41df-bbb0-79b649203868") 
$rolesIds | ForEach-Object {
    $assignGuid = (New-Guid).Guid
    $assignURL = "{0}/subscriptions/{1}/resourcegroups/{2}/providers/Microsoft.Authorization/roleAssignments/{3}?api-version=2015-07-01" -f $azureApiUrl, $subscriptionId,$hpResourceGroupName , $assignGuid
    $assignBody = @{
        properties = @{
            roleDefinitionId = "/subscriptions/{0}/resourcegroups/{1}/providers/Microsoft.Authorization/roleDefinitions/{2}" -f $subscriptionId, $hpResourceGroupName, $_
            principalId      = $logicapp.identity.principalId
        }
    } | ConvertTo-Json 
    Invoke-RestMethod -Method PUT -Uri $assignURL -Headers $graphAuthHeader -Body $assignBody
}


$triggerUrl = "{0}{1}/triggers/manual/listCallbackUrl?api-version=2016-10-01" -f $azureApiUrl, $logicApp.id
$triggerParameters = @{
    uri     = $triggerUrl
    Method  = "POST"
    Headers = $graphAuthHeader
}
$trigger = Invoke-RestMethod @triggerParameters
$trigger.value


$actionGroupBody = @{
    location   = "Global"
    properties = @{
        groupShortName    = "agToLa"
        enabled           = $true
        logicAppReceivers = @(
            @{
                name                 = "{0}" -f $logicApp.name
                resourceId           = "{0}" -f $logicApp.id
                callbackUrl          = "{0}" -f $trigger.value
                useCommonAlertSchema = $false
            }
        )
    }
}
$actionGroupUrl = "{0}/subscriptions/{1}/resourceGroups/{2}/providers/Microsoft.Insights/actionGroups/{3}?api-version=2021-09-01" -f $azureApiUrl, $subscriptionId, $resourceGroupName, $actionGroupName
$actionGroupParameters = @{
    uri     = $actionGroupUrl
    Method  = "PUT"
    Headers = $graphAuthHeader
    Body    = $actionGroupBody | ConvertTo-Json -Depth 5
}
$actionGroup = Invoke-RestMethod @actionGroupParameters
$actionGroup

$monitorRuleBody = @{
    location   = $location
    properties = @{
        severity            = 0
        enabled             = $true
        evaluationFrequency = "PT5M"
        scopes              = @(
            $laws.id
        )
        targetResourceTypes = @(
            $laws.type
        )
        windowSize          = "PT5M"
        criteria            = @{
            allOf = @(
                @{
                    query           = "WVDAgentHealthStatus | project TimeGenerated, LastHeartBeat, SessionHostName, SessionHostResourceId, Status, sessionHostId = strcat(_ResourceId,'/sessionhosts/',SessionHostName),  _ResourceId , EndpointState"
                    timeAggregation = "Count"
                    dimensions      = @(
                        @{
                            name     = "SessionHostName"
                            operator = "Include"
                            values   = @("*")
                        }
                        @{
                            name     = "SessionHostResourceId"
                            operator = "Include"
                            values   = @("*")
                        }
                        @{
                            name     = "Status"
                            operator = "Include"
                            values   = @("Unavailable")
                        }
                        @{
                            name     = "sessionHostId"
                            operator = "Include"
                            values   = @("*")
                        }
                        @{
                            name     = "_ResourceId"
                            operator = "Include"
                            values   = @("*")
                        }
                        @{
                            name     = "EndpointState"
                            operator = "Include"
                            values   = @("Unhealthy")
                        }
                    )
                    operator        = "GreaterThanOrEqual"
                    threshold       = 1
                    failingPeriods  = @{
                        numberOfEvaluationPeriods = 1
                        minFailingPeriodsToAlert  = 1
                    }
                }
            )
        }
        autoMitigate        = $false
        actions             = @{
            actionGroups = @(
                $actionGroup.id
            )
        }
    }
}
$monitorRuleUrl = "{0}/subscriptions/{1}/resourceGroups/{2}/providers/Microsoft.Insights/scheduledQueryRules/{3}?api-version=2021-08-01" -f $azureApiUrl, $subscriptionId, $resourceGroupName, $monitorRuleName
$monitorRuleParameters = @{
    uri     = $monitorRuleUrl
    Method  = "PUT"
    Headers = $graphAuthHeader
    Body    = $monitorRuleBody | ConvertTo-Json -Depth 8
}
$monitorRule = Invoke-RestMethod @monitorRuleParameters
$monitorRule
