
# The script is stored at: https://github.com/srozemuller/Identity/blob/main/Authentication/graph.authentication.interactive.ps1
$authHeader = ./Authentication/graph.authentication.interactive.ps1 -ClientId "1950a258-227b-4e31-a9cf-717495945fc2" -TenantName rozemuller.onmicrosoft.com -Scope  "https://management.azure.com//.default"

$subscriptionId = 'xxx'
$resourceGroup = 'rg-'
$workspaceName = "laws-"



$diagUrl = "https://management.azure.com/providers/microsoft.aadiam/diagnosticSettings?api-version=2017-04-01-preview"
$diagSettings = Invoke-RestMethod -uri $diagUrl -Method get -Headers $authHeader
if ($diagSettings.value.properties.logs | Select-Object -Property * | Where-Object { $_.category -eq "AuditLogs" -and $_.enabled -eq "True" }) {
    "Found a policy that has the audit logs enabled"
}

$laUri = "https://management.azure.com/subscriptions/{0}/resourcegroups/{1}/providers/microsoft.operationalinsights/workspaces/{2}?api-version=2021-12-01-preview" -f $subscriptionId, $resourceGroup, $workspaceName
$laBody = @{
    location   = "westeurope"
    properties = @{
        retentionInDays            = 30
        sku                        = @{
            name = "PerGB2018"
        }
        immediatePurgeDataOn30Days = $true
    }
} | ConvertTo-Json
$laResponse = Invoke-RestMethod -uri $laUri -Method GET -Headers $authHeader -Body $laBody
$laResponse


$diagUrl = "https://management.azure.com/providers/microsoft.aadiam/diagnosticSettings/{0}?api-version=2017-04-01-preview" -f "diagTest"
$diagBody = @{
    name       = "TestDiag"
    properties = @{
        logs        = @(
            @{
                "category"        = "AuditLogs"
                "categoryGroup"   = $null
                "enabled"         = $true
                "retentionPolicy" = @{
                    "days"    = 0
                    "enabled" = $false
                }
            }
        )
        workspaceId = $laResponse.id
    }
} | ConvertTo-Json -Depth 10
Invoke-RestMethod -uri $diagUrl -Method PUT -Headers $authHeader -Body $diagBody

$openAiAccount = 'rozemullerAIBot'
$openAiUri = "https://management.azure.com/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.CognitiveServices/accounts/{2}?api-version=2021-10-01" -f $subscriptionId, $resourceGroup, $openAiAccount
$openAiBody = @{
    location   = "West Europe"
    kind       = "OpenAI"
    sku        = @{
        name = "S0"
    }
    properties = @{
        customSubDomainName = $openAiAccount
    }
} | ConvertTo-Json
$openAiResource = Invoke-RestMethod -Uri $openAiUri -Method PUT -Headers $authHeader -Body $openAiBody

$deploymentName = "find-ca-changes"
$openAIModelUri = "https://management.azure.com/{0}/deployments/{1}?api-version=2023-05-01" -f $openAiResource.id, $deploymentName
$openAIModelBody = @{
    properties = @{
        model                = @{
            format  = "OpenAI"
            name    = "text-davinci-003"
            version = 1
        }
        versionUpgradeOption = "OnceNewDefaultVersionAvailable"
    }
    sku        = @{
        name     = "Standard"
        capacity = 120
    }
} | ConvertTo-Json -Depth 5
Invoke-RestMethod -Uri $openAIModelUri -Method PUT -Headers $authHeader -Body $openAIModelBody

$openAiAccount = 'rozemullerAIBot'
$openAiUri = "https://management.azure.com/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.CognitiveServices/accounts/{2}/listKeys?api-version=2021-10-01" -f $subscriptionId, $resourceGroup, $openAiAccount
$openAiKeys = Invoke-RestMethod -Uri $openAiUri -Method POST -Headers $authHeader
$openAiKeys

$appserviceName = "aspfaweu01"
$appServiceUri = "https://management.azure.com/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Web/serverfarms/{2}?api-version=2022-03-01" -f $subscriptionId, $resourceGroup, $appserviceName
$appServiceBody = @{
    location = "West Europe"
    kind     = "linux"
    sku      = @{
        Tier = "Dynamic"
        Name = "Y1"
    }
} | ConvertTo-Json
$appservice = Invoke-RestMethod -Uri $appServiceUri -Method PUT -Headers $authHeader -Body $appServiceBody

$storageAccountName = "saopenaifa01"
$storageAccountUri = "https://management.azure.com/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Storage/storageAccounts/{2}?api-version=2022-09-01" -f $subscriptionId, $resourceGroup, $storageAccountName
$storageAccountBody = @{
    location   = "West Europe"
    sku        = @{
        Name = "Standard_LRS"
    }
    properties = @{
        supportsHttpsTrafficOnly     = $true
        minimumTlsVersion            = "TLS1_2"
        defaultToOAuthAuthentication = $true
    }
} | ConvertTo-Json
$storageAccount = Invoke-RestMethod -Uri $storageAccountUri -Method PUT -Headers $authHeader -Body $storageAccountBody

$storageAccountKeysUri = "https://management.azure.com/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Storage/storageAccounts/{2}/listKeys?api-version=2022-09-01" -f $subscriptionId, $resourceGroup, $storageAccountName
$storageAccountKey = Invoke-RestMethod -Uri $storageAccountKeysUri -Method POST -Headers $authHeader

$teamsUrl = "teams-webhook-url"
$functionAppName = "faopenaiweu01"
$functionAppUri = "https://management.azure.com/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Web/sites/{2}?api-version=2022-03-01" -f $subscriptionId, $resourceGroup, $functionAppName
$functionAppBody = @{
    location   = "West Europe"
    kind       = "functionapp,linux"
    properties = @{
        powerShellVersion = "7.2"
        serverFarmId      = $appservice.id
        siteConfig        = @{
            appSettings = @(
                @{
                    "name"  = "FUNCTIONS_EXTENSION_VERSION"
                    "value" = "~4"
                },
                @{
                    "name"  = "FUNCTIONS_WORKER_RUNTIME"
                    "value" = "powershell"
                },
                @{
                    "name"  = "AzureWebJobsStorage"
                    "value" = "DefaultEndpointsProtocol=https;AccountName=$storageAccountName;AccountKey=$($storageAccountKey.keys[0].value);EndpointSuffix=core.windows.net"
                },
                @{
                    "name"  = "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING"
                    "value" = "DefaultEndpointsProtocol=https;AccountName=$storageAccountName;AccountKey=$($storageAccountKey.keys[0].value);EndpointSuffix=core.windows.net"
                }
                @{
                    "name"  = "WEBSITE_CONTENTSHARE"
                    "value" = "openaimonitoringbf13"
                },
                @{
                    "name"  = "OpenAIUrl"
                    "value" = "https://{0}.openai.azure.com/" -f $openAiAccount
                }
                @{
                    "name"  = "OpenAIKey"
                    "value" = $openAiKeys.key1
                },
                @{
                    "name"  = "TeamsUrl"
                    "value" = $teamsUrl
                }
            )
        }
        identity = @{
            type = "SystemAssigned"
        }
    }
} | ConvertTo-Json -Depth 5
$functionApp = Invoke-RestMethod -Uri $functionAppUri -Method PUT -Headers $authHeader -Body $functionAppBody


$sourceControlUri = "https://management.azure.com/{0}/sourcecontrols/web?api-version=2022-03-01" -f $functionApp.id
$sourceControlBody = @{
    location   = "GitHub"
    properties = @{
        repoUrl                   = "https://www.github.com/srozemuller/monitoring"
        branch                    = "main"
        isManualIntegration       = $false
        repoAccessToken           = "github_PATTOKEN"
        gitHubActionConfiguration = @{
            generateWorkflowFile = $true
            workflowSettings     = @{
                appType            = "functionapp"
                publishType        = "code"
                os                 = "linux"
                runtimeStack       = "powershell"
                workflowApiVersion = "2020-12-01"
                variables          = @{
                    runtimeVersion = "7.2"
                }
            }
        }
        isGithubAction            = $true
    }
} | ConvertTo-Json -Depth 5
Invoke-RestMethod -Uri $sourceControlUri -Method PATCH -Headers $authHeader -Body $sourceControlBody

$functionName = "Security-ConditionalAccessChanges"
$functionUri = "https://management.azure.com/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Web/sites/{2}/functions/{3}/listKeys?api-version=2022-03-01" -f $subscriptionId, $resourceGroup, $functionAppName, $functionName
$functionKey = Invoke-RestMethod -Uri $functionUri -Method POST -Headers $authHeader

$actionGroupName = "ag-fa-openAi"
$actionGroupUri = "https://management.azure.com/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Insights/actionGroups/{2}?api-version=2021-09-01" -f $subscriptionId, $resourceGroup, $actionGroupName
$actionGroupBody = @{
    location   = "Global"
    properties = @{
        enabled                = $true
        groupShortName         = "toOpenAI"
        azureFunctionReceivers = @(
            @{
                name                  = $functionName
                functionAppResourceId = $functionApp.id
                functionName          = $functionName
                httpTriggerUrl        = "https://{0}.azurewebsites.net/api/{1}?code={2}" -f $functionAppName, $functionName, $functionKey.default
                useCommonAlertSchema  = $true
            }
        )
    }
} | ConvertTo-Json -Depth 5
Invoke-RestMethod -Uri $actionGroupUri -Method PUT -Headers $authHeader -Body $actionGroupBody


$alertRuleName = "Conditional Access Policy Changed"
$alertRuleUri = "https://management.azure.com/subscriptions/{0}/resourceGroups/{1}/providers/microsoft.insights/scheduledqueryrules/{2}?api-version=2023-03-15-preview" -f $subscriptionId, $resourceGroup, $alertRuleName
$alertRuleBody = @{
    location   = "West Europe"
    properties = @{
        displayName         = $alertRuleName
        actions             = @{
            actionGroups = @(
                $actionGroup.id
            )
        }
        criteria            = @{
            allOf = @(
                @{
                    operator        = "GreaterThanOrEqual"
                    query           = "AuditLogs | where OperationName == 'Update conditional access policy' | extend oldValue=parse_json(TargetResources[0].modifiedProperties[0].oldValue) | extend newValue=parse_json(TargetResources[0].modifiedProperties[0].newValue) | project TimeGenerated, OperationName, InitiatedBy, oldValue, newValue"
                    threshold       = 1
                    timeAggregation = "Count"
                    dimensions      = @()
                    failingPeriods  = @{
                        minFailingPeriodsToAlert  = 1
                        numberOfEvaluationPeriods = 1
                    }
                }
            )
        }
        description         = "This rule checks for conditional access policy changes every 15 minutes"
        enabled             = $true
        autoMitigate        = $false
        evaluationFrequency = "PT15M"
        scopes              = @(
            $laResponse.id
        )
        severity            = 2
        windowSize          = "PT15M"
        targetResourceTypes = @(
            "Microsoft.OperationalInsights/workspaces"
        )
    }
} | ConvertTo-Json -Depth 8
Invoke-RestMethod -Uri $alertRuleUri -Method PUT -Headers $authHeader -Body $alertRuleBody