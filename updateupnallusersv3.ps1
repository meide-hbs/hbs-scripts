<# 
.SYNOPSIS
    Permanently removes a custom domain from EVERY user in your tenant owns
    → Fixes UPN, mail attribute and ALL proxyAddresses
    → Works with -WhatIf and real runs
    → Tested December 2025 with Microsoft.Graph 2.x
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$CustomDomain,               # e.g. flambeau.com

    [Parameter(Mandatory = $true)]
    [string]$OnMicrosoftDomain,          # e.g. flambeauinc.onmicrosoft.com

    [Parameter(Mandatory = $false)]
    [string]$TenantId
)

# ──────────────────────────────────────────────────────────────
function Write-Color {
    param([string]$Text, [string]$Color = "White")
    Write-Host $Text -ForegroundColor $Color
}
 ──────────────────────────────────────────────────────────────

# Ensure required modules
@("Microsoft.Graph.Users", "Microsoft.Graph.Identity.DirectoryManagement") | ForEach-Object {
    if (-not (Get-Module -ListAvailable -Name $_)) {
        Write-Color "Installing $_ ..." "Yellow"
        Install-Module $_ -Scope CurrentUser -Force -AllowClobber
    }
    Import-Module $_ -Force
}

try {
    Write-Color "`n=== CUSTOM DOMAIN COMPLETE REMOVAL SCRIPT ===`n" "Cyan"
    Write-Color "Removing     : $CustomDomain" "Red"
    Write-Color "Fallback to  : $OnMicrosoftDomain`n" "Green"

    # Connect
    $scopes = "User.ReadWrite.All", "Directory.ReadWrite.All"
    if ($TenantId) {
        Connect-MgGraph -Scopes $scopes -TenantId $TenantId -NoWelcome
    } else {
        Connect-MgGraph -Scopes $scopes -NoWelcome
    }
    Write-Color "Connected to tenant: $((Get-MgContext).TenantId)`n" "Green"

    # Get every
