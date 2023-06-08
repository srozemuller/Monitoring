# Input bindings are passed in via param block.
param($Request)

# Get the current universal time in the default string format.
$currentUTCtime = (Get-Date).ToUniversalTime()

# The 'IsPastDue' property is 'true' when the current function invocation is later than scheduled.
if ($Timer.IsPastDue) {
    Write-Host "PowerShell timer is running late!"
}
"Request output"
$Request | ConvertFrom-Json
($Request | ConvertFrom-Json).data