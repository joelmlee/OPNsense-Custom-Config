#!/usr/local/bin/python3
"""
VPN Bypass DNS Snooper

This script watches DNS query logs and extracts resolved IPs for domains
matching configured wildcard patterns. It can run in two modes:
1. As a daemon that tails the Unbound log
2. As a one-shot processor for the query log

Discovered domains and IPs are stored in files that the periodic
vpnbypass.sh script uses to update the PF table.
"""

import os
import sys
import re
import time
import fcntl
import subprocess
import signal
from datetime import datetime

# File paths
CONFIG_FILE = "/usr/local/etc/vpn_bypass_domains.conf"
DISCOVERED_DOMAINS_FILE = "/var/db/customconfig_vpnbypass_discovered.txt"
DISCOVERED_IPS_FILE = "/var/db/customconfig_vpnbypass_ips.txt"
PID_FILE = "/var/run/vpnbypass_dns.pid"
PF_TABLE = "customconfig_vpnbypass"

# Global state
wildcard_patterns = []
running = True


def log(msg):
    """Log message with timestamp"""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{timestamp}] {msg}", file=sys.stderr, flush=True)


def load_wildcard_patterns():
    """Load wildcard domain patterns from config file"""
    global wildcard_patterns
    wildcard_patterns = []

    if not os.path.exists(CONFIG_FILE):
        return

    try:
        with open(CONFIG_FILE, 'r') as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                if line.startswith('*.'):
                    # Convert *.domain.com to regex pattern
                    base_domain = line[2:]  # Remove *.
                    # Escape dots and create pattern that matches any subdomain
                    pattern = re.compile(
                        r'^([a-zA-Z0-9-]+\.)*' + re.escape(base_domain) + r'\.?$',
                        re.IGNORECASE
                    )
                    wildcard_patterns.append((line, base_domain, pattern))
    except Exception as e:
        log(f"Error loading config: {e}")


def domain_matches_wildcard(domain):
    """Check if domain matches any wildcard pattern, return base domain if so"""
    domain = domain.rstrip('.')
    for orig_pattern, base_domain, regex in wildcard_patterns:
        if regex.match(domain):
            return base_domain
    return None


def add_discovered_domain(domain):
    """Add a discovered domain to the file (thread-safe)"""
    domain = domain.rstrip('.').lower()

    # Read existing domains
    existing = set()
    if os.path.exists(DISCOVERED_DOMAINS_FILE):
        try:
            with open(DISCOVERED_DOMAINS_FILE, 'r') as f:
                existing = set(line.strip().lower() for line in f if line.strip())
        except:
            pass

    if domain not in existing:
        try:
            with open(DISCOVERED_DOMAINS_FILE, 'a') as f:
                fcntl.flock(f.fileno(), fcntl.LOCK_EX)
                f.write(domain + '\n')
                fcntl.flock(f.fileno(), fcntl.LOCK_UN)
            log(f"Discovered new domain: {domain}")
            return True
        except Exception as e:
            log(f"Error adding domain: {e}")
    return False


def add_ip_to_table(ip):
    """Add IP to PF table and tracking file"""
    ip = ip.strip()
    if not ip:
        return False

    # Add to PF table immediately
    try:
        result = subprocess.run(
            ['/sbin/pfctl', '-t', PF_TABLE, '-T', 'add', ip],
            capture_output=True, text=True
        )
        if result.returncode == 0 and 'added' in result.stderr.lower():
            log(f"Added IP to PF table: {ip}")

            # Also track in file for persistence
            try:
                with open(DISCOVERED_IPS_FILE, 'a') as f:
                    fcntl.flock(f.fileno(), fcntl.LOCK_EX)
                    f.write(f"{ip}\n")
                    fcntl.flock(f.fileno(), fcntl.LOCK_UN)
            except:
                pass
            return True
    except Exception as e:
        log(f"Error adding IP to table: {e}")
    return False


def resolve_and_add(domain):
    """Resolve domain and add IPs to table"""
    try:
        result = subprocess.run(
            ['drill', domain, 'A'],
            capture_output=True, text=True, timeout=5
        )

        ips_added = 0
        for line in result.stdout.split('\n'):
            # Match A record lines: domain. TTL IN A x.x.x.x
            if '\tA\t' in line or ' A ' in line:
                parts = line.split()
                if len(parts) >= 5:
                    ip = parts[-1]
                    if re.match(r'^\d+\.\d+\.\d+\.\d+$', ip):
                        if add_ip_to_table(ip):
                            ips_added += 1

        # Also try AAAA
        result = subprocess.run(
            ['drill', domain, 'AAAA'],
            capture_output=True, text=True, timeout=5
        )
        for line in result.stdout.split('\n'):
            if '\tAAAA\t' in line or ' AAAA ' in line:
                parts = line.split()
                if len(parts) >= 5:
                    ip = parts[-1]
                    if ':' in ip:  # IPv6
                        if add_ip_to_table(ip):
                            ips_added += 1

        return ips_added
    except Exception as e:
        log(f"Error resolving {domain}: {e}")
        return 0


def process_dns_response(domain, ips):
    """Process a DNS response - check if it matches our patterns"""
    base_domain = domain_matches_wildcard(domain)
    if base_domain:
        # This domain matches one of our wildcard patterns
        add_discovered_domain(domain)
        for ip in ips:
            add_ip_to_table(ip)
        return True
    return False


def watch_unbound_log():
    """
    Watch Unbound log for DNS responses.
    This requires log-replies: yes in unbound.conf
    """
    log_file = "/var/log/resolver/dns_replies.log"

    if not os.path.exists(log_file):
        log(f"Log file not found: {log_file}")
        log("Enable 'Log Replies' in Services > Unbound DNS > Advanced")
        return

    log(f"Watching {log_file} for DNS responses...")

    # Pattern to match log lines with replies
    # Format varies but typically: timestamp query_name type response_ip
    reply_pattern = re.compile(
        r'reply:\s+(\S+)\s+.*?(\d+\.\d+\.\d+\.\d+|[0-9a-fA-F:]+)',
        re.IGNORECASE
    )

    with open(log_file, 'r') as f:
        # Seek to end
        f.seek(0, 2)

        while running:
            line = f.readline()
            if not line:
                time.sleep(0.1)
                continue

            # Try to parse the line
            match = reply_pattern.search(line)
            if match:
                domain = match.group(1)
                ip = match.group(2)
                process_dns_response(domain, [ip])


def scan_discovered_domains():
    """Re-resolve all discovered domains (called by periodic script)"""
    if not os.path.exists(DISCOVERED_DOMAINS_FILE):
        return 0

    total_ips = 0
    try:
        with open(DISCOVERED_DOMAINS_FILE, 'r') as f:
            domains = [line.strip() for line in f if line.strip()]

        for domain in domains:
            ips = resolve_and_add(domain)
            total_ips += ips
    except Exception as e:
        log(f"Error scanning discovered domains: {e}")

    return total_ips


def get_status():
    """Return status information as dict"""
    status = {
        'wildcard_patterns': len(wildcard_patterns),
        'discovered_domains': [],
        'discovered_ips_count': 0
    }

    if os.path.exists(DISCOVERED_DOMAINS_FILE):
        try:
            with open(DISCOVERED_DOMAINS_FILE, 'r') as f:
                status['discovered_domains'] = [
                    line.strip() for line in f if line.strip()
                ]
        except:
            pass

    # Get IP count from PF table
    try:
        result = subprocess.run(
            ['/sbin/pfctl', '-t', PF_TABLE, '-T', 'show'],
            capture_output=True, text=True
        )
        if result.returncode == 0:
            ips = [line.strip() for line in result.stdout.split('\n') if line.strip()]
            status['discovered_ips_count'] = len(ips)
    except:
        pass

    return status


def signal_handler(signum, frame):
    """Handle shutdown signals"""
    global running
    log("Received shutdown signal")
    running = False


def main():
    global running

    if len(sys.argv) < 2:
        print("Usage: vpnbypass_dns.py <command>")
        print("Commands:")
        print("  scan      - Scan and resolve discovered domains")
        print("  status    - Show status")
        print("  clear     - Clear discovered domains")
        sys.exit(1)

    command = sys.argv[1]
    load_wildcard_patterns()

    if command == 'scan':
        # Re-resolve all discovered domains
        ips = scan_discovered_domains()
        print(f"Resolved {ips} IPs from discovered domains")

    elif command == 'status':
        import json
        status = get_status()
        print(json.dumps(status, indent=2))

    elif command == 'clear':
        # Clear discovered domains file
        if os.path.exists(DISCOVERED_DOMAINS_FILE):
            os.remove(DISCOVERED_DOMAINS_FILE)
            print("Cleared discovered domains")
        else:
            print("No discovered domains file")

    elif command == 'add':
        # Manually add a domain (for testing or from external sources)
        if len(sys.argv) < 3:
            print("Usage: vpnbypass_dns.py add <domain>")
            sys.exit(1)
        domain = sys.argv[2]
        if add_discovered_domain(domain):
            ips = resolve_and_add(domain)
            print(f"Added {domain}, resolved {ips} IPs")
        else:
            print(f"Domain {domain} already known")

    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == '__main__':
    main()
