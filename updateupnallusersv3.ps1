#Requires -Modules Microsoft.Graph.Users, Microsoft.Graph.Identity.DirectoryManagement

<#
.SYNOPSIS
    Removes a custom domain from EVERY user in the tenant (UPN, mail, proxyAddresses)
    Works even if you accidentally copied a broken version before
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    # ← this was missing in your broken copy
(
    [Parameter(Mandatory = $true)]
    [string]$CustomDomain,

    [Parameter(Mandatory = $true)]
    [string]$OnMicrosoftDomain,

    [Parameter(Mandatory = $false)]
    [string]$TenantId
)

function Write-Color {
    param(
        [string]$Text,
        [string]$Color = "White"
    )
    Write-Host $Text -ForegroundColor $Color
}

# Install modules if missing
foreach ($mod in "Microsoft.Graph.Users", "Microsoft.Graph.Identity.DirectoryManagement") {
    if (-not (Get-Module -ListAvailable -Name $mod)) {
        Write-Color "Installing module $mod ..." "Yellow"
        Install-Module $mod -Scope CurrentUser -Force -AllowClobber
    }
    Import-Module $mod -Force
}

# ===================================================================
# MAIN SCRIPT
# ===================================================================
try {
    Write-Color "`n=== COMPLETE CUSTOM DOMAIN CLEANUP ===`n" "Cyan"
    Write-Color "Removing domain : $CustomDomain" "Red"
    Write-Color "Fallback domain : $OnMicrosoftDomain`n" "Green"

    # Connect
    $scopes = "User.ReadWrite.All", "Directory.ReadWrite.All"
    if ($TenantId) {
        Connect-MgGraph -Scopes $scopes -TenantId $TenantId -NoWelcome
        Write-Color "Targeting tenant: $TenantId" "Cyan"
    } else {
        Connect-MgGraph -Scopes $scopes -NoWelcome
    }

    $tenant = (Get-MgContext).TenantId
    Write-Color "Successfully connected to tenant: $tenant`n" "Green"

    # Get ALL users
    Write-Color "Retrieving ALL users in the tenant..." "Yellow"
    $allUsers = Get-MgUser -All -Property Id, UserPrincipalName, DisplayName, Mail, ProxyAddresses

    Write-Color "Found $($allUsers.Count) users. Starting cleanup...`n" "Green"

    $results  = @()
    $changed  = 0
    $skipped  = 0
    $unchanged = 0

    foreach ($user in $allUsers) {
        $oldUPN       = $user.UserPrincipalName
        $usernamePart = $oldUPN.Split('@')[0]
        $newUPN       = "$usernamePart@$OnMicrosoftDomain"

        $needsUpdate = $false
        $body    = @{}

        Write-Color "Processing → $($user.DisplayName) ($oldUPN)" "Cyan"

        # 1. UPN
        if ($oldUPN -like "*@$CustomDomain") {
            Write-Color "   • Changing UPN → $newUPN" "Yellow"
            $body.userPrincipalName = $newUPN
            $needsUpdate = $true
        }

        # 2. Mail attribute
        if ($user.Mail -and $user.Mail -like "*@$CustomDomain") {
            Write-Color "   • Changing mail → $newUPN" "Yellow"
            $body.mail = $newUPN
            $needsUpdate = $true
        }

        # 3. ProxyAddresses
        $newProxy   = @()
        $removed    = 0
        $hasPrimary = $false

        foreach ($p in $user.ProxyAddresses) {
            if ($p -match "(?i)@$CustomDomain") {
                Write-Color "     Removing proxy: $p" "DarkGray"
                $removed++
                continue
            }
            if ($p -eq "SMTP:$newUPN") { $hasPrimary = $true }
            $newProxy += $p
        }

        if ($removed -gt 0) {
            Write-Color "   • Removed $removed proxy address(es)" "Magenta"
            $needsUpdate = $true
        }

        # Make sure new address is primary
        if ($oldUPN -like "*@$CustomDomain" -or -not $hasPrimary) {
            $newProxy = @("SMTP:$newUPN") + ($newProxy | Where-Object { $_ -notlike "SMTP:*" })
            Write-Color "   • Set primary SMTP: SMTP:$newUPN" "Gray"
        }

        if ($newProxy.Count -gt 0) {
            $body.proxyAddresses = $newProxy
        }

        # Nothing to do?
        if (-not $needsUpdate) {
            Write-Color "   → No changes needed`n" "Gray"
            $unchanged++
            continue
        }

        # UPN conflict check
        if ($body.ContainsKey("userPrincipalName")) {
            $conflict = Get-MgUser -Filter "userPrincipalName eq '$newUPN'" -ErrorAction SilentlyContinue
            if ($conflict -and $conflict.Id -ne $user.Id) {
                Write-Color "   SKIPPED – $newUPN already exists`n" "Red"
                $skipped++
                $results += [pscustomobject]@{
                    DisplayName = $user.DisplayName
                    OldUPN      = $oldUPN
                    IntendedUPN = $newUPN
                    Status      = "Skipped – UPN conflict"
                }
                continue
            }
        }

        # Apply or WhatIf
        if ($PSCmdlet.ShouldProcess($oldUPN, "Remove $CustomDomain (UPN/mail/proxy)")) {
            Update-MgUser -UserId $user.Id -BodyParameter $body
            Write-Color "   SUCCESS`n" "Green"
            $changed++
        } else {
            Write-Color "   WHATIF – changes would be applied`n" "Magenta"
            $changed++
        }

        $results += [pscustomobject]@{
            DisplayName     = $user.DisplayName
            OldUPN          = $oldUPN
            NewUPN          = $newUPN
            ProxiesRemoved  = $removed
            Status          = if ($PSCmdlet.ShouldProcess) { "Success" else "WhatIf"
        }
    }

    # Summary
    Write-Color "=== CLEANUP COMPLETE ===" "Cyan"
    Write-Color "Scanned    : $($allUsers.Count)" "White"
    Write-Color "Changed    : $changed" "Green"
    Write-Color "Unchanged  : $unchanged" "Gray"
    Write-Color "Skipped    : $skipped`n" "Yellow"

    $csv = ".\Cleanup_$CustomDomain_$(Get-Date -Format yyyyMMdd_HHmmss).csv"
    $results | Export-Csv -Path $csv -NoTypeInformation
    Write-Color "Full report → $csv" "Cyan"

    Disconnect-MgGraph | Out-Null
}
catch {
    Write-Color "`nFATAL ERROR: $($_.Exception.Message)" "Red"
    Write-Error $_
    Disconnect-MgGraph -ErrorAction SilentlyContinue
}
