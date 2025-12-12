#!/usr/local/bin/python3
"""
IDS Email Alert Script
Monitors Suricata eve.json for new alerts and sends email notifications.

Configuration is read from /usr/local/etc/ids_alert.conf
"""

import json
import os
import smtplib
from email.mime.text import MIMEText
from configparser import ConfigParser

# Paths
CONFIG_FILE = '/usr/local/etc/ids_alert.conf'
EVE_LOG = '/var/log/suricata/eve.json'
STATE_FILE = '/var/run/ids_alert_pos'

def load_config():
    """Load configuration from file."""
    if not os.path.exists(CONFIG_FILE):
        print(f'Config file not found: {CONFIG_FILE}')
        print('Create it with:')
        print('[smtp]')
        print('server = smtp.gmail.com')
        print('port = 587')
        print('user = your@email.com')
        print('password = your_app_password')
        print('from = your@email.com')
        print('to = your@email.com')
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

    alerts = []
    new_pos = last_pos

    with open(EVE_LOG, 'r') as f:
        f.seek(last_pos)
        for line in f:
            try:
                event = json.loads(line)
                if event.get('event_type') == 'alert':
                    alerts.append(event)
            except:
                pass
        new_pos = f.tell()

    save_position(new_pos, current_inode)

    if alerts:
        # Group by signature to reduce noise
        sig_counts = {}
        for a in alerts:
            sig = a.get('alert', {}).get('signature', 'Unknown')
            if sig not in sig_counts:
                sig_counts[sig] = {'count': 0, 'example': a}
            sig_counts[sig]['count'] += 1

        body = f"OPNsense IDS detected {len(alerts)} alert(s):\n"
        body += "=" * 50 + "\n"

        for sig, data in sorted(sig_counts.items(), key=lambda x: -x[1]['count']):
            count = data['count']
            body += format_alert(data['example'])
            if count > 1:
                body += f"  (repeated {count} times)\n"

        subject = f"[OPNsense IDS] {len(alerts)} alert(s) - {list(sig_counts.keys())[0][:50]}"

        if send_email(config, subject, body):
            print(f'Sent alert email for {len(alerts)} alerts')
        else:
            print('Failed to send email')
    else:
        print('No new alerts')

if __name__ == '__main__':
    main()
