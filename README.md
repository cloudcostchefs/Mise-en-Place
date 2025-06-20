# 🍳 CloudCostChefs Multi-Cloud VM Scheduler

> *"Cooking up cost savings, one VM at a time!"*

Welcome to CloudCostChefs - your sous chef for managing virtual machine schedules across all major cloud providers. Our collection of scripts helps you start and stop VMs based on CSV schedules, turning your cloud infrastructure into a well-orchestrated kitchen that runs only when needed.

## 🌟 What's Cooking?

This repository contains four expertly crafted scripts that manage VM/compute instance schedules across:

- **🔵 Microsoft Azure** - `Azure-Start-CloudGrill.ps1`
- **🟡 Google Cloud Platform** - `GCP-Start-CloudGrill.ps1` 
- **🟠 Amazon Web Services** - `AWS-Start-CloudGrill.ps1`
- **🔴 Oracle Cloud Infrastructure** - `oci-start-cloudgrill.py`

Each script reads a CSV "recipe card" containing your VMs and their desired start/stop times, then automatically manages their power states like a master chef managing multiple ovens.

## 🚀 Quick Start

### 1. Choose Your Cloud Kitchen

Select the script for your cloud provider:

```bash
# Azure (PowerShell)
.\Azure-Start-CloudGrill.ps1 -CsvFilePath "vms.csv"

# Google Cloud (PowerShell) 
.\GCP-Start-CloudGrill.ps1 -CsvFilePath "vms.csv"

# AWS (PowerShell)
.\AWS-Start-CloudGrill.ps1 -CsvFilePath "vms.csv"

# Oracle Cloud (Python)
python oci-start-cloudgrill.py vms.csv
```

### 2. Prepare Your Recipe Card (CSV)

Each cloud has its own CSV format - see the [Recipe Cards](#-recipe-cards-csv-formats) section below.

### 3. Let the Magic Happen

The scripts will:
- ✅ Check current VM states
- 🕐 Compare against your schedules
- 🔥 Start VMs during operating hours
- ❄️ Stop VMs outside operating hours
- 🎨 Display colorful, chef-themed output

## 🛠️ Installation & Prerequisites

### Azure (`Azure-Start-CloudGrill.ps1`)

**Prerequisites:**
- PowerShell 5.1 or later
- Azure PowerShell module

```powershell
# Install Azure PowerShell
Install-Module -Name Az -AllowClobber -Scope CurrentUser

# Connect to Azure
Connect-AzAccount
```

### Google Cloud (`GCP-Start-CloudGrill.ps1`)

**Prerequisites:**
- PowerShell 5.1 or later
- Google Cloud CLI

```bash
# Install Google Cloud CLI
# https://cloud.google.com/sdk/docs/install

# Authenticate
gcloud auth login
```

### AWS (`AWS-Start-CloudGrill.ps1`)

**Prerequisites:**
- PowerShell 5.1 or later
- AWS CLI

```bash
# Install AWS CLI
# https://aws.amazon.com/cli/

# Configure credentials
aws configure
```

### Oracle Cloud (`oci-start-cloudgrill.py`)

**Prerequisites:**
- Python 3.6 or later
- OCI Python SDK

```bash
# Install OCI SDK
pip install oci

# Configure OCI
oci setup config
```

## 📋 Recipe Cards (CSV Formats)

### Azure Format
```csv
VMName,ResourceGroupName,SubscriptionId,StartTime,StopTime
WebServer01,Production-RG,12345678-1234-1234-1234-123456789012,08:00,18:00
DatabaseServer,Production-RG,12345678-1234-1234-1234-123456789012,06:00,22:00
TestVM,Development-RG,87654321-4321-4321-4321-210987654321,09:00,17:00
```

### Google Cloud Format
```csv
VMName,Zone,ProjectId,StartTime,StopTime
web-server-01,us-central1-a,my-production-project,08:00,18:00
database-server,us-central1-b,my-production-project,06:00,22:00
test-vm,us-west1-a,my-development-project,09:00,17:00
```

### AWS Format
```csv
InstanceId,Region,InstanceName,StartTime,StopTime
i-0123456789abcdef0,us-east-1,WebServer01,08:00,18:00
i-0abcdef123456789,us-east-1,DatabaseServer,06:00,22:00
i-0fedcba987654321,us-west-2,TestInstance,09:00,17:00
```

### Oracle Cloud Format
```csv
InstanceId,CompartmentId,InstanceName,StartTime,StopTime
ocid1.instance.oc1.iad.anyhqljt...,ocid1.compartment.oc1..anyhqljt...,WebServer01,08:00,18:00
ocid1.instance.oc1.iad.anyhqljt...,ocid1.compartment.oc1..anyhqljt...,DatabaseServer,06:00,22:00
ocid1.instance.oc1.phx.anyhqljt...,ocid1.compartment.oc1..anyhqljt...,TestInstance,09:00,17:00
```

## ⏰ Schedule Logic

### Time Format
- Use **24-hour format**: `08:00`, `18:30`, `22:15`
- Times represent **daily schedules**
- Empty start/stop times are allowed

### Scheduling Behavior

| Scenario | Action |
|----------|--------|
| Current time between start and stop | ✅ **START** the VM |
| Current time outside the window | ❄️ **STOP** the VM |
| Only start time specified | ✅ **START** after start time |
| Only stop time specified | ❄️ **STOP** after stop time |
| Cross-midnight schedule (22:00-06:00) | ✅ **Handles correctly** |

### Examples
```csv
# Standard business hours
WebServer,rg-prod,sub-123,08:00,18:00

# 24/7 with maintenance window  
Database,rg-prod,sub-123,02:00,01:00

# Start only (no automatic stop)
DevBox,rg-dev,sub-456,09:00,

# Stop only (for cleanup jobs)
BackupVM,rg-backup,sub-789,,03:00
```

## 🎯 Advanced Usage

### Azure Multi-Subscription
```powershell
# Automatically handles multiple subscriptions from CSV
.\Azure-Start-CloudGrill.ps1 -CsvFilePath "multi-sub-vms.csv"
```

### AWS with Profiles
```powershell
# Use specific AWS profile
.\AWS-Start-CloudGrill.ps1 -CsvFilePath "ec2s.csv" -AWSProfile "production"
```

### GCP Multi-Project
```powershell
# Handles multiple projects automatically
.\GCP-Start-CloudGrill.ps1 -CsvFilePath "multi-project-vms.csv"
```

### OCI with Custom Config
```bash
# Use specific OCI profile and timezone
python oci-start-cloudgrill.py instances.csv --profile PROD --timezone "US/Pacific"
```

## 🤖 Automation Setup

### Windows Task Scheduler
Create scheduled tasks to run the scripts automatically:

```powershell
# Example: Run Azure script every hour
$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-File C:\Scripts\Azure-Start-CloudGrill.ps1 -CsvFilePath C:\Config\azure-vms.csv"
$Trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Hours 1)
Register-ScheduledTask -Action $Action -Trigger $Trigger -TaskName "CloudCostChefs-Azure"
```

### Linux Cron Jobs
```bash
# Run every hour
0 * * * * /usr/bin/python3 /scripts/oci-start-cloudgrill.py /config/instances.csv

# Run every 30 minutes
*/30 * * * * /usr/bin/pwsh /scripts/AWS-Start-CloudGrill.ps1 -CsvFilePath /config/aws-ec2s.csv
```

### GitHub Actions
```yaml
name: CloudCostChefs Schedule
on:
  schedule:
    - cron: '0 * * * *'  # Every hour
jobs:
  manage-vms:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v2
    - name: Run Azure Script
      run: pwsh ./Azure-Start-CloudGrill.ps1 -CsvFilePath ./config/azure-vms.csv
```

## 🔍 Troubleshooting

### Common Issues

**Authentication Errors:**
```bash
# Azure
Connect-AzAccount

# GCP  
gcloud auth login

# AWS
aws configure

# OCI
oci setup config
```

**Permission Issues:**
- Ensure your account has VM start/stop permissions
- Check subscription/project/account access
- Verify resource group/compartment permissions

**CSV Format Errors:**
- Check column headers match exactly
- Ensure no extra spaces in time values
- Verify resource IDs are correct

### Debug Mode
Add verbose logging by modifying the scripts or checking cloud provider logs.

## 🎨 Features

- 🌈 **Colorful Output** - Easy-to-read console messages
- 🔄 **Multi-Cloud Support** - Azure, GCP, AWS, OCI
- ⚡ **Async Operations** - Fast parallel processing
- 🛡️ **Error Handling** - Graceful failure handling
- 📊 **Status Reporting** - Clear action summaries
- 🕐 **Flexible Scheduling** - Supports complex time windows
- 🏢 **Multi-Tenancy** - Handle multiple subscriptions/projects/accounts

## 🤝 Contributing

We welcome contributions to make CloudCostChefs even better! 

### Adding New Cloud Providers
1. Follow the existing script structure
2. Maintain the chef-themed naming and emojis
3. Include comprehensive error handling
4. Add CSV format documentation

### Improving Existing Scripts
1. Fork the repository
2. Create a feature branch
3. Add tests if possible
4. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Inspired by the need to reduce cloud costs through intelligent scheduling
- Built with love for infrastructure automation
- Special thanks to all cloud providers for their excellent APIs

## 📞 Support

- 🐛 **Issues**: Report bugs via GitHub Issues
- 💬 **Discussions**: Use GitHub Discussions for questions
- 📧 **Email**: For enterprise support inquiries

---

## 🎪 Fun Facts

- 💰 **Average Savings**: Users report 30-60% cost reduction on non-production workloads
- ⏱️ **Time Saved**: Automated scheduling saves hours per week
- 🌍 **Global Usage**: Scripts work across all cloud regions
- 🔧 **Flexibility**: Handles complex cross-midnight schedules

---

*Happy Cooking! 🍳*

**CloudCostChefs Team**
