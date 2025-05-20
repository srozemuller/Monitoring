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
    Start-Sleep -Seconds 2
    $statusResp = Invoke-RestMethod -Method Get `
        -Uri "$endpoint/threads/$threadId/runs/$runId`?api-version=$apiVersion" `
        -Headers $openAIheaders
    $status = $statusResp.status
    Write-Host "Run status: $status"
    $i++
} until (
    ($status -in @("completed","failed","cancelled")) -or  # done by status 
    ($i -ge 10)                                          # or max 10 tries
)

# post‐loop check
if ($status -in @("completed","failed","cancelled")) {
    Write-Host "Finished with status: $status"
} else {
    Write-Warning "Max retries reached; last status was: $status"
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