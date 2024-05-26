# Input bindings are passed in via param block.
param($Timer)

# Get the current West Europe time in the default string format.
$currentTime = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId( (Get-Date), 'W. Europe Standard Time').ToString('yyyy-MM-dd HH:mm:ss')
$informationPreference = 'Continue'
# Write an information log with the current time.
Write-Output "PowerShell timer trigger function ran! TIME: $currentTime"
# Connect to Azure using the system assigned identity
Connect-AzAccount -Identity

$ProgressPreference = "SilentlyContinue"
$azureApiUrl = "https://management.azure.com"
$keyvaultToken = Get-AzAccessToken -ResourceUrl "https://vault.azure.net"
$token = Get-AzAccessToken -ResourceUrl $azureApiUrl
$azureHeaders = @{
    'Content-Type' = 'application/json'
    Authorization  = "Bearer $token" #-f $keyvaultToken.token
}


try {
    import-module .\Modules\mem-monitor-functions.psm1
}
catch {
    Write-Error "Functions module not found!"
    exit;
}
try {
    $authHeader = Get-AuthApiToken -resource $env:graphApiUrl
}
catch {
    Throw "No token received, $_"
}

try {
    Write-Information "Searching for certificates in key vault" -InformationAction Continue
    $breakglassCertificateUrl = "{0}/certificates/{1}/versions?api-version=7.0&maxresults=25&_=1714746115235" -f $env:KEYVAULT_URL, $env:BREAKGLASS_CERTNAME
    $results = Invoke-RestMethod -Uri $breakglassCertificateUrl -Headers $azureHeaders -Method Get
}
catch {
    Throw "Unable to request certificates, $_"
}

try {
    #Renew the certificate
    $certificate = 

    $renewUrl = "{0}/certificates/{1}/versions/{2}/create?action=Renew&api-version=7.0" -f $env:KEYVAULT_URL, $env:BREAKGLASS_CERTNAME, $certificate.properties.version

}
catch {

}
