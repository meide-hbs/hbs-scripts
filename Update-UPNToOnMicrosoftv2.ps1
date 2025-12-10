#Requires -Modules Microsoft.Graph.Users

<#
.SYNOPSIS
    Updates UserPrincipalName for all users from a custom domain to onmicrosoft.com domain.

.DESCRIPTION
    This script connects to Microsoft Graph and updates the UPN for all users
    in an Entra ID tenant from a specified custom domain to the onmicrosoft.com domain.

.PARAMETER CustomDomain
    The custom domain to replace (e.g., "contoso.com")

.PARAMETER OnMicrosoftDomain
    The onmicrosoft.com domain to use (e.g., "contoso.onmicrosoft.com")

.PARAMETER TenantId
    Optional. The Tenant ID (GUID) to ensure you're connecting to the correct tenant

.PARAMETER WhatIf
    Shows what changes would be made without actually making them

.EXAMPLE
    .\Update-UPNToOnMicrosoft.ps1 -CustomDomain "contoso.com" -OnMicrosoftDomain "contoso.onmicrosoft.com"

.EXAMPLE
    .\Update-UPNToOnMicrosoft.ps1 -CustomDomain "contoso.com" -OnMicrosoftDomain "contoso.onmicrosoft.com" -TenantId "12345678-1234-1234-1234-123456789012"

.EXAMPLE
    .\Update-UPNToOnMicrosoft.ps1 -CustomDomain "contoso.com" -OnMicrosoftDomain "contoso.onmicrosoft.com" -WhatIf
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [string]$CustomDomain,
    
    [Parameter(Mandatory = $true)]
    [string]$OnMicrosoftDomain,
    
    [Parameter(Mandatory = $false)]
    [string]$TenantId
)

# Function to write colored output
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

# Function to test if Microsoft.Graph module is installed
function Test-GraphModule {
    $module = Get-Module -ListAvailable -Name Microsoft.Graph.Users
    if (-not $module) {
        Write-ColorOutput "Microsoft.Graph.Users module is not installed." "Red"
        Write-ColorOutput "Please install it using: Install-Module Microsoft.Graph.Users -Scope CurrentUser" "Yellow"
        return $false
    }
    return $true
}

# Main script execution
try {
    Write-ColorOutput "`n=== Entra ID UPN Update Script ===" "Cyan"
    Write-ColorOutput "Custom Domain: $CustomDomain" "White"
    Write-ColorOutput "Target Domain: $OnMicrosoftDomain" "White"
    if ($TenantId) {
        Write-ColorOutput "Target Tenant: $TenantId" "White"
    }
    Write-Host ""

    # Check if module is installed
    if (-not (Test-GraphModule)) {
        exit 1
    }

    # Import the module
    Write-ColorOutput "Importing Microsoft Graph modules..." "Yellow"
    Import-Module Microsoft.Graph.Users

    # Connect to Microsoft Graph with required permissions
    Write-ColorOutput "Connecting to Microsoft Graph..." "Yellow"
    Write-ColorOutput "Please sign in with an account that has User Administrator or Global Administrator permissions." "Cyan"
    
    if ($TenantId) {
        Write-ColorOutput "Targeting tenant: $TenantId" "Cyan"
        Connect-MgGraph -Scopes "User.ReadWrite.All" -TenantId $TenantId -NoWelcome
    }
    else {
        Connect-MgGraph -Scopes "User.ReadWrite.All" -NoWelcome
    }
    
    $context = Get-MgContext
    if (-not $context) {
        throw "Failed to connect to Microsoft Graph"
    }
    
    Write-ColorOutput "Successfully connected to tenant: $($context.TenantId)" "Green"
    
    # Verify tenant if TenantId was specified
    if ($TenantId -and $context.TenantId -ne $TenantId) {
        throw "Connected to tenant $($context.TenantId) but expected $TenantId. Aborting for safety."
    }

    # Get all users with the custom domain in their UPN
    Write-ColorOutput "`nRetrieving users with UPN ending in @$CustomDomain..." "Yellow"
    
    $users = Get-MgUser -All -Filter "endsWith(userPrincipalName, '@$CustomDomain')" -Property Id, UserPrincipalName, DisplayName, Mail -ConsistencyLevel eventual -CountVariable userCount
    
    if ($users.Count -eq 0) {
        Write-ColorOutput "No users found with UPN ending in @$CustomDomain" "Yellow"
        Disconnect-MgGraph | Out-Null
        exit 0
    }

    Write-ColorOutput "Found $($users.Count) user(s) to update`n" "Green"

    # Initialize counters
    $successCount = 0
    $failureCount = 0
    $skippedCount = 0
    $results = @()

    # Process each user
    foreach ($user in $users) {
        $oldUPN = $user.UserPrincipalName
        $username = $oldUPN.Split('@')[0]
        $newUPN = "$username@$OnMicrosoftDomain"

        Write-ColorOutput "Processing: $($user.DisplayName)" "Cyan"
        Write-ColorOutput "  Old UPN: $oldUPN" "White"
        Write-ColorOutput "  New UPN: $newUPN" "White"

        try {
            # Check if new UPN already exists
            $existingUser = Get-MgUser -Filter "userPrincipalName eq '$newUPN'" -ErrorAction SilentlyContinue
            
            if ($existingUser -and $existingUser.Id -ne $user.Id) {
                Write-ColorOutput "  Status: SKIPPED - UPN $newUPN already exists for another user" "Yellow"
                $skippedCount++
                $results += [PSCustomObject]@{
                    DisplayName = $user.DisplayName
                    OldUPN = $oldUPN
                    NewUPN = $newUPN
                    Status = "Skipped - UPN exists"
                }
                continue
            }

            # Determine if this is a WhatIf run
            $isWhatIf = $WhatIfPreference -or $PSBoundParameters.ContainsKey('WhatIf')
            
            if ($isWhatIf) {
                Write-ColorOutput "  Status: WHATIF - Would update UPN" "Magenta"
                $successCount++
                
                $results += [PSCustomObject]@{
                    DisplayName = $user.DisplayName
                    OldUPN = $oldUPN
                    NewUPN = $newUPN
                    Status = "WhatIf"
                }
            }
            else {
                # Update the UPN
                Update-MgUser -UserId $user.Id -UserPrincipalName $newUPN
                Write-ColorOutput "  Status: SUCCESS" "Green"
                $successCount++
                
                $results += [PSCustomObject]@{
                    DisplayName = $user.DisplayName
                    OldUPN = $oldUPN
                    NewUPN = $newUPN
                    Status = "Success"
                }
            }
        }
        catch {
            Write-ColorOutput "  Status: FAILED - $($_.Exception.Message)" "Red"
            $failureCount++
            $results += [PSCustomObject]@{
                DisplayName = $user.DisplayName
                OldUPN = $oldUPN
                NewUPN = $newUPN
                Status = "Failed"
                Error = $_.Exception.Message
            }
        }
        Write-Host ""
    }

    # Summary
    Write-ColorOutput "=== Update Summary ===" "Cyan"
    Write-ColorOutput "Total users processed: $($users.Count)" "White"
    Write-ColorOutput "Successful updates: $successCount" "Green"
    Write-ColorOutput "Failed updates: $failureCount" "Red"
    Write-ColorOutput "Skipped: $skippedCount" "Yellow"

    # Export results to CSV
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $csvPath = ".\UPN_Update_Results_$timestamp.csv"
    $results | Export-Csv -Path $csvPath -NoTypeInformation
    
    if ($WhatIfPreference) {
        Write-ColorOutput "`nWhatIf mode: Preview results exported to: $csvPath" "Magenta"
    }
    else {
        Write-ColorOutput "`nResults exported to: $csvPath" "Cyan"
    }

    # Disconnect from Graph
    Disconnect-MgGraph | Out-Null
    Write-ColorOutput "`nDisconnected from Microsoft Graph" "Yellow"
}
catch {
    Write-ColorOutput "`nError: $($_.Exception.Message)" "Red"
    Write-ColorOutput "Stack Trace: $($_.Exception.StackTrace)" "Red"
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    exit 1
}
