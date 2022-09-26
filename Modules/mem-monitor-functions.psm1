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