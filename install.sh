#!/bin/sh
#
# Install Custom Config plugin to OPNsense
# Run this script on the OPNsense firewall
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="${SCRIPT_DIR}/src"

echo "Installing Custom Config plugin..."

# Copy MVC files
cp -r ${PLUGIN_DIR}/opnsense/mvc/app/controllers/OPNsense/CustomConfig /usr/local/opnsense/mvc/app/controllers/OPNsense/
cp -r ${PLUGIN_DIR}/opnsense/mvc/app/models/OPNsense/CustomConfig /usr/local/opnsense/mvc/app/models/OPNsense/
cp -r ${PLUGIN_DIR}/opnsense/mvc/app/views/OPNsense/CustomConfig /usr/local/opnsense/mvc/app/views/OPNsense/

# Copy service files
cp ${PLUGIN_DIR}/opnsense/service/conf/actions.d/actions_customconfig.conf /usr/local/opnsense/service/conf/actions.d/
cp -r ${PLUGIN_DIR}/opnsense/service/templates/OPNsense/CustomConfig /usr/local/opnsense/service/templates/OPNsense/

# Copy scripts
mkdir -p /usr/local/opnsense/scripts/OPNsense/CustomConfig
cp ${PLUGIN_DIR}/opnsense/scripts/OPNsense/CustomConfig/*.sh /usr/local/opnsense/scripts/OPNsense/CustomConfig/
chmod +x /usr/local/opnsense/scripts/OPNsense/CustomConfig/*.sh

# Copy plugin integration
cp ${PLUGIN_DIR}/etc/inc/plugins.inc.d/customconfig.inc /usr/local/etc/inc/plugins.inc.d/

# Ensure monit drop-in directory exists
mkdir -p /usr/local/etc/monit.opnsense.d

# Restart configd to pick up new actions
service configd restart

# Flush cache
/usr/local/etc/rc.d/configd restart

echo "Plugin installed. Please refresh the GUI and navigate to Services > Custom Config"
echo ""
echo "You may need to run: configctl template reload OPNsense/CustomConfig"
