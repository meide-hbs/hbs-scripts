# Entra ID UPN Update Script

This PowerShell script updates the UserPrincipalName (UPN) for all users in an Entra ID tenant from a custom domain to the onmicrosoft.com domain.

## Prerequisites

1. **PowerShell 7.0 or later** (recommended) or Windows PowerShell 5.1
2. **Microsoft.Graph.Users module** installed
3. **Appropriate permissions**: User Administrator or Global Administrator role in Entra ID

## Installation

### Install Microsoft Graph PowerShell Module

```powershell
Install-Module Microsoft.Graph.Users -Scope CurrentUser
```

## Usage

### Basic Usage

```powershell
.\Update-UPNToOnMicrosoft.ps1 -CustomDomain "contoso.com" -OnMicrosoftDomain "contoso.onmicrosoft.com"
```

### With Tenant ID (Recommended for Safety)

To ensure you're updating the correct tenant, specify the Tenant ID:

```powershell
.\Update-UPNToOnMicrosoft.ps1 -CustomDomain "contoso.com" -OnMicrosoftDomain "contoso.onmicrosoft.com" -TenantId "12345678-1234-1234-1234-123456789012"
```

**To find your Tenant ID:**
- Azure Portal: Azure Active Directory > Overview > Tenant ID
- PowerShell: `(Get-MgContext).TenantId` (after connecting)
- Or from your onmicrosoft.com domain properties

### Test Run (WhatIf Mode)

To see what changes would be made without actually making them:

```powershell
.\Update-UPNToOnMicrosoft.ps1 -CustomDomain "contoso.com" -OnMicrosoftDomain "contoso.onmicrosoft.com" -TenantId "12345678-1234-1234-1234-123456789012" -WhatIf
```

## Parameters

- **CustomDomain** (Required): The custom domain to replace (e.g., "contoso.com")
- **OnMicrosoftDomain** (Required): The onmicrosoft.com domain to use (e.g., "contoso.onmicrosoft.com")
- **TenantId** (Optional): The Tenant ID (GUID) to ensure you're connecting to the correct tenant for added safety
- **WhatIf** (Optional): Shows what changes would be made without actually making them

## How It Works

1. Connects to Microsoft Graph with User.ReadWrite.All permission
2. If TenantId is specified, validates connection to the correct tenant (aborts if mismatch)
3. Retrieves all users whose UPN ends with the specified custom domain
4. For each user:
   - Extracts the username portion of the UPN
   - Creates a new UPN with the onmicrosoft.com domain
   - Checks if the new UPN already exists (to avoid conflicts)
   - Updates the user's UPN (unless in WhatIf mode)
5. Exports results to a CSV file with timestamp
6. Displays a summary of the operation

## Example Scenarios

### Scenario 1: Migration from Custom Domain
You're migrating from `company.com` to `company.onmicrosoft.com`:

```powershell
.\Update-UPNToOnMicrosoft.ps1 -CustomDomain "company.com" -OnMicrosoftDomain "company.onmicrosoft.com"
```

### Scenario 2: Test Before Executing
Always recommended to test first:

```powershell
# First, run with -WhatIf to see what would happen
.\Update-UPNToOnMicrosoft.ps1 -CustomDomain "company.com" -OnMicrosoftDomain "company.onmicrosoft.com" -WhatIf

# If everything looks good, run without -WhatIf
.\Update-UPNToOnMicrosoft.ps1 -CustomDomain "company.com" -OnMicrosoftDomain "company.onmicrosoft.com"
```

## Output

The script provides:
- Color-coded console output showing progress
- A CSV file with detailed results (saved with timestamp: `UPN_Update_Results_YYYYMMDD_HHMMSS.csv`)

### CSV Columns
- DisplayName
- OldUPN
- NewUPN
- Status (Success/Failed/Skipped/WhatIf)
- Error (if applicable)

## Important Notes

### Before Running

1. **Test in a non-production environment first** if possible
2. **Run with -WhatIf parameter** to preview changes
3. **Specify the TenantId parameter** to ensure you're updating the correct tenant
4. **Back up your tenant configuration** or document current UPNs
5. **Verify the onmicrosoft.com domain** is available in your tenant
6. **Communicate with users** about the UPN change, as it may affect their sign-in credentials

### Considerations

- Users will need to sign in with their new UPN after the change
- Some applications may cache the old UPN and require re-authentication
- Email addresses (mail attribute) are NOT changed by this script, only UPN
- If a new UPN already exists for another user, that user will be skipped
- The script requires User.ReadWrite.All permission in Microsoft Graph

### Permissions Required

The account running the script needs one of the following roles:
- Global Administrator
- User Administrator
- Privileged Authentication Administrator

## Troubleshooting

### "Microsoft.Graph.Users module is not installed"
```powershell
Install-Module Microsoft.Graph.Users -Scope CurrentUser
```

### "Insufficient privileges to complete the operation"
Ensure you're signed in with an account that has User Administrator or Global Administrator role.

### "Failed to connect to Microsoft Graph"
- Check your internet connection
- Verify you have the correct permissions
- Try running: `Disconnect-MgGraph` then retry

### Conflict: UPN already exists
If the new UPN already exists for another user, the script will skip that update. Review your naming convention to resolve conflicts.

## Recovery

If you need to revert changes:
1. Use the generated CSV file to see the old UPNs
2. Modify and run the script with reversed parameters
3. Or manually update affected users in the Entra ID portal

## Security Best Practices

- Run the script from a secure administrative workstation
- Use an account with least-privilege (User Administrator rather than Global Admin if possible)
- Review the audit logs after execution
- Keep the results CSV file secure as it contains user information

## Support

For issues with:
- **The script**: Review the error messages and check the troubleshooting section
- **Microsoft Graph**: Visit https://docs.microsoft.com/graph
- **Entra ID**: Visit https://docs.microsoft.com/entra
