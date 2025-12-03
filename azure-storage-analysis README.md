# Azure Storage Account Analysis & Reserve Capacity Advisor

This PowerShell script provides comprehensive analysis of Azure storage accounts across all subscriptions in your tenant and identifies opportunities to save costs through reserve capacity purchases.

## Features

### 1. **Comprehensive Storage Account Reporting**
- Enumerates all storage accounts across all subscriptions
- Calculates actual storage usage using Azure Monitor metrics
- Reports on storage account types, SKUs, locations, and configurations
- Exports detailed CSV reports

### 2. **Reserve Capacity Analysis**
- Identifies blob storage accounts that would benefit from reserve capacity
- Calculates potential cost savings (1-year and 3-year terms)
- Provides specific recommendations with capacity amounts
- Estimates annual savings based on current Azure pricing

### 3. **Error Handling**
- Validates Azure connection before execution
- Handles missing permissions gracefully
- Continues processing if individual storage accounts fail
- Provides detailed error logging

### 4. **Multiple Output Formats**
- CSV reports for storage account inventory
- CSV reports for reserve capacity recommendations
- HTML dashboard with summary statistics
- Console logging with color-coded messages

## Prerequisites

### Required PowerShell Modules
```powershell
# Install the Azure PowerShell module
Install-Module -Name Az -Repository PSGallery -Force -AllowClobber

# Import the module
Import-Module Az
```

### Required Azure Permissions
Your Azure account needs the following permissions:
- **Reader** access to all subscriptions you want to analyze
- **Monitoring Reader** access to retrieve metrics
- **Storage Account Contributor** (optional) for container counts

## Installation

1. Download the script:
```powershell
# Save the azure-storage-analysis.ps1 file to your preferred location
```

2. Connect to Azure:
```powershell
Connect-AzAccount
```

## Usage

### Basic Usage
```powershell
.\azure-storage-analysis.ps1
```

### Advanced Usage with Parameters
```powershell
# Specify custom output path and threshold
.\azure-storage-analysis.ps1 -OutputPath "C:\Reports\Azure" -ReserveCapacityThresholdTB 50

# Lower threshold for smaller environments
.\azure-storage-analysis.ps1 -ReserveCapacityThresholdTB 25
```

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `OutputPath` | String | Current directory | Directory where reports will be saved |
| `ReserveCapacityThresholdTB` | Integer | 100 | Minimum TB of storage to recommend reserve capacity |
| `MonthsOfHistoricalData` | Integer | 3 | Months of historical data to analyze (future use) |

## Output Files

The script generates three files with timestamps:

### 1. Storage Report CSV
**Filename:** `Azure-Storage-Report-YYYYMMDD-HHMMSS.csv`

Contains detailed information about all storage accounts:
- Subscription name and ID
- Resource group
- Storage account name and location
- Account kind and SKU
- Used capacity (GB and TB)
- Blob service status
- Container count
- Creation time

### 2. Reserve Capacity Recommendations CSV
**Filename:** `Reserve-Capacity-Recommendations-YYYYMMDD-HHMMSS.csv`

Contains recommendations for storage accounts that would benefit from reserve capacity:
- Storage account details
- Current usage in TB
- Recommended capacity to purchase
- Recommended term (1 or 3 years)
- Estimated annual savings
- Reason for recommendation
- Replication type and access tier

### 3. HTML Dashboard
**Filename:** `Azure-Storage-Analysis-YYYYMMDD-HHMMSS.html`

Interactive HTML report featuring:
- Executive summary with key metrics
- Reserve capacity recommendations table
- Complete storage account inventory
- Visual formatting and hover effects

## Reserve Capacity Recommendations Logic

### When Reserve Capacity is Recommended

The script recommends reserve capacity purchases when:

1. **Storage account has blob service enabled** (StorageV2, BlobStorage, or BlockBlobStorage)
2. **Usage exceeds the threshold** (default: 100 TB)
3. **Estimated savings exceed $1,000 per year**

### Recommendation Terms

- **1-Year Term**: For accounts with 100-499 TB
  - Approximately 35% discount vs pay-as-you-go
  - Lower commitment, good for growing workloads

- **3-Year Term**: For accounts with 500+ TB
  - Approximately 50% discount vs pay-as-you-go
  - Maximum savings, best for stable workloads

### Savings Calculation

The script uses approximate Azure pricing:
- **Pay-as-you-go**: ~$20.48/TB/month (Hot tier)
- **1-year reserved**: ~$13.31/TB/month (35% discount)
- **3-year reserved**: ~$10.24/TB/month (50% discount)

*Note: Actual pricing varies by region and tier. Verify current pricing on the Azure portal.*

## Example Output

### Console Output
```
[2024-12-03 10:15:22] [Info] === Azure Storage Account Analysis Script ===
[2024-12-03 10:15:22] [Info] Started at: 12/03/2024 10:15:22
[2024-12-03 10:15:23] [Success] Connected to Azure as: user@company.com
[2024-12-03 10:15:23] [Info] Tenant: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
[2024-12-03 10:15:24] [Success] Found 5 subscription(s)
[2024-12-03 10:15:24] [Info] Processing subscription: Production (sub-id-1)
[2024-12-03 10:15:25] [Info] Found 12 storage account(s) in subscription
[2024-12-03 10:15:26] [Info] Analyzing: prodstorageaccount01
[2024-12-03 10:15:28] [Success] Reserve capacity recommended for prodstorageaccount01

=== Summary ===
[2024-12-03 10:16:45] [Info] Total Storage Accounts: 47
[2024-12-03 10:16:45] [Info] Blob Storage Accounts: 32
[2024-12-03 10:16:45] [Success] Total Storage Used: 2,847.3 TB
[2024-12-03 10:16:45] [Success] Reserve Capacity Recommendations: 8
[2024-12-03 10:16:45] [Success] Potential Annual Savings: $127,584.00
```

## Troubleshooting

### Common Issues

#### Issue: "Not connected to Azure"
**Solution:**
```powershell
Connect-AzAccount
```

#### Issue: "No subscriptions found"
**Solution:**
Ensure your account has access to at least one Azure subscription.

#### Issue: "Could not retrieve metrics"
**Solution:**
- Verify you have Monitoring Reader permissions
- Some storage accounts may not have metrics enabled
- The script will continue and report 0 usage for these accounts

#### Issue: "Could not get container count"
**Solution:**
- Requires Storage Account Contributor permissions
- Container count is optional; the script will continue without it

### Permissions Error
If you see access denied errors:
```powershell
# Check your current Azure context
Get-AzContext

# List available subscriptions
Get-AzSubscription

# Verify you have required roles
Get-AzRoleAssignment -SignInName your-email@domain.com
```

## Best Practices

1. **Run during off-peak hours** - The script queries metrics for all storage accounts
2. **Review recommendations carefully** - Consider growth trends before purchasing
3. **Start with conservative thresholds** - Use default 100 TB threshold initially
4. **Archive reports** - Keep historical reports for trend analysis
5. **Verify pricing** - Confirm current Azure reserve capacity pricing before purchasing

## Understanding Azure Reserve Capacity

### What is Reserve Capacity?

Azure Reserve Capacity allows you to commit to a specific amount of storage for 1 or 3 years at a discounted rate. It applies to:
- Block blob storage
- Azure Data Lake Storage Gen2
- Page blobs (premium)

### Benefits
- Significant cost savings (35-55% discount)
- Predictable costs for budgeting
- No impact on performance
- Flexible scope (subscription or account)

### Considerations
- Upfront or monthly payment commitment
- Capacity is pre-purchased (pay even if unused)
- Best for stable, predictable workloads
- Can exchange or cancel with limitations

## Customization

### Adjusting Cost Calculations

To update pricing in the script, modify these values in the `Analyze-ReserveCapacityOpportunity` function:

```powershell
$monthlyPayAsYouGoCost = $StorageData.UsedCapacityTB * 20.48  # Update with current pricing
$oneYearReservedCost = $StorageData.UsedCapacityTB * 13.31   # Update with current pricing
$threeYearReservedCost = $StorageData.UsedCapacityTB * 10.24 # Update with current pricing
```

### Changing Recommendation Criteria

Modify the threshold and savings requirements:

```powershell
# In Analyze-ReserveCapacityOpportunity function
if ($oneYearSavings -gt 1000) {  # Change minimum savings threshold
    $recommendation.ShouldPurchase = $true
    
    if ($StorageData.UsedCapacityTB -ge 500) {  # Change 3-year term threshold
        $recommendation.RecommendedTerm = "3 years"
        # ...
    }
}
```

## Version History

- **v1.0** (2024-12-03)
  - Initial release
  - Multi-subscription support
  - Reserve capacity recommendations
  - HTML and CSV reporting

## Support & Feedback

For issues, questions, or suggestions:
1. Check the Troubleshooting section
2. Review Azure documentation on reserve capacity
3. Verify your Azure permissions

## License

This script is provided as-is for use in analyzing Azure storage accounts and identifying cost optimization opportunities.

## Disclaimer

- Pricing estimates are approximate and based on general Azure pricing
- Actual costs vary by region, tier, and specific configuration
- Always verify current pricing on the Azure portal before making purchase decisions
- This tool provides recommendations; final decisions should consider business requirements
- Savings estimates do not account for data egress, operations, or other costs

## Related Resources

- [Azure Storage Pricing](https://azure.microsoft.com/en-us/pricing/details/storage/)
- [Azure Reserved Capacity](https://docs.microsoft.com/en-us/azure/storage/blobs/storage-blob-reserved-capacity)
- [Azure PowerShell Documentation](https://docs.microsoft.com/en-us/powershell/azure/)
