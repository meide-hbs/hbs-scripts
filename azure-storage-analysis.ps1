#Requires -Version 5.1
<#
.SYNOPSIS
    Analyzes Azure Storage Account usage across subscriptions and provides reserve capacity recommendations.

.DESCRIPTION
    This script:
    1. Enumerates all storage accounts across all subscriptions in an Azure tenant
    2. Calculates total storage usage for each account
    3. Analyzes blob storage accounts for reserve capacity purchase opportunities
    4. Generates a detailed report with cost-saving recommendations

.PARAMETER OutputPath
    Path where the report will be saved (default: current directory)

.PARAMETER ReserveCapacityThresholdTB
    Minimum storage usage in TB to recommend reserve capacity (default: 100 TB)

.PARAMETER MonthsOfHistoricalData
    Number of months to analyze for growth trends (default: 3)

.EXAMPLE
    .\azure-storage-analysis.ps1 -OutputPath "C:\Reports" -ReserveCapacityThresholdTB 50
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = ".",
    
    [Parameter(Mandatory=$false)]
    [int]$ReserveCapacityThresholdTB = 100,
    
    [Parameter(Mandatory=$false)]
    [int]$MonthsOfHistoricalData = 3
)

# Error handling
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Initialize results collection
$storageReport = @()
$reserveCapacityRecommendations = @()

#region Helper Functions

function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        'Info'    { 'Cyan' }
        'Warning' { 'Yellow' }
        'Error'   { 'Red' }
        'Success' { 'Green' }
    }
    
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

function Test-AzureConnection {
    try {
        Write-Log "Checking Azure connection..." -Level Info
        $context = Get-AzContext
        
        if ($null -eq $context) {
            Write-Log "Not connected to Azure. Please run Connect-AzAccount first." -Level Error
            return $false
        }
        
        Write-Log "Connected to Azure as: $($context.Account.Id)" -Level Success
        Write-Log "Tenant: $($context.Tenant.Id)" -Level Info
        return $true
    }
    catch {
        Write-Log "Error checking Azure connection: $($_.Exception.Message)" -Level Error
        return $false
    }
}

function Get-StorageAccountUsage {
    param(
        [Parameter(Mandatory=$true)]
        [object]$StorageAccount,
        
        [Parameter(Mandatory=$true)]
        [string]$SubscriptionId
    )
    
    try {
        # Set context to the correct subscription
        Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
        
        # Get the resource group and storage account name
        $rgName = $StorageAccount.ResourceGroupName
        $saName = $StorageAccount.StorageAccountName
        
        # Calculate date range for metrics
        $endTime = Get-Date
        $startTime = $endTime.AddDays(-30)
        
        # Get usage metrics
        $usedCapacity = 0
        
        try {
            # Query Azure Monitor for UsedCapacity metric
            $metrics = Get-AzMetric -ResourceId $StorageAccount.Id `
                -MetricName "UsedCapacity" `
                -StartTime $startTime `
                -EndTime $endTime `
                -TimeGrain 01:00:00 `
                -AggregationType Average `
                -ErrorAction SilentlyContinue
            
            if ($metrics -and $metrics.Data) {
                # Get the most recent non-null value
                $recentData = $metrics.Data | Where-Object { $null -ne $_.Average } | Select-Object -Last 1
                if ($recentData) {
                    $usedCapacity = $recentData.Average
                }
            }
        }
        catch {
            Write-Log "Warning: Could not retrieve metrics for $saName. Error: $($_.Exception.Message)" -Level Warning
        }
        
        # Convert bytes to various units
        $usageGB = [math]::Round($usedCapacity / 1GB, 2)
        $usageTB = [math]::Round($usedCapacity / 1TB, 2)
        
        return @{
            UsedCapacityBytes = $usedCapacity
            UsedCapacityGB = $usageGB
            UsedCapacityTB = $usageTB
        }
    }
    catch {
        Write-Log "Error getting usage for storage account $($StorageAccount.StorageAccountName): $($_.Exception.Message)" -Level Error
        return @{
            UsedCapacityBytes = 0
            UsedCapacityGB = 0
            UsedCapacityTB = 0
            Error = $_.Exception.Message
        }
    }
}

function Get-BlobStorageDetails {
    param(
        [Parameter(Mandatory=$true)]
        [object]$StorageAccount,
        
        [Parameter(Mandatory=$true)]
        [string]$SubscriptionId
    )
    
    try {
        Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
        
        $details = @{
            HasBlobService = $false
            AccessTier = "N/A"
            Replication = $StorageAccount.Sku.Name
            ContainerCount = 0
            IsBlockBlob = $false
        }
        
        # Check if this is a storage account with blob capabilities
        if ($StorageAccount.Kind -in @('StorageV2', 'BlobStorage', 'BlockBlobStorage')) {
            $details.HasBlobService = $true
            $details.IsBlockBlob = ($StorageAccount.Kind -eq 'BlockBlobStorage')
            
            # Get access tier
            if ($StorageAccount.AccessTier) {
                $details.AccessTier = $StorageAccount.AccessTier
            }
            
            # Try to get container count
            try {
                $ctx = New-AzStorageContext -StorageAccountName $StorageAccount.StorageAccountName `
                    -UseConnectedAccount -ErrorAction SilentlyContinue
                
                if ($ctx) {
                    $containers = @(Get-AzStorageContainer -Context $ctx -ErrorAction SilentlyContinue)
                    $details.ContainerCount = $containers.Count
                }
            }
            catch {
                Write-Log "Warning: Could not get container count for $($StorageAccount.StorageAccountName)" -Level Warning
            }
        }
        
        return $details
    }
    catch {
        Write-Log "Error getting blob details for $($StorageAccount.StorageAccountName): $($_.Exception.Message)" -Level Warning
        return @{
            HasBlobService = $false
            AccessTier = "Error"
            Replication = "Unknown"
            ContainerCount = 0
            IsBlockBlob = $false
            Error = $_.Exception.Message
        }
    }
}

function Analyze-ReserveCapacityOpportunity {
    param(
        [Parameter(Mandatory=$true)]
        [object]$StorageData
    )
    
    $recommendation = @{
        ShouldPurchase = $false
        Reason = ""
        PotentialSavings = 0
        RecommendedTerm = ""
        RecommendedCapacity = 0
    }
    
    # Only analyze blob storage accounts
    if (-not $StorageData.HasBlobService) {
        $recommendation.Reason = "Not a blob storage account"
        return $recommendation
    }
    
    # Check if usage meets threshold
    if ($StorageData.UsedCapacityTB -lt $ReserveCapacityThresholdTB) {
        $recommendation.Reason = "Usage ($($StorageData.UsedCapacityTB) TB) below threshold ($ReserveCapacityThresholdTB TB)"
        return $recommendation
    }
    
    # Calculate potential savings
    # Reserve capacity typically offers 35-40% discount for 1 year, 45-55% for 3 years
    $monthlyPayAsYouGoCost = $StorageData.UsedCapacityTB * 20.48 # Approximate cost per TB for Hot tier
    
    $oneYearReservedCost = $StorageData.UsedCapacityTB * 13.31 # ~35% discount
    $threeYearReservedCost = $StorageData.UsedCapacityTB * 10.24 # ~50% discount
    
    $oneYearSavings = ($monthlyPayAsYouGoCost - $oneYearReservedCost) * 12
    $threeYearSavings = ($monthlyPayAsYouGoCost - $threeYearReservedCost) * 36
    
    # Recommend if savings are significant
    if ($oneYearSavings -gt 1000) {
        $recommendation.ShouldPurchase = $true
        
        if ($StorageData.UsedCapacityTB -ge 500) {
            $recommendation.RecommendedTerm = "3 years"
            $recommendation.PotentialSavings = [math]::Round($threeYearSavings, 2)
            $recommendation.Reason = "High usage with significant 3-year savings potential"
        }
        else {
            $recommendation.RecommendedTerm = "1 year"
            $recommendation.PotentialSavings = [math]::Round($oneYearSavings, 2)
            $recommendation.Reason = "Moderate usage with good 1-year savings potential"
        }
        
        # Round capacity to nearest 100 TB for recommendation
        $recommendation.RecommendedCapacity = [math]::Ceiling($StorageData.UsedCapacityTB / 100) * 100
    }
    else {
        $recommendation.Reason = "Insufficient savings potential (estimated <$1000/year)"
    }
    
    return $recommendation
}

#endregion

#region Main Script

try {
    Write-Log "=== Azure Storage Account Analysis Script ===" -Level Info
    Write-Log "Started at: $(Get-Date)" -Level Info
    
    # Verify Azure connection
    if (-not (Test-AzureConnection)) {
        throw "Not connected to Azure. Please run Connect-AzAccount and try again."
    }
    
    # Verify output path
    if (-not (Test-Path -Path $OutputPath)) {
        Write-Log "Creating output directory: $OutputPath" -Level Info
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }
    
    # Get all subscriptions
    Write-Log "Retrieving subscriptions..." -Level Info
    $subscriptions = @(Get-AzSubscription -ErrorAction Stop)
    
    if ($subscriptions.Count -eq 0) {
        throw "No subscriptions found in the current Azure tenant."
    }
    
    Write-Log "Found $($subscriptions.Count) subscription(s)" -Level Success
    
    # Process each subscription
    $totalStorageAccounts = 0
    
    foreach ($subscription in $subscriptions) {
        Write-Log "Processing subscription: $($subscription.Name) ($($subscription.Id))" -Level Info
        
        try {
            # Set context to subscription
            Set-AzContext -SubscriptionId $subscription.Id -ErrorAction Stop | Out-Null
            
            # Get all storage accounts in the subscription
            $storageAccounts = @(Get-AzStorageAccount -ErrorAction Stop)
            
            Write-Log "Found $($storageAccounts.Count) storage account(s) in subscription" -Level Info
            $totalStorageAccounts += $storageAccounts.Count
            
            foreach ($sa in $storageAccounts) {
                Write-Log "Analyzing: $($sa.StorageAccountName)" -Level Info
                
                # Get usage data
                $usage = Get-StorageAccountUsage -StorageAccount $sa -SubscriptionId $subscription.Id
                
                # Get blob-specific details
                $blobDetails = Get-BlobStorageDetails -StorageAccount $sa -SubscriptionId $subscription.Id
                
                # Create storage account report entry
                $reportEntry = [PSCustomObject]@{
                    SubscriptionName = $subscription.Name
                    SubscriptionId = $subscription.Id
                    ResourceGroup = $sa.ResourceGroupName
                    StorageAccountName = $sa.StorageAccountName
                    Location = $sa.Location
                    Kind = $sa.Kind
                    SkuName = $sa.Sku.Name
                    AccessTier = $blobDetails.AccessTier
                    UsedCapacityGB = $usage.UsedCapacityGB
                    UsedCapacityTB = $usage.UsedCapacityTB
                    HasBlobService = $blobDetails.HasBlobService
                    ContainerCount = $blobDetails.ContainerCount
                    CreationTime = $sa.CreationTime
                }
                
                $storageReport += $reportEntry
                
                # Analyze for reserve capacity if it's a blob storage account
                if ($blobDetails.HasBlobService) {
                    $analysisData = $reportEntry | Select-Object *, @{N='Replication';E={$sa.Sku.Name}}
                    $recommendation = Analyze-ReserveCapacityOpportunity -StorageData $analysisData
                    
                    if ($recommendation.ShouldPurchase) {
                        $recEntry = [PSCustomObject]@{
                            SubscriptionName = $subscription.Name
                            StorageAccountName = $sa.StorageAccountName
                            Location = $sa.Location
                            CurrentUsageTB = $usage.UsedCapacityTB
                            RecommendedCapacityTB = $recommendation.RecommendedCapacity
                            RecommendedTerm = $recommendation.RecommendedTerm
                            EstimatedAnnualSavings = $recommendation.PotentialSavings
                            Reason = $recommendation.Reason
                            Replication = $sa.Sku.Name
                            AccessTier = $blobDetails.AccessTier
                        }
                        
                        $reserveCapacityRecommendations += $recEntry
                        Write-Log "Reserve capacity recommended for $($sa.StorageAccountName)" -Level Success
                    }
                }
            }
        }
        catch {
            Write-Log "Error processing subscription $($subscription.Name): $($_.Exception.Message)" -Level Error
            continue
        }
    }
    
    # Generate summary statistics
    if ($storageReport.Count -gt 0) {
        $totalUsageGB = ($storageReport | Measure-Object -Property UsedCapacityGB -Sum).Sum
        if ($null -eq $totalUsageGB) { $totalUsageGB = 0 }
    } else {
        $totalUsageGB = 0
    }
    
    $totalUsageTB = [math]::Round($totalUsageGB / 1024, 2)
    $blobStorageCount = @($storageReport | Where-Object { $_.HasBlobService }).Count
    
    if ($reserveCapacityRecommendations.Count -gt 0) {
        $totalPotentialSavings = ($reserveCapacityRecommendations | Measure-Object -Property EstimatedAnnualSavings -Sum).Sum
        if ($null -eq $totalPotentialSavings) { $totalPotentialSavings = 0 }
    } else {
        $totalPotentialSavings = 0
    }
    
    Write-Log "`n=== Summary ===" -Level Info
    Write-Log "Total Storage Accounts: $totalStorageAccounts" -Level Info
    Write-Log "Blob Storage Accounts: $blobStorageCount" -Level Info
    Write-Log "Total Storage Used: $totalUsageTB TB" -Level Success
    Write-Log "Reserve Capacity Recommendations: $($reserveCapacityRecommendations.Count)" -Level Success
    Write-Log "Potential Annual Savings: `$$([math]::Round($totalPotentialSavings, 2))" -Level Success
    
    # Export reports
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    
    # Export main storage report
    $storageReportPath = Join-Path -Path $OutputPath -ChildPath "Azure-Storage-Report-$timestamp.csv"
    $storageReport | Export-Csv -Path $storageReportPath -NoTypeInformation
    Write-Log "Storage report exported to: $storageReportPath" -Level Success
    
    # Export reserve capacity recommendations
    if ($reserveCapacityRecommendations.Count -gt 0) {
        $recommendationsPath = Join-Path -Path $OutputPath -ChildPath "Reserve-Capacity-Recommendations-$timestamp.csv"
        $reserveCapacityRecommendations | Export-Csv -Path $recommendationsPath -NoTypeInformation
        Write-Log "Recommendations exported to: $recommendationsPath" -Level Success
    }
    
    # Create HTML report
    $htmlReportPath = Join-Path -Path $OutputPath -ChildPath "Azure-Storage-Analysis-$timestamp.html"
    
    $htmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>Azure Storage Account Analysis Report</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #0078d4; border-bottom: 3px solid #0078d4; padding-bottom: 10px; }
        h2 { color: #106ebe; margin-top: 30px; }
        .summary { background-color: #fff; padding: 20px; border-radius: 5px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin-bottom: 20px; }
        .summary-item { display: inline-block; margin: 10px 20px 10px 0; }
        .summary-label { font-weight: bold; color: #666; }
        .summary-value { font-size: 24px; color: #0078d4; font-weight: bold; }
        table { border-collapse: collapse; width: 100%; background-color: #fff; box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin-bottom: 20px; }
        th { background-color: #0078d4; color: white; padding: 12px; text-align: left; font-weight: bold; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f5f5f5; }
        .recommendation { background-color: #d4edda; padding: 3px 8px; border-radius: 3px; color: #155724; }
        .footer { margin-top: 30px; padding-top: 20px; border-top: 1px solid #ddd; color: #666; font-size: 12px; }
    </style>
</head>
<body>
    <h1>Azure Storage Account Analysis Report</h1>
    <p>Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
    
    <div class="summary">
        <h2>Summary</h2>
        <div class="summary-item">
            <div class="summary-label">Total Storage Accounts</div>
            <div class="summary-value">$totalStorageAccounts</div>
        </div>
        <div class="summary-item">
            <div class="summary-label">Blob Storage Accounts</div>
            <div class="summary-value">$blobStorageCount</div>
        </div>
        <div class="summary-item">
            <div class="summary-label">Total Usage</div>
            <div class="summary-value">$totalUsageTB TB</div>
        </div>
        <div class="summary-item">
            <div class="summary-label">Potential Annual Savings</div>
            <div class="summary-value">`$$([math]::Round($totalPotentialSavings, 2))</div>
        </div>
    </div>
    
    <h2>Reserve Capacity Recommendations</h2>
    <table>
        <tr>
            <th>Storage Account</th>
            <th>Location</th>
            <th>Current Usage (TB)</th>
            <th>Recommended Capacity (TB)</th>
            <th>Recommended Term</th>
            <th>Est. Annual Savings</th>
            <th>Reason</th>
        </tr>
"@
    
    foreach ($rec in $reserveCapacityRecommendations) {
        $htmlContent += @"
        <tr>
            <td>$($rec.StorageAccountName)</td>
            <td>$($rec.Location)</td>
            <td>$($rec.CurrentUsageTB)</td>
            <td>$($rec.RecommendedCapacityTB)</td>
            <td class="recommendation">$($rec.RecommendedTerm)</td>
            <td>`$$($rec.EstimatedAnnualSavings)</td>
            <td>$($rec.Reason)</td>
        </tr>
"@
    }
    
    $htmlContent += @"
    </table>
    
    <h2>All Storage Accounts</h2>
    <table>
        <tr>
            <th>Subscription</th>
            <th>Storage Account</th>
            <th>Location</th>
            <th>Kind</th>
            <th>SKU</th>
            <th>Usage (TB)</th>
            <th>Blob Service</th>
        </tr>
"@
    
    foreach ($item in $storageReport) {
        $blobStatus = if ($item.HasBlobService) { "Yes" } else { "No" }
        $htmlContent += @"
        <tr>
            <td>$($item.SubscriptionName)</td>
            <td>$($item.StorageAccountName)</td>
            <td>$($item.Location)</td>
            <td>$($item.Kind)</td>
            <td>$($item.SkuName)</td>
            <td>$($item.UsedCapacityTB)</td>
            <td>$blobStatus</td>
        </tr>
"@
    }
    
    $htmlContent += @"
    </table>
    
    <div class="footer">
        <p>This report analyzes Azure storage accounts and provides recommendations for reserve capacity purchases based on usage patterns.</p>
        <p>Reserve capacity recommendations are made for accounts with usage above $ReserveCapacityThresholdTB TB.</p>
    </div>
</body>
</html>
"@
    
    $htmlContent | Out-File -FilePath $htmlReportPath -Encoding UTF8
    Write-Log "HTML report exported to: $htmlReportPath" -Level Success
    
    Write-Log "`nScript completed successfully!" -Level Success
}
catch {
    Write-Log "Critical error: $($_.Exception.Message)" -Level Error
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
}

#endregion
