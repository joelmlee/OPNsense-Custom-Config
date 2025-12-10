#!/bin/sh
#
# Custom Files writer for OPNsense
# Reads file definitions from config.xml and writes them to disk
#

CONFIG_XML="/conf/config.xml"

# Use Python to parse config.xml and write files
/usr/local/bin/python3 << 'PYTHON_SCRIPT'
import xml.etree.ElementTree as ET
import os
import subprocess

config_file = '/conf/config.xml'

try:
    tree = ET.parse(config_file)
    root = tree.getroot()

    # Find customfiles section
    customconfig = root.find('.//OPNsense/CustomConfig/customfiles/files')
    if customconfig is None:
        print("No custom files configured")
        exit(0)

    files_written = 0

    for file_elem in customconfig:
        # Skip non-file elements
        if file_elem.tag == 'file':
            continue

        enabled = file_elem.find('enabled')
        if enabled is None or enabled.text != '1':
            continue

        name = file_elem.find('name')
        filepath = file_elem.find('filepath')
        content = file_elem.find('content')
        permissions = file_elem.find('permissions')
        reloadcmd = file_elem.find('reloadcmd')

        if filepath is None or filepath.text is None:
            continue

        filepath_text = filepath.text.strip()
        content_text = content.text if content is not None and content.text else ''

        # Ensure parent directory exists
        parent_dir = os.path.dirname(filepath_text)
        if parent_dir and not os.path.exists(parent_dir):
            os.makedirs(parent_dir, exist_ok=True)

        # Write file
        with open(filepath_text, 'w') as f:
            f.write(content_text)

        # Set permissions
        if permissions is not None and permissions.text:
            try:
                os.chmod(filepath_text, int(permissions.text, 8))
            except:
                pass

        name_text = name.text if name is not None and name.text else filepath_text
        print(f"Written: {name_text} -> {filepath_text}")
        files_written += 1

        # Run reload command if specified
        if reloadcmd is not None and reloadcmd.text:
            try:
                subprocess.run(reloadcmd.text, shell=True, timeout=30)
                print(f"  Reload command executed: {reloadcmd.text}")
            except Exception as e:
                print(f"  Reload command failed: {e}")

    print(f"\nTotal files written: {files_written}")

except Exception as e:
    print(f"Error: {e}")
    exit(1)
PYTHON_SCRIPT

# Fix monitrc after OPNsense template regeneration
fix_monitrc() {
    if ! grep -q "set daemon" /usr/local/etc/monitrc 2>/dev/null; then
        cat > /usr/local/etc/monitrc << MONITRC
# Monit configuration
set daemon 120
set httpd unixsocket /var/run/monit.sock allow localhost

include /usr/local/etc/monit.opnsense.d/*.conf
MONITRC
        chmod 600 /usr/local/etc/monitrc
        /usr/local/bin/monit -c /usr/local/etc/monitrc 2>/dev/null || true
    fi
}

fix_monitrc
