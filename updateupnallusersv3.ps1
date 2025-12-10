#Requires -Modules Microsoft.Graph.Users, Microsoft.Graph.Identity.DirectoryManagement

<#
.SYNOPSIS
    Cleans ALL users in the tenant:
    - Removes any trace of a specified custom domain from:
        • UserPrincipalName
        • Mail attribute
        • ProxyAddresses (SMTP, smtp, X500, etc.)
    - Migrates affected users to their .onmicrosoft.com equivalent

.PARAMETER CustomDomain
    The domain to completely remove (e.g., contoso.com, oldcompany.org)

.PARAMETER OnMicrosoftDomain
    Your tenant's .onmicrosoft.com domain (e.g., company.onmicrosoft.com)

.PARAMETER TenantId
    Optional: Specify tenant ID for safety

.PARAMETER WhatIf
    Preview all changes without applying them

.EXAMPLE
    .\Remove-CustomDomainFromAllUsers.ps1 -CustomDomain "oldcompany.com" -OnMicrosoftDomain "company.onmicrosoft.com" -WhatIf

.EXAMPLE
    .\Remove-CustomDomainFromAllUsers.ps1 -CustomDomain "fabrikam.org" -OnMicrosoftDomain "fabrikam.onmicrosoft.com"
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$CustomDomain,

    [Parameter(Mandatory = $true)]
    [string]$OnMicrosoftDomain,

    [Parameter(Mandatory = $false)]
    [string]$TenantId
)

function Write-Color {
    param([string]$Text, [string]$Color = "White")
    Write-Host $Text -ForegroundColor $Color
}

# Ensure required modules
foreach ($mod in "Microsoft.Graph.Users", "Microsoft.Graph.Identity.DirectoryManagement") {
    if (-not (Get-Module -ListAvailable -Name $mod) {
        Write-Color "Installing module: $mod" "Yellow"
        Install-Module $mod -Scope CurrentUser -Force -AllowClobber
    }
    Import-Module $mod -Force
}

try {
    Write-Color "`n=== Full Custom Domain Cleanup Script ===" "Cyan"
    Write-Color "Target domain to remove: $CustomDomain" "Red"
    Write-Color "Fallback domain: $OnMicrosoftDomain" "Green"
    if ($TenantId) { Write-Color "Tenant ID: $TenantId" "Gray" }
    Write-Host ""

    # Connect with full permissions
    $scopes = "User.ReadWrite.All", "Directory.ReadWrite.All"
    if ($TenantId) {
        Connect-MgGraph -Scopes $scopes -TenantId $TenantId -NoWelcome
    } else {
        Connect-MgGraph -Scopes $scopes -NoWelcome
    }

    $context = Get-MgContext
    Write-Color "Connected to tenant: $($context.TenantId)" "Green"

    if ($TenantId -and $
