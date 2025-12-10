# 1. Install / update (run once)
Install-Module Microsoft.Graph -Scope CurrentUser

# 2. Connect (interactive or app-only)
Connect-MgGraph -Scopes "Domain.ReadWrite.All"

# 3. Start the force deletion (asynchronous)
$domainName = "contoso.com"

Invoke-MgForceDomainDelete -DomainId $domainName -BodyParameter @{
    disableUserAccounts = $true   # optional
}

# The command outputs the Location header URL automatically, e.g.:
# Location: https://graph.microsoft.com/v1.0/directory/operations/...

# 4. Capture the operation URL and poll it
$operationUrl = (Invoke-MgForceDomainDelete -DomainId $domainName -BodyParameter @{disableUserAccounts=$true}).Headers.Location

do {
    Start-Sleep -Seconds 30
    $op = Invoke-MgGraphRequest -Method GET -Uri $operationUrl
    Write-Host "Status: $($op.status)  -  $($op.lastActionDateTime)"
} while ($op.status -in @("notStarted","running","inProgress"))

# 5. When it finishes, show detailed error if it failed
if ($op.status -eq "failed") {
    $op.error | ConvertTo-Json -Depth 10 | Write-Host -ForegroundColor Red
}
else {
    Write-Host "Domain deleted successfully!" -ForegroundColor Green
}
