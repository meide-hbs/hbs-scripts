#Requires -Version 5.1
<#
.SYNOPSIS
    Exports Scale Computing HC3 VM inventory to CSV for Azure Migrate import.
.DESCRIPTION
    Connects to HC3 REST API, retrieves all VMs including guest IP addresses
    (requires Scale Computing Guest Tools installed on VMs), and exports
    to a CSV compatible with Azure Migrate's import template.
.NOTES
    Guest Tools must be installed on VMs for IP address retrieval.
    VMs without Guest Tools will show blank IP fields.
.Usage
   $cred = Get-Credential -Message "Enter HC3 admin credentials"
   .\Export-ScaleVMInventory.ps1 -ClusterIP "10.0.0.100" -Credential $cred

  Or specify output path
  .\Export-ScaleVMInventory.ps1 -ClusterIP "10.0.0.100" -Credential $cred -OutputPath "C:\Migrate\cluster1.csv"

$cred = Get-Credential -Message "Enter HC3 admin credentials"
.\Export-ScaleVMInventory.ps1 -ClusterIP "10.0.0.100" -Credential $cred

# Or specify output path
.\Export-ScaleVMInventory.ps1 -ClusterIP "10.0.0.100" -Credential $cred -OutputPath "C:\Migrate\cluster1.csv"


#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ClusterIP,

    [Parameter(Mandatory = $true)]
    [PSCredential]$Credential,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ".\scale_vm_inventory.csv"
)

# ── Ignore self-signed certs ──
if (-not ([System.Management.Automation.PSTypeName]'TrustAllCertsPolicy').Type) {
    Add-Type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint srvPoint, X509Certificate certificate,
        WebRequest request, int certificateProblem) { return true; }
}
"@
}
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

# ── Authenticate ──
$loginBody = @{
    username = $Credential.UserName
    password = $Credential.GetNetworkCredential().Password
} | ConvertTo-Json

try {
    $null = Invoke-WebRequest `
        -Uri "https://$ClusterIP/rest/v1/login" `
        -Method POST `
        -Body $loginBody `
        -ContentType "application/json" `
        -SessionVariable hc3Session
    Write-Host "Authenticated to HC3 cluster at $ClusterIP" -ForegroundColor Green
}
catch {
    Write-Error "Failed to authenticate: $_"
    return
}

# ── Retrieve all VMs ──
try {
    $vms = Invoke-RestMethod `
        -Uri "https://$ClusterIP/rest/v1/VirDomain" `
        -WebSession $hc3Session
    Write-Host "Retrieved $($vms.Count) VMs" -ForegroundColor Green
}
catch {
    Write-Error "Failed to retrieve VMs: $_"
    return
}

# ── Process VMs and extract IP addresses from netDevs ──
$inventory = foreach ($vm in $vms) {

    # Collect all IPv4 addresses across all NICs
    # Guest Tools populates the ipv4Addresses array on each netDev
    $allIPs = @()
    $guestToolsDetected = $false

    foreach ($nic in $vm.netDevs) {
        if ($nic.ipv4Addresses -and $nic.ipv4Addresses.Count -gt 0) {
            $guestToolsDetected = $true
            $allIPs += $nic.ipv4Addresses
        }
    }

    $ipAddressString = ($allIPs | Select-Object -Unique) -join "; "

    # Calculate individual disk sizes
    $disks = $vm.blockDevs | Where-Object { $_.type -ne "IDE_CDROM" }

    $vmRecord = [ordered]@{
        "Server name"              = $vm.name
        "IP addresses"             = $ipAddressString
        "Guest Tools"              = if ($guestToolsDetected) { "Detected" } else { "Not Detected" }
        "State"                    = $vm.state
        "Cores"                    = $vm.numVCPU
        "Memory (MB)"             = [math]::Round($vm.mem / 1MB)
        "OS name"                  = $vm.operatingSystem
        "Tags"                     = ($vm.tags -join "; ")
        "Number of disks"          = ($disks | Measure-Object).Count
        "Total disk (GB)"          = [math]::Round(($disks | Measure-Object -Property capacity -Sum).Sum / 1GB, 1)
        "Number of NICs"           = ($vm.netDevs | Measure-Object).Count
    }

    # Add individual disk sizes (Azure Migrate supports up to 64)
    for ($i = 0; $i -lt $disks.Count; $i++) {
        $vmRecord["Disk $($i+1) size (GB)"] = [math]::Round($disks[$i].capacity / 1GB, 1)
    }

    # Add per-NIC detail: MAC, VLAN, IPs
    for ($i = 0; $i -lt $vm.netDevs.Count; $i++) {
        $nic = $vm.netDevs[$i]
        $nicIPs = if ($nic.ipv4Addresses) { ($nic.ipv4Addresses -join ", ") } else { "" }
        $vmRecord["NIC $($i+1) MAC"]  = $nic.macAddress
        $vmRecord["NIC $($i+1) VLAN"] = $nic.vlan
        $vmRecord["NIC $($i+1) IPs"]  = $nicIPs
    }

    [PSCustomObject]$vmRecord
}

# ── Summary ──
$withIP    = ($inventory | Where-Object { $_."IP addresses" -ne "" }).Count
$withoutIP = ($inventory | Where-Object { $_."IP addresses" -eq "" }).Count

Write-Host "`n── Inventory Summary ──" -ForegroundColor Cyan
Write-Host "  Total VMs:              $($inventory.Count)"
Write-Host "  With Guest Tools (IPs): $withIP" -ForegroundColor Green
Write-Host "  Without Guest Tools:    $withoutIP" -ForegroundColor Yellow

# ── Export ──
$inventory | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
Write-Host "`nExported to: $OutputPath" -ForegroundColor Green
