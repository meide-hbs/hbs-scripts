<#
.SYNOPSIS
    Queries Active Directory for Windows Server computer objects and documents their IP addresses.

.DESCRIPTION
    Retrieves all computer objects from AD with a Server OS, attempts to resolve their
    IP addresses via DNS, and optionally attempts a WMI/CIM ping for live IP confirmation.
    Exports results to CSV and optionally to the console.

.PARAMETER OutputPath
    Path for the CSV export. Defaults to current directory with timestamp.

.PARAMETER SearchBase
    Optional OU distinguished name to scope the AD search.

.PARAMETER SkipPingCheck
    Skip live connectivity check and rely solely on DNS resolution.

.PARAMETER DomainController
    Target a specific DC for the AD query.

.EXAMPLE
    .\Get-ServerInventory.ps1 -OutputPath "C:\Reports\servers.csv"

.EXAMPLE
    .\Get-ServerInventory.ps1 -SearchBase "OU=Servers,DC=contoso,DC=com" -SkipPingCheck
#>

[CmdletBinding()]
param (
    [Parameter()]
    [string]$OutputPath = ".\ServerInventory_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv",

    [Parameter()]
    [string]$SearchBase,

    [Parameter()]
    [switch]$SkipPingCheck,

    [Parameter()]
    [string]$DomainController
)

#region Prerequisites
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Error "ActiveDirectory module not found. Install RSAT or run from a Domain Controller."
    exit 1
}
Import-Module ActiveDirectory -ErrorAction Stop
#endregion

#region Build AD Query Parameters
$adParams = @{
    Filter     = { OperatingSystem -like "*Server*" }
    Properties = @(
        'Name',
        'OperatingSystem',
        'OperatingSystemVersion',
        'IPv4Address',
        'DNSHostName',
        'LastLogonDate',
        'Enabled',
        'Description',
        'DistinguishedName',
        'Created',
        'Modified'
    )
}

if ($SearchBase)       { $adParams['SearchBase']  = $SearchBase }
if ($DomainController) { $adParams['Server']      = $DomainController }
#endregion

#region Retrieve Computer Objects
Write-Host "[*] Querying Active Directory for Server OS computer objects..." -ForegroundColor Cyan

try {
    $servers = Get-ADComputer @adParams | Sort-Object Name
} catch {
    Write-Error "Failed to query Active Directory: $_"
    exit 1
}

Write-Host "[+] Found $($servers.Count) server object(s) in AD." -ForegroundColor Green
#endregion

#region Process Each Server
$results = [System.Collections.Generic.List[PSCustomObject]]::new()
$i = 0

foreach ($server in $servers) {
    $i++
    Write-Progress -Activity "Processing Servers" -Status "$($server.Name) ($i of $($servers.Count))" `
                   -PercentComplete (($i / $servers.Count) * 100)

    # --- IP Resolution ---
    # AD may already have the IPv4Address attribute populated via DNS registration
    $adIP       = $server.IPv4Address
    $resolvedIP = $null
    $dnsStatus  = 'Unknown'

    $dnsHostname = if ($server.DNSHostName) { $server.DNSHostName } else { $server.Name }

    try {
        $dns = [System.Net.Dns]::GetHostAddresses($dnsHostname) |
               Where-Object { $_.AddressFamily -eq 'InterNetwork' } |
               Select-Object -ExpandProperty IPAddressToString
        $resolvedIP = $dns -join ', '
        $dnsStatus  = 'Resolved'
    } catch {
        $dnsStatus = 'DNS Lookup Failed'
    }

    # --- Determine best IP to report ---
    $reportedIP = if ($adIP)        { $adIP }
                  elseif ($resolvedIP) { $resolvedIP }
                  else              { 'Unresolvable' }

    # --- Live Connectivity Check ---
    $pingStatus = 'Skipped'
    $confirmedIP = $null

    if (-not $SkipPingCheck) {
        try {
            $ping = Test-Connection -ComputerName $dnsHostname -Count 1 -ErrorAction Stop
            $pingStatus  = 'Online'
            $confirmedIP = $ping.IPV4Address.IPAddressToString
        } catch {
            $pingStatus = 'Offline / Unreachable'
        }
    }

    # --- Compile Result ---
    $results.Add([PSCustomObject]@{
        ComputerName         = $server.Name
        DNSHostName          = $server.DNSHostName
        Enabled              = $server.Enabled
        OperatingSystem      = $server.OperatingSystem
        OSVersion            = $server.OperatingSystemVersion
        AD_IPv4Address       = $adIP
        DNS_ResolvedIP       = $resolvedIP
        DNS_Status           = $dnsStatus
        PingStatus           = $pingStatus
        Ping_ConfirmedIP     = $confirmedIP
        BestIP               = if ($confirmedIP) { $confirmedIP } else { $reportedIP }
        LastLogonDate        = $server.LastLogonDate
        Created              = $server.Created
        Modified             = $server.Modified
        Description          = $server.Description
        DistinguishedName    = $server.DistinguishedName
    })
}

Write-Progress -Activity "Processing Servers" -Completed
#endregion

#region Output
Write-Host "`n[*] Exporting results to: $OutputPath" -ForegroundColor Cyan
$results | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
Write-Host "[+] Export complete." -ForegroundColor Green

# Console summary table
$results | Format-Table -AutoSize -Property ComputerName, BestIP, OperatingSystem, PingStatus, Enabled, LastLogonDate

# Summary stats
$online    = ($results | Where-Object { $_.PingStatus -eq 'Online' }).Count
$offline   = ($results | Where-Object { $_.PingStatus -eq 'Offline / Unreachable' }).Count
$noIP      = ($results | Where-Object { $_.BestIP -eq 'Unresolvable' }).Count
$disabled  = ($results | Where-Object { $_.Enabled -eq $false }).Count

Write-Host "`n--- Summary ---" -ForegroundColor Yellow
Write-Host "  Total Servers  : $($results.Count)"
Write-Host "  Online         : $online"
Write-Host "  Offline/No Ping: $offline"
Write-Host "  No IP Resolved : $noIP"
Write-Host "  Disabled in AD : $disabled"
Write-Host "  Report saved to: $OutputPath`n"
#endregion
