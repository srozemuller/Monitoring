# Input bindings are passed in via param block.
param($Request)
# Get the current West Europe time in the default string format.
$currentTime = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId( (Get-Date), 'W. Europe Standard Time').ToString('yyyy-MM-dd HH:mm:ss')
$informationPreference = 'Continue'
# Write an information log with the current time.
Write-Output "PowerShell timer trigger function ran! TIME: $currentTime"
# Connect to Azure using the system assigned identity
Connect-AzAccount -Identity

$ProgressPreference = "SilentlyContinue"
$keyvaultToken = Get-AzAccessToken -ResourceUrl "https://vault.azure.net"
$graphToken = Get-AzAccessToken -ResourceUrl $env:GRAPHAPI_URL
$keyvaultHeaders = @{
    'Content-Type' = 'application/json'
    Authorization  = "Bearer {0}" -f $keyvaultToken.token
}
$graphHeader = @{
    'Content-Type' = 'application/json'
    Authorization  = "Bearer {0}" -f $graphToken.token
}

$graphToken.token
try {
    import-module .\Modules\mem-monitor-functions.psm1
}
catch {
    Write-Error "Functions module not found!"
    exit;
}


try {
    Write-Information "Searching for certificates in key vault" -InformationAction Continue
    $breakglassCertificateUrl = "{0}/certificates/{1}?api-version=7.4&maxresults=25&_=1714746115235" -f $env:KEYVAULT_URL, $env:BREAKGLASS_CERTNAME
    $results = Invoke-RestMethod -Uri $breakglassCertificateUrl -Headers $keyvaultHeaders -Method Get
}
catch {
    Throw "Unable to request certificates, $_"
}

try {
    if (!$results) {
        Throw "No certificates found"
    }
    Write-Output "First renew certifcate"
    #Renew the certificate
    $renewBody = @{
        attributes = $results.attributes
        policy     = $results.policy
    } | ConvertTo-Json -Depth 99
    $renewUrl = "{0}/certificates/{1}/create?api-version=7.0" -f $env:KEYVAULT_URL, $env:BREAKGLASS_CERTNAME
    $status = Invoke-RestMethod -Uri $renewUrl -Headers $keyvaultHeaders -Method POST -Body $renewBody
    do {
        $status = Invoke-RestMethod -Uri $renewUrl -Headers $keyvaultHeaders -Method GET
    }
    while ($status.status)

    Write-Output "Exporting certificate and make it ready for attaching it to the application"
    # Convert the secret value to a byte array
    $certBytes = [System.Convert]::FromBase64String($status.cer)
    # Create a new X509Certificate2 object using the byte array and password
    $x509Cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList ($certBytes, $certPassword, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable)
    # Export the certificate with the private key
    $pfxBytes = $x509Cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx, $certPassword)
    $certFilePath = "certificate.pfx"
    # Write the byte array to a file
    [System.IO.File]::WriteAllBytes($certFilePath, $pfxBytes)
    # Read the certificate file
    $certBytes = [System.IO.File]::ReadAllBytes($certFilePath)
    $base64Cert = [Convert]::ToBase64String($certBytes)
}
catch {
    Throw $_
}
    
try {
    Write-Output "Upload the certificate to the application"
    $graphUrl = "{0}/beta/applications/{1}" -f $env:GRAPHAPI_URL, $env:APPLICATION_ID
    $createdAt = Get-Date -UnixTimeSeconds $status.attributes.created -AsUTC -Format "o"
    $expiresAt = Get-Date -UnixTimeSeconds $status.attributes.exp -AsUTC -Format "o"
    $certBody = @{
        "keyCredentials" = @(
            @{
                "endDateTime"   = $expiresAt
                "startDateTime" = $createdAt
                "type"          = "AsymmetricX509Cert"
                "usage"         = "Verify"
                "key"           = $status.cer
                "displayName"   = "breakglass"
            }
        )
    } | ConvertTo-Json
    Invoke-RestMethod -Method PATCH -Uri $graphUrl -Headers $graphHeader -Body $certBody

    Write-Output "Send mail to administrator"
    $body =
    @"
{
    "message": {
      "subject": "Meet for lunch?",
      "body": {
        "contentType": "Text",
        "content": "New certificate for break glass"
      },
      "toRecipients": [
        {
          "emailAddress": {
            "address": "$($env:ADMIN_EMAIL)"
          }
        }
      ],
      "attachments": [
        {
          "@odata.type": "#microsoft.graph.fileAttachment",
          "name": "cert.pfx",
          "contentType": "application/x-pkcs12",
          "contentBytes": "$base64Cert"
        }
      ]
    }
  }
"@

    $sendMailUrl = "https://graph.microsoft.com/v1.0/users/{0}/sendMail" -f $env:ADMIN_EMAIL
    Invoke-RestMethod -Method POST -Uri $sendMailUrl -Headers $graphHeader -Body $body
}
catch {
    Throw $_
}
