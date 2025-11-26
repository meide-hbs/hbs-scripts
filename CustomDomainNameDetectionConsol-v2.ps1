<#
CustomDomainNameDetectionConsol-v2.ps1

To remove a custom domain, you must verify the following no longer use that domain:

User UPNs (UserPrincipalName)
User proxy addresses (additional email addresses)
Group email addresses
Distribution group proxy addresses
Mail-enabled security groups
Application identifier URIs
Admin account UPNs
Mailbox email addresses
Mail contacts

#>

# Connect to Microsoft Graph
Connect-MgGraph -Scopes "User.Read.All" -TenantId "f3feb555-d1d6-432d-b947-ad6c52d0005b"

# Define the domain to check
$domain = "az1041.philynn.com"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Checking domain usage for: $domain" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Initialize results collection
$results = @{
    Users = @()
    Groups = @()
    Mailboxes = @()
    DistributionGroups = @()
    MailContacts = @()
    Applications = @()
}

# ============================================
# 1. CHECK USERS IN ENTRA ID
# ============================================
Write-Host "Checking Entra ID Users..." -ForegroundColor Yellow

try {
    # Check if already connected to Microsoft Graph
    $context = Get-MgContext
    if (-not $context) {
        Connect-MgGraph -Scopes "User.Read.All", "Group.Read.All", "Application.Read.All"
    }
    
    # Get users with domain in UPN or Mail
    $users = Get-MgUser -All -Property DisplayName,UserPrincipalName,Mail,ProxyAddresses,Id | 
        Where-Object {
            $_.UserPrincipalName -like "*@$domain" -or 
            $_.Mail -like "*@$domain" -or
            ($_.ProxyAddresses -join ';') -like "*@$domain*"
        }
    
    foreach ($user in $users) {
        $results.Users += [PSCustomObject]@{
            DisplayName = $user.DisplayName
            UserPrincipalName = $user.UserPrincipalName
            Mail = $user.Mail
            ProxyAddresses = ($user.ProxyAddresses -join '; ')
        }
    }
    
    Write-Host "Found $($results.Users.Count) user(s) using this domain`n" -ForegroundColor Green
}
catch {
    Write-Host "Error checking users: $_" -ForegroundColor Red
}

# ============================================
# 2. CHECK ENTRA ID GROUPS
# ============================================
Write-Host "Checking Entra ID Groups..." -ForegroundColor Yellow

try {
    $groups = Get-MgGroup -All -Property DisplayName,Mail,ProxyAddresses,Id | 
        Where-Object {
            $_.Mail -like "*@$domain" -or
            ($_.ProxyAddresses -join ';') -like "*@$domain*"
        }
    
    foreach ($group in $groups) {
        $results.Groups += [PSCustomObject]@{
            DisplayName = $group.DisplayName
            Mail = $group.Mail
            ProxyAddresses = ($group.ProxyAddresses -join '; ')
        }
    }
    
    Write-Host "Found $($results.Groups.Count) Entra group(s) using this domain`n" -ForegroundColor Green
}
catch {
    Write-Host "Error checking groups: $_" -ForegroundColor Red
}

# ============================================
# 3. CHECK EXCHANGE ONLINE RESOURCES
# ============================================
Write-Host "Checking Exchange Online resources..." -ForegroundColor Yellow
Write-Host "(This requires Exchange Online PowerShell connection)" -ForegroundColor Gray

try {
    # Check if connected to Exchange Online
    $exoConnection = Get-ConnectionInformation -ErrorAction SilentlyContinue
    
    if (-not $exoConnection) {
        Write-Host "Connecting to Exchange Online..." -ForegroundColor Gray
        Connect-ExchangeOnline -ShowBanner:$false
    }
    
    # Check mailboxes
    Write-Host "  - Checking mailboxes..." -ForegroundColor Gray
    $mailboxes = Get-Mailbox -ResultSize Unlimited | 
        Where-Object {$_.EmailAddresses -like "*@$domain*"}
    
    foreach ($mailbox in $mailboxes) {
        $results.Mailboxes += [PSCustomObject]@{
            DisplayName = $mailbox.DisplayName
            PrimarySmtpAddress = $mailbox.PrimarySmtpAddress
            EmailAddresses = ($mailbox.EmailAddresses -join '; ')
            RecipientType = $mailbox.RecipientTypeDetails
        }
    }
    
    Write-Host "    Found $($results.Mailboxes.Count) mailbox(es)" -ForegroundColor Green
    
    # Check distribution groups
    Write-Host "  - Checking distribution groups..." -ForegroundColor Gray
    $distGroups = Get-DistributionGroup -ResultSize Unlimited | 
        Where-Object {$_.EmailAddresses -like "*@$domain*"}
    
    foreach ($distGroup in $distGroups) {
        $results.DistributionGroups += [PSCustomObject]@{
            DisplayName = $distGroup.DisplayName
            PrimarySmtpAddress = $distGroup.PrimarySmtpAddress
            EmailAddresses = ($distGroup.EmailAddresses -join '; ')
            GroupType = $distGroup.RecipientTypeDetails
        }
    }
    
    Write-Host "    Found $($results.DistributionGroups.Count) distribution group(s)" -ForegroundColor Green
    
    # Check mail contacts
    Write-Host "  - Checking mail contacts..." -ForegroundColor Gray
    $mailContacts = Get-MailContact -ResultSize Unlimited | 
        Where-Object {$_.EmailAddresses -like "*@$domain*"}
    
    foreach ($contact in $mailContacts) {
        $results.MailContacts += [PSCustomObject]@{
            DisplayName = $contact.DisplayName
            PrimarySmtpAddress = $contact.PrimarySmtpAddress
            EmailAddresses = ($contact.EmailAddresses -join '; ')
        }
    }
    
    Write-Host "    Found $($results.MailContacts.Count) mail contact(s)`n" -ForegroundColor Green
}
catch {
    Write-Host "Error checking Exchange Online resources: $_" -ForegroundColor Red
    Write-Host "You may need to install/connect Exchange Online PowerShell module`n" -ForegroundColor Yellow
}

# ============================================
# 4. CHECK APPLICATIONS
# ============================================
Write-Host "Checking Applications..." -ForegroundColor Yellow

try {
    $apps = Get-MgApplication -All -Property DisplayName,AppId,IdentifierUris,Web,PublicClient | 
        Where-Object {
            ($_.IdentifierUris -join ';') -like "*$domain*" -or
            ($_.Web.RedirectUris -join ';') -like "*$domain*" -or
            ($_.PublicClient.RedirectUris -join ';') -like "*$domain*"
        }
    
    foreach ($app in $apps) {
        $results.Applications += [PSCustomObject]@{
            DisplayName = $app.DisplayName
            AppId = $app.AppId
            IdentifierUris = ($app.IdentifierUris -join '; ')
            RedirectUris = (($app.Web.RedirectUris + $app.PublicClient.RedirectUris) -join '; ')
        }
    }
    
    Write-Host "Found $($results.Applications.Count) application(s) using this domain`n" -ForegroundColor Green
}
catch {
    Write-Host "Error checking applications: $_" -ForegroundColor Red
}

# ============================================
# 5. DISPLAY RESULTS
# ============================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "SUMMARY REPORT" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$totalObjects = $results.Users.Count + $results.Groups.Count + $results.Mailboxes.Count + 
                $results.DistributionGroups.Count + $results.MailContacts.Count + $results.Applications.Count

Write-Host "Total objects using domain '$domain': $totalObjects`n" -ForegroundColor White

# Display Users
if ($results.Users.Count -gt 0) {
    Write-Host "USERS ($($results.Users.Count)):" -ForegroundColor Yellow
    Write-Host "=" * 80 -ForegroundColor Yellow
    $results.Users | Format-Table -AutoSize -Wrap
}

# Display Entra Groups
if ($results.Groups.Count -gt 0) {
    Write-Host "ENTRA ID GROUPS ($($results.Groups.Count)):" -ForegroundColor Yellow
    Write-Host "=" * 80 -ForegroundColor Yellow
    $results.Groups | Format-Table -AutoSize -Wrap
}

# Display Mailboxes
if ($results.Mailboxes.Count -gt 0) {
    Write-Host "MAILBOXES ($($results.Mailboxes.Count)):" -ForegroundColor Yellow
    Write-Host "=" * 80 -ForegroundColor Yellow
    $results.Mailboxes | Format-Table -AutoSize -Wrap
}

# Display Distribution Groups
if ($results.DistributionGroups.Count -gt 0) {
    Write-Host "DISTRIBUTION GROUPS ($($results.DistributionGroups.Count)):" -ForegroundColor Yellow
    Write-Host "=" * 80 -ForegroundColor Yellow
    $results.DistributionGroups | Format-Table -AutoSize -Wrap
}

# Display Mail Contacts
if ($results.MailContacts.Count -gt 0) {
    Write-Host "MAIL CONTACTS ($($results.MailContacts.Count)):" -ForegroundColor Yellow
    Write-Host "=" * 80 -ForegroundColor Yellow
    $results.MailContacts | Format-Table -AutoSize -Wrap
}

# Display Applications
if ($results.Applications.Count -gt 0) {
    Write-Host "APPLICATIONS ($($results.Applications.Count)):" -ForegroundColor Yellow
    Write-Host "=" * 80 -ForegroundColor Yellow
    $results.Applications | Format-Table -AutoSize -Wrap
}

# ============================================
# 6. EXPORT OPTION
# ============================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "EXPORT RESULTS" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$export = Read-Host "Would you like to export results to CSV files? (Y/N)"

if ($export -eq 'Y' -or $export -eq 'y') {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $exportPath = ".\DomainUsage-$domain-$timestamp"
    
    New-Item -ItemType Directory -Path $exportPath -Force | Out-Null
    
    if ($results.Users.Count -gt 0) {
        $results.Users | Export-Csv "$exportPath\Users.csv" -NoTypeInformation
        Write-Host "Exported: $exportPath\Users.csv" -ForegroundColor Green
    }
    
    if ($results.Groups.Count -gt 0) {
        $results.Groups | Export-Csv "$exportPath\Groups.csv" -NoTypeInformation
        Write-Host "Exported: $exportPath\Groups.csv" -ForegroundColor Green
    }
    
    if ($results.Mailboxes.Count -gt 0) {
        $results.Mailboxes | Export-Csv "$exportPath\Mailboxes.csv" -NoTypeInformation
        Write-Host "Exported: $exportPath\Mailboxes.csv" -ForegroundColor Green
    }
    
    if ($results.DistributionGroups.Count -gt 0) {
        $results.DistributionGroups | Export-Csv "$exportPath\DistributionGroups.csv" -NoTypeInformation
        Write-Host "Exported: $exportPath\DistributionGroups.csv" -ForegroundColor Green
    }
    
    if ($results.MailContacts.Count -gt 0) {
        $results.MailContacts | Export-Csv "$exportPath\MailContacts.csv" -NoTypeInformation
        Write-Host "Exported: $exportPath\MailContacts.csv" -ForegroundColor Green
    }
    
    if ($results.Applications.Count -gt 0) {
        $results.Applications | Export-Csv "$exportPath\Applications.csv" -NoTypeInformation
        Write-Host "Exported: $exportPath\Applications.csv" -ForegroundColor Green
    }
    
    Write-Host "`nAll reports exported to: $exportPath" -ForegroundColor Cyan
}

Write-Host "`nScript completed!" -ForegroundColor Green