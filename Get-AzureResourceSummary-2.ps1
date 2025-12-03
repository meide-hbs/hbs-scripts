<#
.SYNOPSIS
    Summarizes all Azure resource types across subscriptions in a tenant.

.DESCRIPTION
    This script connects to Azure and retrieves all resources across all subscriptions
    in the tenant, then provides a summary of resource types, counts, and distribution.

.PARAMETER ExportToCSV
    If specified, exports the results to a CSV file.

.PARAMETER OutputPath
    Path for the CSV export. Default is current directory.

.EXAMPLE
    .\Get-AzureResourceSummary.ps1
    Runs the script and automatically exports results to CSV files in the current directory.
    
.EXAMPLE
    .\Get-AzureResourceSummary.ps1 -OutputPath "C:\Reports"
    Exports results to CSV files in C:\Reports.

.EXAMPLE
    .\Get-AzureResourceSummary.ps1 -NoExport
    Runs the script without exporting to CSV (console output only).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [switch]$NoExport,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = "."
)

# Function to display colored output
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

# Check if Az module is installed
if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
    Write-ColorOutput "Az.Accounts module not found. Installing..." -Color Yellow
    Install-Module -Name Az.Accounts -Scope CurrentUser -Force -AllowClobber
}

if (-not (Get-Module -ListAvailable -Name Az.Resources)) {
    Write-ColorOutput "Az.Resources module not found. Installing..." -Color Yellow
    Install-Module -Name Az.Resources -Scope CurrentUser -Force -AllowClobber
}

# Import required modules
Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Resources -ErrorAction Stop

Write-ColorOutput "`n=== Azure Resource Type Summary ===" -Color Cyan
Write-ColorOutput "Starting analysis...`n" -Color Cyan

# Connect to Azure
try {
    $context = Get-AzContext
    if (-not $context) {
        Write-ColorOutput "Not connected to Azure. Initiating login..." -Color Yellow
        Connect-AzAccount
        $context = Get-AzContext
    }
    
    Write-ColorOutput "Connected to Azure as: $($context.Account.Id)" -Color Green
    Write-ColorOutput "Tenant: $($context.Tenant.Id)`n" -Color Green
}
catch {
    Write-ColorOutput "Failed to connect to Azure: $_" -Color Red
    exit 1
}

# Get all subscriptions in the tenant
Write-ColorOutput "Retrieving subscriptions..." -Color Yellow
$subscriptions = Get-AzSubscription | Where-Object {$_.State -eq "Enabled"}
Write-ColorOutput "Found $($subscriptions.Count) enabled subscription(s)`n" -Color Green

# Initialize collections
$allResources = @()
$subscriptionSummary = @()

# Loop through each subscription
foreach ($sub in $subscriptions) {
    Write-ColorOutput "Processing subscription: $($sub.Name) ($($sub.Id))" -Color Yellow
    
    try {
        # Set context to current subscription
        Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
        
        # Get all resources in the subscription
        $resources = Get-AzResource -ErrorAction Stop
        
        Write-ColorOutput "  Found $($resources.Count) resources" -Color Gray
        
        if ($resources.Count -eq 0) {
            Write-ColorOutput "  No resources found in this subscription" -Color Gray
            continue
        }
        
        # Add subscription info to each resource
        $processedCount = 0
        foreach ($resource in $resources) {
            try {
                # Handle tags safely
                $tagsString = ""
                if ($resource.Tags -and $resource.Tags.Count -gt 0) {
                    $tagsString = ($resource.Tags.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "; "
                }
                
                $allResources += [PSCustomObject]@{
                    SubscriptionName = $sub.Name
                    SubscriptionId = $sub.Id
                    ResourceType = if ($resource.ResourceType) { $resource.ResourceType } else { "Unknown" }
                    ResourceName = if ($resource.Name) { $resource.Name } else { "Unknown" }
                    ResourceGroup = if ($resource.ResourceGroupName) { $resource.ResourceGroupName } else { "Unknown" }
                    Location = if ($resource.Location) { $resource.Location } else { "Unknown" }
                    Tags = $tagsString
                }
                $processedCount++
            }
            catch {
                Write-ColorOutput "  Warning: Failed to process resource $($resource.Name): $_" -Color Yellow
            }
        }
        
        Write-ColorOutput "  Successfully processed $processedCount resources" -Color Gray
        
        $subscriptionSummary += [PSCustomObject]@{
            SubscriptionName = $sub.Name
            SubscriptionId = $sub.Id
            ResourceCount = $processedCount
        }
    }
    catch {
        Write-ColorOutput "  Error processing subscription: $_" -Color Red
        Write-ColorOutput "  Error details: $($_.Exception.Message)" -Color Red
    }
}

Write-ColorOutput "`n=== Summary Results ===" -Color Cyan

# Overall statistics
Write-ColorOutput "`nTotal Resources: $($allResources.Count)" -Color Green
Write-ColorOutput "Total Subscriptions: $($subscriptions.Count)" -Color Green

# Resources by subscription
Write-ColorOutput "`n--- Resources by Subscription ---" -Color Cyan
$subscriptionSummary | Sort-Object ResourceCount -Descending | Format-Table -AutoSize

# Define resource types eligible for Azure Reservations and Savings Plans
$reservationEligibleTypes = @{
    # Virtual Machines
    'Microsoft.Compute/virtualMachines' = @{
        EligibleFor = 'Reserved VM Instances'
        SavingsRange = '40-72%'
        Terms = '1 year, 3 year'
        Scope = 'Shared, Subscription, Resource Group'
    }
    # SQL Database
    'Microsoft.Sql/servers/databases' = @{
        EligibleFor = 'SQL Database Reserved Capacity'
        SavingsRange = '33-80%'
        Terms = '1 year, 3 year'
        Scope = 'Shared, Subscription, Resource Group'
    }
    # SQL Managed Instance
    'Microsoft.Sql/managedInstances' = @{
        EligibleFor = 'SQL Managed Instance Reserved Capacity'
        SavingsRange = '33-80%'
        Terms = '1 year, 3 year'
        Scope = 'Shared, Subscription, Resource Group'
    }
    # Cosmos DB
    'Microsoft.DocumentDB/databaseAccounts' = @{
        EligibleFor = 'Cosmos DB Reserved Capacity'
        SavingsRange = '20-65%'
        Terms = '1 year, 3 year'
        Scope = 'Shared, Subscription, Resource Group'
    }
    # Azure Synapse Analytics (SQL Data Warehouse)
    'Microsoft.Synapse/workspaces/sqlPools' = @{
        EligibleFor = 'Synapse Analytics Reserved Capacity'
        SavingsRange = '37-65%'
        Terms = '1 year, 3 year'
        Scope = 'Shared, Subscription, Resource Group'
    }
    # Azure Cache for Redis
    'Microsoft.Cache/redis' = @{
        EligibleFor = 'Azure Cache for Redis Reserved Capacity'
        SavingsRange = '30-60%'
        Terms = '1 year, 3 year'
        Scope = 'Shared, Subscription, Resource Group'
    }
    # Azure Database for MySQL
    'Microsoft.DBforMySQL/servers' = @{
        EligibleFor = 'MySQL Reserved Capacity'
        SavingsRange = '34-78%'
        Terms = '1 year, 3 year'
        Scope = 'Shared, Subscription, Resource Group'
    }
    'Microsoft.DBforMySQL/flexibleServers' = @{
        EligibleFor = 'MySQL Flexible Server Reserved Capacity'
        SavingsRange = '34-78%'
        Terms = '1 year, 3 year'
        Scope = 'Shared, Subscription, Resource Group'
    }
    # Azure Database for PostgreSQL
    'Microsoft.DBforPostgreSQL/servers' = @{
        EligibleFor = 'PostgreSQL Reserved Capacity'
        SavingsRange = '34-78%'
        Terms = '1 year, 3 year'
        Scope = 'Shared, Subscription, Resource Group'
    }
    'Microsoft.DBforPostgreSQL/flexibleServers' = @{
        EligibleFor = 'PostgreSQL Flexible Server Reserved Capacity'
        SavingsRange = '34-78%'
        Terms = '1 year, 3 year'
        Scope = 'Shared, Subscription, Resource Group'
    }
    # Azure Database for MariaDB
    'Microsoft.DBforMariaDB/servers' = @{
        EligibleFor = 'MariaDB Reserved Capacity'
        SavingsRange = '34-78%'
        Terms = '1 year, 3 year'
        Scope = 'Shared, Subscription, Resource Group'
    }
    # App Service
    'Microsoft.Web/serverFarms' = @{
        EligibleFor = 'App Service Reserved Capacity'
        SavingsRange = '35-55%'
        Terms = '1 year, 3 year'
        Scope = 'Shared, Subscription, Resource Group'
    }
    # Azure Data Explorer
    'Microsoft.Kusto/clusters' = @{
        EligibleFor = 'Azure Data Explorer Reserved Capacity'
        SavingsRange = '35-65%'
        Terms = '1 year, 3 year'
        Scope = 'Shared, Subscription, Resource Group'
    }
    # Azure VMware Solution
    'Microsoft.AVS/privateClouds' = @{
        EligibleFor = 'Azure VMware Solution Reserved Instances'
        SavingsRange = '33-50%'
        Terms = '1 year, 3 year'
        Scope = 'Shared, Subscription'
    }
    # Azure Dedicated Host
    'Microsoft.Compute/hostGroups/hosts' = @{
        EligibleFor = 'Dedicated Host Reserved Instances'
        SavingsRange = '32-49%'
        Terms = '1 year, 3 year'
        Scope = 'Shared, Subscription'
    }
    # Azure Blob Storage
    'Microsoft.Storage/storageAccounts' = @{
        EligibleFor = 'Storage Reserved Capacity (Blob only)'
        SavingsRange = '30-38%'
        Terms = '1 year, 3 year'
        Scope = 'Subscription'
    }
    # Azure Files
    'Microsoft.Storage/storageAccounts/fileServices' = @{
        EligibleFor = 'Azure Files Reserved Capacity'
        SavingsRange = '36-39%'
        Terms = '1 year, 3 year'
        Scope = 'Subscription'
    }
    # Azure NetApp Files
    'Microsoft.NetApp/netAppAccounts/capacityPools' = @{
        EligibleFor = 'Azure NetApp Files Reserved Capacity'
        SavingsRange = '17-34%'
        Terms = '1 year, 3 year'
        Scope = 'Subscription'
    }
    # Virtual Machine Scale Sets
    'Microsoft.Compute/virtualMachineScaleSets' = @{
        EligibleFor = 'Reserved VM Instances'
        SavingsRange = '40-72%'
        Terms = '1 year, 3 year'
        Scope = 'Shared, Subscription, Resource Group'
    }
    # Azure Databricks
    'Microsoft.Databricks/workspaces' = @{
        EligibleFor = 'Databricks Reserved Capacity'
        SavingsRange = '37-45%'
        Terms = '1 year, 3 year'
        Scope = 'Shared, Subscription'
    }
}

# Group by resource type and add reservation eligibility
$resourceTypeSummary = $allResources | 
    Group-Object ResourceType | 
    Select-Object @{Name='ResourceType';Expression={$_.Name}}, 
                  @{Name='Count';Expression={$_.Count}},
                  @{Name='ReservationEligible';Expression={
                      if ($reservationEligibleTypes.ContainsKey($_.Name)) { 'Yes' } else { 'No' }
                  }},
                  @{Name='EligibleFor';Expression={
                      if ($reservationEligibleTypes.ContainsKey($_.Name)) { 
                          $reservationEligibleTypes[$_.Name].EligibleFor 
                      } else { 
                          'N/A' 
                      }
                  }},
                  @{Name='PotentialSavings';Expression={
                      if ($reservationEligibleTypes.ContainsKey($_.Name)) { 
                          $reservationEligibleTypes[$_.Name].SavingsRange 
                      } else { 
                          'N/A' 
                      }
                  }},
                  @{Name='Terms';Expression={
                      if ($reservationEligibleTypes.ContainsKey($_.Name)) { 
                          $reservationEligibleTypes[$_.Name].Terms 
                      } else { 
                          'N/A' 
                      }
                  }},
                  @{Name='AvailableScopes';Expression={
                      if ($reservationEligibleTypes.ContainsKey($_.Name)) { 
                          $reservationEligibleTypes[$_.Name].Scope 
                      } else { 
                          'N/A' 
                      }
                  }} |
    Sort-Object Count -Descending

Write-ColorOutput "--- Top 20 Resource Types ---" -Color Cyan
$resourceTypeSummary | Select-Object -First 20 | Format-Table -AutoSize

# Show reservation-eligible resources
Write-ColorOutput "`n--- COST OPTIMIZATION OPPORTUNITIES ---" -Color Green
Write-ColorOutput "Resources Eligible for Azure Reservations & Savings Plans:" -Color Green
$reservationEligibleResources = $resourceTypeSummary | Where-Object {$_.ReservationEligible -eq 'Yes'}

if ($reservationEligibleResources) {
    $reservationEligibleResources | Format-Table -AutoSize -Wrap
    
    $totalEligible = ($reservationEligibleResources | Measure-Object -Property Count -Sum).Sum
    $totalResources = ($resourceTypeSummary | Measure-Object -Property Count -Sum).Sum
    $eligiblePercent = [math]::Round(($totalEligible / $totalResources) * 100, 2)
    
    Write-ColorOutput "`nSummary:" -Color Cyan
    Write-ColorOutput "  Total resources eligible for reservations: $totalEligible out of $totalResources ($eligiblePercent%)" -Color Yellow
    Write-ColorOutput "  Unique resource types with reservation options: $($reservationEligibleResources.Count)" -Color Yellow
    Write-ColorOutput "`n  💡 TIP: Reservations offer 20-80% savings and support flexible scoping:" -Color Green
    Write-ColorOutput "     - Shared scope: Apply across all subscriptions in billing account" -Color Gray
    Write-ColorOutput "     - Subscription scope: Apply to specific subscription" -Color Gray
    Write-ColorOutput "     - Resource group scope: Apply to specific resource group" -Color Gray
    Write-ColorOutput "`n  📊 Next Steps:" -Color Green
    Write-ColorOutput "     1. Review the CSV export for detailed resource lists" -Color Gray
    Write-ColorOutput "     2. Analyze usage patterns over the last 30-60 days" -Color Gray
    Write-ColorOutput "     3. Use Azure Advisor for specific recommendations" -Color Gray
    Write-ColorOutput "     4. Consider Azure Savings Plans for flexible compute commitments" -Color Gray
} else {
    Write-ColorOutput "  No resources found that are eligible for Azure Reservations." -Color Yellow
}

# Resources by location
$locationSummary = $allResources | 
    Group-Object Location | 
    Select-Object @{Name='Location';Expression={$_.Name}}, 
                  @{Name='Count';Expression={$_.Count}} |
    Sort-Object Count -Descending

Write-ColorOutput "--- Resources by Location ---" -Color Cyan
$locationSummary | Format-Table -AutoSize

# Resource type distribution by subscription
Write-ColorOutput "--- Resource Types per Subscription ---" -Color Cyan
foreach ($sub in $subscriptions) {
    $subResources = $allResources | Where-Object {$_.SubscriptionId -eq $sub.Id}
    $subTypes = $subResources | Group-Object ResourceType | Measure-Object
    Write-ColorOutput "$($sub.Name): $($subTypes.Count) unique resource types" -Color Gray
}

# Export to CSV (default behavior unless -NoExport is specified)
if (-not $NoExport) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    
    # Ensure output path exists
    if (-not (Test-Path $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
    }
    
    Write-ColorOutput "`nExporting results to CSV files..." -Color Cyan
    
    # Export detailed resource list
    $detailedFile = Join-Path $OutputPath "AzureResources_Detailed_$timestamp.csv"
    $allResources | Export-Csv -Path $detailedFile -NoTypeInformation
    Write-ColorOutput "Detailed resource list exported to: $detailedFile" -Color Green
    
    # Export resource type summary
    $summaryFile = Join-Path $OutputPath "AzureResources_TypeSummary_$timestamp.csv"
    $resourceTypeSummary | Export-Csv -Path $summaryFile -NoTypeInformation
    Write-ColorOutput "Resource type summary exported to: $summaryFile" -Color Green
    
    # Export reservation-eligible resources only
    $reservationFile = Join-Path $OutputPath "AzureResources_ReservationOpportunities_$timestamp.csv"
    $reservationEligibleResources | Export-Csv -Path $reservationFile -NoTypeInformation
    Write-ColorOutput "Reservation opportunities exported to: $reservationFile" -Color Green
    
    # Export subscription summary
    $subSummaryFile = Join-Path $OutputPath "AzureResources_SubscriptionSummary_$timestamp.csv"
    $subscriptionSummary | Export-Csv -Path $subSummaryFile -NoTypeInformation
    Write-ColorOutput "Subscription summary exported to: $subSummaryFile" -Color Green
    
    # Export location summary
    $locationFile = Join-Path $OutputPath "AzureResources_LocationSummary_$timestamp.csv"
    $locationSummary | Export-Csv -Path $locationFile -NoTypeInformation
    Write-ColorOutput "Location summary exported to: $locationFile" -Color Green
}
else {
    Write-ColorOutput "`nSkipping CSV export (-NoExport specified)" -Color Yellow
}

Write-ColorOutput "`n=== Analysis Complete ===" -Color Cyan
