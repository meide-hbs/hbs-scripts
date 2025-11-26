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
# CONNECT TO MICROSOFT GRAPH WITH PROPER SCOPES
# ============================================
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Yellow

try {
    # Disconnect any existing session first
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    
    # Connect with all required permissions
    Connect-MgGraph -Scopes "User.Read.All", "Group.Read.All", "Application.Read.All", "Directory.Read.All" -NoWelcome
    
    $context = Get-MgContext
    Write-Host "Connected as: $($context.Account)" -ForegroundColor Green
    Write-Host "Scopes: $($context.Scopes -join ', ')`n" -ForegroundColor Gray
}
catch {
    Write-Host "Error connecting to Microsoft Graph: $_" -ForegroundColor Red
    Write-Host "Please ensure you have the Microsoft.Graph module installed." -ForegroundColor Yellow
    Write-Host "Run: Install-Module Microsoft.Graph -Scope CurrentUser`n" -ForegroundColor Yellow
    exit
}

# ============================================
# 1. CHECK USERS IN ENTRA ID
# ============================================
Write-Host "Checking Entra ID Users..." -ForegroundColor Yellow

try {
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
    Write-Host "Make sure you have Group.Read.All permission`n" -ForegroundColor Yellow
}

# ============================================
# 3. CHECK EXCHANGE ONLINE RESOURCES
# ============================================
Write-Host "Checking Exchange Online resources..." -ForegroundColor Yellow
Write-Host "(This requires Exchange Online PowerShell connection)" -ForegroundColor Gray

try {
    # Check if Exchange Online Management module is installed
    if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
        Write-Host "Exchange Online Management module not installed." -ForegroundColor Yellow
        Write-Host "To install: Install-Module -Name ExchangeOnlineManagement -Scope CurrentUser" -ForegroundColor Gray
        Write-Host "Skipping Exchange Online checks...`n" -ForegroundColor Yellow
    }
    else {
        # Import the module
        Import-Module ExchangeOnlineManagement -ErrorAction Stop
        
        # Check if connected to Exchange Online
        $exoConnection = Get-ConnectionInformation -ErrorAction SilentlyContinue
        
        if (-not $exoConnection) {
            Write-Host "Connecting to Exchange Online..." -ForegroundColor Gray
            
            # Connect with UseRPSSession parameter to avoid WAM issues
            Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
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
}
catch {
    Write-Host "Error checking Exchange Online resources: $_" -ForegroundColor Red
    Write-Host "Skipping Exchange Online checks...`n" -ForegroundColor Yellow
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
    Write-Host "Make sure you have Application.Read.All permission`n" -ForegroundColor Yellow
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
else {
    Write-Host "No users found using this domain`n" -ForegroundColor Gray
}

# Display Entra Groups
if ($results.Groups.Count -gt 0) {
    Write-Host "ENTRA ID GROUPS ($($results.Groups.Count)):" -ForegroundColor Yellow
    Write-Host "=" * 80 -ForegroundColor Yellow
    $results.Groups | Format-Table -AutoSize -Wrap
}
else {
    Write-Host "No Entra ID groups found using this domain`n" -ForegroundColor Gray
}

# Display Mailboxes
if ($results.Mailboxes.Count -gt 0) {
    Write-Host "MAILBOXES ($($results.Mailboxes.Count)):" -ForegroundColor Yellow
    Write-Host "=" * 80 -ForegroundColor Yellow
    $results.Mailboxes | Format-Table -AutoSize -Wrap
}
else {
    Write-Host "No mailboxes found using this domain`n" -ForegroundColor Gray
}

# Display Distribution Groups
if ($results.DistributionGroups.Count -gt 0) {
    Write-Host "DISTRIBUTION GROUPS ($($results.DistributionGroups.Count)):" -ForegroundColor Yellow
    Write-Host "=" * 80 -ForegroundColor Yellow
    $results.DistributionGroups | Format-Table -AutoSize -Wrap
}
else {
    Write-Host "No distribution groups found using this domain`n" -ForegroundColor Gray
}

# Display Mail Contacts
if ($results.MailContacts.Count -gt 0) {
    Write-Host "MAIL CONTACTS ($($results.MailContacts.Count)):" -ForegroundColor Yellow
    Write-Host "=" * 80 -ForegroundColor Yellow
    $results.MailContacts | Format-Table -AutoSize -Wrap
}
else {
    Write-Host "No mail contacts found using this domain`n" -ForegroundColor Gray
}

# Display Applications
if ($results.Applications.Count -gt 0) {
    Write-Host "APPLICATIONS ($($results.Applications.Count)):" -ForegroundColor Yellow
    Write-Host "=" * 80 -ForegroundColor Yellow
    $results.Applications | Format-Table -AutoSize -Wrap
}
else {
    Write-Host "No applications found using this domain`n" -ForegroundColor Gray
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