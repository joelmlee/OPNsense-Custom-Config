#!/usr/local/bin/python3
"""
IDS Email Alert Script
Monitors Suricata eve.json for new alerts and sends email notifications.

Configuration is read from /usr/local/etc/ids_alert.conf
"""

import json
import os
import smtplib
import re
from email.mime.text import MIMEText
from configparser import ConfigParser
from datetime import datetime

# Paths
CONFIG_FILE = '/usr/local/etc/ids_alert.conf'
EVE_LOG = '/var/log/suricata/eve.json'
STATE_FILE = '/var/run/ids_alert_pos'
DIGEST_FILE = '/var/run/ids_alert_digest.json'

def load_config():
    """Load configuration from file."""
    if not os.path.exists(CONFIG_FILE):
        print(f'Config file not found: {CONFIG_FILE}')
        return None

    config = ConfigParser()
    config.read(CONFIG_FILE)
    return config

def get_last_position():
    """Get last read position from state file."""
    try:
        with open(STATE_FILE, 'r') as f:
            data = json.load(f)
            return data.get('position', 0), data.get('inode', 0)
    except:
        return 0, 0

def save_position(position, inode):
    """Save current position to state file."""
    with open(STATE_FILE, 'w') as f:
        json.dump({'position': position, 'inode': inode}, f)

def load_digest():
    """Load digest alerts from file."""
    try:
        with open(DIGEST_FILE, 'r') as f:
            return json.load(f)
    except:
        return {'date': None, 'alerts': []}

def save_digest(digest):
    """Save digest alerts to file."""
    with open(DIGEST_FILE, 'w') as f:
        json.dump(digest, f)

def should_digest(config, alert):
    """Check if alert should go to daily digest instead of immediate email."""
    if not config.has_section('digest'):
        return False
    
    sig = alert.get('alert', {}).get('signature', '')
    dest_port = str(alert.get('dest_port', ''))
    
    # Check signature patterns
    if config.has_option('digest', 'signatures'):
        patterns = config.get('digest', 'signatures').split(',')
        for pattern in patterns:
            pattern = pattern.strip()
            if pattern and re.search(pattern, sig, re.IGNORECASE):
                return True
    
    # Check destination ports
    if config.has_option('digest', 'dest_ports'):
        ports = [p.strip() for p in config.get('digest', 'dest_ports').split(',')]
        if dest_port in ports:
            return True
    
    return False

def should_ignore(config, alert):
    """Check if alert should be completely ignored."""
    if not config.has_section('ignore'):
        return False
    
    sig = alert.get('alert', {}).get('signature', '')
    
    if config.has_option('ignore', 'signatures'):
        patterns = config.get('ignore', 'signatures').split(',')
        for pattern in patterns:
            pattern = pattern.strip()
            if pattern and re.search(pattern, sig, re.IGNORECASE):
                return True
    
    return False

def send_email(config, subject, body):
    """Send email via SMTP."""
    msg = MIMEText(body)
    msg['Subject'] = subject
    msg['From'] = config.get('smtp', 'from')
    msg['To'] = config.get('smtp', 'to')

    try:
        server = smtplib.SMTP(
            config.get('smtp', 'server'),
            config.getint('smtp', 'port'),
            timeout=30
        )
        server.starttls()
        server.login(
            config.get('smtp', 'user'),
            config.get('smtp', 'password')
        )
        server.sendmail(
            config.get('smtp', 'from'),
            [config.get('smtp', 'to')],
            msg.as_string()
        )
        server.quit()
        return True
    except Exception as e:
        print(f'Email error: {e}')
        return False

def format_alert(alert):
    """Format a single alert for email."""
    ts = alert.get('timestamp', 'Unknown time')
    sig = alert.get('alert', {}).get('signature', 'Unknown signature')
    severity = alert.get('alert', {}).get('severity', '?')
    src_ip = alert.get('src_ip', '?')
    src_port = alert.get('src_port', '')
    dest_ip = alert.get('dest_ip', '?')
    dest_port = alert.get('dest_port', '')
    proto = alert.get('proto', '?')
    category = alert.get('alert', {}).get('category', 'Unknown')

    src = f"{src_ip}:{src_port}" if src_port else src_ip
    dest = f"{dest_ip}:{dest_port}" if dest_port else dest_ip

    return f"""
[Severity {severity}] {sig}
  Category: {category}
  Time: {ts}
  {src} -> {dest} ({proto})
"""

def send_digest(config, digest_alerts):
    """Send daily digest email."""
    if not digest_alerts:
        return
    
    # Group by signature
    sig_counts = {}
    for a in digest_alerts:
        sig = a.get('alert', {}).get('signature', 'Unknown')
        if sig not in sig_counts:
            sig_counts[sig] = {'count': 0, 'examples': []}
        sig_counts[sig]['count'] += 1
        if len(sig_counts[sig]['examples']) < 3:
            sig_counts[sig]['examples'].append(a)
    
    body = f"Daily IDS Digest - {len(digest_alerts)} alert(s):\n"
    body += "=" * 50 + "\n"
    
    for sig, data in sorted(sig_counts.items(), key=lambda x: -x[1]['count']):
        count = data['count']
        body += f"\n{sig} ({count} times)\n"
        body += "-" * 40 + "\n"
        for example in data['examples']:
            src_ip = example.get('src_ip', '?')
            dest_port = example.get('dest_port', '?')
            body += f"  {src_ip} -> port {dest_port}\n"
    
    subject = f"[OPNsense IDS Digest] {len(digest_alerts)} alerts"
    send_email(config, subject, body)

def main():
    config = load_config()
    if not config:
        return

    if not os.path.exists(EVE_LOG):
        print(f'Eve log not found: {EVE_LOG}')
        return

    # Check if log rotated (inode changed)
    current_inode = os.stat(EVE_LOG).st_ino
    last_pos, last_inode = get_last_position()

    if current_inode != last_inode:
        last_pos = 0  # Log rotated, start from beginning

    # Load digest
    today = datetime.now().strftime('%Y-%m-%d')
    digest = load_digest()
    if digest['date'] != today:
        # New day - send yesterday's digest if any, start fresh
        if digest['alerts']:
            send_digest(config, digest['alerts'])
        digest = {'date': today, 'alerts': []}

    immediate_alerts = []
    new_pos = last_pos

    with open(EVE_LOG, 'r') as f:
        f.seek(last_pos)
        for line in f:
            try:
                event = json.loads(line)
                if event.get('event_type') == 'alert':
                    if should_ignore(config, event):
                        continue
                    elif should_digest(config, event):
                        digest['alerts'].append(event)
                    else:
                        immediate_alerts.append(event)
            except:
                pass
        new_pos = f.tell()

    save_position(new_pos, current_inode)
    save_digest(digest)

    if immediate_alerts:
        # Group by signature to reduce noise
        sig_counts = {}
        for a in immediate_alerts:
            sig = a.get('alert', {}).get('signature', 'Unknown')
            if sig not in sig_counts:
                sig_counts[sig] = {'count': 0, 'example': a}
            sig_counts[sig]['count'] += 1

        body = f"OPNsense IDS detected {len(immediate_alerts)} alert(s):\n"
        body += "=" * 50 + "\n"

        for sig, data in sorted(sig_counts.items(), key=lambda x: -x[1]['count']):
            count = data['count']
            body += format_alert(data['example'])
            if count > 1:
                body += f"  (repeated {count} times)\n"

        subject = f"[OPNsense IDS] {len(immediate_alerts)} alert(s) - {list(sig_counts.keys())[0][:50]}"

        if send_email(config, subject, body):
            print(f'Sent alert email for {len(immediate_alerts)} alerts')
        else:
            print('Failed to send email')
    else:
        print('No new immediate alerts')
    
    if digest['alerts']:
        print(f"{len(digest['alerts'])} alerts queued for daily digest")

if __name__ == '__main__':
    main()
