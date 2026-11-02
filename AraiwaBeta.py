#!/data/data/com.termux/files/usr/bin/python
import subprocess
import time
import random
import re
import json
import os
import sys
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor
from threading import Lock

class TermuxRobloxRejoin:
    def __init__(self, config_file='roblox_config.json'):
        self.config_file = config_file
        self.device_ready = False
        self.roblox_packages = []
        self.print_lock = Lock()
        self.load_config()
        
    def print_safe(self, message, error=False):
        """Thread-safe printing"""
        with self.print_lock:
            prefix = "❌" if error else "✅" if "✅" in message else "🔄" if "🔄" in message else "📱" if "📱" in message else "⚠️" if "⚠️" in message else "ℹ️"
            if not any(x in message for x in ["✅", "❌", "🔄", "📱", "⚠️", "ℹ️"]):
                prefix = "ℹ️"
            print(f"{prefix} {message}")
    
    def load_config(self):
        """Load or create configuration"""
        default_config = {
            'private_server_link': 'https://www.roblox.com/games/YOUR_GAME_ID/YOUR_SERVER_ID',
            'max_instances': 2,
            'rejoin_delay_min': 300,
            'rejoin_delay_max': 600,
            'auto_detect_packages': True,
            'custom_packages': [],
            'use_root': True,
            'rejoin_on_disconnect': True,
            'check_interval': 10,
            'log_file': 'roblox_rejoin.log'
        }
        
        if os.path.exists(self.config_file):
            with open(self.config_file, 'r') as f:
                self.config = json.load(f)
            self.print_safe(f"Config loaded from {self.config_file}")
        else:
            self.config = default_config
            with open(self.config_file, 'w') as f:
                json.dump(default_config, f, indent=4)
            self.print_safe(f"Created default config at {self.config_file}")
            self.print_safe("Please edit the config file with your private server link!")
            sys.exit(0)
    
    def log_message(self, message):
        """Log messages to file"""
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        log_entry = f"[{timestamp}] {message}\n"
        
        try:
            with open(self.config['log_file'], 'a') as f:
                f.write(log_entry)
        except:
            pass
    
    def run_termux_command(self, command, use_su=False):
        """Run command in Termux environment"""
        try:
            if use_su and self.config['use_root']:
                # For rooted devices, use su
                full_cmd = f"su -c '{command}'"
            else:
                full_cmd = command
                
            result = subprocess.run(full_cmd, shell=True, capture_output=True, text=True, timeout=30)
            return result.stdout.strip(), result.stderr.strip(), result.returncode
        except subprocess.TimeoutExpired:
            return "", "Timeout", 1
        except Exception as e:
            return "", str(e), 1
    
    def check_termux_environment(self):
        """Check if running in Termux and setup necessary tools"""
        self.print_safe("Checking Termux environment...")
        
        # Check if running in Termux
        try:
            result = subprocess.run("pwd", shell=True, capture_output=True, text=True)
            if "/data/data/com.termux" not in result.stdout:
                self.print_safe("Not running in Termux? Continuing anyway...", error=True)
        except:
            pass
        
        # Check for required packages
        required_commands = ['adb', 'pm', 'am', 'su']
        missing = []
        
        for cmd in required_commands:
            result, _, _ = self.run_termux_command(f"which {cmd}")
            if not result:
                missing.append(cmd)
        
        if missing:
            self.print_safe(f"Missing commands: {missing}", error=True)
            self.print_safe("Install with: pkg install android-tools root-repo", error=True)
            return False
        
        self.print_safe("Termux environment ready")
        return True
    
    def detect_roblox_packages(self):
        """Auto-detect all com.roblox.* packages"""
        self.print_safe("Detecting Roblox packages...")
        
        # Use pm to list all packages
        cmd = "pm list packages | grep com.roblox"
        output, error, code = self.run_termux_command(cmd, use_su=self.config['use_root'])
        
        packages = []
        if output:
            # Parse package names from output
            lines = output.strip().split('\n')
            for line in lines:
                match = re.search(r'com\.roblox\.[^\s]+', line)
                if match:
                    packages.append(match.group(0))
        
        # Remove duplicates and sort
        packages = sorted(list(set(packages)))
        
        if packages:
            self.print_safe(f"Found {len(packages)} Roblox packages:")
            for i, pkg in enumerate(packages):
                self.print_safe(f"  {i+1}. {pkg}")
            return packages
        else:
            self.print_safe("No Roblox packages found!", error=True)
            self.print_safe("Make sure Roblox is installed and device is rooted", error=True)
            return []
    
    def check_package_status(self, package_name):
        """Check if a package is installed and its process status"""
        # Check if package is installed
        cmd = f"pm path {package_name}"
        output, _, code = self.run_termux_command(cmd, use_su=self.config['use_root'])
        
        if code != 0 or not output:
            return None  # Not installed
        
        # Check if process is running
        cmd = f"ps -A | grep {package_name}"
        output, _, _ = self.run_termux_command(cmd, use_su=self.config['use_root'])
        
        return bool(output)  # True if running
    
    def kill_roblox_instance(self, package_name):
        """Force stop a Roblox instance"""
        self.print_safe(f"Killing {package_name}...")
        
        cmd = f"am force-stop {package_name}"
        output, error, code = self.run_termux_command(cmd, use_su=self.config['use_root'])
        
        if code == 0:
            self.print_safe(f"Killed {package_name}")
            self.log_message(f"Killed {package_name}")
            time.sleep(2)
            return True
        else:
            self.print_safe(f"Failed to kill {package_name}: {error}", error=True)
            return False
    
    def open_roblox_private_server(self, package_name):
        """Open Roblox with private server link"""
        self.print_safe(f"Opening {package_name} with private server...")
        
        # Create intent to open URL
        cmd = f'am start -a android.intent.action.VIEW -d "{self.config["private_server_link"]}" {package_name}'
        output, error, code = self.run_termux_command(cmd, use_su=self.config['use_root'])
        
        if code == 0 and "Starting" in output:
            self.print_safe(f"Opened {package_name}")
            self.log_message(f"Opened {package_name} with private server")
            return True
        else:
            self.print_safe(f"Failed to open {package_name}: {error}", error=True)
            return False
    
    def monitor_and_rejoin(self, package_name, instance_id):
        """Monitor a single Roblox instance and rejoin if needed"""
        self.print_safe(f"Starting monitor for {package_name} (Instance {instance_id})")
        
        while True:
            try:
                # Check if package is running
                is_running = self.check_package_status(package_name)
                
                if not is_running and self.config['rejoin_on_disconnect']:
                    self.print_safe(f"{package_name} not running, restarting...")
                    self.open_roblox_private_server(package_name)
                
                # Random delay before next check
                delay = random.randint(self.config['rejoin_delay_min'], self.config['rejoin_delay_max'])
                self.print_safe(f"{package_name}: Next rejoin in {delay} seconds")
                
                # Countdown timer
                for remaining in range(delay, 0, -self.config['check_interval']):
                    if remaining % 60 == 0 or remaining < 60:
                        self.print_safe(f"{package_name}: Rejoin in {remaining} seconds")
                    time.sleep(min(self.config['check_interval'], remaining))
                
                # Perform rejoin
                self.kill_roblox_instance(package_name)
                time.sleep(random.uniform(2, 5))
                self.open_roblox_private_server(package_name)
                
            except KeyboardInterrupt:
                self.print_safe(f"Stopping monitor for {package_name}")
                break
            except Exception as e:
                self.print_safe(f"Error in {package_name}: {str(e)}", error=True)
                self.log_message(f"Error in {package_name}: {str(e)}")
                time.sleep(30)
    
    def start_multi_instance(self):
        """Start multiple Roblox instances"""
        self.print_safe("=" * 50)
        self.print_safe("Roblox Multi-Instance Rejoin System for Termux")
        self.print_safe("=" * 50)
        
        # Check environment
        if not self.check_termux_environment():
            self.print_safe("Environment check failed!", error=True)
            return
        
        # Detect or use packages
        if self.config['auto_detect_packages']:
            packages = self.detect_roblox_packages()
        else:
            packages = self.config['custom_packages']
        
        if not packages:
            self.print_safe("No Roblox packages found! Please install Roblox or configure manually.", error=True)
            return
        
        # Limit to max instances
        self.roblox_packages = packages[:self.config['max_instances']]
        
        if len(packages) < self.config['max_instances']:
            self.print_safe(f"Warning: Only found {len(packages)} packages, but max_instances is {self.config['max_instances']}")
        
        self.print_safe(f"\nStarting {len(self.roblox_packages)} Roblox instances:")
        
        # Kill existing instances first
        self.print_safe("Cleaning up existing instances...")
        for pkg in self.roblox_packages:
            self.kill_roblox_instance(pkg)
        
        time.sleep(3)
        
        # Open all instances
        self.print_safe("Opening all Roblox instances...")
        for i, pkg in enumerate(self.roblox_packages):
            success = self.open_roblox_private_server(pkg)
            if not success:
                self.print_safe(f"Failed to open {pkg}, trying alternative method...", error=True)
                # Alternative method: open via intent without specifying package
                cmd = f'am start -a android.intent.action.VIEW -d "{self.config["private_server_link"]}"'
                self.run_termux_command(cmd, use_su=self.config['use_root'])
            time.sleep(random.uniform(3, 6))
        
        # Start monitoring threads
        self.print_safe("\nStarting rejoin monitors...")
        with ThreadPoolExecutor(max_workers=len(self.roblox_packages)) as executor:
            futures = []
            for i, pkg in enumerate(self.roblox_packages):
                future = executor.submit(self.monitor_and_rejoin, pkg, i+1)
                futures.append(future)
            
            # Keep running until interrupted
            try:
                for future in futures:
                    future.result()
            except KeyboardInterrupt:
                self.print_safe("\nShutting down...")
                executor.shutdown(wait=False)
    
    def rejoin_all_now(self):
        """Force rejoin all instances immediately"""
        self.print_safe("Force rejoining all instances...")
        
        if not self.roblox_packages:
            packages = self.detect_roblox_packages()
            if not packages:
                self.print_safe("No packages found!", error=True)
                return
            self.roblox_packages = packages[:self.config['max_instances']]
        
        for pkg in self.roblox_packages:
            self.kill_roblox_instance(pkg)
            time.sleep(1)
            self.open_roblox_private_server(pkg)
            time.sleep(1)
        
        self.print_safe("All instances rejoined!")
    
    def show_status(self):
        """Show status of all Roblox instances"""
        self.print_safe("Roblox Instance Status:")
        self.print_safe("-" * 30)
        
        packages = self.detect_roblox_packages()
        
        if not packages:
            self.print_safe("No Roblox packages found!")
            return
        
        for pkg in packages:
            is_running = self.check_package_status(pkg)
            status = "🟢 Running" if is_running else "🔴 Stopped"
            self.print_safe(f"{pkg}: {status}")
    
    def interactive_menu(self):
        """Interactive menu for easier control"""
        while True:
            print("\n" + "=" * 50)
            print("Roblox Rejoin System - Termux")
            print("=" * 50)
            print("1. Start auto rejoin system")
            print("2. Force rejoin all now")
            print("3. Show instance status")
            print("4. Kill all instances")
            print("5. Detect packages only")
            print("6. Edit config")
            print("7. Exit")
            
            choice = input("\nSelect option (1-7): ").strip()
            
            if choice == '1':
                self.start_multi_instance()
            elif choice == '2':
                self.rejoin_all_now()
            elif choice == '3':
                self.show_status()
            elif choice == '4':
                packages = self.detect_roblox_packages()
                for pkg in packages:
                    self.kill_roblox_instance(pkg)
                self.print_safe("All instances killed")
            elif choice == '5':
                packages = self.detect_roblox_packages()
                if packages:
                    self.print_safe(f"Found {len(packages)} packages")
            elif choice == '6':
                self.print_safe(f"Edit config file: {self.config_file}")
                self.print_safe("Run: nano " + self.config_file)
                input("Press Enter after editing...")
                self.load_config()  # Reload config
            elif choice == '7':
                self.print_safe("Goodbye!")
                sys.exit(0)
            else:
                self.print_safe("Invalid choice!", error=True)

# Termux-specific launcher script content
termux_launcher = """#!/data/data/com.termux/files/usr/bin/bash
# Termux launcher for Roblox Rejoin System

echo "Starting Roblox Rejoin System..."
cd ~/roblox-rejoin

# Check Python installation
if ! command -v python &> /dev/null; then
    echo "Python not found! Installing..."
    pkg install python -y
fi

# Install required packages
echo "Checking dependencies..."
pip install --upgrade pip

# Run the script
python roblox_rejoin.py

# Keep Termux open
read -p "Press Enter to exit..."
"""

if __name__ == "__main__":
    # Banner
    print("""
    ╔══════════════════════════════════════════════╗
    ║     Roblox Multi-Instance Rejoin Tool        ║
    ║           For Termux (Rooted)                ║
    ╚══════════════════════════════════════════════╝
    """)
    
    # Create launcher script
    with open("start_roblox.sh", "w") as f:
        f.write(termux_launcher)
    os.chmod("start_roblox.sh", 0o755)
    
    # Initialize and run
    rejoin = TermuxRobloxRejoin()
    
    # Check if running with arguments
    if len(sys.argv) > 1:
        if sys.argv[1] == "--auto":
            rejoin.start_multi_instance()
        elif sys.argv[1] == "--rejoin":
            rejoin.rejoin_all_now()
        elif sys.argv[1] == "--status":
            rejoin.show_status()
        else:
            rejoin.interactive_menu()
    else:
        rejoin.interactive_menu()
