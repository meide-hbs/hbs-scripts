<# 
.SYNOPSIS
    Completely removes a custom domain from ALL users in the tenant
                 (UPN, mail attribute and all proxyAddresses)
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

function Write-Color([string]$Text, [string]$Color = "White") {
    Write-Host $Text -ForegroundColor $Color
}

# --- Ensure modules are available -------------------------------------------------
@("Microsoft.Graph.Users", "Microsoft.Graph.Identity.DirectoryManagement") | ForEach-Object {
    if (-not (Get-Module -ListAvailable -Name $_)) {
        Write-Color "Installing module $_ ..." "Yellow"
        Install-Module $_ -Scope CurrentUser -Force -AllowClobber
    }
    Import-Module $_ -Force
}

# --- Main script ------------------------------------------------------------------
try {
    Write-Color "`n=== CUSTOM DOMAIN CLEANUP SCRIPT ===`n" "Cyan"
    Write-Color "Domain to remove : $CustomDomain" "Red"
    Write-Color "Fallback domain  : $OnMicrosoftDomain`n" "Green"

    # Connect to Graph
    $scopes = "User.ReadWrite.All", "Directory.ReadWrite.All"
    if ($TenantId) {
        Connect-MgGraph -Scopes $scopes -TenantId $TenantId -NoWelcome
        Write-Color "Targeting tenant : $TenantId" "Cyan"
    } else {
        Connect-MgGraph -Scopes $scopes -NoWelcome
    }

    Write-Color "Connected to tenant : $((Get-MgContext).TenantId)`n" "Green"

    # Get every user
    Write-Color "Retrieving ALL users..." "Yellow"
    $users = Get-MgUser -All -Property Id, UserPrincipalName, DisplayName, Mail, ProxyAddresses

    Write-Color "Found $($users.Count) users. Processing...`n" "Green"

    $results   = @()
    $changed   = 0
    # includes WhatIf
    $unchanged = 0
    $skipped   = 0

    foreach ($user in $users) {
        $oldUPN       = $user.UserPrincipalName
        $username     = $oldUPN.Split('@')[0]
        $newUPN       = "$username@$OnMicrosoftDomain"
        $needsUpdate  = $false
        $body         = @{}

        Write-Color "User: $($user.DisplayName)  ($oldUPN)" "Cyan"

        # 1. Fix UPN if needed
        if ($oldUPN -like "*@$CustomDomain") {
            Write-Color "   → Changing UPN to $newUPN" "Yellow"
            $body.userPrincipalName = $newUPN
            $needsUpdate = $true
        }

        # 2. Fix mail attribute if needed
        if ($user.Mail -and $user.Mail -like "*@$CustomDomain") {
            Write-Color "   → Changing mail to $newUPN" "Yellow"
            $body.mail = $newUPN
            $needsUpdate = $true
        }

        # 3. Clean proxyAddresses
        $newProxy   = @()
        $removed    = 0
        $hasPrimary = $false

        foreach ($proxy in $user.ProxyAddresses) {
            if ($proxy -match "(?i)@$CustomDomain") {
                Write-Color "      Removing → $proxy" "DarkGray"
                $removed++
                continue
            }
            if ($proxy -eq "SMTP:$newUPN") { $hasPrimary = $true }
            $newProxy += $proxy
        }

        if ($removed -gt 0) {
            Write-Color "   → Removed $removed proxy address(es)" "Magenta"
            $needsUpdate = $true
        }

        # Ensure the new address is the primary SMTP
        if ($oldUPN -like "*@$CustomDomain" -or -not $hasPrimary) {
            $newProxy = @("SMTP:$newUPN") + ($newProxy | Where-Object { $_ -notlike "SMTP:*" })
            Write-Color "   → Set primary address SMTP:$newUPN" "Gray"
        }

        if ($newProxy.Count -gt 0) {
            $body.proxyAddresses = $newProxy
        }

        # Nothing to do?
        if (-not $needsUpdate) {
            Write-Color "   No changes needed`n" "Gray"
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
                    NewUPN      = $newUPN
                    Status      = "Skipped - UPN conflict"
                }
                continue
            }
        }

        # Apply changes (or WhatIf)
        if ($PSCmdlet.ShouldProcess($oldUPN, "Remove $CustomDomain from UPN/mail/proxyAddresses")) {
            Update-MgUser -UserId $user.Id -BodyParameter $body
            Write-Color "   SUCCESS`n" "Green"
        } else {
            Write-Color "   WHATIF – changes would be applied`n" "Magenta"
        }
        $changed++

        $results += [pscustomobject]@{
            DisplayName    = $user.DisplayName
            OldUPN         = $oldUPN
            NewUPN         = $newUPN
            ProxiesRemoved = $removed
            Status         = if ($PSCmdlet.ShouldProcess) { "Success" } else { "WhatIf" }
        }
    }

    # Final report
    Write-Color "=== SUMMARY ===" "Cyan"
    Write-Color "Total users   : $($users.Count)" "White"
    Write-Color "Changed       : $changed" "Green"
    Write-Color "Unchanged     : $unchanged" "Gray"
    Write-Color "Skipped       : $skipped`n" "Yellow"

    $csvFile = "CleanupResults_$CustomDomain_$(Get-Date -Format yyyyMMdd_HHmmss).csv"
    $results | Export-Csv -Path $csvFile -NoTypeInformation
    Write-Color "Detailed report saved to: $csvFile" "Cyan"

    Disconnect-MgGraph -ErrorAction SilentlyContinue
}
catch {
    Write-Color "`nERROR: $($_.Exception.Message)" "Red"
    Write-Error $_
    Disconnect-MgGraph -ErrorAction SilentlyContinue
}
