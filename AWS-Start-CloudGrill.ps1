# ---------------------------------------------------------------------------
# 🍳 CloudCostChefs "Mise-en-Place" Notes
# AWS EC2 Multi-Account Scheduled Start/Stop Script
# Reads a CSV of EC2s + times and flips power states like a grill master
# ---------------------------------------------------------------------------
param(
    # Where's the recipe card (CSV) stored?
    [Parameter(Mandatory=$true)]
    [string]$CsvFilePath,
    
    # Kitchen clock—defaults to UTC if you don't specify a locale
    [Parameter(Mandatory=$false)]
    [string]$TimeZone = "UTC",
    
    # AWS Profile to use (optional - uses default if not specified)
    [Parameter(Mandatory=$false)]
    [string]$AWSProfile = $null
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

# -- Helper: Decide what action the EC2 needs right now ---------------------
function Get-RequiredAction {
    param(
        [DateTime]$CurrentTime,
        [DateTime]$StartTime,
        [DateTime]$StopTime
    )
    
    # • Returns 'start', 'stop', or 'none'
    # • Handles overnight hours like 22:00 → 06:00 gracefully
    
    # If both times are null, the EC2 is on vacation
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

# -- Helper: Set AWS credentials and region context -------------------------
function Set-AWSContext {
    param(
        [string]$Region,
        [string]$Profile = $null
    )
    
    try {
        # Set region
        if ($env:AWS_DEFAULT_REGION -ne $Region) {
            $env:AWS_DEFAULT_REGION = $Region
            Write-ColorOutput "  🌍 Switching to region: $Region" "Magenta"
        }
        
        # Set profile if specified
        if ($Profile) {
            if ($env:AWS_PROFILE -ne $Profile) {
                $env:AWS_PROFILE = $Profile
                Write-ColorOutput "  👤 Using AWS profile: $Profile" "Magenta"
            }
        }
        
        return $true
    }
    catch {
        Write-ColorOutput "  💥 Failed to set AWS context: $($_.Exception.Message)" "Red"
        return $false
    }
}

# -- Helper: Get EC2 instance status ----------------------------------------
function Get-EC2Status {
    param(
        [string]$InstanceId,
        [string]$Region
    )
    
    try {
        $result = aws ec2 describe-instances --instance-ids $InstanceId --region $Region --query 'Reservations[0].Instances[0].State.Name' --output text 2>&1
        if ($LASTEXITCODE -eq 0) {
            return $result.Trim()
        } else {
            throw "Failed to get EC2 status: $result"
        }
    }
    catch {
        throw $_.Exception.Message
    }
}

# -- Helper: Start an EC2 instance ------------------------------------------
function Start-EC2Instance {
    param(
        [string]$InstanceId,
        [string]$Region
    )
    
    try {
        $result = aws ec2 start-instances --instance-ids $InstanceId --region $Region 2>&1
        if ($LASTEXITCODE -eq 0) {
            return $true
        } else {
            throw "Failed to start EC2: $result"
        }
    }
    catch {
        throw $_.Exception.Message
    }
}

# -- Helper: Stop an EC2 instance -------------------------------------------
function Stop-EC2Instance {
    param(
        [string]$InstanceId,
        [string]$Region
    )
    
    try {
        $result = aws ec2 stop-instances --instance-ids $InstanceId --region $Region 2>&1
        if ($LASTEXITCODE -eq 0) {
            return $true
        } else {
            throw "Failed to stop EC2: $result"
        }
    }
    catch {
        throw $_.Exception.Message
    }
}

# ---------------------------------------------------------------------------
# Mise-en-Place Check: Are we stocked with the right tools?
# ---------------------------------------------------------------------------

# Check if AWS CLI is installed
try {
    $awsVersion = aws --version 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "AWS CLI not found"
    }
} catch {
    Write-ColorOutput "🚫 AWS CLI is not installed or not in PATH." "Red"
    Write-ColorOutput "   Please install it from: https://aws.amazon.com/cli/" "Yellow"
    exit 1
}

# ---------------------------------------------------------------------------
# Main Course
# ---------------------------------------------------------------------------
try {
    # 1) Check AWS credentials (show your ID at the door)
    try {
        if ($AWSProfile) {
            $env:AWS_PROFILE = $AWSProfile
            Write-ColorOutput "👤 Using AWS profile: $AWSProfile" "Green"
        }
        
        $identity = aws sts get-caller-identity --output text 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-ColorOutput "🔐 AWS credentials not configured. Please run 'aws configure' or set up your credentials." "Red"
            Write-ColorOutput "   Or use --profile parameter if using named profiles." "Yellow"
            exit 1
        } else {
            $accountId = ($identity -split '\s+')[0]
            $userName = ($identity -split '\s+')[1]
            Write-ColorOutput "👨‍🍳 Authenticated as: $userName (Account: $accountId)" "Green"
        }
    } catch {
        Write-ColorOutput "💥 AWS authentication check failed: $($_.Exception.Message)" "Red"
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
    $ec2List = Import-Csv -Path $CsvFilePath
    
    # Essential ingredients check
    $requiredHeaders = @('InstanceId', 'Region')
    $csvHeaders = $ec2List[0].PSObject.Properties.Name
    
    foreach ($header in $requiredHeaders) {
        if ($header -notin $csvHeaders) {
            Write-ColorOutput "❌ Missing required column: $header" "Red"
            Write-ColorOutput "   Required columns: InstanceId, Region, StartTime, StopTime" "Yellow"
            Write-ColorOutput "   Optional columns: InstanceName (for display purposes)" "Yellow"
            exit 1
        }
    }
    
    # Check for time columns (need at least one timer)
    if ('StartTime' -notin $csvHeaders -and 'StopTime' -notin $csvHeaders) {
        Write-ColorOutput "⏰ At least one time column (StartTime or StopTime) is required" "Red"
        exit 1
    }
    
    Write-ColorOutput "📊 Found $($ec2List.Count) EC2 instances on the menu" "Green"
    
    # 5) Group EC2s by region so we're not oven-hopping every second
    $ec2sByRegion = $ec2List | Group-Object -Property Region
    Write-ColorOutput "🌍 EC2s span across $($ec2sByRegion.Count) region kitchen(s)" "Green"
    
    Write-ColorOutput "=" * 70 "Gray"
    
    # 6) Iterate per region 🔄
    foreach ($regionGroup in $ec2sByRegion) {
        $region = $regionGroup.Name
        $ec2sInRegion = $regionGroup.Group
        
        Write-ColorOutput "🍳 Firing up region kitchen: $region ($($ec2sInRegion.Count) EC2s)" "Cyan"
        Write-ColorOutput "-" * 50 "Gray"
        
        # 6a) Set AWS context for this region
        if (-not (Set-AWSContext -Region $region -Profile $AWSProfile)) {
            Write-ColorOutput "🚫 Skipping region $region due to context issues" "Red"
            continue
        }
        
        # 6b) Iterate through each EC2 entrée
        foreach ($ec2 in $ec2sInRegion) {
            $instanceId = $ec2.InstanceId.Trim()
            $instanceName = if ($ec2.PSObject.Properties.Name -contains 'InstanceName') { 
                "($($ec2.InstanceName.Trim()))" 
            } else { 
                "" 
            }
            
            Write-ColorOutput "  🖥️  Prepping EC2: $instanceId $instanceName" "White"
            
            # 6c) Parse start/stop times (read the cooking instructions)
            $startTime = $null
            $stopTime = $null
            
            if ($ec2.PSObject.Properties.Name -contains 'StartTime') {
                $startTime = Convert-TimeString -TimeString $ec2.StartTime -TimeZone $TimeZone
            }
            
            if ($ec2.PSObject.Properties.Name -contains 'StopTime') {
                $stopTime = Convert-TimeString -TimeString $ec2.StopTime -TimeZone $TimeZone
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
                Write-ColorOutput "    😴 EC2 is taking a break—no action needed." "Gray"
                Write-ColorOutput "" "White"
                continue
            }
            
            try {
                # 6e) Get current power state & act (check the oven temperature)
                $ec2Status = Get-EC2Status -InstanceId $instanceId -Region $region
                
                Write-ColorOutput "    📊 Current status: $ec2Status" "Gray"
                
                if ($requiredAction -eq 'start') {
                    if ($ec2Status -eq "running") {
                        Write-ColorOutput "    ✅ EC2 is already sizzling. No action needed." "Yellow"
                    } elseif ($ec2Status -eq "pending") {
                        Write-ColorOutput "    ⏳ EC2 is already firing up. No action needed." "Yellow"
                    } else {
                        Write-ColorOutput "    🔥 Firing up the EC2..." "Green"
                        Start-EC2Instance -InstanceId $instanceId -Region $region | Out-Null
                        Write-ColorOutput "    🚀 Start command completed for $instanceId" "Green"
                    }
                }
                elseif ($requiredAction -eq 'stop') {
                    if ($ec2Status -eq "stopped" -or $ec2Status -eq "terminated") {
                        Write-ColorOutput "    ❄️  EC2 is already chilled. No action needed." "Yellow"
                    } elseif ($ec2Status -eq "stopping") {
                        Write-ColorOutput "    ⏳ EC2 is already shutting down. No action needed." "Yellow"
                    } else {
                        Write-ColorOutput "    🛑 Shutting down the EC2..." "Red"
                        Stop-EC2Instance -InstanceId $instanceId -Region $region | Out-Null
                        Write-ColorOutput "    ⏹️  Stop command completed for $instanceId" "Red"
                    }
                }
            }
            catch {
                Write-ColorOutput "    💥 Kitchen accident with EC2 $instanceId`: $($_.Exception.Message)" "Red"
            }
            
            Write-ColorOutput "" "White"
        }
        
        Write-ColorOutput "" "White"
    }
    
    # Plate up the finale
    Write-ColorOutput "=" * 70 "Gray"
    Write-ColorOutput "🎉 Service complete! All EC2 operations have been processed." "Green"
    Write-ColorOutput "🔍 Check the AWS Console to verify all dishes are properly prepared." "Yellow"
}
catch {
    Write-ColorOutput "💥 Kitchen disaster: $($_.Exception.Message)" "Red"
    exit 1
}

# ---------------------------------------------------------------------------
# 🍳 CloudCostChefs Recipe Card Format:
# ---------------------------------------------------------------------------
<#
InstanceId,Region,InstanceName,StartTime,StopTime
i-0123456789abcdef0,us-east-1,WebServer01,08:00,18:00
i-0abcdef123456789,us-east-1,DatabaseServer,06:00,22:00
i-0fedcba987654321,us-west-2,TestInstance,09:00,17:00
i-0987654321fedcba,eu-west-1,BackupServer,,02:00
i-0456789abcdef012,ap-southeast-1,DemoInstance,10:00,

🧑‍🍳 Chef's Notes:
- InstanceId: Your EC2 instance ID (starts with i-)
- Region: AWS region like "us-east-1", "eu-west-1" 
- InstanceName: Optional friendly name for display
- StartTime/StopTime: Use HH:mm format (24-hour kitchen time)
- Empty times are fine—some dishes only need prep OR cleanup
- Cross-midnight schedules work (22:00 start, 06:00 stop)
- EC2s get grouped by region for efficient service
- Requires AWS CLI installed and configured
- Use --profile parameter for named AWS profiles
- Check AWS Console for final EC2 states!

Usage Examples:
  .\AWS-Start-CloudGrill.ps1 -CsvFilePath "ec2-schedule.csv"
  .\AWS-Start-CloudGrill.ps1 -CsvFilePath "ec2-schedule.csv" -AWSProfile "production"
  .\AWS-Start-CloudGrill.ps1 -CsvFilePath "ec2-schedule.csv" -TimeZone "Eastern Standard Time"
#>
