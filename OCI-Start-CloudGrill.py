#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# 🍳 CloudCostChefs "Mise-en-Place" Notes
# OCI Compute Multi-Tenancy Scheduled Start/Stop Script
# Reads a CSV of instances + times and flips power states like a grill master
# ---------------------------------------------------------------------------

import argparse
import csv
import sys
import os
from datetime import datetime, time
from typing import Optional, List, Dict, Any
import logging

# Color codes for our fancy console plating
class Colors:
    RED = '\033[91m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    MAGENTA = '\033[95m'
    CYAN = '\033[96m'
    WHITE = '\033[97m'
    GRAY = '\033[90m'
    RESET = '\033[0m'

def write_color_output(message: str, color: str = Colors.WHITE) -> None:
    """Colorful plating for console output"""
    print(f"{color}{message}{Colors.RESET}")

def convert_time_string(time_string: str, timezone: str = "UTC") -> Optional[datetime]:
    """Convert '08:30' into a DateTime entrée - accepts HH:mm or full timestamp"""
    if not time_string or time_string.strip() == "":
        return None
    
    try:
        time_string = time_string.strip()
        # Try to parse time in HH:mm format (chef's favorite)
        if ":" in time_string and len(time_string.split(":")) == 2:
            today = datetime.now()
            hour, minute = map(int, time_string.split(":"))
            return datetime.combine(today.date(), time(hour, minute))
        # Try to parse full datetime (the deluxe version)
        else:
            return datetime.fromisoformat(time_string)
    except Exception as e:
        write_color_output(f"  🔥 Invalid time format: {time_string}. Use HH:mm or ISO format.", Colors.RED)
        return None

def get_required_action(current_time: datetime, start_time: Optional[datetime], 
                       stop_time: Optional[datetime]) -> str:
    """
    Decide what action the instance needs right now
    • Returns 'start', 'stop', or 'none'
    • Handles overnight hours like 22:00 → 06:00 gracefully
    """
    
    # If both times are null, the instance is on vacation
    if not start_time and not stop_time:
        return "none"
    
    # If only start time is specified (morning prep only)
    if start_time and not stop_time:
        if current_time >= start_time:
            return "start"
        return "none"
    
    # If only stop time is specified (shutdown timer only)
    if not start_time and stop_time:
        if current_time >= stop_time:
            return "stop"
        return "none"
    
    # Both times specified (full service hours)
    if start_time and stop_time:
        # Handle case where stop time is next day (start: 08:00, stop: 18:00)
        if start_time <= stop_time:
            if start_time <= current_time < stop_time:
                return "start"
            elif current_time >= stop_time:
                return "stop"
        # Handle case where stop time crosses midnight (start: 22:00, stop: 06:00)
        else:
            if current_time >= start_time or current_time < stop_time:
                return "start"
            else:
                return "stop"
    
    return "none"

class OCIKitchen:
    """Main kitchen class for managing OCI compute instances"""
    
    def __init__(self, config_file: Optional[str] = None, profile: Optional[str] = None):
        """Initialize the OCI kitchen with proper credentials"""
        try:
            import oci
            self.oci = oci
            
            # Load OCI config (defaults to ~/.oci/config)
            if config_file:
                self.config = oci.config.from_file(config_file, profile or "DEFAULT")
            else:
                self.config = oci.config.from_file(profile_name=profile or "DEFAULT")
            
            # Validate config
            oci.config.validate_config(self.config)
            
            # Initialize compute client
            self.compute_client = oci.core.ComputeClient(self.config)
            
            write_color_output(f"👨‍🍳 Authenticated to OCI tenancy: {self.config.get('tenancy', 'Unknown')}", Colors.GREEN)
            
        except ImportError:
            write_color_output("🚫 OCI Python SDK is not installed. Please install it using:", Colors.RED)
            write_color_output("   pip install oci", Colors.YELLOW)
            sys.exit(1)
        except Exception as e:
            write_color_output(f"💥 Failed to initialize OCI client: {str(e)}", Colors.RED)
            write_color_output("   Make sure ~/.oci/config is properly configured", Colors.YELLOW)
            sys.exit(1)
    
    def get_instance_status(self, instance_id: str, compartment_id: str) -> str:
        """Get current instance status (check the oven temperature)"""
        try:
            response = self.compute_client.get_instance(instance_id)
            return response.data.lifecycle_state
        except Exception as e:
            raise Exception(f"Failed to get instance status: {str(e)}")
    
    def start_instance(self, instance_id: str) -> bool:
        """Fire up an OCI instance"""
        try:
            self.compute_client.instance_action(instance_id, "START")
            return True
        except Exception as e:
            raise Exception(f"Failed to start instance: {str(e)}")
    
    def stop_instance(self, instance_id: str) -> bool:
        """Shut down an OCI instance"""
        try:
            self.compute_client.instance_action(instance_id, "STOP")
            return True
        except Exception as e:
            raise Exception(f"Failed to stop instance: {str(e)}")

def load_recipe_card(csv_file_path: str) -> List[Dict[str, Any]]:
    """Load the CSV recipe card and validate ingredients"""
    
    if not os.path.exists(csv_file_path):
        write_color_output(f"📄 CSV file not found: {csv_file_path}", Colors.RED)
        sys.exit(1)
    
    write_color_output(f"📋 Reading recipe card (CSV): {csv_file_path}", Colors.GREEN)
    
    instances = []
    required_headers = {'InstanceId', 'CompartmentId'}
    
    try:
        with open(csv_file_path, 'r', newline='', encoding='utf-8') as csvfile:
            reader = csv.DictReader(csvfile)
            headers = set(reader.fieldnames or [])
            
            # Essential ingredients check
            missing_headers = required_headers - headers
            if missing_headers:
                write_color_output(f"❌ Missing required columns: {', '.join(missing_headers)}", Colors.RED)
                write_color_output("   Required columns: InstanceId, CompartmentId, StartTime, StopTime", Colors.YELLOW)
                write_color_output("   Optional columns: InstanceName (for display purposes)", Colors.YELLOW)
                sys.exit(1)
            
            # Check for time columns (need at least one timer)
            if 'StartTime' not in headers and 'StopTime' not in headers:
                write_color_output("⏰ At least one time column (StartTime or StopTime) is required", Colors.RED)
                sys.exit(1)
            
            for row in reader:
                # Clean up the data
                instance = {k: v.strip() if v else '' for k, v in row.items()}
                instances.append(instance)
    
    except Exception as e:
        write_color_output(f"💥 Error reading CSV: {str(e)}", Colors.RED)
        sys.exit(1)
    
    write_color_output(f"📊 Found {len(instances)} compute instances on the menu", Colors.GREEN)
    return instances

def group_by_compartment(instances: List[Dict[str, Any]]) -> Dict[str, List[Dict[str, Any]]]:
    """Group instances by compartment so we're not oven-hopping every second"""
    compartments = {}
    for instance in instances:
        compartment_id = instance['CompartmentId']
        if compartment_id not in compartments:
            compartments[compartment_id] = []
        compartments[compartment_id].append(instance)
    
    write_color_output(f"🏢 Instances span across {len(compartments)} compartment kitchen(s)", Colors.GREEN)
    return compartments

def main():
    """Main course - let's start cooking!"""
    
    parser = argparse.ArgumentParser(
        description="🍳 CloudCostChefs OCI Compute Instance Scheduler",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
🧑‍🍳 Chef's Recipe Card Format:
InstanceId,CompartmentId,InstanceName,StartTime,StopTime
ocid1.instance.oc1...,ocid1.compartment.oc1...,WebServer01,08:00,18:00
ocid1.instance.oc1...,ocid1.compartment.oc1...,DatabaseServer,06:00,22:00

Examples:
  python oci-start-cloudgrill.py recipes/production.csv
  python oci-start-cloudgrill.py recipes/dev.csv --profile DEV
  python oci-start-cloudgrill.py recipes/all.csv --config ~/.oci/prod-config
        """
    )
    
    parser.add_argument('csv_file', help='Where\'s the recipe card (CSV) stored?')
    parser.add_argument('--timezone', default='UTC', help='Kitchen clock (defaults to UTC)')
    parser.add_argument('--config', help='OCI config file path (defaults to ~/.oci/config)')
    parser.add_argument('--profile', help='OCI config profile to use (defaults to DEFAULT)')
    
    args = parser.parse_args()
    
    # ---------------------------------------------------------------------------
    # Mise-en-Place Check: Are we stocked with the right ingredients?
    # ---------------------------------------------------------------------------
    
    current_time = datetime.now()
    write_color_output(f"🕐 Current time: {current_time.strftime('%Y-%m-%d %H:%M:%S')} ({args.timezone})", Colors.GREEN)
    
    # Initialize our OCI kitchen
    kitchen = OCIKitchen(config_file=args.config, profile=args.profile)
    
    # Load the recipe card and validate
    instances = load_recipe_card(args.csv_file)
    
    # Group instances by compartment for efficient service
    instances_by_compartment = group_by_compartment(instances)
    
    write_color_output("=" * 70, Colors.GRAY)
    
    # ---------------------------------------------------------------------------
    # Cook each compartment 🔄
    # ---------------------------------------------------------------------------
    
    for compartment_id, compartment_instances in instances_by_compartment.items():
        compartment_name = compartment_id[-8:]  # Show last 8 chars for readability
        write_color_output(f"🍳 Firing up compartment kitchen: ...{compartment_name} ({len(compartment_instances)} instances)", Colors.CYAN)
        write_color_output("-" * 50, Colors.GRAY)
        
        # Process each instance entrée in this compartment
        for instance in compartment_instances:
            instance_id = instance['InstanceId']
            instance_name = instance.get('InstanceName', '')
            display_name = f"({instance_name})" if instance_name else ""
            
            write_color_output(f"  🖥️  Prepping instance: ...{instance_id[-8:]} {display_name}", Colors.WHITE)
            
            # Parse start/stop times (read the cooking instructions)
            start_time = convert_time_string(instance.get('StartTime', ''), args.timezone)
            stop_time = convert_time_string(instance.get('StopTime', ''), args.timezone)
            
            if start_time:
                write_color_output(f"    🌅 Start time: {start_time.strftime('%H:%M')}", Colors.GRAY)
            if stop_time:
                write_color_output(f"    🌙 Stop time: {stop_time.strftime('%H:%M')}", Colors.GRAY)
            
            # Decide if we should fire up or shut down
            required_action = get_required_action(current_time, start_time, stop_time)
            write_color_output(f"    🎯 Required action: {required_action}", Colors.YELLOW)
            
            if required_action == "none":
                write_color_output("    😴 Instance is taking a break—no action needed.", Colors.GRAY)
                print()
                continue
            
            try:
                # Get current power state & act (check the oven temperature)
                instance_status = kitchen.get_instance_status(instance_id, compartment_id)
                write_color_output(f"    📊 Current status: {instance_status}", Colors.GRAY)
                
                if required_action == 'start':
                    if instance_status == "RUNNING":
                        write_color_output("    ✅ Instance is already sizzling. No action needed.", Colors.YELLOW)
                    elif instance_status == "STARTING":
                        write_color_output("    ⏳ Instance is already firing up. No action needed.", Colors.YELLOW)
                    else:
                        write_color_output("    🔥 Firing up the instance...", Colors.GREEN)
                        kitchen.start_instance(instance_id)
                        write_color_output(f"    🚀 Start command completed for ...{instance_id[-8:]}", Colors.GREEN)
                
                elif required_action == 'stop':
                    if instance_status in ["STOPPED", "TERMINATED"]:
                        write_color_output("    ❄️  Instance is already chilled. No action needed.", Colors.YELLOW)
                    elif instance_status == "STOPPING":
                        write_color_output("    ⏳ Instance is already shutting down. No action needed.", Colors.YELLOW)
                    else:
                        write_color_output("    🛑 Shutting down the instance...", Colors.RED)
                        kitchen.stop_instance(instance_id)
                        write_color_output(f"    ⏹️  Stop command completed for ...{instance_id[-8:]}", Colors.RED)
                        
            except Exception as e:
                write_color_output(f"    💥 Kitchen accident with instance ...{instance_id[-8:]}: {str(e)}", Colors.RED)
            
            print()
        
        print()
    
    # Plate up the finale
    write_color_output("=" * 70, Colors.GRAY)
    write_color_output("🎉 Service complete! All OCI compute operations have been processed.", Colors.GREEN)
    write_color_output("🔍 Check the OCI Console to verify all dishes are properly prepared.", Colors.YELLOW)

if __name__ == "__main__":
    main()

# ---------------------------------------------------------------------------
# 🍳 CloudCostChefs Recipe Card Format:
# ---------------------------------------------------------------------------
"""
InstanceId,CompartmentId,InstanceName,StartTime,StopTime
ocid1.instance.oc1.iad.anyhqljt...,ocid1.compartment.oc1..anyhqljt...,WebServer01,08:00,18:00
ocid1.instance.oc1.iad.anyhqljt...,ocid1.compartment.oc1..anyhqljt...,DatabaseServer,06:00,22:00
ocid1.instance.oc1.phx.anyhqljt...,ocid1.compartment.oc1..anyhqljt...,TestInstance,09:00,17:00
ocid1.instance.oc1.iad.anyhqljt...,ocid1.compartment.oc1..anyhqljt...,BackupServer,,02:00
ocid1.instance.oc1.lhr.anyhqljt...,ocid1.compartment.oc1..anyhqljt...,DemoInstance,10:00,

🧑‍🍳 Chef's Notes:
- InstanceId: Your OCI compute instance OCID (starts with ocid1.instance...)
- CompartmentId: OCI compartment OCID (starts with ocid1.compartment...)
- InstanceName: Optional friendly name for display
- StartTime/StopTime: Use HH:mm format (24-hour kitchen time)
- Empty times are fine—some dishes only need prep OR cleanup
- Cross-midnight schedules work (22:00 start, 06:00 stop)
- Instances get grouped by compartment for efficient service
- Requires OCI Python SDK: pip install oci
- Requires ~/.oci/config properly configured with API keys
- Check OCI Console for final instance states!

Prerequisites:
1. Install OCI SDK: pip install oci
2. Configure OCI CLI: oci setup config
3. Or manually create ~/.oci/config with API key details
4. Ensure proper IAM permissions for compute instance management

Usage Examples:
  python oci-start-cloudgrill.py instances.csv
  python oci-start-cloudgrill.py instances.csv --profile PROD
  python oci-start-cloudgrill.py instances.csv --config /path/to/config --timezone "US/Pacific"
"""
