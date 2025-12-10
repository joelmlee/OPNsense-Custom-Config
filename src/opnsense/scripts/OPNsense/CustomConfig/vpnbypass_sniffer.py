#!/usr/local/bin/python3
"""
VPN Bypass DNS Sniffer

Captures DNS responses using tcpdump and adds matching domains/IPs to the bypass list.
Runs as a daemon, watching for DNS responses that match configured wildcard patterns.

Usage:
    vpnbypass_sniffer.py start   - Start the sniffer daemon
    vpnbypass_sniffer.py stop    - Stop the sniffer daemon
    vpnbypass_sniffer.py status  - Check if daemon is running
    vpnbypass_sniffer.py test    - Run in foreground for testing
"""

import os
import sys
import re
import time
import signal
import subprocess
import fcntl
from datetime import datetime

# File paths
CONFIG_FILE = "/usr/local/etc/vpn_bypass_domains.conf"
DISCOVERED_DOMAINS_FILE = "/var/db/customconfig_vpnbypass_discovered.txt"
PID_FILE = "/var/run/vpnbypass_sniffer.pid"
LOG_FILE = "/var/log/vpnbypass_sniffer.log"
PF_TABLE = "customconfig_vpnbypass"

# Global state
wildcard_patterns = []
known_domains = set()
running = True
tcpdump_proc = None


def log(msg, level="INFO"):
    """Log message with timestamp"""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{timestamp}] [{level}] {msg}"
    print(line, flush=True)
    try:
        with open(LOG_FILE, 'a') as f:
            f.write(line + "\n")
    except:
        pass


def get_lan_interface():
    """Detect the LAN interface from OPNsense config"""
    import xml.etree.ElementTree as ET

    try:
        tree = ET.parse("/conf/config.xml")
        root = tree.getroot()

        # Find LAN interface name (e.g., "igb1")
        lan_if = root.find(".//interfaces/lan/if")
        if lan_if is not None and lan_if.text:
            log(f"Detected LAN interface: {lan_if.text}")
            return lan_if.text
    except Exception as e:
        log(f"Error detecting LAN interface: {e}", "ERROR")

    # Fallback to igb1
    log("Falling back to igb1 for LAN interface", "WARN")
    return "igb1"


def load_wildcard_patterns():
    """Load wildcard domain patterns from config file"""
    global wildcard_patterns
    wildcard_patterns = []

    if not os.path.exists(CONFIG_FILE):
        log(f"Config file not found: {CONFIG_FILE}", "WARN")
        return

    try:
        with open(CONFIG_FILE, 'r') as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                if line.startswith('*.'):
                    # Extract base domain (remove *.)
                    base_domain = line[2:].lower()
                    # Create regex pattern that matches the base domain AND any subdomain
                    # (.+\.)? matches optional subdomain prefix, but we use (.*\.)? to also match root
                    pattern = re.compile(
                        r'^(.*\.)?' + re.escape(base_domain) + r'\.?$',
                        re.IGNORECASE
                    )
                    wildcard_patterns.append((line, base_domain, pattern))
                    log(f"Loaded wildcard pattern: {line}")
    except Exception as e:
        log(f"Error loading config: {e}", "ERROR")

    log(f"Loaded {len(wildcard_patterns)} wildcard patterns")


def load_known_domains():
    """Load already-discovered domains to avoid duplicates"""
    global known_domains
    known_domains = set()

    if os.path.exists(DISCOVERED_DOMAINS_FILE):
        try:
            with open(DISCOVERED_DOMAINS_FILE, 'r') as f:
                for line in f:
                    domain = line.strip().lower()
                    if domain:
                        known_domains.add(domain)
        except:
            pass

    log(f"Loaded {len(known_domains)} known domains")


def domain_matches_wildcard(domain):
    """Check if domain matches any wildcard pattern"""
    domain = domain.rstrip('.').lower()
    for orig_pattern, base_domain, regex in wildcard_patterns:
        if regex.match(domain):
            return base_domain
    return None


def add_discovered_domain(domain):
    """Add a discovered domain to the file"""
    domain = domain.rstrip('.').lower()

    if domain in known_domains:
        return False

    try:
        with open(DISCOVERED_DOMAINS_FILE, 'a') as f:
            fcntl.flock(f.fileno(), fcntl.LOCK_EX)
            f.write(domain + '\n')
            fcntl.flock(f.fileno(), fcntl.LOCK_UN)
        known_domains.add(domain)
        log(f"Discovered new domain: {domain}")
        return True
    except Exception as e:
        log(f"Error adding domain: {e}", "ERROR")
    return False


def add_ip_to_table(ip):
    """Add IP to PF table"""
    ip = ip.strip()
    if not ip:
        return False

    try:
        result = subprocess.run(
            ['/sbin/pfctl', '-t', PF_TABLE, '-T', 'add', ip],
            capture_output=True, text=True, timeout=5
        )
        if 'added' in result.stderr.lower() or result.returncode == 0:
            log(f"Added IP to PF table: {ip}")
            return True
    except Exception as e:
        log(f"Error adding IP {ip}: {e}", "ERROR")
    return False


def parse_tcpdump_line(line):
    """
    Parse tcpdump verbose output for DNS responses.

    tcpdump -l -n -v output format:
    127.0.0.1.53 > 127.0.0.1.48562: 65258 3/0/0 portal.discover.com. CNAME portal.discover.com.edgekey.net., portal.discover.com.edgekey.net. CNAME e14577.x.akamaiedge.net., e14577.x.akamaiedge.net. A 23.196.238.175 (132)

    We need to extract:
    - The first domain in the answer (the queried domain)
    - The A/AAAA records (IP addresses)
    """
    try:
        # Skip non-response lines (responses come FROM port 53)
        if '.53 >' not in line:
            return None, []

        # Look for A records (IPv4)
        # Pattern: "A x.x.x.x" where x.x.x.x is an IP
        ipv4_pattern = re.compile(r'\bA\s+(\d+\.\d+\.\d+\.\d+)')
        ipv4_matches = ipv4_pattern.findall(line)

        # Look for AAAA records (IPv6)
        ipv6_pattern = re.compile(r'\bAAAA\s+([0-9a-fA-F:]+)')
        ipv6_matches = ipv6_pattern.findall(line)

        ips = ipv4_matches + ipv6_matches

        if not ips:
            return None, []

        # Extract the first domain in the response (after the answer count like "3/0/0")
        # Format: "65258 3/0/0 portal.discover.com. CNAME ..."
        # The first domain after the answer count is the queried domain
        domain = None

        # Look for pattern: "number/number/number domain.tld."
        answer_pattern = re.compile(r'\d+/\d+/\d+\s+([a-zA-Z0-9][-a-zA-Z0-9]*(?:\.[a-zA-Z0-9][-a-zA-Z0-9]*)+)\.')
        match = answer_pattern.search(line)
        if match:
            domain = match.group(1)

        # If no match, try to find any domain before A/AAAA record
        if not domain:
            full_domain_pattern = re.compile(r'\b((?:[a-zA-Z0-9][-a-zA-Z0-9]*\.)+[a-zA-Z]{2,})\.?\s+(?:A|AAAA|CNAME)')
            full_match = full_domain_pattern.search(line)
            if full_match:
                domain = full_match.group(1)

        return domain, ips

    except Exception as e:
        log(f"Error parsing line: {e}", "DEBUG")
        return None, []


def process_dns_response(domain, ips):
    """Process a DNS response - check if it matches our patterns"""
    if not domain or not ips:
        return

    base_domain = domain_matches_wildcard(domain)
    if base_domain:
        # This domain matches one of our wildcard patterns
        if add_discovered_domain(domain):
            log(f"New subdomain of {base_domain}: {domain} -> {ips}")

        for ip in ips:
            add_ip_to_table(ip)


def run_sniffer():
    """Main sniffer loop using tcpdump"""
    global running, tcpdump_proc

    log("Starting DNS sniffer...")
    load_wildcard_patterns()
    load_known_domains()

    if not wildcard_patterns:
        log("No wildcard patterns configured, nothing to sniff for", "WARN")
        # Still run but check periodically for config changes

    # Detect LAN interface dynamically
    lan_interface = get_lan_interface()

    # Start tcpdump on LAN interface, capturing DNS responses
    # -l: line buffered, -n: no DNS resolution, -v: verbose (shows DNS content)
    cmd = [
        '/usr/sbin/tcpdump',
        '-l',           # Line buffered output
        '-n',           # Don't resolve IPs to names
        '-v',           # Verbose - shows DNS response content
        '-i', lan_interface,
        '-s', '512',    # Capture enough for DNS packets
        'udp port 53 and src port 53'  # Only DNS responses (from port 53)
    ]

    log(f"Running: {' '.join(cmd)}")

    try:
        tcpdump_proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1  # Line buffered
        )

        # Track when we last reloaded config
        last_config_check = time.time()
        config_check_interval = 60  # Check for config changes every 60 seconds

        while running:
            # Read line from tcpdump (with timeout via select would be better but this works)
            line = tcpdump_proc.stdout.readline()

            if not line:
                # Check if process died
                if tcpdump_proc.poll() is not None:
                    log("tcpdump process died, restarting...", "WARN")
                    time.sleep(1)
                    tcpdump_proc = subprocess.Popen(
                        cmd,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        text=True,
                        bufsize=1
                    )
                continue

            line = line.strip()
            if line:
                domain, ips = parse_tcpdump_line(line)
                if domain and ips:
                    process_dns_response(domain, ips)

            # Periodically reload config to pick up changes
            if time.time() - last_config_check > config_check_interval:
                load_wildcard_patterns()
                last_config_check = time.time()

    except Exception as e:
        log(f"Sniffer error: {e}", "ERROR")
    finally:
        if tcpdump_proc:
            tcpdump_proc.terminate()
            tcpdump_proc.wait()


def signal_handler(signum, frame):
    """Handle shutdown signals"""
    global running, tcpdump_proc
    log(f"Received signal {signum}, shutting down...")
    running = False
    if tcpdump_proc:
        tcpdump_proc.terminate()


def daemonize():
    """Fork into background"""
    # First fork
    pid = os.fork()
    if pid > 0:
        sys.exit(0)

    # Decouple from parent
    os.chdir('/')
    os.setsid()
    os.umask(0)

    # Second fork
    pid = os.fork()
    if pid > 0:
        sys.exit(0)

    # Redirect standard file descriptors
    sys.stdout.flush()
    sys.stderr.flush()

    with open('/dev/null', 'r') as devnull:
        os.dup2(devnull.fileno(), sys.stdin.fileno())

    with open(LOG_FILE, 'a') as logfile:
        os.dup2(logfile.fileno(), sys.stdout.fileno())
        os.dup2(logfile.fileno(), sys.stderr.fileno())


def write_pid():
    """Write PID file"""
    with open(PID_FILE, 'w') as f:
        f.write(str(os.getpid()))


def read_pid():
    """Read PID from file"""
    try:
        with open(PID_FILE, 'r') as f:
            return int(f.read().strip())
    except:
        return None


def is_running():
    """Check if daemon is running"""
    pid = read_pid()
    if pid:
        try:
            os.kill(pid, 0)  # Check if process exists
            return True
        except OSError:
            pass
    return False


def start_daemon():
    """Start the daemon"""
    if is_running():
        print("Sniffer is already running")
        return

    print("Starting VPN Bypass DNS Sniffer...")
    daemonize()
    write_pid()

    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

    run_sniffer()


def stop_daemon():
    """Stop the daemon"""
    pid = read_pid()
    if not pid:
        print("Sniffer is not running (no PID file)")
        return

    try:
        os.kill(pid, signal.SIGTERM)
        print(f"Sent SIGTERM to process {pid}")

        # Wait for process to die
        for _ in range(10):
            time.sleep(0.5)
            try:
                os.kill(pid, 0)
            except OSError:
                print("Sniffer stopped")
                break
        else:
            print("Process didn't stop, sending SIGKILL")
            os.kill(pid, signal.SIGKILL)
    except OSError as e:
        print(f"Error stopping daemon: {e}")

    # Clean up PID file
    try:
        os.remove(PID_FILE)
    except:
        pass


def status():
    """Check daemon status"""
    if is_running():
        pid = read_pid()
        print(f"Sniffer is running (PID: {pid})")

        # Show some stats
        try:
            with open(LOG_FILE, 'r') as f:
                lines = f.readlines()
                # Show last 5 log lines
                print("\nRecent log entries:")
                for line in lines[-5:]:
                    print(f"  {line.rstrip()}")
        except:
            pass

        return 0
    else:
        print("Sniffer is not running")
        return 1


def test_mode():
    """Run in foreground for testing"""
    print("Running in test mode (foreground)...")
    print("Press Ctrl+C to stop\n")

    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

    run_sniffer()


def main():
    if len(sys.argv) < 2:
        print("Usage: vpnbypass_sniffer.py {start|stop|status|test}")
        sys.exit(1)

    command = sys.argv[1].lower()

    if command == 'start':
        start_daemon()
    elif command == 'stop':
        stop_daemon()
    elif command == 'status':
        sys.exit(status())
    elif command == 'test':
        test_mode()
    else:
        print(f"Unknown command: {command}")
        print("Usage: vpnbypass_sniffer.py {start|stop|status|test}")
        sys.exit(1)


if __name__ == '__main__':
    main()
