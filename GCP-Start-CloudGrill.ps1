# ---------------------------------------------------------------------------
# 🍳 CloudCostChefs "Mise-en-Place" Notes
# GCP VM Multi-Project Scheduled Start/Stop Script
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

# -- Helper: Flip to the correct GCP project -------------------------------
function Set-GCPProjectContext {
    param(
        [string]$ProjectId
    )
    
    # Switches context only if we're not already in that kitchen
    try {
        $currentProject = gcloud config get-value project 2>$null
        if ($currentProject -ne $ProjectId) {
            Write-ColorOutput "  🔄 Switching to project kitchen: $ProjectId" "Magenta"
            $result = gcloud config set project $ProjectId 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to set project: $result"
            }
            return $true
        }
        return $true
    }
    catch {
        Write-ColorOutput "  💥 Failed to switch to project $ProjectId`: $($_.Exception.Message)" "Red"
        return $false
    }
}

# -- Helper: Get VM current status -------------------------------------------
function Get-VMStatus {
    param(
        [string]$VMName,
        [string]$Zone,
        [string]$ProjectId
    )
    
    try {
        $vmInfo = gcloud compute instances describe $VMName --zone=$Zone --project=$ProjectId --format="value(status)" 2>&1
        if ($LASTEXITCODE -eq 0) {
            return $vmInfo.Trim()
        } else {
            throw "Failed to get VM status: $vmInfo"
        }
    }
    catch {
        throw $_.Exception.Message
    }
}

# -- Helper: Start a GCP VM --------------------------------------------------
function Start-GCPVM {
    param(
        [string]$VMName,
        [string]$Zone,
        [string]$ProjectId
    )
    
    try {
        $result = gcloud compute instances start $VMName --zone=$Zone --project=$ProjectId 2>&1
        if ($LASTEXITCODE -eq 0) {
            return $true
        } else {
            throw "Failed to start VM: $result"
        }
    }
    catch {
        throw $_.Exception.Message
    }
}

# -- Helper: Stop a GCP VM ---------------------------------------------------
function Stop-GCPVM {
    param(
        [string]$VMName,
        [string]$Zone,
        [string]$ProjectId
    )
    
    try {
        $result = gcloud compute instances stop $VMName --zone=$Zone --project=$ProjectId 2>&1
        if ($LASTEXITCODE -eq 0) {
            return $true
        } else {
            throw "Failed to stop VM: $result"
        }
    }
    catch {
        throw $_.Exception.Message
    }
}

# ---------------------------------------------------------------------------
# Mise-en-Place Check: Are we stocked with the right tools?
# ---------------------------------------------------------------------------

# Check if gcloud CLI is installed
try {
    $gcloudVersion = gcloud version --format="value(Google Cloud SDK)" 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "gcloud not found"
    }
} catch {
    Write-ColorOutput "🚫 Google Cloud CLI (gcloud) is not installed or not in PATH." "Red"
    Write-ColorOutput "   Please install it from: https://cloud.google.com/sdk/docs/install" "Yellow"
    exit 1
}

# ---------------------------------------------------------------------------
# Main Course
# ---------------------------------------------------------------------------
try {
    # 1) Check authentication (show your ID at the door)
    try {
        $authAccount = gcloud auth list --filter="status:ACTIVE" --format="value(account)" 2>$null
        if ([string]::IsNullOrWhiteSpace($authAccount) -or $LASTEXITCODE -ne 0) {
            Write-ColorOutput "🔐 Not authenticated to GCP. Please authenticate..." "Yellow"
            gcloud auth login
            if ($LASTEXITCODE -ne 0) {
                throw "Authentication failed"
            }
        } else {
            Write-ColorOutput "👨‍🍳 Authenticated as: $authAccount" "Green"
        }
    } catch {
        Write-ColorOutput "💥 Authentication check failed: $($_.Exception.Message)" "Red"
        exit 1
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
    $requiredHeaders = @('VMName', 'Zone', 'ProjectId')
    $csvHeaders = $vmList[0].PSObject.Properties.Name
    
    foreach ($header in $requiredHeaders) {
        if ($header -notin $csvHeaders) {
            Write-ColorOutput "❌ Missing required column: $header" "Red"
            Write-ColorOutput "   Required columns: VMName, Zone, ProjectId, StartTime, StopTime" "Yellow"
            exit 1
        }
    }
    
    # Check for time columns (need at least one timer)
    if ('StartTime' -notin $csvHeaders -and 'StopTime' -notin $csvHeaders) {
        Write-ColorOutput "⏰ At least one time column (StartTime or StopTime) is required" "Red"
        exit 1
    }
    
    Write-ColorOutput "📊 Found $($vmList.Count) VMs on the menu" "Green"
    
    # 5) Group VMs by project so we're not oven-hopping every second
    $vmsByProject = $vmList | Group-Object -Property ProjectId
    Write-ColorOutput "🏢 VMs span across $($vmsByProject.Count) project kitchen(s)" "Green"
    
    Write-ColorOutput "=" * 70 "Gray"
    
    # 6) Iterate per project 🔄
    foreach ($projectGroup in $vmsByProject) {
        $projectId = $projectGroup.Name
        $vmsInProject = $projectGroup.Group
        
        Write-ColorOutput "🍳 Firing up project kitchen: $projectId ($($vmsInProject.Count) VMs)" "Cyan"
        Write-ColorOutput "-" * 50 "Gray"
        
        # 6a) Flip to correct project
        if (-not (Set-GCPProjectContext -ProjectId $projectId)) {
            Write-ColorOutput "🚫 Skipping project $projectId due to access issues" "Red"
            continue
        }
        
        # 6b) Iterate through each VM entrée
        foreach ($vm in $vmsInProject) {
            $vmName = $vm.VMName.Trim()
            $zone = $vm.Zone.Trim()
            
            Write-ColorOutput "  🖥️  Prepping VM: $vmName in Zone: $zone" "White"
            
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
                $vmStatus = Get-VMStatus -VMName $vmName -Zone $zone -ProjectId $projectId
                
                Write-ColorOutput "    📊 Current status: $vmStatus" "Gray"
                
                if ($requiredAction -eq 'start') {
                    if ($vmStatus -eq "RUNNING") {
                        Write-ColorOutput "    ✅ VM is already sizzling. No action needed." "Yellow"
                    } else {
                        Write-ColorOutput "    🔥 Firing up the VM..." "Green"
                        Start-GCPVM -VMName $vmName -Zone $zone -ProjectId $projectId | Out-Null
                        Write-ColorOutput "    🚀 Start command completed for $vmName" "Green"
                    }
                }
                elseif ($requiredAction -eq 'stop') {
                    if ($vmStatus -eq "TERMINATED" -or $vmStatus -eq "STOPPED") {
                        Write-ColorOutput "    ❄️  VM is already chilled. No action needed." "Yellow"
                    } else {
                        Write-ColorOutput "    🛑 Shutting down the VM..." "Red"
                        Stop-GCPVM -VMName $vmName -Zone $zone -ProjectId $projectId | Out-Null
                        Write-ColorOutput "    ⏹️  Stop command completed for $vmName" "Red"
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
    Write-ColorOutput "🎉 Service complete! All VM operations have been processed." "Green"
    Write-ColorOutput "🔍 Check the GCP Console to verify all dishes are properly prepared." "Yellow"
}
catch {
    Write-ColorOutput "💥 Kitchen disaster: $($_.Exception.Message)" "Red"
    exit 1
}

# ---------------------------------------------------------------------------
# 🍳 CloudCostChefs Recipe Card Format:
# ---------------------------------------------------------------------------
<#
VMName,Zone,ProjectId,StartTime,StopTime
web-server-01,us-central1-a,my-production-project,08:00,18:00
database-server,us-central1-b,my-production-project,06:00,22:00
test-vm,us-west1-a,my-development-project,09:00,17:00
backup-vm,us-east1-a,my-production-project,,02:00
demo-vm,europe-west1-a,my-demo-project,10:00,

🧑‍🍳 Chef's Notes:
- VMName: Instance name in GCP (use hyphens, not underscores)
- Zone: Full zone name like "us-central1-a" 
- ProjectId: Your GCP project ID
- StartTime/StopTime: Use HH:mm format (24-hour kitchen time)
- Empty times are fine—some dishes only need prep OR cleanup
- Cross-midnight schedules work (22:00 start, 06:00 stop)
- VMs get grouped by project for efficient service
- Requires gcloud CLI installed and authenticated
- Check GCP Console for final VM states!
#>
