# ---------------------------------------------------------------------------
# 🍳 CloudCostChefs "Mise-en-Place" Notes
# Azure VM Multi-Subscription Scheduled Start/Stop Script
# Reads a CSV of VMs + times and flips power states like a grill master
# ---------------------------------------------------------------------------
param(
    # Where's the recipe card (CSV) stored?
    [Parameter(Mandatory=$true)]
    [string]$CsvFilePath,
    
    # Kitchen clock—defaults to UTC if you don't specify a locale
    [Parameter(Mandatory=$false)]
    [string]$TimeZone = "UTC"
)

# -- Helper: Colorful plating for console output ----------------------------
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"   # Default salt-and-pepper text
    )
    Write-Host $Message -ForegroundColor $Color
}

# -- Helper: Convert "08:30" into a DateTime entrée -------------------------
function Convert-TimeString {
    param(
        [string]$TimeString,
        [string]$TimeZone
    )
    
    # Accepts HH:mm or a full timestamp; returns $null if the format is funky
    if ([string]::IsNullOrWhiteSpace($TimeString)) {
        return $null
    }
    
    try {
        # Try to parse time in HH:mm format (chef's favorite)
        if ($TimeString -match '^\d{1,2}:\d{2}$') {
            $today = Get-Date
            $timeOnly = [DateTime]::ParseExact($TimeString, "H:mm", $null)
            $fullDateTime = Get-Date -Year $today.Year -Month $today.Month -Day $today.Day -Hour $timeOnly.Hour -Minute $timeOnly.Minute -Second 0
        }
        # Try to parse full datetime (the deluxe version)
        else {
            $fullDateTime = [DateTime]::Parse($TimeString)
        }
        
        return $fullDateTime
    }
    catch {
        Write-ColorOutput "  🔥 Invalid time format: $TimeString. Use HH:mm or full datetime format." "Red"
        return $null
    }
}

# -- Helper: Decide what action the VM needs right now ----------------------
function Get-RequiredAction {
    param(
        [DateTime]$CurrentTime,
        [DateTime]$StartTime,
        [DateTime]$StopTime
    )
    
    # • Returns 'start', 'stop', or 'none'
    # • Handles overnight hours like 22:00 → 06:00 gracefully
    
    # If both times are null, the VM is on vacation
    if (-not $StartTime -and -not $StopTime) {
        return "none"
    }
    
    # If only start time is specified (morning prep only)
    if ($StartTime -and -not $StopTime) {
        if ($CurrentTime -ge $StartTime) {
            return "start"
        }
        return "none"
    }
    
    # If only stop time is specified (shutdown timer only)
    if (-not $StartTime -and $StopTime) {
        if ($CurrentTime -ge $StopTime) {
            return "stop"
        }
        return "none"
    }
    
    # Both times specified (full service hours)
    if ($StartTime -and $StopTime) {
        # Handle case where stop time is next day (start: 08:00, stop: 18:00)
        if ($StartTime -le $StopTime) {
            if ($CurrentTime -ge $StartTime -and $CurrentTime -lt $StopTime) {
                return "start"
            } elseif ($CurrentTime -ge $StopTime) {
                return "stop"
            }
        }
        # Handle case where stop time crosses midnight (start: 22:00, stop: 06:00)
        else {
            if ($CurrentTime -ge $StartTime -or $CurrentTime -lt $StopTime) {
                return "start"
            } else {
                return "stop"
            }
        }
    }
    
    return "none"
}

# -- Helper: Flip to the correct Azure subscription ------------------------
function Set-SubscriptionContext {
    param(
        [string]$SubscriptionId
    )
    
    # Switches context only if we're not already in that kitchen
    try {
        $currentContext = Get-AzContext
        if ($currentContext.Subscription.Id -ne $SubscriptionId) {
            Write-ColorOutput "  🔄 Switching to subscription: $SubscriptionId" "Magenta"
            Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
            return $true
        }
        return $true
    }
    catch {
        Write-ColorOutput "  💥 Failed to switch to subscription $SubscriptionId`: $($_.Exception.Message)" "Red"
        return $false
    }
}

# ---------------------------------------------------------------------------
# Mise-en-Place Check: Are we stocked with the right modules?
# ---------------------------------------------------------------------------
if (-not (Get-Module -ListAvailable -Name Az.Compute)) {
    Write-ColorOutput "🚫 Azure PowerShell module (Az.Compute) is not installed. Please install it using:" "Red"
    Write-ColorOutput "   Install-Module -Name Az -AllowClobber -Scope CurrentUser" "Yellow"
    exit 1
}

# Import the pantry staples
Import-Module Az.Accounts -Force
Import-Module Az.Compute  -Force

# ---------------------------------------------------------------------------
# Main Course
# ---------------------------------------------------------------------------
try {
    # 1) Authenticate to Azure (show your ID at the door)
    $context = Get-AzContext
    if (-not $context) {
        Write-ColorOutput "🔐 Not connected to Azure. Please authenticate..." "Yellow"
        Connect-AzAccount
    }
    
    # 2) Make sure the CSV exists (can't cook without the recipe)
    if (-not (Test-Path $CsvFilePath)) {
        Write-ColorOutput "📄 CSV file not found: $CsvFilePath" "Red"
        exit 1
    }
    
    # 3) Show today's date (chef loves a timestamp)
    $currentTime = Get-Date
    Write-ColorOutput "🕐 Current time: $($currentTime.ToString('yyyy-MM-dd HH:mm:ss')) ($TimeZone)" "Green"
    
    # 4) Load the CSV and sanity-check headers
    Write-ColorOutput "📋 Reading recipe card (CSV): $CsvFilePath" "Green"
    $vmList = Import-Csv -Path $CsvFilePath
    
    # Essential ingredients check
    $requiredHeaders = @('VMName', 'ResourceGroupName', 'SubscriptionId')
    $csvHeaders = $vmList[0].PSObject.Properties.Name
    
    foreach ($header in $requiredHeaders) {
        if ($header -notin $csvHeaders) {
            Write-ColorOutput "❌ Missing required column: $header" "Red"
            Write-ColorOutput "   Required columns: VMName, ResourceGroupName, SubscriptionId, StartTime, StopTime" "Yellow"
            exit 1
        }
    }
    
    # Check for time columns (need at least one timer)
    if ('StartTime' -notin $csvHeaders -and 'StopTime' -notin $csvHeaders) {
        Write-ColorOutput "⏰ At least one time column (StartTime or StopTime) is required" "Red"
        exit 1
    }
    
    Write-ColorOutput "📊 Found $($vmList.Count) VMs on the menu" "Green"
    
    # 5) Group VMs by subscription so we're not oven-hopping every second
    $vmsBySubscription = $vmList | Group-Object -Property SubscriptionId
    Write-ColorOutput "🏢 VMs span across $($vmsBySubscription.Count) subscription kitchen(s)" "Green"
    
    Write-ColorOutput "=" * 70 "Gray"
    
    # 6) Iterate per subscription 🔄
    foreach ($subscriptionGroup in $vmsBySubscription) {
        $subscriptionId = $subscriptionGroup.Name
        $vmsInSubscription = $subscriptionGroup.Group
        
        Write-ColorOutput "🍳 Firing up subscription kitchen: $subscriptionId ($($vmsInSubscription.Count) VMs)" "Cyan"
        Write-ColorOutput "-" * 50 "Gray"
        
        # 6a) Flip to correct subscription
        if (-not (Set-SubscriptionContext -SubscriptionId $subscriptionId)) {
            Write-ColorOutput "🚫 Skipping subscription $subscriptionId due to access issues" "Red"
            continue
        }
        
        # 6b) Iterate through each VM entrée
        foreach ($vm in $vmsInSubscription) {
            $vmName = $vm.VMName.Trim()
            $resourceGroup = $vm.ResourceGroupName.Trim()
            
            Write-ColorOutput "  🖥️  Prepping VM: $vmName in RG: $resourceGroup" "White"
            
            # 6c) Parse start/stop times (read the cooking instructions)
            $startTime = $null
            $stopTime = $null
            
            if ($vm.PSObject.Properties.Name -contains 'StartTime') {
                $startTime = Convert-TimeString -TimeString $vm.StartTime -TimeZone $TimeZone
            }
            
            if ($vm.PSObject.Properties.Name -contains 'StopTime') {
                $stopTime = Convert-TimeString -TimeString $vm.StopTime -TimeZone $TimeZone
            }
            
            if ($startTime) {
                Write-ColorOutput "    🌅 Start time: $($startTime.ToString('HH:mm'))" "Gray"
            }
            if ($stopTime) {
                Write-ColorOutput "    🌙 Stop time: $($stopTime.ToString('HH:mm'))" "Gray"
            }
            
            # 6d) Decide if we should fire up or shut down
            $requiredAction = Get-RequiredAction -CurrentTime $currentTime -StartTime $startTime -StopTime $stopTime
            
            Write-ColorOutput "    🎯 Required action: $requiredAction" "Yellow"
            
            if ($requiredAction -eq "none") {
                Write-ColorOutput "    😴 VM is taking a break—no action needed." "Gray"
                Write-ColorOutput "" "White"
                continue
            }
            
            try {
                # 6e) Get current power state & act (check the oven temperature)
                $vmStatus = Get-AzVM -ResourceGroupName $resourceGroup -Name $vmName -Status -ErrorAction Stop
                $powerState = ($vmStatus.Statuses | Where-Object {$_.Code -like "PowerState/*"}).DisplayStatus
                
                Write-ColorOutput "    📊 Current status: $powerState" "Gray"
                
                if ($requiredAction -eq 'start') {
                    if ($powerState -eq "VM running") {
                        Write-ColorOutput "    ✅ VM is already sizzling. No action needed." "Yellow"
                    } else {
                        Write-ColorOutput "    🔥 Firing up the VM..." "Green"
                        Start-AzVM -ResourceGroupName $resourceGroup -Name $vmName -NoWait
                        Write-ColorOutput "    🚀 Start command initiated for $vmName" "Green"
                    }
                }
                elseif ($requiredAction -eq 'stop') {
                    if ($powerState -eq "VM deallocated" -or $powerState -eq "VM stopped") {
                        Write-ColorOutput "    ❄️  VM is already chilled. No action needed." "Yellow"
                    } else {
                        Write-ColorOutput "    🛑 Shutting down the VM..." "Red"
                        Stop-AzVM -ResourceGroupName $resourceGroup -Name $vmName -Force -NoWait
                        Write-ColorOutput "    ⏹️  Stop command initiated for $vmName" "Red"
                    }
                }
            }
            catch {
                Write-ColorOutput "    💥 Kitchen accident with VM $vmName`: $($_.Exception.Message)" "Red"
            }
            
            Write-ColorOutput "" "White"
        }
        
        Write-ColorOutput "" "White"
    }
    
    # Plate up the finale
    Write-ColorOutput "=" * 70 "Gray"
    Write-ColorOutput "🎉 Service complete! Note: VM operations are running asynchronously." "Green"
    Write-ColorOutput "🔍 Check the Azure portal to verify all dishes are properly prepared." "Yellow"
}
catch {
    Write-ColorOutput "💥 Kitchen disaster: $($_.Exception.Message)" "Red"
    exit 1
}

# ---------------------------------------------------------------------------
# 🍳 CloudCostChefs Recipe Card Format:
# ---------------------------------------------------------------------------
<#
VMName,ResourceGroupName,SubscriptionId,StartTime,StopTime
WebServer01,Production-RG,12345678-1234-1234-1234-123456789012,08:00,18:00
DatabaseServer,Production-RG,12345678-1234-1234-1234-123456789012,06:00,22:00
TestVM,Development-RG,87654321-4321-4321-4321-210987654321,09:00,17:00
BackupVM,Backup-RG,12345678-1234-1234-1234-123456789012,,02:00
DemoVM,Demo-RG,87654321-4321-4321-4321-210987654321,10:00,

🧑‍🍳 Chef's Notes:
- StartTime/StopTime use HH:mm format (24-hour kitchen time)
- Empty times are fine—some dishes only need prep OR cleanup
- Cross-midnight schedules work (22:00 start, 06:00 stop)
- VMs get grouped by subscription for efficient service
- All operations run async—check the Azure portal for final plating!
#>
